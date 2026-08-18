#!/usr/bin/env bash
# Toggle dictation. First press records, second press transcribes and types
# the text into the tmux pane (you press Enter yourself).
#
# Two guards, both learned the hard way:
#   - a lock, so keypresses that pile up while transcribing are dropped
#     instead of cascading into start/stop/start/stop
#   - a minimum recording length, so a stray double-press can't stop a
#     recording half a second after it began
set -uo pipefail
V="$HOME/.claude/voice"
WAV="$V/rec.wav"
PIDF="$V/rec.pid"
STARTF="$V/rec.start"
MIN_MS=1000
PANE="${1:-}"

msg() { [ -n "${TMUX:-}" ] && tmux display-message "$1" || echo "$1"; }

# Only one instance at a time. A press while busy is ignored, not queued.
exec 9>"$V/lock"
flock -n 9 || { msg "voice busy, ignoring"; exit 0; }

now_ms() { echo $(($(date +%s%N)/1000000)); }

if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
  # ---- second press: stop and transcribe ----
  started=$(cat "$STARTF" 2>/dev/null || echo 0)
  elapsed=$(( $(now_ms) - started ))
  if [ "$elapsed" -lt "$MIN_MS" ]; then
    msg "still recording (ignored a fast double-press)"
    exit 0
  fi

  kill -INT "$(cat "$PIDF")" 2>/dev/null
  rm -f "$PIDF" "$STARTF"
  sleep 0.3

  bytes=$(stat -c%s "$WAV" 2>/dev/null || echo 0)
  if [ "$bytes" -lt 32000 ]; then          # under ~1s of 16kHz mono audio
    msg "too short, nothing to transcribe"
    exit 0
  fi

  msg "transcribing..."
  text=$("$V/venv/bin/python" "$V/transcribe.py" "$WAV" 2>/dev/null | tail -1)
  if [ -z "$text" ]; then
    msg "heard nothing"
    exit 0
  fi
  if [ -n "$PANE" ] && [ -n "${TMUX:-}" ]; then
    tmux send-keys -t "$PANE" -l "$text"
    msg "typed: ${text:0:50}"
  else
    printf '%s\n' "$text"
  fi
else
  # ---- first press: start recording ----
  rm -f "$WAV"
  # 9>&- is essential: without it parecord inherits the lock fd and holds
  # the lock for the whole recording, so the stop press can never acquire it.
  parecord --device=RDPSource --rate=16000 --channels=1 \
           --file-format=wav "$WAV" >/dev/null 2>&1 9>&- &
  echo $! > "$PIDF"
  now_ms > "$STARTF"
  msg "recording... press Alt+V again to stop"
fi
