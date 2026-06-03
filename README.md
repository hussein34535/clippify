# 🎬 ClipAI — Local Video Clipper + YouTube Uploader

> Automatically extract the best short vertical clips (9:16) from any long video,
> then upload them to YouTube — **100% offline processing, no AI APIs, no cloud costs.**

---

## How it works

```
Audio waveform → RMS energy per 0.5s window → Normalise → Peak detection → Clip windows → Export → YouTube
```

| Stage | Module | Description |
|---|---|---|
| Extract | `audio.py` | Pull audio as mono 16kHz WAV via moviepy |
| Analyse | `audio.py` | Compute RMS energy per 0.5s window, normalise 0→1 |
| Detect | `detector.py` | Smooth curve, find peaks, remove overlaps |
| Export | `editor.py` | Cut → 9:16 crop → caption bar → mp4 |
| Upload | `uploader.py` | OAuth2 → YouTube API v3 resumable upload |

---

## Requirements

### System
- **Python 3.9+**
- **ffmpeg** — must be installed separately:
  - Windows: `choco install ffmpeg` or download from https://ffmpeg.org/download.html
  - macOS: `brew install ffmpeg`
  - Linux: `sudo apt install ffmpeg`

### Python packages
```bash
pip install -r requirements.txt
```

---

## Desktop App

```bash
python app.py
```

### Features
- 🎬 Drop or browse any video file
- ⚡ Sliders for clip count (1–10) and duration (15–120s)
- 📊 Real-time progress bar
- ✅ Results list with timestamps
- 📁 Open output folder button
- ☀/🌙 Dark/Light mode toggle
- 📤 **Auto-upload to YouTube** (see setup below)

---

## 🎯 Settings Guide — Best Settings Per Video Type

> ClipAI uses **audio energy** to detect the best moments.
> Different content types have very different energy patterns — use this guide to get the best results.

---

### 📻 Podcast / Talk Show

Long conversations between 2–3 people. Energy spikes happen at debates, laughs, surprising facts.

| Setting | Recommended | Reason |
|---|---|---|
| **Clips** | 5–8 | Podcasts have many good moments |
| **Duration** | 45–90s | Enough to capture the full thought |
| **Best moments** | Debate, reaction, storytelling peaks |

```bash
python clipper.py --video podcast.mp4 --clips 6 --duration 60
```

---

### 🎓 Lecture / Educational Video

One speaker, steady pace. Energy peaks mark key points, definitions, or examples.

| Setting | Recommended | Reason |
|---|---|---|
| **Clips** | 3–5 | Fewer but denser information moments |
| **Duration** | 30–60s | One concept per clip |
| **Best moments** | "The key idea is…", formula explanations |

```bash
python clipper.py --video lecture.mp4 --clips 4 --duration 45
```

---

### 🎤 Interview (YouTube / News)

Q&A format. Good clips = strong answers or emotional reactions.

| Setting | Recommended | Reason |
|---|---|---|
| **Clips** | 4–6 | Each answer = one clip |
| **Duration** | 30–60s | Short punchy answers work best for Shorts |
| **Best moments** | Direct answers, personal stories |

```bash
python clipper.py --video interview.mp4 --clips 5 --duration 40
```

---

### 🎮 Gaming / Reaction Video

Very dynamic audio — spikes everywhere. High energy = hype moments.

| Setting | Recommended | Reason |
|---|---|---|
| **Clips** | 5–10 | Lots of good moments |
| **Duration** | 15–30s | Short clips = more viral potential |
| **Best moments** | Clutch plays, wins, jump scares |

```bash
python clipper.py --video gameplay.mp4 --clips 8 --duration 20
```

---

### 🏋️ Motivational Speech / TED Talk

One speaker, strong emotional peaks. Best moments = call to action, key quotes.

| Setting | Recommended | Reason |
|---|---|---|
| **Clips** | 3–5 | Only the strongest moments |
| **Duration** | 30–60s | One powerful idea per clip |
| **Best moments** | "This is why…", emotional crescendos |

```bash
python clipper.py --video tedtalk.mp4 --clips 4 --duration 50
```

---

### 🎵 Music / Concert / Performance

Audio energy is very high throughout. Look for peak moments: drops, solos, choruses.

| Setting | Recommended | Reason |
|---|---|---|
| **Clips** | 3–6 | Highlight best musical moments |
| **Duration** | 30–60s | Enough to feel the vibe |
| **Best moments** | Drop, chorus, key change, crowd reaction |

```bash
python clipper.py --video concert.mp4 --clips 4 --duration 45
```

---

### ⚠️ When results are not great

| Problem | Solution |
|---|---|
| All clips look the same | Reduce `--clips`, the video has few truly "peak" moments |
| Clips cut off mid-sentence | Increase `--duration` by 15–20s |
| Clips start with silence | The energy window is correct — it starts just before the peak, this is normal |
| Too many similar clips | Reduce `--clips` to 3 and use longer duration |
| Video is mostly quiet/music-only | ClipAI works best on speech; evenly-spaced clips will be used instead |

---

## YouTube Upload Setup (one-time, ~5 minutes)

> [!NOTE]
> You only need to do this once. After the first login, a `token.json` is saved
> and you never need to log in again.

### Steps

**1. Go to Google Cloud Console**
```
https://console.cloud.google.com
```

**2. Create a new project**
- Click the project dropdown (top-left) → "New Project"
- Name it `ClipAI` → Create

**3. Enable YouTube Data API v3**
- APIs & Services → Enable APIs & Services
- Search: `YouTube Data API v3` → Enable

**4. Create OAuth 2.0 credentials**
- APIs & Services → Credentials → Create Credentials → OAuth 2.0 Client ID
- Application type: **Desktop App**
- Name: `ClipAI` → Create

**5. Download & rename**
- Click the download icon (⬇) next to your new credential
- Rename the file to: **`client_secrets.json`**

**6. Place the file**
```
clipai/
├── app.py
├── client_secrets.json   ← put it here
└── ...
```

**7. First upload**
- Generate clips in the app
- YouTube section appears → pick privacy → click "Upload All Clips to YouTube"
- Browser opens → log in with your Google account → done
- `token.json` is saved automatically for future sessions

---

## CLI Usage

```bash
# Basic — 5 clips of 60 seconds each
python clipper.py --video podcast.mp4

# Custom
python clipper.py --video interview.mp4 --clips 3 --duration 30 --output my_clips/
```

### Arguments

| Argument | Default | Description |
|---|---|---|
| `--video` | *(required)* | Path to the input video file |
| `--clips` | `5` | Number of clips to generate |
| `--duration` | `60` | Duration of each clip in seconds |
| `--output` | `./output` | Output folder for clips |

---

## File Structure

```
clipai/
├── clipper.py            CLI entry point
├── audio.py              Audio extraction + RMS energy analysis
├── detector.py           Peak detection + overlap removal
├── editor.py             Cutting + 9:16 crop + caption + export
├── uploader.py           YouTube OAuth2 + resumable upload
├── app.py                Desktop GUI (CustomTkinter)
├── requirements.txt      Python dependencies
├── client_secrets.json   [YOU ADD THIS] Google OAuth credentials
├── token.json            [AUTO-GENERATED] Saved login token
└── output/               Generated clips land here
```

---

## Edge Cases Handled

| Situation | Behaviour |
|---|---|
| Video shorter than `--duration` | Exports the entire video as one clip |
| No audio track | Creates evenly-spaced clips |
| Caption fails (Windows) | Skips caption, still exports video |
| `client_secrets.json` missing | Shows step-by-step popup with instructions |
| Token expired | Silent auto-refresh; re-auth if that fails |
| No internet during upload | Shows error per clip, continues with the rest |
| Google packages not installed | Friendly error with pip install command |
| pyperclip unavailable | Falls back to tkinter clipboard |
