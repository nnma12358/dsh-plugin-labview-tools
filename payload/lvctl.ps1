param(
  [string]$ProcName = "LabVIEW",
  [switch]$List,
  [int]$Win = -1,                 # index from -List (default: largest visible)
  [string]$TitleLike = "",
  [switch]$Full,                  # capture whole desktop (image coords == screen coords)
  [int]$X = -1,
  [int]$Y = -1,
  [string]$Click = "",            # left | right | double
  [string]$Keys = "",
  [string]$Type = "",
  [string]$PasteText = "",        # set clipboard then Ctrl+V (bypasses the IME)
  [string]$Out = (Join-Path $env:TEMP "lv_win.png"),
  [switch]$NoFocus,
  [switch]$NoCapture,
  [switch]$Maximize,
  [int]$MaxWidth = 2400,
  [int]$SettleMs = 700
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

if (-not ("LvWin" -as [type])) {
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class LvWin {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int n);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  [DllImport("user32.dll")] public static extern bool SwitchToThisWindow(IntPtr h, bool altTab);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static readonly IntPtr HWND_TOP = IntPtr.Zero;
  public const uint SWP_NOSIZE=0x0001, SWP_NOMOVE=0x0002, SWP_SHOWWINDOW=0x0040;
  public const uint LEFTDOWN=0x0002, LEFTUP=0x0004, RIGHTDOWN=0x0008, RIGHTUP=0x0010;
  public const byte VK_MENU = 0x12;
  public const byte VK_ESCAPE = 0x1B;

  public class W { public IntPtr H; public string Cls; public string Title; public RECT R; public long Area; }
  public static List<W> All = new List<W>();
  public static void Enumerate(uint pid0) {
    All = new List<W>();
    EnumWindows((h,l) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid != pid0) return true;
      if (!IsWindowVisible(h)) return true;
      RECT r; GetWindowRect(h, out r);
      long w = r.Right-r.Left, ht = r.Bottom-r.Top;
      if (w<=0||ht<=0) return true;
      var c=new StringBuilder(256); GetClassNameW(h,c,256);
      var t=new StringBuilder(512); GetWindowTextW(h,t,512);
      All.Add(new W{H=h, Cls=c.ToString(), Title=t.ToString(), R=r, Area=w*ht});
      return true;
    }, IntPtr.Zero);
    All.Sort((a,b) => b.Area.CompareTo(a.Area));
  }
  public static bool IsForeground(IntPtr h){ return GetForegroundWindow()==h; }
  public static void Focus(IntPtr h) {
    if (IsIconic(h)) ShowWindow(h, 9);
    for (int i=0;i<8;i++){
      if (GetForegroundWindow()==h) return;
      var fg=GetForegroundWindow(); uint fpid=0;
      var fgt=GetWindowThreadProcessId(fg, out fpid);
      var my=GetCurrentThreadId();
      AttachThreadInput(my,fgt,true);
      keybd_event(VK_MENU,0,0,IntPtr.Zero);
      BringWindowToTop(h);
      SetWindowPos(h,HWND_TOP,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW);
      SetForegroundWindow(h);
      keybd_event(VK_MENU,0,2,IntPtr.Zero);
      AttachThreadInput(my,fgt,false);
      if (GetForegroundWindow()!=h) SwitchToThisWindow(h,true);
      // The synthetic Alt press/release activates the target's menu bar in some
      // apps (LabVIEW included). Clear that state or later keystrokes get eaten.
      keybd_event(VK_ESCAPE,0,0,IntPtr.Zero);
      keybd_event(VK_ESCAPE,0,2,IntPtr.Zero);
      System.Threading.Thread.Sleep(250);
    }
  }
  public static void ClickAt(int x,int y,bool right){
    SetCursorPos(x,y); System.Threading.Thread.Sleep(160);
    uint d = right?RIGHTDOWN:LEFTDOWN, u = right?RIGHTUP:LEFTUP;
    mouse_event(d,0,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(70);
    mouse_event(u,0,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(80);
  }
}
"@
}
[void][LvWin]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$p = Get-Process -Name $ProcName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { Write-Output "ERROR: process $ProcName not running"; exit 1 }
[LvWin]::Enumerate([uint32]$p.Id)

if ($List) {
  Write-Output ("visible top-level windows of pid " + $p.Id + ":")
  for ($i=0; $i -lt [LvWin]::All.Count; $i++) {
    $w = [LvWin]::All[$i]
    Write-Output ("[$i] area=$($w.Area) rect=$($w.R.Left),$($w.R.Top),$($w.R.Right-$w.R.Left)x$($w.R.Bottom-$w.R.Top) class='$($w.Cls)' title='$($w.Title)'")
  }
  exit 0
}

$target = $null
if ($TitleLike -ne "") { $target = [LvWin]::All | Where-Object { $_.Title -like $TitleLike } | Select-Object -First 1 }
elseif ($Win -ge 0)   { if ($Win -lt [LvWin]::All.Count) { $target = [LvWin]::All[$Win] } }
else                  { if ([LvWin]::All.Count -gt 0) { $target = [LvWin]::All[0] } }
if (-not $target) { Write-Output "ERROR: no matching window"; exit 1 }

Write-Output ("selected: class='$($target.Cls)' title='$($target.Title)' rect=$($target.R.Left),$($target.R.Top),$($target.R.Right-$target.R.Left)x$($target.R.Bottom-$target.R.Top)")

if (-not $NoFocus) {
  [LvWin]::Focus($target.H)
  Write-Output ("foreground=" + [LvWin]::IsForeground($target.H))
  Start-Sleep -Milliseconds 400
  [LvWin]::Enumerate([uint32]$p.Id)
  if ($TitleLike -ne "") { $target = [LvWin]::All | Where-Object { $_.Title -like $TitleLike } | Select-Object -First 1 }
  elseif ($Win -ge 0)   { if ($Win -lt [LvWin]::All.Count) { $target = [LvWin]::All[$Win] } }
  else                  { $target = [LvWin]::All[0] }
}

if ($Maximize) {
  [LvWin]::ShowWindow($target.H, 3)   # SW_MAXIMIZE
  Start-Sleep -Milliseconds 900
  [LvWin]::Focus($target.H)
  Start-Sleep -Milliseconds 500
  [LvWin]::Enumerate([uint32]$p.Id)
  if ($TitleLike -ne "") { $target = [LvWin]::All | Where-Object { $_.Title -like $TitleLike } | Select-Object -First 1 }
  elseif ($Win -ge 0)   { if ($Win -lt [LvWin]::All.Count) { $target = [LvWin]::All[$Win] } }
  else                  { $target = [LvWin]::All[0] }
  Write-Output ("maximized -> rect=$($target.R.Left),$($target.R.Top),$($target.R.Right-$target.R.Left)x$($target.R.Bottom-$target.R.Top)")
}

$originX = $target.R.Left; $originY = $target.R.Top
if ($Click -ne "" -and $X -ge 0 -and $Y -ge 0) {
  $sx = if ($Full) { $X } else { $originX + $X }
  $sy = if ($Full) { $Y } else { $originY + $Y }
  [LvWin]::ClickAt($sx,$sy,($Click -eq "right"))
  Write-Output ("clicked $Click at screen($sx,$sy)")
  if ($Click -eq "double") { Start-Sleep -Milliseconds 100; [LvWin]::ClickAt($sx,$sy,$false) }
  Start-Sleep -Milliseconds $SettleMs
}
if ($Type -ne "") { [System.Windows.Forms.SendKeys]::SendWait($Type); Write-Output ("typed: "+$Type); Start-Sleep -Milliseconds $SettleMs }
if ($Keys -ne "") { [System.Windows.Forms.SendKeys]::SendWait($Keys); Write-Output ("keys: "+$Keys); Start-Sleep -Milliseconds $SettleMs }
if ($PasteText -ne "") {
  Set-Clipboard -Value $PasteText
  Start-Sleep -Milliseconds 350
  [System.Windows.Forms.SendKeys]::SendWait("^v")
  Write-Output ("pasted: " + $PasteText)
  Start-Sleep -Milliseconds $SettleMs
}

if ($NoCapture) { exit 0 }

if ($Full) {
  $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $l=$vs.Left; $t=$vs.Top; $w=$vs.Width; $ht=$vs.Height
  Write-Output ("mode=FULL image coords == SCREEN coords; desktop origin=($l,$t)")
} else {
  [LvWin]::Enumerate([uint32]$p.Id)
  if (-not [LvWin]::IsForeground($target.H)) { [LvWin]::Focus($target.H); Start-Sleep -Milliseconds 300 }
  $l=$target.R.Left; $t=$target.R.Top; $w=$target.R.Right-$target.R.Left; $ht=$target.R.Bottom-$target.R.Top
  Write-Output ("mode=WINDOW origin=($l,$t)  clickXY = imageXY")
}
if ($w -le 0 -or $ht -le 0) { Write-Output "ERROR: bad rect"; exit 1 }

$bmp = New-Object System.Drawing.Bitmap($w,$ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($l,$t,0,0,$bmp.Size); $g.Dispose()
$sc = 1.0
if ($bmp.Width -gt $MaxWidth) {
  $sc = $MaxWidth / $bmp.Width
  $nw=[int]($bmp.Width*$sc); $nh=[int]($bmp.Height*$sc)
  $s=New-Object System.Drawing.Bitmap($nw,$nh)
  $g2=[System.Drawing.Graphics]::FromImage($s)
  $g2.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g2.DrawImage($bmp,0,0,$nw,$nh); $g2.Dispose(); $bmp.Dispose(); $bmp=$s
}
$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$bmp.Save($Out,[System.Drawing.Imaging.ImageFormat]::Png)
Write-Output ("saved=$Out img=$($bmp.Width)x$($bmp.Height) scale=$sc")
$bmp.Dispose()
