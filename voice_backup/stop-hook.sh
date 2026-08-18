#!/usr/bin/env bash
# Claude Code Stop hook: speak the FINAL message of the turn -- the summary
# Claude ends on, not the short lead-ins before each tool call.
#
# The transcript is still being flushed when this fires, so the final message
# may not be on disk yet. Wait for the file to stop growing before reading,
# otherwise we speak the previous block instead.
set -uo pipefail
V="$HOME/.claude/voice"
payload=$(cat)
tp=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
[ -z "$tp" ] || [ ! -f "$tp" ] && exit 0

pick() {
  jq -rs '
    [ .[]
      | select(.type == "assistant")
      | [ .message.content[]? | select(.type == "text") | .text ]
      | select(length > 0)
      | join("\n\n")
    ] | last // empty
  ' "$tp" 2>/dev/null
}

# Wait until the transcript is unchanged twice in a row (max ~3s).
prev=""; stable=0; waited=0
for _ in $(seq 1 30); do
  cur=$(stat -c%s "$tp" 2>/dev/null || echo 0)
  if [ "$cur" = "$prev" ]; then
    stable=$((stable + 1))
    [ "$stable" -ge 2 ] && break
  else
    stable=0
  fi
  prev=$cur; waited=$((waited + 1)); sleep 0.1
done

text=$(pick)
# Leave a breadcrumb so a mis-pick can be diagnosed without guessing.
{ printf '%s waited=%sms bytes=%s picked=%s\n' \
    "$(date +%H:%M:%S)" "$((waited * 100))" "$prev" "$(printf '%s' "$text" | head -c 70 | tr '\n' ' ')"
} >> "$V/last-spoken.log"
printf '%s' "$text" | "$V/speak.sh"
exit 0
