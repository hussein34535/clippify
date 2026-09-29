# fetch_fonts.ps1 - Squad-B0 [TokenSmith]
# Downloads OFL-licensed variable TTFs from google/fonts (GitHub raw).
# FAIL-SAFE: on network failure, writes a placeholder note and exits 2
# so the pipeline stops gracefully instead of fabricating binaries.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root     = Split-Path -Parent $PSScriptRoot
$fontsDir = Join-Path $root 'assets\fonts'
if (-not (Test-Path -LiteralPath $fontsDir)) {
    New-Item -ItemType Directory -Path $fontsDir -Force | Out-Null
}

# UA header required by some CDNs / avoids GitHub raw blocking default PS UA
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) TokenSmith-font-fetcher/1.0'

$targets = @(
    @{
        Url  = 'https://github.com/google/fonts/raw/main/ofl/cairo/Cairo%5Bslnt%2Cwght%5D.ttf'
        Dest = Join-Path $fontsDir 'Cairo-Variable.ttf'
    },
    @{
        Url  = 'https://github.com/google/fonts/raw/main/ofl/rubik/Rubik%5Bwght%5D.ttf'
        Dest = Join-Path $fontsDir 'Rubik-Variable.ttf'
    }
)

$failed = $false
foreach ($t in $targets) {
    try {
        Write-Host ("Downloading {0} ..." -f $t.Dest)
        Invoke-WebRequest -Uri $t.Url -OutFile $t.Dest -UserAgent $ua -UseBasicParsing
        $len = (Get-Item -LiteralPath $t.Dest).Length
        Write-Host ("OK  {0} ({1:N0} bytes)" -f $t.Dest, $len)
        if ($len -lt 81920) {
            Write-Warning ("File smaller than 80KB - may be an error page: " + $t.Dest)
            $failed = $true
        }
    }
    catch {
        Write-Warning ("FAILED: " + $t.Url + " -> " + $_.Exception.Message)
        $failed = $true
    }
}

if ($failed) {
    $notePath = Join-Path $fontsDir 'FONTS_PLACEHOLDER.md'
    $noteLines = @(
        '# Fonts placeholder note',
        '',
        'Font download failed (network blocked or URL unreachable).',
        'No binaries were fabricated. To fix manually:',
        '',
        '1. Download Cairo variable font:',
        '   https://github.com/google/fonts/raw/main/ofl/cairo/Cairo[slnt,wght].ttf',
        '   Save as: assets/fonts/Cairo-Variable.ttf',
        '2. Download Rubik variable font:',
        '   https://github.com/google/fonts/raw/main/ofl/rubik/Rubik[wght].ttf',
        '   Save as: assets/fonts/Rubik-Variable.ttf',
        '3. Re-run: powershell -ExecutionPolicy Bypass -File scripts/fetch_fonts.ps1',
        '4. Then: flutter pub get',
        '',
        'Both fonts are SIL Open Font License 1.1.'
    )
    Set-Content -LiteralPath $notePath -Value $noteLines -Encoding UTF8
    Write-Host ("BLOCKED: wrote " + $notePath + " - stopping gracefully.")
    exit 2
}

Write-Host "All fonts fetched successfully."
exit 0
