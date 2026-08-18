#!/usr/bin/env bash
# Alt+R: replay the last thing spoken for THIS tmux window.
set -uo pipefail
V="$HOME/.claude/voice"
PANE="${1:-${TMUX_PANE:-}}"

msg() { [ -n "${TMUX:-}" ] && tmux display-message "$1" || echo "$1"; }

label=$(tmux display-message -p -t "$PANE" '#{window_name}' 2>/dev/null \
        | tr '_-' '  ' | tr -s ' ')
[ -z "$label" ] && label="another session"
key=$(printf '%s' "$label" | tr -c '[:alnum:]' '_')
src="$V/last/$key.txt"

[ -f "$src" ] || { msg "nothing to repeat for '$label'"; exit 0; }

rm -f "$V/muted"                      # a repeat is an explicit request to hear it
mkdir -p "$V/queue"
tmp=$(mktemp "$V/queue/.pending.XXXXXX") || exit 0
cp "$src" "$tmp"
mv "$tmp" "$V/queue/$(date +%s%N).txt"
setsid "$V/player.sh" >/dev/null 2>&1 &
msg "repeating $label"
