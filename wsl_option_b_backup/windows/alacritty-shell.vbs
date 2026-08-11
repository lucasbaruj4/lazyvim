' alacritty-shell.vbs
' Used as the Windows login Shell (replaces explorer.exe).
' Starts background helpers, then launches Alacritty and BLOCKS until it
' exits. This is required: whatever process the Shell registry key points
' to must stay alive for the whole session -- when it exits, Windows logs
' the user off, exactly like closing explorer.exe normally would.
' Practical effect: closing the Alacritty window now logs you out.

Set WshShell = CreateObject("WScript.Shell")

' Background helper: screenshot clipboard watcher (fire-and-forget)
WshShell.Run "powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\Users\Admin\AppData\Local\clipboard-watcher.ps1""", 0, False

' Background helper: wallpaper window, so Alacritty's opacity has something
' to show through. Launched before Alacritty so it's already on screen.
WshShell.Run "powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\Users\Admin\AppData\Local\wallpaper-window.ps1""", 0, False

' Background helper: always-on-top clock overlay in the top-right corner, so
' the time is readable from the browser without switching to the tmux bar.
' It hides itself whenever the foreground window is truly fullscreen --
' YouTube video fullscreen, and Alacritty (which starts fullscreen and
' already shows the same clock in its status bar).
WshShell.Run "powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\Users\Admin\AppData\Local\clock-overlay.ps1""", 0, False

' Background helper: system-wide hotkey listener (GlobalHotkeys.exe) --
' screenshot (Shift+S), volume up/down (Ctrl+Alt+Up/Down), mute toggle
' (Ctrl+Shift+M). Registers real Windows global hotkeys, so they work no
' matter which app has focus -- not just Alacritty.
WshShell.Run """C:\Users\Admin\AppData\Local\GlobalHotkeys.exe""", 0, False
WScript.Sleep 400

' Foreground: Alacritty. 1 = normal window (it self-fullscreens via its own
' config), True = wait here until it exits, keeping the session alive.
WshShell.Run """C:\Program Files\Alacritty\alacritty.exe""", 1, True
