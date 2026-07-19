#!/usr/bin/env bash

NETSH='/mnt/c/Windows/System32/netsh.exe'

CACHE="$HOME/.cache/tmux-hw"; mkdir -p "$CACHE"

atomic_write() {
  # writes stdin to "$1" without ever exposing a truncated/empty file to readers
  local dest="$1" tmp
  tmp=$(mktemp "$dest.XXXXXX")
  cat > "$tmp"
  mv -f "$tmp" "$dest"
}

# Run all three probes in parallel -- each one shells out to Windows and
# takes several hundred ms; sequentially that added up to ~1.6s per poll
# cycle, making the status bar lag well behind real changes (e.g. volume
# key presses). In parallel the cycle takes as long as the slowest one.

(
  ~/.local/bin/tmux-battery 2>/dev/null | atomic_write "$CACHE/battery" || printf ' ??' | atomic_write "$CACHE/battery"
) &

(
  info=$("$NETSH" wlan show interfaces 2>/dev/null | tr -d '\r')
  ssid=$(echo "$info" | awk -F': ' '/^ *SSID/ && !/BSSID/ {print $2; exit}')
  sig=$(echo "$info"  | awk -F': ' '/^ *Signal/ {print $2; exit}')
  if [ -n "$ssid" ]; then
    printf '󰤨 %s %s' "$ssid" "$sig" | atomic_write "$CACHE/wifi"
  else
    printf '󰤭 offline' | atomic_write "$CACHE/wifi"
  fi
) &

(
  ~/.local/bin/tmux-volume 2>/dev/null | atomic_write "$CACHE/volume" || printf ' ??' | atomic_write "$CACHE/volume"
) &

wait

# Force tmux to redraw the status line right now instead of waiting for its
# own status-interval timer (1s) to tick -- the cache above is already fresh
# within ~0.1-0.3s, but without this the *visible* bar could still lag up to
# a second behind it since that's a separate, tmux-internal redraw cadence.
tmux refresh-client -S 2>/dev/null
