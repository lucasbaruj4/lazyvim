#!/usr/bin/env bash
# Alt+S: stop talking now. Twice in a row = mute permanently until Alt+S again.
V="$HOME/.claude/voice"
if [ -f "$V/muted" ]; then
  rm -f "$V/muted"; m="voice UNMUTED"
else
  if [ -f "$V/pid" ] && kill -0 "$(cat "$V/pid")" 2>/dev/null; then
    kill -- "-$(cat "$V/pid")" 2>/dev/null; rm -f "$V/pid"; m="stopped"
  else
    touch "$V/muted"; m="voice MUTED"
  fi
fi
[ -n "${TMUX:-}" ] && tmux display-message "$m" || echo "$m"
