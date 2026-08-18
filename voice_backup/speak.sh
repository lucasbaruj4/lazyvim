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

setsid bash -c '
  LD_LIBRARY_PATH="$1/piper" "$1/piper/piper" \
    --espeak_data "$1/piper/espeak-ng-data" \
    --model "$1/voices/en_US-lessac-medium.onnx" --output_raw 2>/dev/null \
  | paplay --raw --rate=22050 --format=s16le --channels=1
' _ "$V" <<<"$clean" >/dev/null 2>&1 &
echo $! > "$V/pid"
