import os
import sys
import math
import subprocess
from pydub import AudioSegment

# Define cache and output paths
CACHE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cache", "audio")
os.makedirs(CACHE_DIR, exist_ok=True)

# Configure pydub and resolve ffmpeg binary path
FFMPEG_PATH = "ffmpeg"
FFPROBE_PATH = "ffprobe"
try:
    import imageio_ffmpeg
    ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()
    FFMPEG_PATH = ffmpeg_exe
    # pydub settings
    AudioSegment.converter = ffmpeg_exe
    AudioSegment.ffmpeg = ffmpeg_exe
    
    # Resolve ffprobe path next to ffmpeg
    ffprobe_exe = ffmpeg_exe.replace("ffmpeg", "ffprobe")
    if os.path.exists(ffprobe_exe):
        FFPROBE_PATH = ffprobe_exe
        AudioSegment.ffprobe = ffprobe_exe
    elif os.path.exists(ffmpeg_exe.replace("ffmpeg.exe", "ffprobe.exe")):
        FFPROBE_PATH = ffmpeg_exe.replace("ffmpeg.exe", "ffprobe.exe")
        AudioSegment.ffprobe = FFPROBE_PATH
    print(f"  [AUDIO INTEL] Resolved bundled FFmpeg: {FFMPEG_PATH}")
except Exception as e:
    print(f"  [AUDIO INTEL WARNING] imageio_ffmpeg check failed: {e}")

def separate_audio_tracks(media_path: str) -> dict:
    """
    Separates speech (vocals) and background music/noise from a video or audio file.
    Uses Meta's Demucs model locally via command line subprocess.
    Returns paths to separated vocal and no-vocal audio tracks.
    """
    if not os.path.exists(media_path):
        raise FileNotFoundError(f"Source media not found: {media_path}")

    # Generate deterministic output filename based on file size and path
    base_name = os.path.splitext(os.path.basename(media_path))[0]
    output_vocal = os.path.join(CACHE_DIR, f"{base_name}_vocals.wav")
    output_background = os.path.join(CACHE_DIR, f"{base_name}_background.wav")

    # If already computed, return cached paths
    if os.path.exists(output_vocal) and os.path.exists(output_background):
        print(f"  [AUDIO INTEL] Using cached separated tracks for: {base_name}")
        return {"vocals": output_vocal, "background": output_background}

    print(f"  [AUDIO INTEL] Launching Demucs for: {base_name}...")
    
    # We will try to run demucs as a subprocess
    # Command: demucs --two-stems vocals -o [out_dir] [file]
    temp_out_dir = os.path.join(CACHE_DIR, "demucs_temp")
    os.makedirs(temp_out_dir, exist_ok=True)

    # Use CPU or GPU based on torch/demucs detection
    # Run Demucs in non-interactive background process
    cmd = [
        sys.executable, "-m", "demucs.cli",
        "--two-stems", "vocals",
        "-o", temp_out_dir,
        media_path
    ]

    try:
        # Check if demucs package is installed, if not, we try direct subprocess cmd or fallback
        import demucs
        print("  [AUDIO INTEL] Demucs library detected. Starting extraction...")
        
        result = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=300)
        print("  [AUDIO INTEL] Demucs process finished successfully.")
        
        # Locate the output files. Demucs creates subdirectories like: temp_out_dir/htdemucs/filename/vocals.wav
        model_dir = os.path.join(temp_out_dir, "htdemucs", base_name)
        if not os.path.exists(model_dir):
            # Try to search for vocals.wav in temp_out_dir recursively
            found_v = False
            for root, dirs, files in os.walk(temp_out_dir):
                if "vocals.wav" in files:
                    model_dir = root
                    found_v = True
                    break
            if not found_v:
                raise FileNotFoundError("Demucs output directory/files not found.")

        src_vocals = os.path.join(model_dir, "vocals.wav")
        src_no_vocals = os.path.join(model_dir, "no_vocals.wav")

        # Copy to cache directory with friendly names
        import shutil
        shutil.copy2(src_vocals, output_vocal)
        shutil.copy2(src_no_vocals, output_background)

        # Cleanup temp dir
        shutil.rmtree(temp_out_dir, ignore_errors=True)

        return {"vocals": output_vocal, "background": output_background}

    except (ImportError, subprocess.SubprocessError, FileNotFoundError) as e:
        print(f"  [AUDIO INTEL WARNING] Demucs extraction failed or not installed: {e}")
        print("  [AUDIO INTEL] Falling back to a lightweight heuristic-based vocal/bg split (highpass/lowpass filters)...")
        
        # Fast Heuristic Fallback:
        # In a real system, if Demucs is not installed, we can fall back to frequency-based splitting using FFmpeg:
        # Vocals: keep mid frequencies (human voice 300Hz - 3400Hz)
        # Background: cut mid frequencies or output raw file as fallback background
        try:
            # Simple fallback using ffmpeg to separate vocals (bandpass filter) and music
            # Vocals bandpass: 200Hz to 4000Hz
            ffmpeg_v_cmd = [
                FFMPEG_PATH, "-y", "-i", media_path,
                "-af", "bandpass=f=1500:width_type=h:w=3000",
                output_vocal
            ]
            # Background bandreject: cut vocals frequency or just copy original audio as fallback bg
            ffmpeg_bg_cmd = [
                FFMPEG_PATH, "-y", "-i", media_path,
                "-af", "bandreject=f=1500:width_type=h:w=2000",
                output_background
            ]
            
            # Run highpass/lowpass filters via ffmpeg
            subprocess.run(ffmpeg_v_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            subprocess.run(ffmpeg_bg_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            
            print("  [AUDIO INTEL] Heuristic fallback vocal separation completed successfully using FFmpeg filters.")
            return {"vocals": output_vocal, "background": output_background}
        except Exception as ex:
            print(f"  [AUDIO INTEL ERROR] FFmpeg fallback separation also failed: {ex}")
            # Absolute fallback: duplicate audio as both vocals and background to avoid crashing
            try:
                sound = AudioSegment.from_file(media_path)
                sound.export(output_vocal, format="wav")
                sound.export(output_background, format="wav")
                return {"vocals": output_vocal, "background": output_background}
            except Exception as final_ex:
                raise RuntimeError(f"All audio separation attempts failed: {final_ex}")


def apply_auto_ducking(vocals_path: str, background_path: str, output_path: str, duck_factor: float = 0.2, words: list = None) -> str:
    """
    Applies real-time Auto-Ducking on background music whenever speech is active.
    `duck_factor` represents the volume scale of background music during speech (e.g. 0.15 = 15%).
    Uses Pydub for precise timing transitions (fades) and mix.
    """
    if not os.path.exists(vocals_path) or not os.path.exists(background_path):
        raise FileNotFoundError("Vocal or background audio track is missing.")

    print(f"  [AUDIO INTEL] Applying Auto-Ducking (factor={duck_factor})...")

    # Load audio files
    vocals = AudioSegment.from_file(vocals_path)
    background = AudioSegment.from_file(background_path)

    # Ensure they are the same length
    duration_ms = min(len(vocals), len(background))
    vocals = vocals[:duration_ms]
    background = background[:duration_ms]

    # Convert word timestamps to speech segments in ms
    speech_segments = []
    if words:
        sorted_words = sorted(words, key=lambda w: w.get('start', 0))
        current_segment = None
        
        for w in sorted_words:
            start_ms = int(w.get('start', 0) * 1000)
            end_ms = int(w.get('end', 0) * 1000)
            
            if current_segment is None:
                current_segment = [start_ms, end_ms]
            else:
                # Merge if the gap between speech is less than 600ms
                if start_ms - current_segment[1] < 600:
                    current_segment[1] = end_ms
                else:
                    speech_segments.append(current_segment)
                    current_segment = [start_ms, end_ms]
        if current_segment:
            speech_segments.append(current_segment)
    else:
        # Heuristic fallback: check RMS energy to detect speech periods
        chunk_size = 150 # ms
        is_speech = False
        speech_start = 0
        
        for i in range(0, duration_ms, chunk_size):
            chunk = vocals[i : i + chunk_size]
            # Simple threshold for speech detection in vocals track
            if chunk.rms > 600:
                if not is_speech:
                    speech_start = i
                    is_speech = True
            else:
                if is_speech:
                    speech_segments.append([speech_start, i])
                    is_speech = False
        if is_speech:
            speech_segments.append([speech_start, duration_ms])

    # Convert volume ratio to dB
    if duck_factor <= 0.001:
        db_reduction = -60.0 # Silent
    else:
        db_reduction = 20.0 * math.log10(duck_factor)

    # Reconstruct the background track with ducking applied
    ducked_background = AudioSegment.silent(duration=0)
    last_idx = 0
    fade_ms = 150 # Smooth fade in/out transition

    for start, end in speech_segments:
        if start >= duration_ms:
            break
        end = min(end, duration_ms)

        # 1. Background section before speech starts (Normal volume)
        if start > last_idx:
            non_speech_part = background[last_idx:start]
            ducked_background += non_speech_part

        # 2. Background section during speech (Ducked volume)
        speech_part = background[start:end]
        ducked_part = speech_part + db_reduction

        # Append with a smooth transition (crossfade)
        if len(ducked_background) > 0:
            ducked_background = ducked_background.append(ducked_part, crossfade=fade_ms)
        else:
            ducked_background += ducked_part

        last_idx = end

    # Add any remaining background music at normal volume
    if last_idx < duration_ms:
        remaining_part = background[last_idx:]
        if len(ducked_background) > 0:
            ducked_background = ducked_background.append(remaining_part, crossfade=fade_ms)
        else:
            ducked_background += remaining_part

    # Mix vocals and ducked background together
    final_mix = ducked_background.overlay(vocals)

    # Save output file (export to MP3 or WAV)
    final_mix.export(output_path, format="mp3", bitrate="192k")
    print(f"  [AUDIO INTEL] Auto-Ducking applied successfully. Exported to: {output_path}")
    return output_path
