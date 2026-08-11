#!/usr/bin/env bash
# Claude Code pet -- launcher (WSL).
#   pet.sh start   copy pet.ps1 to the Windows side and run it (hidden)
#   pet.sh stop    kill it
#   pet.sh status  is it running?
#   pet.sh ensure  start it only if it isn't already up (for .bashrc)

set -u
SRC="$HOME/.claude/pet/pet.ps1"
WINDIR="/mnt/c/Users/Admin/.claudepet"
PS="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
HB="$WINDIR/heartbeat"

case "${1:-start}" in
  ensure)
    # The pet touches $HB every ~3.5s. A fresh heartbeat means it is alive, so
    # this costs one stat -- no powershell.exe, no delay on shell startup.
    if [ -f "$HB" ] && [ $(( $(date +%s) - $(stat -c %Y "$HB") )) -lt 12 ]; then
      exit 0
    fi
    exec "$0" start
    ;;
  start)
    mkdir -p "$WINDIR/sessions"
    cp "$SRC" "$WINDIR/pet.ps1"
    "$PS" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass \
      -File 'C:\Users\Admin\.claudepet\pet.ps1' </dev/null >/dev/null 2>&1 &
    disown
    echo "pet started"
    ;;
  stop)
    "$PS" -NoProfile -Command \
      "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { \$_.CommandLine -like '*claudepet*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" \
      </dev/null >/dev/null 2>&1
    echo "pet stopped"
    ;;
  status)
    "$PS" -NoProfile -Command \
      "if (Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { \$_.CommandLine -like '*claudepet*' }) { 'running' } else { 'not running' }" \
      </dev/null | tr -d '\r'
    ;;
  *)
    echo "usage: pet.sh {start|stop|status|ensure}" >&2; exit 1 ;;
esac
