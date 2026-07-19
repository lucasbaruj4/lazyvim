# clipboard-watcher.ps1
# Watches the Windows clipboard. The instant a new image shows up on it
# (Win+Shift+S, PrtSc, Snipping Tool, etc.), it runs `paste-screenshot`
# inside WSL, which saves the image into ~/Pictures/screenshots and puts
# the resulting WSL path back on the clipboard as text — ready for
# Ctrl+Shift+V in the terminal. No manual command needed anymore.

Add-Type -AssemblyName System.Windows.Forms

$wasImage = $false

while ($true) {
    try {
        if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
            if (-not $wasImage) {
                $wasImage = $true
                Start-Process -FilePath "wsl.exe" `
                    -ArgumentList "-d", "Ubuntu", "--", "/home/lucas/.local/bin/paste-screenshot" `
                    -WindowStyle Hidden -Wait
            }
        } else {
            $wasImage = $false
        }
    } catch {
        # Clipboard can be transiently locked by another app; just retry next tick.
    }
    Start-Sleep -Milliseconds 800
}
