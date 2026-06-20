import pytest
from downloader import validate_url


def test_validate_url_valid_youtube():
    url = validate_url("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    assert url == "https://www.youtube.com/watch?v=dQw4w9WgXcQ"


def test_validate_url_youtu_be():
    url = validate_url("https://youtu.be/dQw4w9WgXcQ")
    assert url == "https://youtu.be/dQw4w9WgXcQ"


def test_validate_url_rejects_http():
    with pytest.raises(ValueError, match="HTTPS"):
        validate_url("http://youtube.com/watch?v=abc")


def test_validate_url_rejects_non_youtube():
    with pytest.raises(ValueError, match="YouTube"):
        validate_url("https://evil-site.com/watch?v=abc")


def test_validate_url_rejects_empty():
    with pytest.raises(ValueError, match="empty"):
        validate_url("")


def test_validate_url_rejects_non_string():
    with pytest.raises(ValueError, match="string"):
        validate_url(123)  # type: ignore
