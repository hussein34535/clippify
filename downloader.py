"""
downloader.py — YouTube downloader helper for ClipAI
Downloads a video from YouTube using yt-dlp and returns its local path.
"""

import os
import yt_dlp

def download_youtube_video(url: str, output_dir: str, progress_callback=None) -> str:
    """
    Downloads a YouTube video at the best quality (or pre-merged MP4 format)
    and returns the local file path.
    
    :param url: The YouTube video URL
    :param output_dir: Directory where the video should be saved
    :param progress_callback: Optional callable with signature (percentage: int, status: str)
    :return: Absolute path of the downloaded video file
    """
    os.makedirs(output_dir, exist_ok=True)

    class MyLogger:
        def debug(self, msg):
            pass
        def warning(self, msg):
            pass
        def error(self, msg):
            pass

    def progress_hook(d):
        if d['status'] == 'downloading':
            total = d.get('total_bytes') or d.get('total_bytes_estimate') or 0
            downloaded = d.get('downloaded_bytes', 0)
            if total > 0:
                pct = int(downloaded / total * 100)
                if progress_callback:
                    progress_callback(pct, f"Downloading… {pct}%")
            else:
                # If we don't have total bytes, just show downloading
                if progress_callback:
                    progress_callback(50, "Downloading…")
        elif d['status'] == 'finished':
            if progress_callback:
                progress_callback(100, "Merging files & saving…")

    # ── Try to find FFmpeg path from imageio_ffmpeg ─────────────────────────
    try:
        import imageio_ffmpeg
        ffmpeg_path = imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        ffmpeg_path = None

    base_ydl_opts = {
        'format': 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best',
        'merge_output_format': 'mp4',
        'outtmpl': os.path.join(output_dir, '%(title)s.%(ext)s'),
        'logger': MyLogger(),
        'progress_hooks': [progress_hook],
        'nocheckcertificate': True,
        'quiet': True,
        'no_warnings': True,
    }
    if ffmpeg_path:
        base_ydl_opts['ffmpeg_location'] = ffmpeg_path

    # ── Check for a local cookies.txt file first ────────────────────────────
    app_dir = os.path.dirname(os.path.abspath(__file__))
    cookies_txt_path = os.path.join(app_dir, "cookies.txt")

    if os.path.exists(cookies_txt_path):
        try:
            ydl_opts = dict(base_ydl_opts)
            ydl_opts['cookiefile'] = cookies_txt_path
            
            try:
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(url, download=True)
                    filename = ydl.prepare_filename(info)
            except yt_dlp.utils.DownloadError as de:
                # If ffmpeg is missing, retry with best (pre-merged format which requires no merging)
                if 'ffmpeg' in str(de) or 'merging' in str(de) or 'merge' in str(de):
                    ydl_opts['format'] = 'best[ext=mp4]/best'
                    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                        info = ydl.extract_info(url, download=True)
                        filename = ydl.prepare_filename(info)
                else:
                    raise de

            # In case merging files changed the extension (e.g., to .mkv)
            if os.path.exists(filename):
                return os.path.abspath(filename)

            base, _ = os.path.splitext(filename)
            for ext in ['.mp4', '.mkv', '.webm', '.avi']:
                p = base + ext
                if os.path.exists(p):
                    return os.path.abspath(p)

            return os.path.abspath(filename)
        except Exception:
            # Fall back to standard browser search if cookies.txt fails
            pass

    browsers = ['chrome', 'edge', 'firefox', 'opera', 'brave', 'safari', None]
    last_error = None

    if progress_callback:
        progress_callback(5, "Contacting YouTube…")

    # ── Check if already downloaded ──────────────────────────────────────
    try:
        with yt_dlp.YoutubeDL({'quiet': True, 'no_warnings': True}) as ydl:
            info = ydl.extract_info(url, download=False)
        predicted = ydl.prepare_filename(info)
        base, _ = os.path.splitext(predicted)
        for ext in ['.mp4', '.mkv', '.webm', '.avi']:
            cached = base + ext
            if os.path.exists(cached):
                if progress_callback:
                    progress_callback(100, "Already downloaded!")
                return os.path.abspath(cached)
        cached = predicted
        if os.path.exists(cached):
            if progress_callback:
                progress_callback(100, "Already downloaded!")
            return os.path.abspath(cached)
    except Exception:
        pass

    if progress_callback:
        progress_callback(10, "Not cached — downloading…")

    for browser in browsers:
        try:
            ydl_opts = dict(base_ydl_opts)
            if browser:
                ydl_opts['cookiesfrombrowser'] = browser

            try:
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(url, download=True)
                    filename = ydl.prepare_filename(info)
            except yt_dlp.utils.DownloadError as de:
                # If ffmpeg is missing, retry with best (pre-merged format which requires no merging)
                if 'ffmpeg' in str(de) or 'merging' in str(de) or 'merge' in str(de):
                    ydl_opts['format'] = 'best[ext=mp4]/best'
                    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                        info = ydl.extract_info(url, download=True)
                        filename = ydl.prepare_filename(info)
                else:
                    raise de

            # In case merging files changed the extension (e.g., to .mkv)
            if os.path.exists(filename):
                return os.path.abspath(filename)

            base, _ = os.path.splitext(filename)
            for ext in ['.mp4', '.mkv', '.webm', '.avi']:
                p = base + ext
                if os.path.exists(p):
                    return os.path.abspath(p)

            return os.path.abspath(filename)
        except Exception as e:
            last_error = e
            # Try next browser
            continue

    if last_error:
        raise last_error
    raise Exception("Failed to download video from YouTube.")

