"""
storage.py — pluggable file storage for Clippify v2 (contract: docs/CONTRACTS.md
Upload section). Backends selected purely by env:

    S3_BUCKET set  -> boto3 client (S3 / Cloudflare R2 via S3_ENDPOINT / MinIO)
    otherwise      -> LOCAL backend under ./storage/

LOCAL mode note for api.py owners:
    Mount the storage dir as static files so public_url() links work:
        from fastapi.staticfiles import StaticFiles
        app.mount("/files", StaticFiles(directory="storage"), name="files")
    and keep PUBLIC_BASE_URL unset so urls are relative ("/files/<key>").
    In cloud mode set PUBLIC_BASE_URL=https://cdn.example.com to get absolute urls.

All heavy deps (boto3) are imported lazily inside functions — their absence
never breaks `import storage`.

Public API:
    put_file(local_path, key)          -> url
    open_url(url)                      -> local_path (downloaded into temp cache)
    delete(key)
    public_url(local_path_or_key)      -> client-usable url
    presign_put(key)                   -> pre-signed PUT upload url (S3 backends;
                                          local mode returns an api-side PUT path)
"""

from __future__ import annotations

import hashlib
import os
import shutil
import tempfile

DEFAULT_STORAGE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "storage")
_CACHE_ROOT = os.path.join(tempfile.gettempdir(), "clippify_storage_cache")


# ---------------------------------------------------------------------------
# Env helpers
# ---------------------------------------------------------------------------


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def storage_dir() -> str:
    d = _env("STORAGE_DIR") or DEFAULT_STORAGE_DIR
    os.makedirs(d, exist_ok=True)
    return d


def is_s3_mode() -> bool:
    return bool(_env("S3_BUCKET"))


def _s3_client():
    """Lazily build a boto3 client. Raises with guidance if boto3 missing."""
    try:
        import boto3
    except ImportError as exc:
        raise RuntimeError(
            "S3_BUCKET is set but boto3 is not installed. "
            "Run: pip install boto3  (or unset S3_BUCKET for local ./storage backend)"
        ) from exc
    kwargs = {}
    if _env("S3_ENDPOINT"):  # R2 / MinIO style endpoint
        kwargs["endpoint_url"] = _env("S3_ENDPOINT")
    if _env("AWS_ACCESS_KEY_ID"):
        kwargs["aws_access_key_id"] = _env("AWS_ACCESS_KEY_ID")
    if _env("AWS_SECRET_ACCESS_KEY"):
        kwargs["aws_secret_access_key"] = _env("AWS_SECRET_ACCESS_KEY")
    if _env("AWS_REGION"):
        kwargs["region_name"] = _env("AWS_REGION")
    return boto3.client("s3", **kwargs)


def _bucket() -> str:
    return _env("S3_BUCKET")


# ---------------------------------------------------------------------------
# Key normalisation
# ---------------------------------------------------------------------------


def _key_from(value: str) -> str:
    """Accept a key, absolute local path inside storage dir, or /files URL."""
    value = value.replace("\\", "/").strip()
    if value.startswith("/files/"):
        value = value[len("/files/"):]
    base = storage_dir().replace("\\", "/").rstrip("/") + "/"
    if value.startswith(base):
        value = value[len(base):]
    return value.lstrip("/")


def _norm_key(key: str) -> str:
    return "/".join(p for p in key.replace("\\", "/").split("/") if p not in ("", ".", ".."))


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def put_file(local_path: str, key: str) -> str:
    """Store a local file under `key`; returns its public URL."""
    key = _norm_key(key)
    if not os.path.exists(local_path):
        raise FileNotFoundError(local_path)

    if is_s3_mode():
        extra = {"ContentType": "application/octet-stream"}
        _s3_client().upload_file(local_path, _bucket(), key, ExtraArgs=extra)
    else:
        dest = os.path.join(storage_dir(), *key.split("/"))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copy2(local_path, dest)

    return public_url(key)


def open_url(url: str) -> str:
    """
    Resolve any stored URL/path into a LOCAL file path.

    Accepts s3:// URLs, http(s) URLs, "/files/<key>" urls produced by
    public_url(), and plain filesystem paths (returned as-is).
    Downloads land in a temp cache dir keyed by content hash of the URL.
    """
    url = url.strip()

    # Plain local path -> passthrough
    if os.path.exists(url):
        return url

    os.makedirs(_CACHE_ROOT, exist_ok=True)

    if url.startswith("s3://"):
        rest = url[len("s3://"):]
        bucket, _, key = rest.partition("/")
        local = _cache_name(url)
        _s3_client().download_file(bucket or _bucket(), key, local)
        return local

    if url.startswith(("http://", "https://")):
        local = _cache_name(url)
        if os.path.exists(local):  # cache hit
            return local
        import requests
        resp = requests.get(url, stream=True, timeout=300)
        resp.raise_for_status()
        tmp = local + ".part"
        with open(tmp, "wb") as fh:
            for chunk in resp.iter_content(chunk_size=1 << 20):
                fh.write(chunk)
        os.replace(tmp, local)
        return local

    # /files/<key> from local backend (or bare key)
    key = _key_from(url)
    candidate = os.path.join(storage_dir(), *key.split("/"))
    if os.path.exists(candidate):
        return candidate

    raise FileNotFoundError(f"storage.open_url: cannot resolve {url!r}")


def _cache_name(url: str) -> str:
    digest = hashlib.sha256(url.encode("utf-8")).hexdigest()[:16]
    ext = os.path.splitext(url.replace("\\", "/"))[1][:10]
    return os.path.join(_CACHE_ROOT, digest + ext)


def delete(key: str) -> None:
    key = _key_from(_norm_key(key))
    if is_s3_mode():
        _s3_client().delete_object(Bucket=_bucket(), Key=key)
        return
    target = os.path.join(storage_dir(), *key.split("/"))
    if os.path.exists(target):
        os.remove(target)


def public_url(local_path_or_key: str) -> str:
    """Client-usable URL for a stored object."""
    key = _key_from(_norm_key(str(local_path_or_key)))

    if is_s3_mode():
        endpoint = _env("S3_ENDPOINT").rstrip("/")
        if endpoint:  # R2/MinIO path-style
            return f"{endpoint}/{_bucket()}/{key}"
        return f"https://{_bucket()}.s3.amazonaws.com/{key}"

    base = _env("PUBLIC_BASE_URL").rstrip("/")
    return f"{base}/files/{key}"


def presign_put(key: str, expires_sec: int = 3600) -> str:
    """
    Pre-signed PUT url for direct client upload (CONTRACTS.md /api/upload/init).

    S3/R2/MinIO -> real presigned url.
    Local mode   -> relative API path; api.py should implement
                    PUT /api/upload/local/{key:path} writing the body into
                    the storage dir (documented in DEPLOY.md).
    """
    key = _norm_key(key)
    if is_s3_mode():
        return _s3_client().generate_presigned_url(
            "put_object",
            Params={"Bucket": _bucket(), "Key": key},
            ExpiresIn=int(expires_sec),
        )
    return f"/api/upload/local/{key}"
