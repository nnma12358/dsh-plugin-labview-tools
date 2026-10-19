param(
  [string]$ProcName = "LabVIEW",
  [string]$TitleLike = "",
  [int]$Win = 0,
  [string]$Out = (Join-Path $env:TEMP "lv_pw.png"),
  [switch]$List
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class LvP {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowDC(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hdc);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public class W { public IntPtr H; public string Cls; public string Title; public RECT R; public long Area; }
  public static List<W> All = new List<W>();
  public static void Enumerate(uint pid0) {
    All = new List<W>();
    EnumWindows((h,l) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid != pid0) return true;
      if (!IsWindowVisible(h)) return true;
      RECT r; GetWindowRect(h, out r);
      long w=r.Right-r.Left, ht=r.Bottom-r.Top;
      if (w<=0||ht<=0) return true;
      var c=new StringBuilder(256); GetClassNameW(h,c,256);
      var t=new StringBuilder(512); GetWindowTextW(h,t,512);
      All.Add(new W{H=h, Cls=c.ToString(), Title=t.ToString(), R=r, Area=w*ht});
      return true;
    }, IntPtr.Zero);
    All.Sort((a,b)=>b.Area.CompareTo(a.Area));
  }
}
"@
[void][LvP]::SetProcessDPIAware()
Add-Type -AssemblyName System.Drawing

$p = Get-Process -Name $ProcName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { Write-Output "no process $ProcName"; exit 1 }
[LvP]::Enumerate([uint32]$p.Id)

if ($List) {
  for ($i=0; $i -lt [LvP]::All.Count; $i++) {
    $w = [LvP]::All[$i]
    Write-Output ("[$i] $($w.R.Left),$($w.R.Top),$($w.R.Right-$w.R.Left)x$($w.R.Bottom-$w.R.Top) '$($w.Cls)' title='$($w.Title)'")
  }
  exit 0
}

$t = $null
if ($TitleLike -ne "") { $t = [LvP]::All | Where-Object { $_.Title -like $TitleLike } | Select-Object -First 1 }
else { if ($Win -lt [LvP]::All.Count) { $t = [LvP]::All[$Win] } }
if (-not $t) { Write-Output "no matching window"; exit 1 }

$w = $t.R.Right - $t.R.Left; $h = $t.R.Bottom - $t.R.Top
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [LvP]::PrintWindow($t.H, $hdc, 2)   # 2 = PW_RENDERFULLCONTENT
$g.ReleaseHdc($hdc)
$g.Dispose()
$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output ("PrintWindow=$ok  title='$($t.Title)'  rect=$($t.R.Left),$($t.R.Top),${w}x${h}  saved=$Out")
$bmp.Dispose()
