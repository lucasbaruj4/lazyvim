# wallpaper-window.ps1
# Since explorer.exe no longer runs, nothing renders the desktop wallpaper.
# This opens a plain borderless window showing the wallpaper image, scaled
# to fully cover the screen (cropping overflow, like Windows' "Fill" style
# -- BackgroundImageLayout=Zoom letterboxes instead, hence custom painting).
# Launched before Alacritty, so Alacritty (focused after) sits on top --
# its opacity lets this show through underneath.

$logPath = "C:\Users\Admin\AppData\Local\wallpaper-window.log"
"[$(Get-Date -Format o)] starting" | Out-File -FilePath $logPath -Append

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # ShowInTaskbar=$false only hides this from the taskbar -- Alt+Tab uses
    # a separate rule (the WS_EX_TOOLWINDOW extended style), so without this
    # the wallpaper window was still showing up as a blank entry when
    # Alt+Tabbing between Alacritty and the browser.
    #
    # WallpaperForm additionally makes the window impossible to raise or focus.
    # A plain form is activatable, and SendToBack() only applies once: when
    # focus left Alacritty, Windows could pick this window as the next thing to
    # activate, floating a fullscreen wallpaper above the browser (so switching
    # Alacritty -> Brave appeared to leave the terminal on top). Three guards:
    #   ShowWithoutActivation  -- Show() doesn't steal focus
    #   WM_MOUSEACTIVATE       -- clicking the wallpaper doesn't activate/raise
    #   WM_WINDOWPOSCHANGING   -- every z-order change is rewritten to
    #                             HWND_BOTTOM, so it can never come forward
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class WinExStyle {
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
}
public class WallpaperForm : Form {
    const int WM_WINDOWPOSCHANGING = 0x0046;
    const int WM_MOUSEACTIVATE     = 0x0021;
    const int MA_NOACTIVATE        = 3;
    const uint SWP_NOZORDER        = 0x0004;
    static readonly IntPtr HWND_BOTTOM = new IntPtr(1);

    [StructLayout(LayoutKind.Sequential)]
    struct WINDOWPOS {
        public IntPtr hwnd; public IntPtr hwndInsertAfter;
        public int x; public int y; public int cx; public int cy; public uint flags;
    }

    protected override bool ShowWithoutActivation { get { return true; } }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_MOUSEACTIVATE) { m.Result = (IntPtr)MA_NOACTIVATE; return; }
        if (m.Msg == WM_WINDOWPOSCHANGING) {
            WINDOWPOS wp = (WINDOWPOS)Marshal.PtrToStructure(m.LParam, typeof(WINDOWPOS));
            wp.hwndInsertAfter = HWND_BOTTOM;
            wp.flags &= ~SWP_NOZORDER;
            Marshal.StructureToPtr(wp, m.LParam, false);
        }
        base.WndProc(ref m);
    }
}
"@
    $GWL_EXSTYLE = -20
    $WS_EX_TOOLWINDOW = 0x80
    $WS_EX_APPWINDOW = 0x40000
    $WS_EX_NOACTIVATE = 0x08000000

    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        "[$(Get-Date -Format o)] ThreadException: $($e.Exception)" | Out-File -FilePath $logPath -Append
    })

    $form = New-Object WallpaperForm
    $form.FormBorderStyle = 'None'
    $form.ShowInTaskbar = $false
    $form.TopMost = $false
    $form.StartPosition = 'Manual'
    $form.BackColor = [System.Drawing.Color]::Black

    [void]$form.Handle
    $exStyle = [WinExStyle]::GetWindowLong($form.Handle, $GWL_EXSTYLE)
    $exStyle = ($exStyle -band (-bnot $WS_EX_APPWINDOW)) -bor $WS_EX_TOOLWINDOW -bor $WS_EX_NOACTIVATE
    [WinExStyle]::SetWindowLong($form.Handle, $GWL_EXSTYLE, $exStyle)

    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $form.Bounds = $bounds

    $image = [System.Drawing.Image]::FromFile("C:\Users\Admin\Pictures\Wallpaper\canyon-light-trails.jpg")

    $scale = [Math]::Max($bounds.Width / $image.Width, $bounds.Height / $image.Height)
    $w = $image.Width * $scale
    $h = $image.Height * $scale
    $x = ($bounds.Width - $w) / 2
    $y = ($bounds.Height - $h) / 2

    $form.Add_Paint({
        param($sender, $e)
        try {
            $e.Graphics.DrawImage($image, $x, $y, $w, $h)
        } catch {
            "[$(Get-Date -Format o)] Paint error: $_" | Out-File -FilePath $logPath -Append
        }
    })

    $form.Add_Shown({ $form.SendToBack() })
    $form.Show()

    "[$(Get-Date -Format o)] entering message loop" | Out-File -FilePath $logPath -Append
    [System.Windows.Forms.Application]::Run($form)
    "[$(Get-Date -Format o)] message loop exited normally" | Out-File -FilePath $logPath -Append
} catch {
    "[$(Get-Date -Format o)] FATAL: $_" | Out-File -FilePath $logPath -Append
}
