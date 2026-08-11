#!/usr/bin/env bash
# Claude Code pet -- hook side (WSL).
# Writes this session's state to a file the Windows overlay polls.
#
# Usage (from settings.json hooks):  pet-hook.sh working|waiting|done|gone
#
# Reads the hook JSON on stdin to get session_id and cwd. Deliberately does not
# call any Windows .exe -- writing a file on /mnt/c is enough, and keeps the
# hook fast.

set -u

STATE="${1:-done}"
DIR="/mnt/c/Users/Admin/.claudepet/sessions"

payload="$(cat)"
sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"

[ -n "$sid" ] || sid="unknown"
[ -n "$cwd" ] && label="$(basename "$cwd")" || label="claude"

mkdir -p "$DIR" 2>/dev/null

if [ "$STATE" = "gone" ]; then
  rm -f "$DIR/$sid" 2>/dev/null
  exit 0
fi

printf '%s\t%s\t%s\n' "$STATE" "$label" "$(date +%s)" > "$DIR/$sid" 2>/dev/null
exit 0
