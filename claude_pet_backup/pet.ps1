# Claude Code pet -- overlay side (Windows).
#
# A small always-on-top ASCII face that shows whether Claude is working, done,
# or waiting on you. Hides itself when the foreground window is fullscreen
# (YouTube, games) or when the terminal running Claude is already focused.
#
# Launch:  powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File pet.ps1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class PetNative {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetShellWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

# ---------------------------------------------------------------- config ----
$Root      = Join-Path $env:USERPROFILE ".claudepet"
$SessDir   = Join-Path $Root "sessions"
$PosFile   = Join-Path $Root "position.txt"
$HbFile    = Join-Path $Root "heartbeat"
$StaleSecs = 8 * 3600
# Foreground processes that mean "you are already looking at Claude".
$TermProcs = @("alacritty", "WindowsTerminal", "wezterm-gui", "wt")

$W = 214
$H = 78

$Palette = @{
  working = @{ fg = [Drawing.Color]::FromArgb(122, 162, 247); face = "[-_-]"; word = "working"  }
  done    = @{ fg = [Drawing.Color]::FromArgb(158, 206, 106); face = "[^_^]"; word = "done"     }
  waiting = @{ fg = [Drawing.Color]::FromArgb(224, 175, 104); face = "[o_o]?"; word = "needs you" }
}

New-Item -ItemType Directory -Force -Path $SessDir | Out-Null

# ----------------------------------------------------------------- state ----
function Get-PetState {
  $states = @()
  $labels = @()
  Get-ChildItem -File $SessDir -ErrorAction SilentlyContinue | ForEach-Object {
    if (((Get-Date) - $_.LastWriteTime).TotalSeconds -gt $StaleSecs) {
      Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
      return
    }
    $line = (Get-Content $_.FullName -First 1 -ErrorAction SilentlyContinue)
    if (-not $line) { return }
    $p = $line -split "`t"
    $states += $p[0]
    if ($p.Count -gt 1) { $labels += $p[1] }
  }
  if ($states -contains "waiting") { $s = "waiting" }
  elseif ($states -contains "working") { $s = "working" }
  elseif ($states -contains "done") { $s = "done" }
  else { return $null }

  $label = if ($states.Count -gt 1) { "$($states.Count) sessions" }
           elseif ($labels.Count -gt 0) { $labels[0] }
           else { "claude" }
  return @{ state = $s; label = $label }
}

function Test-ShouldHide {
  param([IntPtr]$Self)
  $h = [PetNative]::GetForegroundWindow()
  if ($h -eq [IntPtr]::Zero -or $h -eq $Self) { return $false }
  if ($h -eq [PetNative]::GetShellWindow() -or $h -eq [PetNative]::GetDesktopWindow()) { return $false }

  # Already looking at the terminal? Nothing to notify.
  $procId = 0
  [void][PetNative]::GetWindowThreadProcessId($h, [ref]$procId)
  try {
    $name = (Get-Process -Id $procId -ErrorAction Stop).ProcessName
    if ($TermProcs -contains $name) { return $true }
  } catch { }

  # Fullscreen? Two things must hold together:
  #   1. the window covers the whole monitor
  #   2. it has no title bar -- going fullscreen drops WS_CAPTION
  # Measured on this machine: maximized Brave is style 0x17CF0000 (caption set,
  # rect overhangs by 8px), fullscreen Brave is 0x170B0000 (no caption, exact
  # rect). Note IsZoomed is True for BOTH, so it cannot be used here -- and
  # there is no taskbar on this box (no explorer.exe), so WorkingArea equals
  # Bounds and geometry alone cannot separate them either.
  $r = New-Object "PetNative+RECT"
  if (-not [PetNative]::GetWindowRect($h, [ref]$r)) { return $false }
  $scr = [Windows.Forms.Screen]::FromHandle($h).Bounds
  $tol = 2
  $covers = ($r.Left -le $scr.Left + $tol) -and ($r.Top -le $scr.Top + $tol) -and
            ($r.Right -ge $scr.Right - $tol) -and ($r.Bottom -ge $scr.Bottom - $tol)
  if (-not $covers) { return $false }

  $GWL_STYLE  = -16
  $WS_CAPTION = 0x00C00000
  $style = [PetNative]::GetWindowLong($h, $GWL_STYLE)
  if (($style -band $WS_CAPTION) -eq $WS_CAPTION) { return $false }

  return $true
}

# ------------------------------------------------------------------ form ----
$form = New-Object Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.ShowInTaskbar   = $false
$form.TopMost         = $true
$form.StartPosition   = 'Manual'
$form.Size            = New-Object Drawing.Size($W, $H)
$form.BackColor       = [Drawing.Color]::FromArgb(17, 18, 24)
$form.Opacity         = 1.0

# Without this the timer-driven repaints flicker.
$form.GetType().GetProperty("DoubleBuffered",
  [Reflection.BindingFlags]"Instance,NonPublic").SetValue($form, $true, $null)

# Rounded corners.
$rad = 14
$gp  = New-Object Drawing.Drawing2D.GraphicsPath
$gp.AddArc(0, 0, $rad, $rad, 180, 90)
$gp.AddArc($W - $rad, 0, $rad, $rad, 270, 90)
$gp.AddArc($W - $rad, $H - $rad, $rad, $rad, 0, 90)
$gp.AddArc(0, $H - $rad, $rad, $rad, 90, 90)
$gp.CloseFigure()
$form.Region = New-Object Drawing.Region($gp)

# Same shape, inset by 1px, for the border stroke.
$script:borderPath = New-Object Drawing.Drawing2D.GraphicsPath
$script:borderPath.AddArc(1, 1, $rad, $rad, 180, 90)
$script:borderPath.AddArc($W - $rad - 2, 1, $rad, $rad, 270, 90)
$script:borderPath.AddArc($W - $rad - 2, $H - $rad - 2, $rad, $rad, 0, 90)
$script:borderPath.AddArc(1, $H - $rad - 2, $rad, $rad, 90, 90)
$script:borderPath.CloseFigure()

# Default position: bottom-left of the primary work area.
$wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$pos = New-Object Drawing.Point(($wa.Left + 24), ($wa.Bottom - $H - 24))
if (Test-Path $PosFile) {
  $pp = (Get-Content $PosFile -First 1) -split ','
  if ($pp.Count -eq 2) { $pos = New-Object Drawing.Point([int]$pp[0], [int]$pp[1]) }
}
$form.Location = $pos

$faceFont = New-Object Drawing.Font("Consolas", 19, [Drawing.FontStyle]::Bold)
$subFont  = New-Object Drawing.Font("Consolas", 9)

$script:cur   = @{ state = "working"; label = "claude" }
$script:tick  = 0

$form.Add_Paint({
  param($s, $e)
  $g = $e.Graphics
  $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit
  $p = $Palette[$script:cur.state]

  $brFace = New-Object Drawing.SolidBrush($p.fg)
  $brSub  = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(150, 155, 170))
  $g.DrawString($p.face, $faceFont, $brFace, 14, 8)
  $g.DrawString("$($p.word) . $($script:cur.label)", $subFont, $brSub, 16, 50)

  # Accent bar down the left edge.
  $g.FillRectangle($brFace, 0, 0, 3, $H)

  # Hairline border so it reads as a panel against a bright page.
  $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(58, 62, 78))
  $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.DrawPath($pen, $script:borderPath)

  $brFace.Dispose(); $brSub.Dispose(); $pen.Dispose()
})

# Drag to reposition; right-click to quit.
$script:dragging = $false
$script:dragOff  = New-Object Drawing.Point(0, 0)
$form.Add_MouseDown({
  param($s, $e)
  if ($e.Button -eq [Windows.Forms.MouseButtons]::Left) {
    $script:dragging = $true
    $script:dragOff  = New-Object Drawing.Point($e.X, $e.Y)
  }
})
$form.Add_MouseMove({
  param($s, $e)
  if ($script:dragging) {
    $form.Location = New-Object Drawing.Point(
      ($form.Location.X + $e.X - $script:dragOff.X),
      ($form.Location.Y + $e.Y - $script:dragOff.Y))
  }
})
$form.Add_MouseUp({
  $script:dragging = $false
  "$($form.Location.X),$($form.Location.Y)" | Set-Content $PosFile
})

$menu = New-Object Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add("Quit pet", $null, { $form.Close() })
$form.ContextMenuStrip = $menu

# Never take focus, never appear in alt-tab.
$form.Add_Shown({
  $GWL_EXSTYLE = -20
  $ex = [PetNative]::GetWindowLong($form.Handle, $GWL_EXSTYLE)
  [void][PetNative]::SetWindowLong($form.Handle, $GWL_EXSTYLE, $ex -bor 0x08000000 -bor 0x00000080)
})

# ------------------------------------------------------------------ loop ----
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 700
$timer.Add_Tick({
  $script:tick++
  # Heartbeat, ~every 3.5s. Lets the WSL side answer "is the pet already
  # running?" with a plain stat instead of spawning powershell.exe.
  if ($script:tick % 5 -eq 0) {
    Set-Content -Path $HbFile -Value $script:tick -ErrorAction SilentlyContinue
  }
  $st = Get-PetState
  $hide = (-not $st) -or (Test-ShouldHide -Self $form.Handle)

  if ($hide) {
    if ($form.Visible) { $form.Hide() }
    return
  }

  if ($st.state -ne $script:cur.state -or $st.label -ne $script:cur.label) {
    $script:cur = $st
    $form.Invalidate()
  }
  if (-not $form.Visible) { $form.Show() }
  $form.TopMost = $true
})
$timer.Start()

[void][Windows.Forms.Application]::Run($form)
