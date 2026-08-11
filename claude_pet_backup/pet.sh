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
    # Kill any existing instance first: `ensure` from a concurrently starting
    # shell can otherwise race this and leave two pets stacked on screen.
    "$0" stop >/dev/null 2>&1
    "$PS" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass \
      -File 'C:\Users\Admin\.claudepet\pet.ps1' </dev/null >/dev/null 2>&1 &
    disown
    echo "pet started"
    ;;
  # NOTE: these must exclude $PID. The query string itself contains the match
  # pattern, so the querying powershell.exe matches its own command line --
  # without the exclusion, `stop` kills itself and `status` always reports
  # "running".
  stop)
    "$PS" -NoProfile -Command \
      "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { \$_.CommandLine -like '*pet.ps1*' -and \$_.ProcessId -ne \$PID } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" \
      </dev/null >/dev/null 2>&1
    echo "pet stopped"
    ;;
  status)
    "$PS" -NoProfile -Command \
      "\$n = @(Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { \$_.CommandLine -like '*pet.ps1*' -and \$_.ProcessId -ne \$PID }).Count; if (\$n -eq 0) { 'not running' } else { \"running (\$n)\" }" \
      </dev/null | tr -d '\r'
    ;;
  *)
    echo "usage: pet.sh {start|stop|status|ensure}" >&2; exit 1 ;;
esac
