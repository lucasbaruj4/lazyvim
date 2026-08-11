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

# The Notification hook fires for two different things: a permission or
# multiple-choice prompt DURING a turn, and an idle "waiting for your input"
# notice AFTER one ends. The idle one arrives just after Stop and would
# overwrite `done` with `waiting`, so the badge read QUESTION every time Claude
# finished. Within a turn the order is always working -> (waiting) -> done, so
# once a session is done its turn is over and any further notification is idle
# chatter -- ignore it. UserPromptSubmit resets to working on the next turn.
if [ "$STATE" = "waiting" ] && [ -f "$DIR/$sid" ]; then
  case "$(cat "$DIR/$sid" 2>/dev/null)" in
    done*) exit 0 ;;
  esac
fi

printf '%s\t%s\t%s\n' "$STATE" "$label" "$(date +%s)" > "$DIR/$sid" 2>/dev/null
exit 0
