[CmdletBinding()]
param(
    [string]$EnginePath = "$PSScriptRoot/../../engine/target/release/clippify_engine.exe",
    [string]$FfmpegPath = "$PSScriptRoot/../../engine/target/release/ffmpeg.exe",
    [string]$WhisperPath = "$PSScriptRoot/../build/short-asr/Release/whisper-cli.exe",
    [string]$WhisperModel = "$PSScriptRoot/../build/short-asr/ggml-small-q5_1.bin",
    [string]$BaseUrl = 'https://coarena.ai/api/v1',
    [string]$Model = 'deepseek-v4-1-flash-1017',
    [switch]$WithAi,
    [switch]$WithVision
)

$ErrorActionPreference = 'Stop'
$session = New-Item -ItemType Directory -Force "$PSScriptRoot/../build/mobile-engine-session"
$start = [System.Diagnostics.ProcessStartInfo]::new()
$start.FileName = (Resolve-Path -LiteralPath $EnginePath).Path
$start.WorkingDirectory = $session.FullName
$start.Arguments = 'serve --port 8768 --local-short --mobile-upload'
$start.UseShellExecute = $false
$start.EnvironmentVariables['CLIPPIFY_FFMPEG'] = (Resolve-Path -LiteralPath $FfmpegPath).Path
$start.EnvironmentVariables['CLIPPIFY_SHORT_TEAMSOCLO_KEY'] = ''
$start.EnvironmentVariables['CLIPPIFY_SHORT_AI_BASE_URL'] = $BaseUrl
$start.EnvironmentVariables['CLIPPIFY_SHORT_TEAMSOCLO_MODEL'] = $Model
$start.EnvironmentVariables['CLIPPIFY_SHORT_AI_VISION'] = if ($WithAi -and $WithVision) { '1' } else { '' }
if ((Test-Path -LiteralPath $WhisperPath -PathType Leaf) -and
    (Test-Path -LiteralPath $WhisperModel -PathType Leaf)) {
    $start.EnvironmentVariables['CLIPPIFY_WHISPER_EXE'] = (Resolve-Path -LiteralPath $WhisperPath).Path
    $start.EnvironmentVariables['WHISPER_MODEL_PATH'] = (Resolve-Path -LiteralPath $WhisperModel).Path
}

$secret = $null
$engine = $null
try {
    if ($WithAi) {
        $secret = Read-Host 'AI API key (hidden, for this session only)' -AsSecureString
        $start.EnvironmentVariables['CLIPPIFY_SHORT_TEAMSOCLO_KEY'] = [System.Net.NetworkCredential]::new('', $secret).Password
    }
    $engine = [System.Diagnostics.Process]::Start($start)
} finally {
    $start.EnvironmentVariables['CLIPPIFY_SHORT_TEAMSOCLO_KEY'] = ''
    if ($null -ne $secret) { $secret.Dispose() }
}

try {
    while (-not $engine.WaitForExit(500)) { }
    if ($engine.ExitCode -ne 0) { throw "Short Engine exited with code $($engine.ExitCode)." }
} finally {
    if (-not $engine.HasExited) { $engine.Kill() }
    $engine.Dispose()
}
