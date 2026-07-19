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
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinExStyle {
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
}
"@
    $GWL_EXSTYLE = -20
    $WS_EX_TOOLWINDOW = 0x80
    $WS_EX_APPWINDOW = 0x40000

    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        "[$(Get-Date -Format o)] ThreadException: $($e.Exception)" | Out-File -FilePath $logPath -Append
    })

    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.ShowInTaskbar = $false
    $form.TopMost = $false
    $form.StartPosition = 'Manual'
    $form.BackColor = [System.Drawing.Color]::Black

    [void]$form.Handle
    $exStyle = [WinExStyle]::GetWindowLong($form.Handle, $GWL_EXSTYLE)
    $exStyle = ($exStyle -band (-bnot $WS_EX_APPWINDOW)) -bor $WS_EX_TOOLWINDOW
    [WinExStyle]::SetWindowLong($form.Handle, $GWL_EXSTYLE, $exStyle)

    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $form.Bounds = $bounds

    $image = [System.Drawing.Image]::FromFile("C:\Users\Admin\Pictures\Wallpaper\mountain.jpg")

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
