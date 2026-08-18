#!/usr/bin/env bash
# Speaks stdin aloud with Piper. Prose only: code blocks and markdown are stripped.
# Touch ~/.claude/voice/muted to silence; remove it to unmute.
set -uo pipefail
V="$HOME/.claude/voice"
[ -f "$V/muted" ] && exit 0

# Only one voice at a time: kill whatever is still talking.
[ -f "$V/pid" ] && kill -- "-$(cat "$V/pid")" 2>/dev/null
rm -f "$V/pid"

text=$(cat)
clean=$(printf '%s' "$text" | awk '
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  { print }
' | sed -E '
  s/!?\[([^]]*)\]\([^)]*\)/\1/g;   # links -> label
  s/`([^`]*)`/\1/g;                 # inline code -> bare word
  s/[*_#>|]+//g;                    # markdown syntax
  s/^[[:space:]]*[-+][[:space:]]+/ /;# bullets
  s/[[:space:]]+/ /g;
')
clean=$(printf '%s' "$clean" | tr -s ' \n' ' ' | sed 's/^ *//; s/ *$//')
[ -z "$clean" ] && exit 0

# Piper synthesises line by line. One 800-character line becomes a single
# breathless utterance; one sentence per line gives it natural boundaries.
clean=$(printf '%s' "$clean" | sed 's/\([.!?]\) \+/\1\n/g')

# Which voice to use. Change it with: ~/.claude/voice/voice.sh set <name>
MODEL=$(cat "$V/voice.conf" 2>/dev/null || echo "en_US-lessac-medium")
[ -f "$V/voices/$MODEL.onnx" ] || MODEL="en_US-lessac-medium"
RATE=$(jq -r '.audio.sample_rate // 22050' "$V/voices/$MODEL.onnx.json" 2>/dev/null)

# Play through WINDOWS, not WSLg. Both paplay and ffplay clip scattered
# dropouts through the middle, which puts the fault below them in WSLg's RDP
# audio. Writing a wav to the Windows temp dir and playing it with SoundPlayer
# skips that path entirely. Falls back to paplay if interop is unavailable.
setsid bash -c '
  PS=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
  WTMP=/mnt/c/Users/Admin/AppData/Local/Temp
  raw=$(mktemp "${TMPDIR:-/tmp}/piper.XXXXXX.raw") || exit 0
  wav=""
  [ -d "$WTMP" ] && wav="$WTMP/piper_$$_$RANDOM.wav"
  trap "rm -f \"$raw\" \"$wav\"" EXIT

  if [ -n "$wav" ] && [ -x "$PS" ]; then
    LD_LIBRARY_PATH="$1/piper" "$1/piper/piper" \
      --espeak_data "$1/piper/espeak-ng-data" \
      --model "$1/voices/$2.onnx" --output_file "$wav" 2>/dev/null
    if [ -s "$wav" ]; then
      win=$(wslpath -w "$wav")
      # stdin from /dev/null: a Windows exe otherwise drains the script stdin
      "$PS" -NoProfile -NonInteractive -Command \
        "(New-Object Media.SoundPlayer \"$win\").PlaySync()" </dev/null >/dev/null 2>&1
      exit 0
    fi
  fi

  # fallback: WSLg audio
  lead=$(( $3 * 4 / 5 )); lead=$(( lead - lead % 2 ))
  tail=$(( $3 / 2 ));     tail=$(( tail - tail % 2 ))
  { head -c "$lead" /dev/zero
    LD_LIBRARY_PATH="$1/piper" "$1/piper/piper" \
      --espeak_data "$1/piper/espeak-ng-data" \
      --model "$1/voices/$2.onnx" --output_raw 2>/dev/null
    head -c "$tail" /dev/zero
  } > "$raw"
  paplay --raw --rate="$3" --format=s16le --channels=1 "$raw"
' _ "$V" "$MODEL" "$RATE" <<<"$clean" >/dev/null 2>&1 &
echo $! > "$V/pid"
