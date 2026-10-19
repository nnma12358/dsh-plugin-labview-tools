param(
  [string]$Out = (Join-Path $env:TEMP "lv_shot.png"),
  [int]$MaxWidth = 1600
)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap($vs.Width, $vs.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($vs.Left, $vs.Top, 0, 0, $bmp.Size)
$g.Dispose()

# downscale if wider than MaxWidth so the image stays cheap to read
if ($bmp.Width -gt $MaxWidth) {
  $ratio = $MaxWidth / $bmp.Width
  $nw = [int]($bmp.Width * $ratio)
  $nh = [int]($bmp.Height * $ratio)
  $small = New-Object System.Drawing.Bitmap($nw, $nh)
  $g2 = [System.Drawing.Graphics]::FromImage($small)
  $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g2.DrawImage($bmp, 0, 0, $nw, $nh)
  $g2.Dispose()
  $bmp.Dispose()
  $bmp = $small
}

$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output ("saved=" + $Out)
Write-Output ("size=" + $bmp.Width + "x" + $bmp.Height)
$bmp.Dispose()
