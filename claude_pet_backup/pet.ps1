# Claude Code pet -- overlay side (Windows).
#
# A small movable dot-matrix badge, after the Nothing phone glyph display.
# Colour and word are the message:
#   working   dim blue   WORKING    (Claude is busy; ignore it)
#   done      green      DONE       (turn finished)
#   waiting   amber      QUESTION   (Claude needs your input)
#
# Drag it anywhere; the position is remembered. The size never changes, so it
# does not jump around under your cursor when the state changes.
#
# Hides entirely when the foreground window is fullscreen (YouTube, games) or
# when the terminal running Claude is already focused. Nothing animates -- the
# window only repaints when the state actually changes.
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
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

# Without this the process is DPI-unaware: it draws into a 1280x800 logical
# surface that Windows then stretches to the real 1920x1200, which smears every
# dot. Aware, the dots land on true pixels. Must run before any window is
# created or any screen bound is read.
[void][PetNative]::SetProcessDPIAware()

# ---------------------------------------------------------------- config ----
$Root      = Join-Path $env:USERPROFILE ".claudepet"
$SessDir   = Join-Path $Root "sessions"
$HbFile    = Join-Path $Root "heartbeat"
$PosFile   = Join-Path $Root "position.txt"
$StaleSecs = 8 * 3600

# Foreground processes that mean "you are already looking at Claude".
$TermProcs = @("alacritty", "WindowsTerminal", "wezterm-gui", "wt")

# Size of the badge. Same for every state -- colour and word carry the meaning,
# not size. Tweak these two numbers to match the clock widget.
#
# These are raw pixels, which do not track the display scale, so the 150%
# factor is baked in to keep the badge its usual physical size. Originals at
# 100% are in the comments; redo them if the display scale changes.
$W = 225   # was 150
$H = 66    # was 44

# Dot-matrix look, after the Nothing phone glyph display: the label is rendered
# into a tiny offscreen bitmap, then each lit pixel is drawn as a circle.
# $DotPitch is the grid spacing in px; smaller = finer matrix, more legible
# text, less chunky. $DotRadius is the size of each lit dot.
$DotPitch  = 3.0   # was 2.0
$DotRadius = 1.2   # was 0.8
$Pad       = 0
# Unlit cells, drawn faintly so the grid itself reads as a display. Ignored
# when $Transparent is on -- an unlit grid floating over video just reads as
# dark speckle.
$GridAlpha = 26

# $true drops the dark panel entirely: only the lit dots show, floating over
# whatever is behind. $false brings back the rounded dark badge.
# Caveat: with the panel gone, clicks pass through everywhere except the lit
# dots, so dragging it means grabbing a dot. Flip this to $false if you want
# to reposition it easily, then flip it back.
$Transparent = $false
$BgColor     = [Drawing.Color]::FromArgb(10, 11, 14)
# Only used in transparent mode; must be a colour the dots never use.
$KeyColor    = [Drawing.Color]::FromArgb(255, 0, 255)

# Marquee: ms between one-column steps, and the blank gap between repeats.
$ScrollMs  = 90
$ScrollGap = 10
# Mask font. Consolas is used because it stays crisp at the very small pixel
# sizes the matrix samples from; the visible result is dots, not glyphs.
$FontName  = "Consolas"

# Per state: label, dot colour, window opacity. All fully opaque -- a
# see-through badge picks up whatever is behind it and looks washed out. To
# make `working` recede, dim its dot colour rather than the window.
$Palette = @{
  working = @{ text = "WORKING";  fg = [Drawing.Color]::FromArgb(122, 162, 247); op = 1.00 }
  done    = @{ text = "DONE";     fg = [Drawing.Color]::FromArgb(158, 206, 106); op = 1.00 }
  waiting = @{ text = "QUESTION"; fg = [Drawing.Color]::FromArgb(255, 166, 46);  op = 1.00 }
}

New-Item -ItemType Directory -Force -Path $SessDir | Out-Null

# ----------------------------------------------------------------- state ----
# Uses raw .NET IO rather than Get-ChildItem/Get-Content: this runs several
# times a second, and the cmdlet pipeline overhead dominated the pet's CPU.
function Get-PetState {
  $waiting = $false; $working = $false; $done = $false
  $now = [DateTime]::UtcNow
  try { $files = [IO.Directory]::GetFiles($SessDir) } catch { return $null }
  foreach ($f in $files) {
    try {
      if (($now - [IO.File]::GetLastWriteTimeUtc($f)).TotalSeconds -gt $StaleSecs) {
        [IO.File]::Delete($f); continue
      }
      $line = [IO.File]::ReadAllText($f)
    } catch { continue }
    if     ($line.StartsWith("waiting")) { $waiting = $true }
    elseif ($line.StartsWith("working")) { $working = $true }
    elseif ($line.StartsWith("done"))    { $done    = $true }
  }
  # Loudest state wins: if any session wants you, the badge wants you.
  if ($waiting) { return "waiting" }
  if ($working) { return "working" }
  if ($done)    { return "done" }
  return $null
}

$script:fgHandle = [IntPtr]::Zero
$script:fgIsTerm = $false
$script:fgBounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds

function Test-ShouldHide {
  param([IntPtr]$Self)
  $h = [PetNative]::GetForegroundWindow()
  if ($h -eq [IntPtr]::Zero -or $h -eq $Self) { return $false }
  if ($h -eq [PetNative]::GetShellWindow() -or $h -eq [PetNative]::GetDesktopWindow()) { return $false }

  # Already looking at the terminal? Nothing to notify.
  # Get-Process is by far the most expensive call here, and the foreground
  # window rarely changes, so its result is cached per handle. The rect/style
  # checks below stay uncached: Brave keeps the same handle when it goes
  # fullscreen, so those must be re-read every tick.
  if ($h -ne $script:fgHandle) {
    $script:fgHandle = $h
    $procId = 0
    [void][PetNative]::GetWindowThreadProcessId($h, [ref]$procId)
    $script:fgIsTerm = $false
    try {
      $name = (Get-Process -Id $procId -ErrorAction Stop).ProcessName
      $script:fgIsTerm = ($TermProcs -contains $name)
    } catch { }
    $script:fgBounds = [Windows.Forms.Screen]::FromHandle($h).Bounds
  }
  if ($script:fgIsTerm) { return $true }

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
  $scr = $script:fgBounds
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
$scr = [Windows.Forms.Screen]::PrimaryScreen.Bounds
$defaultPos = New-Object Drawing.Point(($scr.Left + 42), ($scr.Bottom - 42 - $H))   # 28 at 100%
$pos = $defaultPos
if (Test-Path $PosFile) {
  $pp = (Get-Content $PosFile -First 1) -split ','
  if ($pp.Count -eq 2) {
    $saved = New-Object Drawing.Point([int]$pp[0], [int]$pp[1])
    # Display scaling or monitor changes can leave the remembered physical
    # coordinate outside today's logical WinForms bounds. Accept it only when
    # the whole badge fits on a currently attached screen.
    $fits = $false
    foreach ($screen in [Windows.Forms.Screen]::AllScreens) {
      $b = $screen.Bounds
      if ($saved.X -ge $b.Left -and $saved.Y -ge $b.Top -and
          ($saved.X + $W) -le $b.Right -and ($saved.Y + $H) -le $b.Bottom) {
        $fits = $true; break
      }
    }
    if ($fits) {
      $pos = $saved
    } else {
      "$($defaultPos.X),$($defaultPos.Y)" | Set-Content $PosFile
    }
  }
}

$form = New-Object Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.ShowInTaskbar   = $false
$form.TopMost         = $true
$form.StartPosition   = 'Manual'
$form.Size            = New-Object Drawing.Size($W, $H)
$form.Location        = $pos
$form.GetType().GetProperty("DoubleBuffered",
  [Reflection.BindingFlags]"Instance,NonPublic").SetValue($form, $true, $null)

# Rounded rectangle, computed once -- the size never changes.
$rad = 18   # was 12
$gp = New-Object Drawing.Drawing2D.GraphicsPath
$gp.AddArc(0, 0, $rad, $rad, 180, 90)
$gp.AddArc($W - $rad, 0, $rad, $rad, 270, 90)
$gp.AddArc($W - $rad, $H - $rad, $rad, $rad, 0, 90)
$gp.AddArc(0, $H - $rad, $rad, $rad, 90, 90)
$gp.CloseFigure()
$form.Region = New-Object Drawing.Region($gp)

# Matrix dimensions.
$Cols = [int](($W - 2 * $Pad) / $DotPitch)
$Rows = [int](($H - 2 * $Pad) / $DotPitch)

# Render $Text into a strip of lit/unlit cells, $Rows tall and as wide as the
# text needs plus a gap. The strip is wider than the display and gets scrolled
# past it, which is what makes the marquee. Font size is fitted to the row
# count, so changing $H or $DotPitch just works.
function Build-Strip {
  param([string]$Text)
  $probe = New-Object Drawing.Bitmap(1, 1)
  $pg    = [Drawing.Graphics]::FromImage($probe)

  $size = $Rows + 2
  $font = $null
  while ($size -gt 3) {
    $try = New-Object Drawing.Font($FontName, $size, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
    if ($pg.MeasureString($Text, $try).Height -le ($Rows + 2)) { $font = $try; break }
    $try.Dispose(); $size--
  }
  if (-not $font) {
    $font = New-Object Drawing.Font($FontName, 6, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
  }

  $textW  = [int][Math]::Ceiling($pg.MeasureString($Text, $font).Width)
  $stripW = $textW + $ScrollGap
  if ($stripW -lt ($Cols + $ScrollGap)) { $stripW = $Cols + $ScrollGap }
  $pg.Dispose(); $probe.Dispose()

  $bmp = New-Object Drawing.Bitmap($stripW, $Rows)
  $g   = [Drawing.Graphics]::FromImage($bmp)
  $g.Clear([Drawing.Color]::Black)
  $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
  $g.DrawString($Text, $font, [Drawing.Brushes]::White, 0, 0)
  $g.Flush()

  $map = New-Object 'bool[,]' $stripW, $Rows
  for ($y = 0; $y -lt $Rows; $y++) {
    for ($x = 0; $x -lt $stripW; $x++) {
      $map[$x, $y] = ($bmp.GetPixel($x, $y).R -gt 110)
    }
  }
  $font.Dispose(); $g.Dispose(); $bmp.Dispose()
  return @{ map = $map; w = $stripW }
}

# Pre-render every scroll position of a state into a finished bitmap. Animating
# is then one image blit per frame instead of ~460 FillEllipse calls, which is
# what keeps a moving marquee affordable on a CPU-only machine.
function Build-Frames {
  param([string]$State)
  $p      = $Palette[$State]
  $strip  = Build-Strip -Text $p.text
  $map    = $strip.map
  $sw     = $strip.w
  $d      = $DotRadius * 2
  $lit    = New-Object Drawing.SolidBrush($p.fg)
  $unlit  = New-Object Drawing.SolidBrush(
    [Drawing.Color]::FromArgb($GridAlpha, $p.fg.R, $p.fg.G, $p.fg.B))

  $frames = New-Object 'Drawing.Bitmap[]' $sw
  for ($f = 0; $f -lt $sw; $f++) {
    $bmp = New-Object Drawing.Bitmap($W, $H)
    $g   = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    if (-not $Transparent) { $g.Clear($BgColor) }
    for ($y = 0; $y -lt $Rows; $y++) {
      for ($x = 0; $x -lt $Cols; $x++) {
        $on = $map[(($f + $x) % $sw), $y]
        if ((-not $on) -and ($Transparent -or $GridAlpha -le 0)) { continue }
        $cx = $Pad + $x * $DotPitch + $DotPitch / 2 - $DotRadius
        $cy = $Pad + $y * $DotPitch + $DotPitch / 2 - $DotRadius
        $g.FillEllipse(($(if ($on) { $lit } else { $unlit })), $cx, $cy, $d, $d)
      }
    }
    $g.Dispose()
    $frames[$f] = $bmp
  }
  $lit.Dispose(); $unlit.Dispose()
  return $frames
}

# All three states are built up front. Building one takes about a second at
# this grid density, and doing it lazily meant the badge froze for that second
# the first time Claude asked a question -- exactly the moment it must not.
$script:frames = @{}
foreach ($k in $Palette.Keys) { $script:frames[$k] = Build-Frames -State $k }
$script:cur   = "working"
$script:frame = 0

$form.Add_Paint({
  param($s, $e)
  $set = $script:frames[$script:cur]
  if ($set) { $e.Graphics.DrawImageUnscaled($set[$script:frame % $set.Length], 0, 0) }
})

function Set-Look {
  param([string]$State)
  $form.Opacity = $Palette[$State].op
  $script:frame = 0
  $form.Invalidate()
}

if ($Transparent) {
  $form.BackColor       = $KeyColor
  $form.TransparencyKey = $KeyColor
} else {
  $form.BackColor = $BgColor
}
Set-Look -State "working"

# The marquee. Separate from the state poll: it only advances while the badge
# is actually on screen, so a hidden pet costs nothing.
$anim = New-Object Windows.Forms.Timer
$anim.Interval = $ScrollMs
$anim.Add_Tick({
  if (-not $form.Visible) { return }
  $script:frame++
  $form.Invalidate()
})
$anim.Start()

# Drag to reposition; the anchor moves with it.
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

# Right-click to quit.
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
# Two cadences on one timer. Show/hide runs every tick so the badge is there
# the instant you switch to Brave -- it is only P/Invoke calls, no disk. The
# session-state read touches the filesystem, so it runs every 5th tick.
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 120
$script:tick  = 0
$script:state = $null
$timer.Add_Tick({
  $script:tick++

  if ($script:tick % 5 -eq 1) { $script:state = Get-PetState }

  # Heartbeat, ~every 3.5s. Lets the WSL side answer "is the pet already
  # running?" with a plain stat instead of spawning powershell.exe.
  if ($script:tick % 29 -eq 0) {
    Set-Content -Path $HbFile -Value $script:tick -ErrorAction SilentlyContinue
  }

  if ((-not $script:state) -or (Test-ShouldHide -Self $form.Handle)) {
    if ($form.Visible) { $form.Hide() }
    return
  }

  if ($script:state -ne $script:cur) {
    $script:cur = $script:state
    Set-Look -State $script:state
  }
  if (-not $form.Visible) { $form.Show() }
  $form.TopMost = $true
})
$timer.Start()

[void][Windows.Forms.Application]::Run($form)
