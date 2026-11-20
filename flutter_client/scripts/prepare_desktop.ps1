# Bundles the imageio-ffmpeg binary next to the built exe so the app runs
# fully standalone (thumbnails, AutoCut, demo video — no backend, no PATH).
# Usage: powershell scripts\prepare_desktop.ps1 [-Configuration Release]

param(
    [string]$Configuration = "Release",
    [string]$FfmpegPath,
    [string]$EnginePath,
    [string]$WhisperDirectory = "$PSScriptRoot/../build/short-asr/Release",
    [string]$WhisperModel = "$PSScriptRoot/../build/short-asr/ggml-small-q5_1.bin"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot   # flutter_client/
$dest = Join-Path $root "build\windows\x64\runner\$Configuration"
$project = Split-Path -Parent $root
if (-not (Test-Path -LiteralPath $dest -PathType Container)) {
    throw "Build Flutter for Windows first: $dest"
}
if (-not $EnginePath) {
    $EnginePath = Join-Path $project 'engine\target\release\clippify_engine.exe'
}
if (-not $FfmpegPath) {
    $FfmpegPath = python -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())"
}
if (-not $FfmpegPath -or -not (Test-Path -LiteralPath $FfmpegPath -PathType Leaf)) {
    throw "FFmpeg was not found; supply -FfmpegPath."
}
if (-not (Test-Path -LiteralPath $EnginePath -PathType Leaf)) {
    throw "The Rust engine was not found; run cargo build --release --locked in engine."
}

Copy-Item -LiteralPath $FfmpegPath -Destination (Join-Path $dest 'ffmpeg.exe') -Force
Copy-Item -LiteralPath $EnginePath -Destination (Join-Path $dest 'clippify_engine.exe') -Force
Write-Host "[prepare] bundled ffmpeg.exe and clippify_engine.exe -> $dest"

$whisperExe = Join-Path $WhisperDirectory 'whisper-cli.exe'
if ((Test-Path -LiteralPath $whisperExe -PathType Leaf) -and
    (Test-Path -LiteralPath $WhisperModel -PathType Leaf)) {
    $asr = New-Item -ItemType Directory -Force (Join-Path $dest 'short-asr')
    Copy-Item -LiteralPath $whisperExe -Destination $asr.FullName -Force
    Get-ChildItem -LiteralPath $WhisperDirectory -Filter '*.dll' -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $asr.FullName -Force
    }
    Copy-Item -LiteralPath $WhisperModel -Destination (Join-Path $asr.FullName 'ggml-small-q5_1.bin') -Force
    $vad = Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $WhisperModel).Path) 'ggml-silero-v6.2.0.bin'
    if (Test-Path -LiteralPath $vad -PathType Leaf) {
        Copy-Item -LiteralPath $vad -Destination $asr.FullName -Force
    }
    Write-Host "[prepare] bundled local Whisper transcription -> $($asr.FullName)"
}
