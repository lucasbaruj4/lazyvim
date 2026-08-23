# clock-overlay.ps1
# Always-on-top copy of the tmux status bar, so its contents are readable
# without switching to the terminal (mainly while in the browser).
#
# Shows the same four fields as `status-right` in ~/.tmux.conf, in the same
# order and with the same icons:  volume | battery | date+time | wifi
#
# Behaviour:
#   - click-through and never focusable (WS_EX_TRANSPARENT | WS_EX_NOACTIVATE),
#     so it can sit over the browser without ever eating a click.
#   - hides itself whenever the FOREGROUND window is genuinely fullscreen.
#     That covers the two cases that matter: YouTube/video fullscreen (must
#     not be covered) and Alacritty (which starts fullscreen and already
#     shows this same clock in the tmux bar, so the overlay is redundant
#     there).
#   - "fullscreen" is deliberately NOT just "window fills the screen":
#     explorer.exe isn't running, so there is no taskbar and a merely
#     MAXIMISED window also fills the screen exactly. The extra test is the
#     window style -- a maximised window keeps WS_CAPTION (and the
#     WS_MAXIMIZE bit); a real fullscreen window drops the caption.

$logPath = "C:\Users\Admin\AppData\Local\clock-overlay.log"
# GlobalHotkeys.exe writes a new token here for each Ctrl+, press made while
# Brave is focused. The token is an event, not saved visibility state.
$toggleSignalPath = "C:\Users\Admin\AppData\Local\clock-overlay.toggle"
"[$(Get-Date -Format o)] starting" | Out-File -FilePath $logPath -Append

# Set to $true to log the foreground window's title/rect/style on every
# show/hide flip -- used to calibrate the fullscreen test against real apps.
$debugDetect = $false

# Debug aid: CLOCK_ALWAYS_SHOW=1 keeps the pill on screen even over
# fullscreen windows, so it can be inspected while the terminal is focused.
$alwaysShow = $env:CLOCK_ALWAYS_SHOW -eq '1'

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int pid);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    public static string TitleOf(IntPtr h) {
        int len = GetWindowTextLength(h);
        if (len <= 0) return "";
        var sb = new System.Text.StringBuilder(len + 1);
        GetWindowText(h, sb, sb.Capacity);
        return sb.ToString();
    }
}
"@

    $GWL_STYLE       = -16
    $GWL_EXSTYLE     = -20
    $WS_CAPTION      = 0x00C00000
    $WS_MAXIMIZE     = 0x01000000
    $WS_EX_TOOLWINDOW  = 0x00000080
    $WS_EX_APPWINDOW   = 0x00040000
    $WS_EX_TRANSPARENT = 0x00000020
    $WS_EX_NOACTIVATE  = 0x08000000
    $HWND_TOPMOST    = [IntPtr]::new(-1)
    $SWP_NOMOVE      = 0x0002
    $SWP_NOSIZE      = 0x0001
    $SWP_NOACTIVATE  = 0x0010
    $SW_HIDE         = 0
    $SW_SHOWNA       = 8    # show without activating (never steals focus)

    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        "[$(Get-Date -Format o)] ThreadException: $($e.Exception)" | Out-File -FilePath $logPath -Append
    })

    # --- appearance: dot-matrix panel, matching the Claude Code pet overlay
    # (~/.claude/pet/pet.ps1) so the two read as one system. The time is drawn
    # as an LED grid rather than as glyphs: it is rendered into a tiny offscreen
    # bitmap, then every lit pixel becomes a circle. No motion here -- the pet
    # scrolls, the clock does not.
    $fg      = [System.Drawing.ColorTranslator]::FromHtml("#ffffff")
    $bg      = [System.Drawing.Color]::FromArgb(10, 11, 14)   # same panel as the pet
    # Mask font. The tmux bar's icons (battery, volume, wifi) live in the Nerd
    # Font private-use range, so the font sampled by the grid has to carry them
    # or they come out as empty boxes. "NFM" is the mono variant -- this is
    # columnar status text, same as the bar it copies.
    $fontName = "CaskaydiaMono NFM"
    $fontSize = 15
    $margin   = 20       # gap from the bottom-right screen corner
    $padX     = 14
    $padY     = 7

    # Grid geometry, same values the pet uses.
    $DotPitch  = 2.0
    $DotRadius = 0.8
    $DotPad    = 0      # no inset: the grid runs edge to edge
    $GridAlpha = 26      # unlit cells, so the grid itself reads as a display
    $Radius    = 12      # rounded-rect corners, same as the pet

    $font = New-Object System.Drawing.Font($fontName, $fontSize, [System.Drawing.FontStyle]::Regular)
    if ($font.Name -ne $fontName) {
        "[$(Get-Date -Format o)] WARN: font '$fontName' unavailable, fell back to '$($font.Name)'" | Out-File -FilePath $logPath -Append
    }

    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.ShowInTaskbar   = $false
    $form.TopMost         = $true
    $form.StartPosition   = 'Manual'
    $form.BackColor       = $bg
    $form.Opacity         = 1.0           # fully solid -- nothing shows through the pill

    # DoubleBuffered is protected, so it has to be set by reflection -- without
    # it the pill flickers each minute when the region and size are reapplied.
    [System.Windows.Forms.Control].GetProperty("DoubleBuffered",
        [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance
    ).SetValue($form, $true, $null)

    $script:barText   = ""
    $script:dotMap    = $null
    $script:dotCols   = 0
    $script:dotRows   = 0

    # Sixteen brightness steps let edge dots taper instead of snapping from
    # fully dark to fully lit. The marks are still discrete circles; only their
    # intensity changes, like a real low-resolution LED matrix photographed
    # slightly out of focus.
    $dotBrushes = @()
    for ($level = 0; $level -lt 16; $level++) {
        $alpha = [int]($GridAlpha + ($level / 15.0) * (255 - $GridAlpha))
        $dotBrushes += New-Object System.Drawing.SolidBrush(
            [System.Drawing.Color]::FromArgb($alpha, $fg.R, $fg.G, $fg.B))
    }

    # Render $Text into a $Cols x $Rows grid and record which cells are lit.
    # The mask font size is fitted to the row count, so the grid stays filled
    # whatever the pill ends up sized at.
    function Build-DotMap {
        param([string]$Text, [int]$Cols, [int]$Rows)
        $bmp = New-Object System.Drawing.Bitmap($Cols, $Rows)
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $g.Clear([System.Drawing.Color]::Black)
        # Sample smooth glyph shapes, then apply the hard threshold below. This
        # keeps every visible dot fully lit without breaking thin letter strokes.
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment     = [System.Drawing.StringAlignment]::Center
        $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center

        $size = $Rows + 2
        $mask = $null
        while ($size -gt 3) {
            $try = New-Object System.Drawing.Font($fontName, $size,
                [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
            $m = $g.MeasureString($Text, $try)
            if ($m.Width -le $Cols -and $m.Height -le ($Rows + 2)) { $mask = $try; break }
            $try.Dispose(); $size--
        }
        if (-not $mask) {
            $mask = New-Object System.Drawing.Font($fontName, 6,
                [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        }

        $g.DrawString($Text, $mask, [System.Drawing.Brushes]::White,
            (New-Object System.Drawing.RectangleF(0, 0, $Cols, $Rows)), $fmt)
        $g.Flush()

        $map = New-Object 'byte[,]' $Cols, $Rows
        for ($y = 0; $y -lt $Rows; $y++) {
            for ($x = 0; $x -lt $Cols; $x++) {
                # Preserve partial edge coverage so small glyphs stay smooth,
                # with a mild brightness boost so the text remains visible.
                $coverage = $bmp.GetPixel($x, $y).R / 255.0
                $map[$x, $y] = [byte][math]::Min(15,
                    [math]::Round([math]::Pow($coverage, 0.62) * 15))
            }
        }
        $mask.Dispose(); $g.Dispose(); $bmp.Dispose()
        # NOTE the comma: returning a 2-D array bare makes PowerShell enumerate
        # it into loose bytes. `,$map` returns the array itself.
        return ,$map
    }

    $form.Add_Paint({
        param($sender, $e)
        try {
            [System.Windows.Forms.TextRenderer]::DrawText(
                $e.Graphics,
                $script:barText,
                $font,
                $form.ClientRectangle,
                $fg,
                ([System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor
                 [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
                 [System.Windows.Forms.TextFormatFlags]::NoPadding))
        } catch {
            "[$(Get-Date -Format o)] Paint error: $_" | Out-File -FilePath $logPath -Append
        }
    })

    [void]$form.Handle

    # Hide from Alt+Tab / taskbar, make click-through, never take focus.
    $ex = [Win32]::GetWindowLong($form.Handle, $GWL_EXSTYLE)
    $ex = ($ex -band (-bnot $WS_EX_APPWINDOW)) -bor $WS_EX_TOOLWINDOW -bor $WS_EX_TRANSPARENT -bor $WS_EX_NOACTIVATE
    [void][Win32]::SetWindowLong($form.Handle, $GWL_EXSTYLE, $ex)

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

    # --- hardware fields, read from the same sources as the tmux bar --------
    # AudioCtl.exe / BatteryCtl.exe are the precompiled helpers that
    # ~/.local/bin/tmux-volume and tmux-battery already shell out to, and netsh
    # is what tmux-hw-status.sh calls. Going to the source directly (rather
    # than reading ~/.cache/tmux-hw) means the overlay is still correct when
    # no tmux client is attached to refresh that cache.
    $script:hw = [hashtable]::Synchronized(@{ volume = ''; battery = ''; wifi = '' })

    $probeScript = {
        $AUDIO = "C:\Users\Admin\AppData\Local\AudioCtl.exe"
        $BATT  = "C:\Users\Admin\AppData\Local\BatteryCtl.exe"
        $NETSH = Join-Path $env:SystemRoot "System32\netsh.exe"

        # Icons are built from codepoints instead of pasted in literally so this
        # file stays pure ASCII: Windows PowerShell 5.1 reads a BOM-less UTF-8
        # script as ANSI, which would mangle any literal glyph.
        function G { param([int]$cp) [char]::ConvertFromUtf32($cp) }
        $icoBolt = G 0xF0E7
        $battIco = @((G 0xF244), (G 0xF243), (G 0xF242), (G 0xF241), (G 0xF240))
        $icoMute = G 0xF0581 ; $icoZero = G 0xF075F
        $icoLow  = G 0xF027  ; $icoHigh = G 0xF028
        $icoWifi = G 0xF0928 ; $icoOff  = G 0xF092D
        $blkFull = [char]0x2588 ; $blkEmpty = [char]0x2591

        function Read-Volume {
            $raw = [string](& $AUDIO status 2>$null)
            if (-not $raw) { return '' }
            $pct = 80 ; $muted = $false
            if ($raw -match 'volume=([0-9.]+)') { $pct = [int][math]::Round([double]$Matches[1]) }
            if ($raw -match 'muted=(\w+)')      { $muted = ($Matches[1] -eq 'True') }
            if ($muted) { return "$icoMute  x" }
            $pct = [math]::Max(0, [math]::Min(100, $pct))
            $icon = if ($pct -eq 0) { $icoZero } elseif ($pct -lt 30) { $icoLow } else { $icoHigh }
            # 3 segments at 34/67/100 -- tmux-volume's thresholds, picked so the
            # last block can actually fill when pct tops out at 100.
            $bar = ''
            foreach ($i in 1..3) {
                $bar += if ($pct -ge [int](($i * 100 + 2) / 3)) { $blkFull } else { $blkEmpty }
            }
            "$icon  $bar $pct%"
        }

        function Read-Battery {
            $raw = [string](& $BATT 2>$null)
            if (-not $raw) { return '' }
            $f = $raw.Trim() -split '\s+'
            if ($f.Count -lt 2) { return '' }
            $pct = [int]$f[0] ; $st = [int]$f[1]
            # BatteryStatus 2,6,7,8,9 all mean on-AC/charging -- same list as
            # tmux-battery, which shows a bolt for all of them.
            if (@(2,6,7,8,9) -contains $st) { return "$icoBolt $pct%" }
            # 0-19,20-39,40-59,60-79,80+ -> the five discharge icons.
            $tier = [math]::Min(4, [math]::Max(0, [int][math]::Floor($pct / 20)))
            "$($battIco[$tier]) $pct%"
        }

        function Read-Wifi {
            $info = & $NETSH wlan show interfaces 2>$null
            if (-not $info) { return "$icoOff offline" }
            $ssid = '' ; $sig = ''
            foreach ($line in ($info -split "`r?`n")) {
                # "^\s*SSID" deliberately will not match "BSSID"; first wins.
                if (-not $ssid -and $line -match '^\s*SSID\s*:\s*(.+?)\s*$')   { $ssid = $Matches[1] }
                if (-not $sig  -and $line -match '^\s*Signal\s*:\s*(.+?)\s*$') { $sig  = $Matches[1] }
            }
            if ($ssid) { "$icoWifi $ssid $sig" } else { "$icoOff offline" }
        }

        $tick = 0
        while ($true) {
            try {
                $v = Read-Volume  ; if ($v) { $hw['volume']  = $v }
                $b = Read-Battery ; if ($b) { $hw['battery'] = $b }
                # netsh costs ~110ms against ~10ms for the two helpers, and the
                # SSID essentially never changes, so it runs every 15th pass.
                if ($tick % 15 -eq 0) { $w = Read-Wifi ; if ($w) { $hw['wifi'] = $w } }
            } catch {
                "[$(Get-Date -Format o)] probe error: $_" | Out-File -FilePath $logPath -Append
            }
            $tick++
            Start-Sleep -Milliseconds 1000
        }
    }

    # The probes run off the UI thread. netsh alone blocks ~110ms, and stalling
    # the 120ms tick would bring back exactly the lag that interval was chosen
    # to kill (the pill lingering for a beat after you leave the browser).
    $script:hwRunspace = [runspacefactory]::CreateRunspace()
    $script:hwRunspace.ApartmentState = 'MTA'
    $script:hwRunspace.ThreadOptions  = 'ReuseThread'
    $script:hwRunspace.Open()
    $script:hwRunspace.SessionStateProxy.SetVariable('hw', $script:hw)
    $script:hwRunspace.SessionStateProxy.SetVariable('logPath', $logPath)
    $script:hwPs = [powershell]::Create()
    $script:hwPs.Runspace = $script:hwRunspace
    [void]$script:hwPs.AddScript($probeScript)
    [void]$script:hwPs.BeginInvoke()

    function Update-Status {
        # Same fields, order and separator as `status-right` in ~/.tmux.conf:
        #   volume | battery | %a %d %b %H:%M | wifi
        # A field is left out entirely until its first probe lands, rather than
        # showing a blank slot, so the pill never renders a stray " | ".
        $now  = [datetime]::Now
        $when = $now.ToString("ddd dd MMM HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
        $parts = @()
        if ($script:hw['volume'])  { $parts += $script:hw['volume'] }
        if ($script:hw['battery']) { $parts += $script:hw['battery'] }
        $parts += $when
        if ($script:hw['wifi'])    { $parts += $script:hw['wifi'] }
        $text = $parts -join ' | '

        # Everything past here resizes the window and re-samples the dot grid,
        # so it is gated on the text actually changing. Building the string
        # above is a handful of concats -- doing that 8x a second is free, and
        # it replaces the old minute-rollover check, which would have missed
        # volume and battery changes.
        if ($script:barText -eq $text) { return }
        $script:barText = $text

        $size = [System.Windows.Forms.TextRenderer]::MeasureText($text, $font)
        $w = $size.Width + (2 * $padX)
        $h = $size.Height + (2 * $padY)
        $form.Size     = New-Object System.Drawing.Size($w, $h)
        # Bottom-right corner. No taskbar (no explorer.exe), so the full
        # screen bounds are usable and WorkingArea would be identical.
        $form.Location = New-Object System.Drawing.Point(
            ($screen.Right - $w - $margin), ($screen.Bottom - $h - $margin))

        # Rounded rectangle, same corner radius as the pet, applied as the
        # window region so the corners outside it aren't drawn at all.
        $r = $Radius
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc(0, 0, $r, $r, 180, 90)
        $path.AddArc(($w - $r), 0, $r, $r, 270, 90)
        $path.AddArc(($w - $r), ($h - $r), $r, $r, 0, 90)
        $path.AddArc(0, ($h - $r), $r, $r, 90, 90)
        $path.CloseFigure()
        $region = New-Object System.Drawing.Region($path)
        $old = $form.Region
        $form.Region = $region
        if ($old) { $old.Dispose() }
        $path.Dispose()

        # Rebuild the dot grid for the new text. Sampling the mask bitmap costs
        # ~23ms at this width, but it only runs when the string changed -- the
        # minute rolling over, or a volume/battery/wifi value moving.
        $script:dotCols = [int](($w - 2 * $DotPad) / $DotPitch)
        $script:dotRows = [int](($h - 2 * $DotPad) / $DotPitch)
        $script:dotMap  = Build-DotMap -Text $text -Cols $script:dotCols -Rows $script:dotRows

        $form.Invalidate()
    }

    # The overlay belongs to Brave only. It never appears over the terminal or
    # any other browser/application.
    $browserProcesses = @('brave')

    $script:lastHwnd    = [IntPtr]::Zero
    $script:lastIsBrowser = $false

    function Test-ForegroundIsBrowser {
        param([IntPtr]$h)
        # Resolving a PID to a process name is the expensive part of the tick,
        # so it's cached and only redone when the foreground window changes.
        if ($h -eq $script:lastHwnd) { return $script:lastIsBrowser }
        $script:lastHwnd = $h
        $pid_ = 0
        [void][Win32]::GetWindowThreadProcessId($h, [ref]$pid_)
        $name = ''
        try { $name = (Get-Process -Id $pid_ -ErrorAction Stop).ProcessName.ToLowerInvariant() } catch { }
        $script:lastIsBrowser = $browserProcesses -contains $name
        return $script:lastIsBrowser
    }

    function Test-ForegroundFullscreen {
        param([IntPtr]$h)
        $r = New-Object Win32+RECT
        if (-not [Win32]::GetWindowRect($h, [ref]$r)) { return $false }

        $mon = [System.Windows.Forms.Screen]::FromHandle($h).Bounds
        $coversScreen = ($r.Left -le $mon.Left) -and ($r.Top -le $mon.Top) -and
                        ($r.Right -ge $mon.Right) -and ($r.Bottom -ge $mon.Bottom)
        if (-not $coversScreen) { return $false }

        $style = [Win32]::GetWindowLong($h, $GWL_STYLE)
        # Fullscreen == covers the monitor AND has dropped its caption.
        # A merely maximised window keeps WS_CAPTION, which is the only thing
        # separating the two cases now that there is no taskbar to eat a row
        # of pixels.
        return ($style -band $WS_CAPTION) -ne $WS_CAPTION
    }

    # Enabled by default on every start. Read the current token so an event from
    # an older process is not replayed after a restart.
    $script:enabled = $true
    $script:lastToggleToken = ''
    if ([System.IO.File]::Exists($toggleSignalPath)) {
        try { $script:lastToggleToken = [System.IO.File]::ReadAllText($toggleSignalPath) } catch { }
    }
    # Start hidden; the first timer tick shows it only if Brave qualifies.
    $script:hidden = $true

    $timer = New-Object System.Windows.Forms.Timer
    # 120ms, not 1s: at 1s the pill visibly lingered for a beat after switching
    # away from the browser. A tick is two or three user32 calls plus a string
    # compare (the PID lookup is cached), so this is still nothing.
    $timer.Interval = 120
    $timer.Add_Tick({
        try {
            Update-Status
            # Consume each Brave-only Ctrl+, event once.
            $toggleToken = $script:lastToggleToken
            if ([System.IO.File]::Exists($toggleSignalPath)) {
                try { $toggleToken = [System.IO.File]::ReadAllText($toggleSignalPath) } catch { }
            }
            if ($toggleToken -ne $script:lastToggleToken) {
                $script:lastToggleToken = $toggleToken
                $script:enabled = -not $script:enabled
            }

            $fg = [Win32]::GetForegroundWindow()
            # Exactly one visibility rule: enabled AND Brave foreground AND not
            # true fullscreen. Every other state is hidden.
            $shouldHide = $true
            if ($fg -ne [IntPtr]::Zero -and $fg -ne $form.Handle) {
                $shouldHide = -not ($script:enabled -and
                    (Test-ForegroundIsBrowser $fg) -and
                    (-not (Test-ForegroundFullscreen $fg)))
            }
            if ($alwaysShow) { $shouldHide = $false }
            if ($shouldHide -ne $script:hidden) {
                $script:hidden = $shouldHide
                if ($shouldHide) {
                    $form.Visible = $false
                } else {
                    # Must go through WinForms rather than a raw ShowWindow call:
                    # Opacity makes this a layered window, and bypassing
                    # Form.Visible leaves it mapped but never composed (invisible).
                    # WS_EX_NOACTIVATE is what keeps this from stealing focus.
                    $form.Visible = $true
                    # Re-assert topmost: another app going fullscreen and back
                    # can otherwise leave us behind it in the Z-order.
                    [void][Win32]::SetWindowPos($form.Handle, $HWND_TOPMOST, 0, 0, 0, 0,
                        ($SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_NOACTIVATE))
                }
                if ($debugDetect) {
                    $h = [Win32]::GetForegroundWindow()
                    $r = New-Object Win32+RECT
                    [void][Win32]::GetWindowRect($h, [ref]$r)
                    $st = [Win32]::GetWindowLong($h, $GWL_STYLE)
                    $t  = [Win32]::TitleOf($h)
                    "[$(Get-Date -Format o)] hide=$shouldHide style=0x$('{0:X8}' -f $st) rect=($($r.Left),$($r.Top))-($($r.Right),$($r.Bottom)) title='$t'" |
                        Out-File -FilePath $logPath -Append
                }
            }
        } catch {
            "[$(Get-Date -Format o)] Tick error: $_" | Out-File -FilePath $logPath -Append
        }
    })

    Update-Status
    if (-not $script:hidden) {
        $form.Show()
        [void][Win32]::SetWindowPos($form.Handle, $HWND_TOPMOST, 0, 0, 0, 0,
            ($SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_NOACTIVATE))
    }
    $timer.Start()

    "[$(Get-Date -Format o)] entering message loop" | Out-File -FilePath $logPath -Append
    [System.Windows.Forms.Application]::Run()

    # The probe loop never returns on its own, so stop it explicitly -- without
    # this the process would linger after the window is gone.
    if ($script:hwPs)       { $script:hwPs.Stop() ; $script:hwPs.Dispose() }
    if ($script:hwRunspace) { $script:hwRunspace.Dispose() }

    "[$(Get-Date -Format o)] message loop exited normally" | Out-File -FilePath $logPath -Append
} catch {
    "[$(Get-Date -Format o)] FATAL: $_" | Out-File -FilePath $logPath -Append
}
