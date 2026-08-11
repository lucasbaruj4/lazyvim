# Claude Code pet

An always-on-top overlay that shows whether Claude Code is working, done, or
waiting for input — so you know to come back to the terminal without having to
keep checking it. Part of the Plan B / WSL-as-login-shell setup (see
`../wsl_option_b_backup/`).

Manually-synced copies of the live files in `~/.claude/pet/`.

| State | Face | Fires on |
|---|---|---|
| working | `[-_-]` blue | `UserPromptSubmit` |
| done | `[^_^]` green | `Stop` |
| needs you | `[o_o]?` amber | `Notification` |

Hides itself when the foreground window is fullscreen, or when the terminal
running Claude is already focused.

## Files

- `pet.ps1` — the overlay (PowerShell + WinForms, no dependencies). Runs on the
  Windows side, copied to `C:\Users\Admin\.claudepet\pet.ps1` at launch.
- `pet-hook.sh` — hook side. Writes `state<TAB>label<TAB>epoch` to
  `C:\Users\Admin\.claudepet\sessions\<session_id>`. Never calls a `.exe`, so
  it adds no latency to turns.
- `pet.sh` — `start` / `stop` / `status` / `ensure`.

## Restoring

1. `cp pet.* pet-hook.sh ~/.claude/pet/ && chmod +x ~/.claude/pet/*.sh`
2. Add to `~/.claude/settings.json`:

```json
"hooks": {
  "UserPromptSubmit": [
    { "hooks": [ { "type": "command", "command": "~/.claude/pet/pet-hook.sh working" } ] }
  ],
  "Notification": [
    { "hooks": [ { "type": "command", "command": "~/.claude/pet/pet-hook.sh waiting" } ] }
  ],
  "Stop": [
    { "hooks": [ { "type": "command", "command": "~/.claude/pet/pet-hook.sh done" } ] }
  ],
  "SessionEnd": [
    { "hooks": [ { "type": "command", "command": "~/.claude/pet/pet-hook.sh gone" } ] }
  ]
}
```

3. Autostart is the last block in `../bashrc_backup/.bashrc`. There is no
   `explorer.exe` on this setup, so the Startup folder and the `HKCU\...\Run`
   key are both dead — the shell is what launches it.

## Two gotchas worth remembering

- **`IsZoomed` cannot detect fullscreen.** It returns `True` for *both*
  maximized and fullscreen Chromium windows. The discriminator is `WS_CAPTION`
  (`0x00C00000`): maximized Brave is style `0x17CF0000`, fullscreen Brave is
  `0x170B0000`. Geometry alone does not work either — with no taskbar,
  `WorkingArea == Bounds`.
- **Never animate the window's `Opacity`.** Pulsing a layered window's opacity
  flickers badly. The pet is deliberately static.
