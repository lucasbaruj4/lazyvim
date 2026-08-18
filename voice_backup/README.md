# Voice for Claude Code

Talk to Claude Code and have it talk back, entirely offline. No subscription,
no API calls, nothing leaves the machine. Part of the Plan B / WSL-as-login-
shell setup (see `../wsl_option_b_backup/`).

Manually-synced copies of the live files in `~/.claude/voice/`.

| Key | Does |
|---|---|
| `Alt+V` | Start recording; press again to transcribe and type the text into the pane |
| `Alt+S` | Stop speech mid-sentence; press again while silent to mute/unmute |

Bindings live in `../tmux_backup/.tmux.conf`. Both use `run-shell -b` — without
`-b` the whole tmux server freezes for the length of the transcription.

## Pieces

| File | Role |
|---|---|
| `dictate.sh` | `Alt+V` toggle: record → transcribe → type |
| `transcribe.py` | One-shot Whisper call; holds the vocabulary prompt |
| `speak.sh` | Reads stdin aloud via Piper; strips code blocks and markdown |
| `stop-hook.sh` | Claude Code `Stop` hook; speaks the final message of a turn |
| `shush.sh` | `Alt+S` stop/mute |
| `whisperd.py.disabled` | Abandoned persistent daemon — see Gotchas |

## Rebuilding on a new machine

Not in git: the Piper binary, the voice model, and the Python venv (600MB+).

1. Piper from the rhasspy/piper releases — **match the arch**, this box is
   `aarch64`, not `x86_64`. Extract to `~/.claude/voice/piper/`.
2. Voice `en_US-lessac-medium` (`.onnx` + `.onnx.json`) into
   `~/.claude/voice/voices/`.
3. `python3 -m venv ~/.claude/voice/venv && ~/.claude/voice/venv/bin/pip
   install faster-whisper`. First run downloads `small.en` (~470MB) to the HF
   cache; after that `local_files_only=True` keeps it offline.
4. Register `stop-hook.sh` in the `Stop` array of `~/.claude/settings.json`,
   alongside the pet hook.

## Gotchas

Each of these cost real debugging time:

- **Piper needs `--espeak_data` explicitly.** Without it, it silently emits
  zero bytes and `paplay` still exits 0 — a false pass.
- **`parecord` must get `9>&-`.** It otherwise inherits the lock file
  descriptor and holds the lock for the whole recording, so the stop press can
  never acquire it and dictation wedges permanently.
- **`run-shell` is synchronous.** Without `-b`, tmux freezes while Whisper
  runs, keypresses queue, then cascade into start/stop/start/stop.
- **The daemon idea killed WSL.** `whisperd.py` loaded its 570MB model *before*
  binding its port, so nothing stopped duplicates during the ~20s startup, and
  `dictate.sh` spawned one on both the record and stop press. It OOM'd a 9.9GB
  box. Kept disabled as a warning. Doing it properly means binding the port
  first, then loading, plus a lockfile.
- **Whisper needs the vocabulary prompt.** Without `initial_prompt` it hears
  "Alt+V" as "all V" and "tmux" as "T-Mux". Add new terms to `PROMPT` in
  `transcribe.py`.
- **The Stop hook speaks only the final message.** A turn is many text blocks
  interleaved with tool calls; the lead-ins narrate work in progress and are
  deliberately skipped.

Transcription takes ~4s per utterance. `WHISPER_MODEL=base.en` is ~2s and
noticeably worse on technical words.
