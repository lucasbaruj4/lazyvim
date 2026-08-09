# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
*i*) ;;
*) return ;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
xterm-color | *-256color) color_prompt=yes ;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
  if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    # We have color support; assume it's compliant with Ecma-48
    # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
    # a case would tend to support setf rather than setaf.)
    color_prompt=yes
  else
    color_prompt=
  fi
fi

if [ "$color_prompt" = yes ]; then
  PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
  PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm* | rxvt*)
  PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
  ;;
*) ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
  test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
  alias ls='ls --color=auto'
  #alias dir='dir --color=auto'
  #alias vdir='vdir --color=auto'

  alias grep='grep --color=auto'
  alias fgrep='fgrep --color=auto'
  alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
  . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

eval "$(starship init bash)"
alias code='code -r'

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                   # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion

alias clear='printf "\033c"'
alias ls="lsd"

export LS_COLORS="di=01;38;2;0;255;102"
. "$HOME/.cargo/env"


export TMUX_TMPDIR=/tmp

# Always start from home, then tmux (but only for the outer login shell --
# panes spawned inside an existing tmux session should keep their own cwd)
if [[ $- == *i* ]] && command -v tmux >/dev/null 2>&1 \
   && [ -z "$TMUX" ] && [ -z "$VSCODE_INJECTION" ]; then
  cd ~
  exec tmux new-session -A -s main
fi

# brave as default browser
export BROWSER=wslview

# ---- hardware control via Windows interop ----
_PS='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
_NETSH='/mnt/c/Windows/System32/netsh.exe'

# battery: percentage + charging state
battery() {
  "$_PS" -NoProfile -Command '$b=Get-CimInstance Win32_Battery; "{0}% ({1})" -f $b.EstimatedChargeRemaining, $(if($b.BatteryStatus -eq 2){"charging / AC"}else{"on battery"})'
}

# brightness: no arg = show, `brightness 60` = set to 60%
brightness() {
  if [ -z "$1" ]; then
    "$_PS" -NoProfile -Command '(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness).CurrentBrightness'
  else
    "$_PS" -NoProfile -Command "(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods).WmiSetBrightness(1,$1)" >/dev/null
  fi
}

# volume: up | down | mute  (each up/down step ≈ 10%)
# Uses Windows key simulation so it affects the real machine volume (same as host hotkeys).
# The tmux bar (and `~/.local/bin/tmux-volume`) now reads the *actual* current Windows volume
# on every refresh, so it will always match what your machine reports regardless of
# whether you used `volume up/down/mute`, Windows keyboard keys, or the taskbar slider.
volume() {
  case "$1" in
    up)   "$_PS" -NoProfile -Command '$w=New-Object -ComObject WScript.Shell; 1..5|%{$w.SendKeys([char]175)}' ;;
    down) "$_PS" -NoProfile -Command '$w=New-Object -ComObject WScript.Shell; 1..5|%{$w.SendKeys([char]174)}' ;;
    mute) "$_PS" -NoProfile -Command '$w=New-Object -ComObject WScript.Shell; $w.SendKeys([char]173)' ;;
    *) echo "usage: volume up|down|mute" ; return ;;
  esac
  # Small delay so the keypress(es) register before returning to prompt.
  # The status bar (refreshes from cache every ~2s) and direct `~/.local/bin/tmux-volume` will show the live machine value.
  sleep 0.2
}

# sshot / take-screenshot: press F2 + s (or type sshot) to take a full screenshot.
# It captures the screen, saves a timestamped PNG, and puts the path on the clipboard.
# Then just Ctrl+Shift+V to paste the path. Fully automatic.
sshot() {
  ~/.local/bin/take-screenshot "$@"
}

# Keep the old one for manual region snips (Win+Shift+S then paste-screenshot)
pastescreenshot() {
  ~/.local/bin/paste-screenshot "$@"
}

# (sshot is the function above. Type "sshot" or use F2+s in tmux)


# poll hardware status for tmux -- singleton across ALL shells/panes via
# flock, not just this shell. A per-shell env var guard (the old approach)
# doesn't work in tmux: each pane starts an independent shell, so every
# pane ended up running its own copy of this loop, and the PowerShell
# calls they all made concurrently slowed each other down via contention.
mkdir -p "$HOME/.cache/tmux-hw"
(
  flock -n 9 || exit 0
  while true; do ~/.local/bin/tmux-hw-status.sh; sleep 0.1; done
) 9>"$HOME/.cache/tmux-hw/poller.lock" &
disown

# >>> grok installer >>>
export PATH="$HOME/.grok/bin:$PATH"
[[ -r "$HOME/.grok/completions/bash/grok.bash" ]] && source "$HOME/.grok/completions/bash/grok.bash"
# <<< grok installer <<<

# --- tmux tab auto-rename: window name tracks the last component of cwd ---
# Skipped for any window Claude has pinned (see the `claude` wrapper below
# and ~/.claude/CLAUDE.md), so an in-progress claude session's 2-word
# identifier isn't immediately overwritten by this on the next prompt.
_tmux_rename_to_cwd() {
  [ -n "$TMUX" ] || return
  [ "$(tmux show-window-options -v -t "$TMUX_PANE" @pinned 2>/dev/null)" = "1" ] && return
  local name="${PWD##*/}"
  [ "$PWD" = "$HOME" ] && name="~"
  tmux rename-window -- "$name"
}
PROMPT_COMMAND="_tmux_rename_to_cwd${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# Wrap `claude` so that once the session ends, the tab un-pins and reverts
# to tracking the directory name again instead of keeping Claude's last
# 2-word identifier forever.
claude() {
  command claude "$@"
  local status=$?
  if [ -n "$TMUX" ]; then
    tmux set-window-option -t "$TMUX_PANE" @pinned 0 >/dev/null 2>&1
    _tmux_rename_to_cwd
  fi
  return $status
}

# GitHub PAT for MCP (file is 600, never committed)
[ -f "$HOME/.config/secrets/github-pat.env" ] && . "$HOME/.config/secrets/github-pat.env"
