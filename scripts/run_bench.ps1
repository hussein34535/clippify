# scripts/run_bench.ps1 — SpeedProbe wrapper (PowerShell 5.1, no &&)
# Runs: python bench\bench.py --quick ; propagates exit code ; prints summary table from docs\BASELINE.json

$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root

& python bench\bench.py --quick
$code = $LASTEXITCODE

$jsonPath = Join-Path $root "docs\BASELINE.json"
if (-not (Test-Path -LiteralPath $jsonPath)) {
    Write-Host ""
    Write-Host "[run_bench] BASELINE.json NOT FOUND - bench run likely failed" -ForegroundColor Red
    exit $code
}

try {
    $j = Get-Content -Raw -LiteralPath $jsonPath | ConvertFrom-Json
} catch {
    Write-Host "[run_bench] BASELINE.json failed to parse: $_" -ForegroundColor Red
    exit $code
}

$t = $j.results.transcribe
$r = $j.results.render
$ai = $j.results.api_import_s

function Fmt($v) {
    if ($null -eq $v) { return "n/a".PadLeft(10) }
    return ("{0:N3}s" -f [double]$v).PadLeft(10)
}

Write-Host ""
Write-Host "==================== CLIPPIFY BASELINE ($($j.mode)) ====================" -ForegroundColor Cyan
Write-Host ("  {0,-24} {1}" -f "timestamp", $j.timestamp_iso)
if ($j.machine.gpu) { Write-Host ("  {0,-24} {1}" -f "gpu", $j.machine.gpu) }
Write-Host ("  {0,-24} {1}" -f "cpu_count", $j.machine.cpu_count)
Write-Host ""
Write-Host "  METRIC                        SECONDS"
Write-Host "  --------------------------------------"
Write-Host ("  {0,-30}{1}" -f "whisper tiny load",   (Fmt $t.tiny_load))
Write-Host ("  {0,-30}{1}" -f "whisper tiny run",    (Fmt $t.tiny_run))
Write-Host ("  {0,-30}{1}" -f "whisper base load",   (Fmt $t.base_load))
Write-Host ("  {0,-30}{1}" -f "whisper base run",    (Fmt $t.base_run))
Write-Host ("  {0,-30}{1}" -f "render x264 veryfast",(Fmt $r.x264_s))
Write-Host ("  {0,-30}{1}" -f "render h264_nvenc",   (Fmt $r.nvenc_s))
Write-Host ("  {0,-30}{1}" -f "render h264_qsv",     (Fmt $r.qsv_s))
Write-Host ("  {0,-30}{1}" -f "import api (cold)",   (Fmt $ai))
Write-Host ""

if ($j.notes.Count -gt 0) {
    Write-Host "  NOTES:" -ForegroundColor Yellow
    foreach ($n in $j.notes) { Write-Host "   - $n" }
    Write-Host ""
}

if ($code -eq 0) {
    Write-Host "[run_bench] PASS (core metrics present)" -ForegroundColor Green
} else {
    Write-Host "[run_bench] FAIL (exit $code from bench.py)" -ForegroundColor Red
}
exit $code
