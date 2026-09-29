# Bundles the imageio-ffmpeg binary next to the built exe so the app runs
# fully standalone (thumbnails, AutoCut, demo video — no backend, no PATH).
# Usage: powershell scripts\prepare_desktop.ps1 [-Configuration Release]

param([string]$Configuration = "Release")

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot   # flutter_client/
$dest = Join-Path $root "build\windows\x64\runner\$Configuration"

$ff = python -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())"
if (-not (Test-Path $ff)) { Write-Error "imageio ffmpeg not found"; exit 1 }

Copy-Item $ff (Join-Path $dest "ffmpeg.exe") -Force
Write-Host "[prepare] bundled ffmpeg.exe -> $dest ($([math]::Round((Get-Item (Join-Path $dest 'ffmpeg.exe')).Length/1MB,1)) MB)"
