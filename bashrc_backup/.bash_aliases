# NOTE: BOOKMARKS values with personal IDs are replaced by <PLACEHOLDERS>
# in this backup copy. The live ~/.bash_aliases has the real URLs.

alias ros='docker run -it --rm -e DISPLAY=:0.0 -v /tmp/.X11-unix:/tmp/.X11-unix ros2-humble-dev-full bash'

# --- bri: interactive brightness TUI ---
alias bri='~/.local/bin/brightness-tui'

# --- camera: open webcam viewer from WSL ---
# The real Windows Camera app is a UWP/MSIX package. Its activation now
# takes ~45s (fixed COM timeout) because there's no shell broker running
# (no explorer.exe). Route around it entirely: a local webcam page opened
# in Brave (plain Win32 app, launches instantly here).
camera() {
  _brave --app="file:///C:/Users/Admin/AppData/Local/camera.html"
}

# --- browse: open bookmarks or any URL in Windows Brave ---
declare -A BOOKMARKS=(
  [ecampus]="https://ecampus.srh-berlin.de/my/"
  [campusnet]="https://campus.srh-hochschule-berlin.de/scripts/mgrqispi.dll?APPNAME=CampusNet&PRGNAME=MLSSTART&ARGUMENTS=-N<ACCOUNT_ARG>,-N000308,"
  [gmail]="https://mail.google.com/mail/u/1/#inbox"
  [cal]="https://calendar.google.com/calendar/u/1/r"
  [gh]="https://github.com/lucasbaruj4"
  [linkedin]="https://www.linkedin.com/in/<PROFILE>/"
  [claude]="https://claude.ai/new"
  [gpt]="https://chatgpt.com/"
  [books]="https://play.google.com/books/s/<SHELF_ID>"
  [grok]="https://grok.com/"
  [plx]="https://www.perplexity.ai/"
  [yt]="https://www.youtube.com/"
  [docs]="https://docs.google.com/document/u/1/"
  [classroom]="https://classroom.google.com/u/1/?pli=1"
  [folio]="https://bashfoliovercel.vercel.app/"
  [teams]="https://teams.microsoft.com/v2/"
  [outlook]="https://outlook.office.com/mail/?realm=<REALM>&login_hint=<EMAIL>"
  [x]="https://x.com/home"
  [ig]="https://www.instagram.com/?hl=en"
  [whatsapp]="https://web.whatsapp.com"
  [notes]="https://app.notion.com/p/<PAGE_ID>?v=<VIEW_ID>"
  [drive]="https://drive.google.com/drive/u/1/starred"
  [home]="https://app.notion.com/p/Home-<PAGE_ID>"
  [thesis]="https://app.notion.com/p/Thesis-<PAGE_ID>"
  [tasks]="https://app.notion.com/p/<PAGE_ID>?v=<VIEW_ID>"
)

BRAVE="/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe"

# Fullscreen video captions (YouTube CC) render fine in a window but vanish in
# fullscreen on this setup: Chromium promotes the fullscreen video to a
# DirectComposition overlay plane and the caption layer is lost. Verified by
# A/B test -- captions come back with direct composition off. Keeps GPU
# rasterization and hardware video decode; only the overlay path is disabled.
# (Narrower --disable-features=DirectCompositionLetterboxVideoOptimization was
# tested and did NOT fix it.)
BRAVE_FLAGS=( --disable-direct-composition )

# Single entry point so every Brave launch carries BRAVE_FLAGS. Flags only bind
# on a cold start -- if Brave is already running, this just forwards the URL to
# the existing instance, which already has them.
_brave() {
  "$BRAVE" "${BRAVE_FLAGS[@]}" "$@" < /dev/null >/dev/null 2>&1 &
  disown
  return 0
}

browse() {
  if [ -z "$1" ]; then
    echo "Bookmarks:"; printf '  %s\n' "${!BOOKMARKS[@]}" | sort; return 0
  fi

  # incognito: `browse gi` = blank window, `browse gi <query>` = incognito search
  if [ "$1" = "gi" ]; then
    shift
    if [ -z "$1" ]; then
      _brave --incognito
    else
      local q="$*"; q="${q// /+}"
      _brave --incognito "https://www.google.com/search?q=${q}"
    fi
    return 0
  fi

  # google search: `browse g <query>`
  if [ "$1" = "g" ]; then
    shift
    local q="$*"; q="${q// /+}"
    _brave "https://www.google.com/search?q=${q}"
    return 0
  fi

  # bookmark shortcut or raw URL
  _brave "${BOOKMARKS[$1]:-$1}"
}

_browse_complete() {
  COMPREPLY=( $(compgen -W "g gi ${!BOOKMARKS[*]}" -- "${COMP_WORDS[COMP_CWORD]}") )
}
complete -F _browse_complete browse

# --- obsidian: open Obsidian (Windows Win32 app) from WSL ---
obsidian() {
  "/mnt/c/Users/Admin/AppData/Local/Programs/Obsidian/Obsidian.exe" < /dev/null >/dev/null 2>&1 &
  disown
  return 0
}

# --- CLIProxyAPI: Claude Code on ChatGPT/Codex subscription ---
_claudex_update() {
  local repo="router-for-me/CLIProxyAPI"
  local binary="$HOME/cliproxyapi/cli-proxy-api"
  local arch latest current tmp archive

  case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) echo "unsupported architecture: $(uname -m)"; return 1 ;;
  esac

  command -v gh >/dev/null || { echo "gh is required"; return 1; }
  [ -x "$binary" ] || { echo "CLIProxyAPI not found: $binary"; return 1; }

  latest="$(gh release view --repo "$repo" --json tagName --jq '.tagName')" || return 1
  current="$("$binary" -h 2>&1)"
  current="${current%%$'\n'*}"

  if [[ "$current" == *"${latest#v}"* ]]; then
    echo "CLIProxyAPI is already up to date ($latest)"
    return 0
  fi

  tmp="$(mktemp -d)" || return 1
  archive="$tmp/CLIProxyAPI_${latest#v}_linux_${arch}.tar.gz"
  echo "Updating CLIProxyAPI to $latest..."

  if ! gh release download "$latest" --repo "$repo" \
      --pattern "$(basename "$archive")" --dir "$tmp" ||
      ! tar -xzf "$archive" -C "$tmp" ||
      ! "$tmp/cli-proxy-api" -h >/dev/null 2>&1; then
    rm -rf -- "$tmp"
    echo "update download or validation failed"
    return 1
  fi

  cp -p "$binary" "$binary.previous" || { rm -rf -- "$tmp"; return 1; }
  install -m 755 "$tmp/cli-proxy-api" "$binary.new" || { rm -rf -- "$tmp"; return 1; }
  mv "$binary.new" "$binary"

  if ! systemctl --user restart cliproxyapi.service; then
    mv "$binary.previous" "$binary"
    systemctl --user restart cliproxyapi.service
    rm -rf -- "$tmp"
    echo "update failed; restored previous version"
    return 1
  fi

  rm -f "$binary.previous"
  rm -rf -- "$tmp"
  "$binary" -h 2>&1 | { IFS= read -r line; echo "$line"; }
}

claudex() {
  if [ "${1-}" = "update" ]; then
    [ "$#" -eq 1 ] || { echo "usage: claudex update"; return 2; }
    _claudex_update
    return
  fi

  local key
  key="$(cat ~/.cli-proxy-api/.claudex-key 2>/dev/null)" || { echo "no claudex key"; return 1; }
  ANTHROPIC_BASE_URL=http://127.0.0.1:8317 \
  ANTHROPIC_AUTH_TOKEN="$key" \
  CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1 \
  claude "$@"
}

alias kill-exporer='/mnt/c/Windows/System32/taskkill.exe /F /IM explorer.exe 2>&1 < /dev/null'
