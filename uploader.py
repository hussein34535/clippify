"""
uploader.py — YouTube OAuth2 + Upload for Clippify
Handles authentication, resumable upload, and progress callbacks.

Requirements:
    pip install google-auth-oauthlib google-api-python-client google-auth-httplib2

Setup (one-time):
    1. Go to https://console.cloud.google.com
    2. Create project → Enable "YouTube Data API v3"
    3. Create OAuth 2.0 credentials → Desktop App
    4. Download JSON → rename to client_secrets.json
    5. Place client_secrets.json next to app.py
"""

import os
import datetime

# ── Paths (relative to this file's directory) ───────────────────────────────
APP_DIR      = os.path.dirname(os.path.abspath(__file__))
TOKEN_FILE   = os.path.join(APP_DIR, "token.json")
SECRETS_FILE = os.path.join(APP_DIR, "client_secrets.json")

SCOPES = ["https://www.googleapis.com/auth/youtube.upload"]


# ═══════════════════════════════════════════════════════════════════════════
#  authenticate() — returns valid google.oauth2.credentials.Credentials
# ═══════════════════════════════════════════════════════════════════════════
def authenticate():
    """
    Return valid OAuth2 credentials.

    Flow:
    - token.json exists and valid  → return immediately
    - token.json exists but expired → silent refresh
    - no token / refresh fails     → open browser for login, save token.json

    Raises
    ------
    FileNotFoundError
        If client_secrets.json is not present in APP_DIR.
    RuntimeError
        If google packages are not installed.
    """
    try:
        from google.oauth2.credentials      import Credentials
        from google.auth.transport.requests import Request
        from google_auth_oauthlib.flow      import InstalledAppFlow
    except ImportError as e:
        raise RuntimeError(
            "Google packages not installed.\n"
            "Run: pip install google-auth-oauthlib google-api-python-client google-auth-httplib2"
        ) from e

    if not os.path.exists(SECRETS_FILE):
        raise FileNotFoundError(
            f"client_secrets.json not found in:\n{APP_DIR}\n\n"
            "Please follow the setup instructions to create it."
        )

    creds = None

    # ── Load saved token ────────────────────────────────────────────────────
    if os.path.exists(TOKEN_FILE):
        try:
            creds = Credentials.from_authorized_user_file(TOKEN_FILE, SCOPES)
        except Exception:
            creds = None   # corrupt token — will re-auth below

    # ── Refresh or re-authenticate ──────────────────────────────────────────
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            try:
                creds.refresh(Request())
            except Exception:
                # refresh failed (revoked) → full re-auth
                creds = None

        if not creds or not creds.valid:
            flow  = InstalledAppFlow.from_client_secrets_file(SECRETS_FILE, SCOPES)
            creds = flow.run_local_server(port=0)

        # Save for next time
        with open(TOKEN_FILE, "w") as fh:
            fh.write(creds.to_json())

    return creds


# ═══════════════════════════════════════════════════════════════════════════
#  upload_video() — uploads one mp4 to YouTube, returns watch URL
# ═══════════════════════════════════════════════════════════════════════════
def upload_video(
    file_path:   str,
    title:       str  = None,
    description: str  = "Created with Clippify — https://github.com/clippify",
    privacy:     str  = "private",
    progress_cb        = None,
) -> str:
    """
    Upload a video file to YouTube.

    Parameters
    ----------
    file_path    : absolute path to the .mp4 file
    title        : video title (default: filename + date)
    description  : video description
    privacy      : "private" | "unlisted" | "public"
    progress_cb  : optional callable(pct: int) called with 0-100 during upload

    Returns
    -------
    str  — full YouTube watch URL, e.g. "https://youtube.com/watch?v=XXXXXX"

    Raises
    ------
    FileNotFoundError  — client_secrets.json missing
    RuntimeError       — Google packages not installed
    ConnectionError    — network error during upload
    """
    try:
        from googleapiclient.discovery import build
        from googleapiclient.http      import MediaFileUpload
        from googleapiclient.errors    import HttpError
    except ImportError as e:
        raise RuntimeError(
            "Google packages not installed.\n"
            "Run: pip install google-api-python-client"
        ) from e

    # ── Validate file ───────────────────────────────────────────────────────
    if not os.path.isfile(file_path):
        raise FileNotFoundError(f"Video file not found: {file_path}")

    # ── Default title ───────────────────────────────────────────────────────
    if not title:
        base  = os.path.splitext(os.path.basename(file_path))[0]
        today = datetime.date.today().strftime("%Y-%m-%d")
        title = f"{base} — {today}"

    # ── Authenticate ────────────────────────────────────────────────────────
    creds   = authenticate()
    youtube = build("youtube", "v3", credentials=creds)

    # ── Build request body ──────────────────────────────────────────────────
    body = {
        "snippet": {
            "title":       title,
            "description": description,
            "tags":        ["shorts", "clippify", "viral"],
            "categoryId":  "22",   # People & Blogs
        },
        "status": {
            "privacyStatus": privacy.lower(),
            "madeForKids":   False,
            "selfDeclaredMadeForKids": False,
        },
    }

    # ── Media upload (resumable, 1 MB chunks) ───────────────────────────────
    media = MediaFileUpload(
        file_path,
        mimetype="video/mp4",
        chunksize=1024 * 1024,
        resumable=True,
    )

    request = youtube.videos().insert(
        part="snippet,status",
        body=body,
        media_body=media,
    )

    # ── Upload loop ─────────────────────────────────────────────────────────
    response = None
    try:
        while response is None:
            status, response = request.next_chunk()
            if status and progress_cb:
                pct = int(status.progress() * 100)
                progress_cb(pct)
    except HttpError as e:
        raise ConnectionError(
            f"YouTube API error during upload: {e.reason}"
        ) from e
    except Exception as e:
        err_msg = str(e).lower()
        if any(k in err_msg for k in ("connection", "timeout", "network", "socket")):
            raise ConnectionError(f"Network error: {e}") from e
        raise

    # Final 100% callback
    if progress_cb:
        progress_cb(100)

    video_id = response.get("id", "")
    return f"https://youtube.com/watch?v={video_id}"
