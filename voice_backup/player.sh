#!/usr/bin/env bash
# Drains ~/.claude/voice/queue in order, one item at a time.
#
# Several Claude Code sessions (different tmux panes) share this queue. Only one
# player runs at a time -- the flock guarantees it -- so a response never gets
# cut off by another session finishing. Between items it says a short line so
# it is obvious the speaker changed.
set -uo pipefail
V="$HOME/.claude/voice"
Q="$V/queue"
PS=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
WTMP=/mnt/c/Users/Admin/AppData/Local/Temp


exec 9>"$V/player.lock"
flock -n 9 || exit 0            # another player is already draining the queue
echo $$ > "$V/pid"
trap 'rm -f "$V/pid"' EXIT

MODEL=$(cat "$V/voice.conf" 2>/dev/null || echo "en_US-lessac-medium")
[ -f "$V/voices/$MODEL.onnx" ] || MODEL="en_US-lessac-medium"

render() {  # $1 = text file, $2 = out wav
  LD_LIBRARY_PATH="$V/piper" "$V/piper/piper" \
    --espeak_data "$V/piper/espeak-ng-data" \
    --model "$V/voices/$MODEL.onnx" --output_file "$2" 2>/dev/null < "$1"
}

play_wav() {
  if [ -x "$PS" ]; then
    "$PS" -NoProfile -NonInteractive -Command \
      "(New-Object Media.SoundPlayer \"$(wslpath -w "$1")\").PlaySync()" \
      </dev/null >/dev/null 2>&1
  else
    paplay "$1" 2>/dev/null
  fi
}

# Speak one text file, chunked so playback starts after the first sentence
# rather than after the whole thing is rendered.
speak_file() {
  local src="$1"
  local work; work=$(mktemp -d "${TMPDIR:-/tmp}/spk.XXXXXX") || return
  local wdir="$WTMP/spk_$$_$RANDOM"
  mkdir -p "$wdir" 2>/dev/null || wdir="$work"
  awk -v d="$work" '
    NR==1 { f=sprintf("%s/c%03d.txt", d, 0); print > f; close(f); next }
    { i=int((NR-2)/4)+1; f=sprintf("%s/c%03d.txt", d, i); print >> f }
  ' "$src"
  ( for t in "$work"/c*.txt; do
      b=$(basename "$t" .txt)
      render "$t" "$wdir/$b.part" && mv "$wdir/$b.part" "$wdir/$b.wav"
    done
    touch "$work/rendered" ) &
  local prod=$!
  for t in "$work"/c*.txt; do
    b=$(basename "$t" .txt)
    while [ ! -f "$wdir/$b.wav" ]; do
      [ -f "$work/rendered" ] && [ ! -f "$wdir/$b.wav" ] && break
      sleep 0.1
    done
    [ -f "$wdir/$b.wav" ] || continue
    play_wav "$wdir/$b.wav"
    rm -f "$wdir/$b.wav"
  done
  wait "$prod" 2>/dev/null
  rm -rf "$work" "$wdir"
}

say_line() {  # short spoken notice
  local t; t=$(mktemp); printf '%s\n' "$1" > "$t"
  local w="$WTMP/hand_$$_$RANDOM.wav"
  render "$t" "$w" && [ -s "$w" ] && play_wav "$w"
  rm -f "$t" "$w"
}

first=1
while :; do
  [ -f "$V/muted" ] && { rm -f "$Q"/*.txt 2>/dev/null; break; }
  next=$(ls -1 "$Q"/*.txt 2>/dev/null | sort | head -1)
  [ -z "$next" ] && break
  label=$(head -1 "$next")
  body=$(mktemp); tail -n +2 "$next" > "$body"
  prev=$(cat "$V/last-label" 2>/dev/null || echo "")

  # Only announce when the speaker actually changes -- consecutive replies from
  # the same session should not each get an announcement.
  if [ -n "$prev" ] && [ "$label" != "$prev" ]; then
    sleep 0.8
    say_line "Now reading the output of session $label."
    sleep 0.3
  fi
  printf '%s' "$label" > "$V/last-label"
  printf '%s played [%s] prev=[%s]\n' "$(date +%H:%M:%S)" "$label" "$prev" >> "$V/player.log"
  tail -n 200 "$V/player.log" > "$V/player.log.t" 2>/dev/null && mv "$V/player.log.t" "$V/player.log"

  speak_file "$body"
  rm -f "$body" "$next"
  first=0
done
