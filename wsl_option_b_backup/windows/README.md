# Windows-side helpers (Plan B)

Backup copies of the Windows files behind the no-explorer.exe setup, where
Alacritty replaces `explorer.exe` as the login shell. Live location for all of
them is `C:\Users\Admin\AppData\Local\` (except `alacritty.toml`, which lives
in `C:\Users\Admin\AppData\Roaming\alacritty\`).

These are copies, not symlinks — after editing a live file, copy it back here
by hand.

| File | What it does |
| --- | --- |
| `alacritty-shell.vbs` | The login shell itself. Starts the clipboard watcher and hotkey listener, then runs Alacritty in the foreground and blocks. Closing Alacritty logs you out. |
| `alacritty.toml` | Alacritty config; spawns `wsl.exe -d Ubuntu`. |
| `GlobalHotkeys.cs` | System-wide hotkeys: Shift+S screenshot, Ctrl+Alt+Up/Down volume, Ctrl+Shift+M mute, Alt+1 Alacritty, Alt+2 Brave. Also blocks Alt+Tab and Alt+Space. |
| `AudioCtl.cs` | COM audio-endpoint helper the volume hotkeys call. |
| `wallpaper-window.ps1` | Optional borderless fullscreen wallpaper; not started automatically. Pins itself to the bottom of the z-order. |
| `clock-overlay.ps1` | Always-on-top corner clock, hides over fullscreen windows. |
| `clipboard-watcher.ps1` | Writes clipboard screenshots out to a file. |

## Building the .cs files

They're plain .NET Framework, no project file:

```
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe ^
  /out:C:\Users\Admin\AppData\Local\GlobalHotkeys.exe ^
  C:\Users\Admin\AppData\Local\GlobalHotkeys.cs
```

`/target:winexe` matters — it's what keeps the process from opening a console
window. Same command for `AudioCtl.cs`.

To restart a helper after rebuilding, launch it detached, or it dies with the
shell that started it:

```
powershell.exe -NoProfile -Command "Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='C:\Users\Admin\AppData\Local\GlobalHotkeys.exe'}"
```
