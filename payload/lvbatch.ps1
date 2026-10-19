param(
  [string]$ProcName = "LabVIEW",
  [Parameter(Mandatory=$true)][string]$Steps,
  [string]$TitleLike = "",
  [string]$Out = (Join-Path $env:TEMP "lv_batch.png"),
  [switch]$Full,
  [int]$MaxWidth = 2400,
  [int]$DefaultWaitMs = 700
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

if (-not ("LvB" -as [type])) {
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class LvB {
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
  public const byte VK_MENU=0x12, VK_ESCAPE=0x1B;

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
      keybd_event(VK_ESCAPE,0,0,IntPtr.Zero);
      keybd_event(VK_ESCAPE,0,2,IntPtr.Zero);
      System.Threading.Thread.Sleep(250);
    }
  }
  public static void ClickAt(int x,int y,bool right){
    SetCursorPos(x,y); System.Threading.Thread.Sleep(140);
    uint d = right?RIGHTDOWN:LEFTDOWN, u = right?RIGHTUP:LEFTUP;
    mouse_event(d,0,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    mouse_event(u,0,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
  }
  // drag: press at (x1,y1), move in steps, release at (x2,y2)
  public static void DragTo(int x1,int y1,int x2,int y2,bool right){
    SetCursorPos(x1,y1); System.Threading.Thread.Sleep(160);
    mouse_event(right?RIGHTDOWN:LEFTDOWN,0,0,0,IntPtr.Zero);
    System.Threading.Thread.Sleep(120);
    int steps=14;
    for(int i=1;i<=steps;i++){
      int x=x1+(x2-x1)*i/steps, y=y1+(y2-y1)*i/steps;
      SetCursorPos(x,y); System.Threading.Thread.Sleep(25);
    }
    System.Threading.Thread.Sleep(150);
    mouse_event(right?RIGHTUP:LEFTUP,0,0,0,IntPtr.Zero);
    System.Threading.Thread.Sleep(120);
  }
}
"@
}
[void][LvB]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$p = Get-Process -Name $ProcName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { Write-Output "ERROR: process $ProcName not running"; exit 1 }

foreach ($raw in $Steps.Split(';')) {
  $s = $raw.Trim()
  if ($s -eq "") { continue }
  $op = $s.Substring(0,1).ToUpper()
  $arg = $s.Substring(1).Trim()
  switch ($op) {
    "L" { $c=$arg.Split(','); [LvB]::ClickAt([int]$c[0],[int]$c[1],$false); Write-Output "L $arg"; Start-Sleep -Milliseconds $DefaultWaitMs }
    "R" { $c=$arg.Split(','); [LvB]::ClickAt([int]$c[0],[int]$c[1],$true);  Write-Output "R $arg"; Start-Sleep -Milliseconds $DefaultWaitMs }
    "D" { $c=$arg.Split(','); [LvB]::ClickAt([int]$c[0],[int]$c[1],$false); Start-Sleep -Milliseconds 80; [LvB]::ClickAt([int]$c[0],[int]$c[1],$false); Write-Output "D $arg"; Start-Sleep -Milliseconds $DefaultWaitMs }
    "V" { $c=$arg.Split(','); [LvB]::DragTo([int]$c[0],[int]$c[1],[int]$c[2],[int]$c[3],$false); Write-Output "V(drag) $arg"; Start-Sleep -Milliseconds $DefaultWaitMs }
    "M" { $c=$arg.Split(','); [void][LvB]::SetCursorPos([int]$c[0],[int]$c[1]); Write-Output "M(move) $arg"; Start-Sleep -Milliseconds 500 }
    "K" { [System.Windows.Forms.SendKeys]::SendWait($arg); Write-Output "K $arg"; Start-Sleep -Milliseconds $DefaultWaitMs }
    "P" { Set-Clipboard -Value $arg; Start-Sleep -Milliseconds 300; [System.Windows.Forms.SendKeys]::SendWait("^v"); Write-Output "P $arg"; Start-Sleep -Milliseconds $DefaultWaitMs }
    "W" { Start-Sleep -Milliseconds ([int]$arg); Write-Output "W $arg" }
    "F" { $t = [LvB]::All | Where-Object { $_.Title -like $arg } | Select-Object -First 1
          if ($t) { [LvB]::Focus($t.H); Write-Output ("F(focus) " + $t.Title) } else { Write-Output ("F: no window like " + $arg) }
          Start-Sleep -Milliseconds 500 }
    "X" { $t = [LvB]::All | Where-Object { $_.Title -like $arg } | Select-Object -First 1
          if ($t) { [LvB]::ShowWindow($t.H,3); [LvB]::Focus($t.H); Write-Output ("X(maximize) " + $t.Title) } else { Write-Output ("X: no window like " + $arg) }
          Start-Sleep -Milliseconds 900 }
    "N" { [LvB]::Enumerate([uint32]$p.Id); Write-Output ("windows=" + [LvB]::All.Count) }
    "G" { $t = [LvB]::All | Where-Object { $_.Title -like $arg } | Select-Object -First 1
          if ($t) { [void][LvB]::BringWindowToTop($t.H); [void][LvB]::SetForegroundWindow($t.H); Write-Output ("G(gentle) " + $t.Title) }
          else { Write-Output ("G: no window like " + $arg) }
          Start-Sleep -Milliseconds 700 }
    default { Write-Output ("?? unknown step: " + $s) }
  }
}

[LvB]::Enumerate([uint32]$p.Id)
$target = $null
if ($TitleLike -ne "") { $target = [LvB]::All | Where-Object { $_.Title -like $TitleLike } | Select-Object -First 1 }
else { if ([LvB]::All.Count -gt 0) { $target = [LvB]::All[0] } }

if ($Full -or -not $target) {
  $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $l=$vs.Left; $t=$vs.Top; $w=$vs.Width; $ht=$vs.Height
  Write-Output "capture: FULL"
} else {
  $l=$target.R.Left; $t=$target.R.Top; $w=$target.R.Right-$target.R.Left; $ht=$target.R.Bottom-$target.R.Top
  Write-Output ("capture: WINDOW '" + $target.Title + "' origin=($l,$t)")
}

$bmp = New-Object System.Drawing.Bitmap($w,$ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($l,$t,0,0,$bmp.Size); $g.Dispose()
if ($bmp.Width -gt $MaxWidth) {
  $sc=$MaxWidth/$bmp.Width; $nw=[int]($bmp.Width*$sc); $nh=[int]($bmp.Height*$sc)
  $s2=New-Object System.Drawing.Bitmap($nw,$nh)
  $g2=[System.Drawing.Graphics]::FromImage($s2)
  $g2.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g2.DrawImage($bmp,0,0,$nw,$nh); $g2.Dispose(); $bmp.Dispose(); $bmp=$s2
}
$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$bmp.Save($Out,[System.Drawing.Imaging.ImageFormat]::Png)
Write-Output ("saved=$Out img=$($bmp.Width)x$($bmp.Height)")
$bmp.Dispose()
