# Claude Code pet

A small always-on-top dot-matrix badge that shows whether Claude Code is
working, done, or waiting for input — so a long turn can be left running while
watching something else, without checking the terminal. Part of the Plan B /
WSL-as-login-shell setup (see `../wsl_option_b_backup/`).

The look is after the Nothing phone's glyph display: the label is rendered into
a tiny offscreen bitmap, then every lit pixel is drawn as a circle, and the
whole strip scrolls past like an LED marquee.

Manually-synced copies of the live files in `~/.claude/pet/`.

| State | Label | Colour | Fires on |
|---|---|---|---|
| working | `WORKING` | blue | `UserPromptSubmit` |
| done | `DONE` | green | `Stop` |
| needs input | `QUESTION` | amber | `Notification` |

`Notification` covers both permission prompts and multiple-choice questions.
Hides itself when the foreground window is fullscreen, or when the terminal
running Claude is already focused. Drag to move; position is remembered.

`../wsl_option_b_backup/windows/clock-overlay.ps1` shares this aesthetic —
same panel colour, corner radius, and dot grid — but does not scroll.

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

## Tuning

All at the top of `pet.ps1`:

- `$W` / `$H` — badge size, matched to the clock overlay.
- `$DotPitch` / `$DotRadius` — grid density. Smaller pitch is finer and more
  legible; larger is chunkier and more Nothing-like. `$Pad` is 0 so the grid
  runs edge to edge.
- `$ScrollMs` / `$ScrollGap` — marquee speed and the gap between repeats.
- `$Transparent` — `$true` drops the dark panel so only lit dots show. Note
  clicks then pass through everywhere except the dots, making it hard to drag.

## Gotchas worth remembering

- **`IsZoomed` cannot detect fullscreen.** It returns `True` for *both*
  maximized and fullscreen Chromium windows. The discriminator is `WS_CAPTION`
  (`0x00C00000`): maximized Brave is style `0x17CF0000`, fullscreen Brave is
  `0x170B0000`. Geometry alone does not work either — with no taskbar,
  `WorkingArea == Bounds`.
- **Never animate the window's `Opacity`.** Pulsing a layered window's opacity
  flickers badly. The marquee animates pre-rendered bitmaps instead.
- **`return $map` on a 2-D array is a trap.** PowerShell enumerates it into
  loose booleans, and `$map[$x,$y]` on the resulting 1-D array returns a
  2-element slice, which is always truthy — every cell reads as lit and the
  panel fills solid. Use `return ,$map`.
- **Frames are pre-rendered per state at startup.** Building one takes about a
  second at this density; doing it lazily froze the badge for that second the
  first time a question arrived.
- **Anything matching `*pet.ps1*` in a `Get-CimInstance` filter matches the
  querying process too** — its own command line contains the pattern. `stop`
  and `status` exclude `$PID` for this reason.
