#!/usr/bin/env bash
# Pick the voice Claude speaks with.  list | demo | set <name> | current
set -uo pipefail
V="$HOME/.claude/voice"
CONF="$V/voice.conf"
SAMPLE="Right, the lock bug is fixed and the recording survives now. Transcription takes about four seconds."
cur() { cat "$CONF" 2>/dev/null || echo "en_US-lessac-medium"; }

case "${1:-list}" in
  list)
    for f in "$V"/voices/*.onnx; do
      n=$(basename "$f" .onnx)
      [ "$n" = "$(cur)" ] && echo "* $n  (current)" || echo "  $n"
    done ;;
  current) cur ;;
  demo)
    for f in "$V"/voices/*.onnx; do
      n=$(basename "$f" .onnx)
      echo ">>> $n"
      r=$(jq -r '.audio.sample_rate // 22050' "$f.json" 2>/dev/null)
      printf '%s. This is %s.' "$SAMPLE" "${n#en_??-}" | \
        LD_LIBRARY_PATH="$V/piper" "$V/piper/piper" --espeak_data "$V/piper/espeak-ng-data" \
          --model "$f" --output_raw 2>/dev/null | \
        paplay --raw --rate="$r" --format=s16le --channels=1
      sleep 0.4
    done ;;
  set)
    n="${2:-}"
    [ -f "$V/voices/$n.onnx" ] || { echo "no such voice: $n"; "$0" list; exit 1; }
    echo "$n" > "$CONF"; echo "voice set to $n"
    printf 'Voice switched. This is how I will sound from now on.' | \
      "$V/speak.sh" ;;
  *) echo "usage: voice.sh [list|demo|set <name>|current]" ;;
esac
