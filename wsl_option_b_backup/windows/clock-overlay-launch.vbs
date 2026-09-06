' Launch clock-overlay.ps1 with no console window.
' Kept separate from the login-shell script so the overlay can be restarted
' during development without ever leaving a floating PowerShell terminal.
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\Users\Admin\AppData\Local\clock-overlay.ps1""", 0, False
