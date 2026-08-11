# clock-overlay.ps1
# Always-on-top clock, styled like the tmux status bar, so the time is
# readable without switching to the terminal (mainly while in the browser).
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
    $fontName = "Consolas"   # mask font: stays crisp at the tiny sizes the grid samples
    $fontSize = 16
    $margin   = 20       # gap from the bottom-right screen corner
    $padX     = 20
    $padY     = 9

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

    $script:clockText = ""
    $script:dotMap    = $null
    $script:dotCols   = 0
    $script:dotRows   = 0

    $litBrush   = New-Object System.Drawing.SolidBrush($fg)
    $unlitBrush = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb($GridAlpha, $fg.R, $fg.G, $fg.B))

    # Render $Text into a $Cols x $Rows grid and record which cells are lit.
    # The mask font size is fitted to the row count, so the grid stays filled
    # whatever the pill ends up sized at.
    function Build-DotMap {
        param([string]$Text, [int]$Cols, [int]$Rows)
        $bmp = New-Object System.Drawing.Bitmap($Cols, $Rows)
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $g.Clear([System.Drawing.Color]::Black)
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit

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

        $map = New-Object 'bool[,]' $Cols, $Rows
        for ($y = 0; $y -lt $Rows; $y++) {
            for ($x = 0; $x -lt $Cols; $x++) {
                $map[$x, $y] = ($bmp.GetPixel($x, $y).R -gt 110)
            }
        }
        $mask.Dispose(); $g.Dispose(); $bmp.Dispose()
        # NOTE the comma: returning a 2-D array bare makes PowerShell enumerate
        # it into loose booleans, and $map[$x,$y] on the resulting 1-D array
        # returns a 2-element slice, which is always truthy -- every cell reads
        # as lit and the panel fills solid. `,$map` returns the array itself.
        return ,$map
    }

    $form.Add_Paint({
        param($sender, $e)
        try {
            if (-not $script:dotMap) { return }
            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $d = $DotRadius * 2
            for ($y = 0; $y -lt $script:dotRows; $y++) {
                for ($x = 0; $x -lt $script:dotCols; $x++) {
                    $cx = $DotPad + $x * $DotPitch + $DotPitch / 2 - $DotRadius
                    $cy = $DotPad + $y * $DotPitch + $DotPitch / 2 - $DotRadius
                    $e.Graphics.FillEllipse(
                        ($(if ($script:dotMap[$x, $y]) { $litBrush } else { $unlitBrush })),
                        $cx, $cy, $d, $d)
                }
            }
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

    $script:lastMinute = -1

    function Update-Clock {
        # Ticking 8x a second, so bail on an int compare before doing any date
        # formatting or string allocation -- only the minute rollover matters.
        $now = [datetime]::Now
        if ($now.Minute -eq $script:lastMinute) { return }
        $script:lastMinute = $now.Minute

        # Time only -- the tmux bar keeps the full "%a %d %b %H:%M" version.
        $text = $now.ToString("HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
        if ($script:clockText -eq $text) { return }
        $script:clockText = $text

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

        # Rebuild the dot grid for the new time. Once a minute, so the cost of
        # rendering and sampling the mask bitmap does not matter.
        $script:dotCols = [int](($w - 2 * $DotPad) / $DotPitch)
        $script:dotRows = [int](($h - 2 * $DotPad) / $DotPitch)
        $script:dotMap  = Build-DotMap -Text $text -Cols $script:dotCols -Rows $script:dotRows

        $form.Invalidate()
    }

    # The clock is pinned to the browser: it only exists while a browser window
    # is the one you're looking at. Anywhere else (terminal included) it is
    # simply not there, so it can never cover the tmux status bar.
    $browserProcesses = @('brave', 'chrome', 'msedge', 'firefox', 'vivaldi', 'zen')

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

    $script:hidden = $false  # matches the initial Show() below

    $timer = New-Object System.Windows.Forms.Timer
    # 120ms, not 1s: at 1s the pill visibly lingered for a beat after switching
    # away from the browser. A tick is two or three user32 calls plus a string
    # compare (the PID lookup is cached), so this is still nothing.
    $timer.Interval = 120
    $timer.Add_Tick({
        try {
            Update-Clock
            $fg = [Win32]::GetForegroundWindow()
            # Visible only when a browser is in front and not in video
            # fullscreen. Our own window as foreground is ignored -- reusing
            # the previous decision -- so the pill can't flicker itself away.
            if ($fg -eq [IntPtr]::Zero -or $fg -eq $form.Handle) {
                $shouldHide = $script:hidden
            } else {
                $shouldHide = -not ((Test-ForegroundIsBrowser $fg) -and (-not (Test-ForegroundFullscreen $fg)))
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

    Update-Clock
    $form.Show()
    [void][Win32]::SetWindowPos($form.Handle, $HWND_TOPMOST, 0, 0, 0, 0,
        ($SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_NOACTIVATE))
    $timer.Start()

    "[$(Get-Date -Format o)] entering message loop" | Out-File -FilePath $logPath -Append
    [System.Windows.Forms.Application]::Run()
    "[$(Get-Date -Format o)] message loop exited normally" | Out-File -FilePath $logPath -Append
} catch {
    "[$(Get-Date -Format o)] FATAL: $_" | Out-File -FilePath $logPath -Append
}
