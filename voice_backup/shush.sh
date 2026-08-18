#!/usr/bin/env bash
# Alt+S: stop talking now and drop anything queued behind it.
# Pressing it again while silent toggles mute.
V="$HOME/.claude/voice"
if [ -f "$V/muted" ]; then
  rm -f "$V/muted"; m="voice UNMUTED"
elif [ -f "$V/pid" ] && kill -0 "$(cat "$V/pid")" 2>/dev/null; then
  rm -f "$V/queue"/*.txt 2>/dev/null
  kill -- "-$(cat "$V/pid")" 2>/dev/null
  pkill -f 'SoundPlayer' 2>/dev/null
  rm -f "$V/pid"
  m="stopped (queue cleared)"
else
  touch "$V/muted"; rm -f "$V/queue"/*.txt 2>/dev/null; m="voice MUTED"
fi
[ -n "${TMUX:-}" ] && tmux display-message "$m" || echo "$m"
