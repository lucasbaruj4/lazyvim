#!/usr/bin/env bash
# Claude Code Stop hook: speak only the FINAL message of the turn -- the
# summary Claude ends on. The short lead-ins before each tool call are
# deliberately skipped; they narrate work in progress, not the answer.
set -uo pipefail
payload=$(cat)
tp=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
[ -z "$tp" ] || [ ! -f "$tp" ] && exit 0

jq -rs '
  [ .[]
    | select(.type == "assistant")
    | [ .message.content[]? | select(.type == "text") | .text ]
    | select(length > 0)
    | join("\n\n")
  ] | last // empty
' "$tp" 2>/dev/null | "$HOME/.claude/voice/speak.sh"
exit 0
