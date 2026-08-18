# Voice for Claude Code

Talk to Claude Code and have it talk back, entirely offline. No subscription,
no API calls, nothing leaves the machine. Part of the Plan B / WSL-as-login-
shell setup (see `../wsl_option_b_backup/`).

Manually-synced copies of the live files in `~/.claude/voice/`.

| Key | Does |
|---|---|
| `Alt+V` | Start recording; press again to transcribe and type the text into the pane |
| `Alt+S` | Stop speech mid-sentence; press again while silent to mute/unmute |

Dictation **sends the message immediately** — attach screenshots before
dictating, not after. Change the voice with `voice.sh set <name>`; `voice.sh
demo` plays every installed voice. Voices live in `~/.claude/voice/voices/`
and are not in git.

Bindings live in `../tmux_backup/.tmux.conf`. Both use `run-shell -b` — without
`-b` the whole tmux server freezes for the length of the transcription.

## Pieces

| File | Role |
|---|---|
| `dictate.sh` | `Alt+V` toggle: record → transcribe → type |
| `transcribe.py` | One-shot Whisper call; holds the vocabulary prompt |
| `speak.sh` | Cleans stdin and queues it; does not play anything itself |
| `player.sh` | Drains the queue, one item at a time, across all sessions |
| `stop-hook.sh` | Claude Code `Stop` hook; speaks the final message of a turn |
| `shush.sh` | `Alt+S` stop/mute |
| `voice.sh` | list / demo / set the voice |
| `voice.conf` | the currently selected voice |
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

## One queue, many sessions

Several Claude Code sessions in different tmux panes share one queue. `speak.sh`
only *enqueues*; a single `player.sh` holds a lock and drains it in order, so a
reply is never cut off by another pane finishing. When the speaker changes, the
player announces "Now reading the output of session X", taking X from the tmux
window name. Consecutive replies from the same session are not announced.

`Alt+S` stops the current item **and** clears the queue.

Rendering is chunked: the first sentence is rendered and played while the rest
is still being synthesised. This matters because a `-high` voice runs at only
~0.27x realtime -- rendering a long answer in one go meant ~36s of silence
first, versus ~1s now.

## Playback goes through Windows, not WSLg

`speak.sh` writes a wav into the Windows temp directory and plays it with
PowerShell's `SoundPlayer`. That looks like a detour and it is not — **WSLg's
audio is the problem.** Playing through PulseAudio produced dropouts scattered
right through the middle of every sentence, badly enough to hurt comprehension.

What was tried and rejected, in order:

| Attempt | Result |
|---|---|
| `paplay`, default buffer | scattered dropouts |
| `paplay --latency-msec=500` | much worse |
| `paplay --latency-msec=30` | much worse still |
| 44100 stereo via ffmpeg | dramatically worse |
| `ffplay` instead of `paplay` | worse, and slower to start |
| **wav → Windows `SoundPlayer`** | **clean** |

Two independent Linux clients failing the same way put the fault below both.
Do not "simplify" this back to `paplay`. The PulseAudio path is kept only as a
fallback for when interop is unavailable.

Worth knowing: none of this was visible from inside WSL. Recording the sink
monitor showed byte-perfect audio — same length, no gaps, no saturation — while
it sounded broken at the speakers. The fault is past the last point Linux can
measure, so listening was the only reliable instrument.

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

- **The Whisper prompt caps at 224 tokens** and is silently truncated past
  that. The current one is ~178. Measure with the tokenizer before adding
  words; it carries the repo names, so new projects belong there.
- **Text is filtered before synthesis.** Commit hashes, `--flags`, paths and
  filenames like `speak.sh` are gibberish when read aloud, so they are stripped
  or reduced. Add new patterns to the second `sed` in `speak.sh`.
- **The Stop hook must wait for the transcript to settle.** It fires while
  Claude Code is still flushing the final message, so reading immediately gets
  the previous block instead.

Transcription takes ~4s per utterance. `WHISPER_MODEL=base.en` is ~2s and
noticeably worse on technical words.
