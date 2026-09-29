#Requires -Version 5.1
<#
.SYNOPSIS
  Generates assets/icon/icon.png (1024x1024) for Clippify store builds.
.DESCRIPTION
  Diagonal gradient #7C3AED -> #4F46E5, centered white bold "C"
  (Segoe UI, ~55% height), subtle semi-transparent white play-triangle
  accent bottom-right. Launcher masks handle rounded corners.
#>
param(
    [string]$OutPath = (Join-Path $PSScriptRoot "..\assets\icon\icon.png"),
    [int]$Size = 1024
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$dir = Split-Path -Parent $OutPath
if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

$bmp = New-Object System.Drawing.Bitmap($Size, $Size)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode   = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

try {
    # ---- Background: diagonal gradient #7C3AED -> #4F46E5 ----
    $c1 = [System.Drawing.ColorTranslator]::FromHtml('#7C3AED')
    $c2 = [System.Drawing.ColorTranslator]::FromHtml('#4F46E5')
    $rect  = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                 $rect, $c1, $c2,
                 [System.Drawing.Drawing2D.LinearGradientMode]::Diagonal)
    try     { $g.FillRectangle($brush, $rect) }
    finally { $brush.Dispose() }

    # ---- Centered white bold "C" (~55% height) ----
    $family = New-Object System.Drawing.FontFamily('Segoe UI')
    $emSize = $Size * 0.55
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    try {
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment     = [System.Drawing.StringAlignment]::Center
        $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
        # slight optical lift: cap-height sits above the em-box center
        $layout = New-Object System.Drawing.RectangleF(0, ($Size * -0.03), $Size, $Size)
        $path.AddString('C', $family,
                        [int][System.Drawing.FontStyle]::Bold,
                        $emSize, $layout, $fmt)
        $g.FillPath([System.Drawing.Brushes]::White, $path)
    } finally { $path.Dispose(); $family.Dispose() }

    # ---- Subtle play-triangle accent, bottom-right ----
    $t  = $Size * 0.16   # triangle bounds
    $m  = $Size * 0.09   # corner margin
    $x0 = $Size - $m - $t
    $y0 = $Size - $m - $t
    $softWhite = [System.Drawing.Color]::FromArgb(80, 255, 255, 255)
    $triBrush  = New-Object System.Drawing.SolidBrush($softWhite)
    try {
        $pts = [System.Drawing.PointF[]](
            (New-Object System.Drawing.PointF(($x0 + $t * 0.22), ($y0 + $t * 0.12))),
            (New-Object System.Drawing.PointF(($x0 + $t * 0.22), ($y0 + $t * 0.88))),
            (New-Object System.Drawing.PointF(($x0 + $t * 0.88), ($y0 + $t * 0.50)))
        )
        $g.FillPolygon($triBrush, $pts)
    } finally { $triBrush.Dispose() }
} finally {
    $g.Dispose()
}

$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

$item = Get-Item -LiteralPath $OutPath
Write-Host ("ICON OK  {0}  ({1:N0} bytes)" -f $item.FullName, $item.Length)
if ($item.Length -lt 20KB) {
    throw "icon.png is smaller than 20KB ($($item.Length) bytes)"
}
