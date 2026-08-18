#!/usr/bin/env bash
# Speaks stdin aloud with Piper. Prose only: code blocks and markdown are stripped.
# Touch ~/.claude/voice/muted to silence; remove it to unmute.
set -uo pipefail
V="$HOME/.claude/voice"
[ -f "$V/muted" ] && exit 0

# Do NOT kill whatever is talking. Several Claude Code sessions share one
# queue; player.sh drains it in order so nothing gets cut off mid-sentence.

text=$(cat)
clean=$(printf '%s' "$text" | awk '
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  { print }
' | sed -E '
  s/!?\[([^]]*)\]\([^)]*\)/\1/g;   # links -> label
  s/`([^`]*)`/\1/g;                 # inline code -> bare word
  s/[*_#>|]+//g;                    # markdown syntax
  s/^[[:space:]]*[-+][[:space:]]+/ /;# bullets
  s/[[:space:]]+/ /g;
')
clean=$(printf '%s' "$clean" | tr -s ' \n' ' ' | sed 's/^ *//; s/ *$//')
[ -z "$clean" ] && exit 0

# Drop tokens that cannot be read aloud sensibly: commit hashes, command-line
# flags, file paths and version-ish blobs all come out as gibberish.
clean=$(printf '%s' "$clean" | sed -E '
  s#(^| )[0-9a-f]{7,40}([ .,;:]|$)# #g;      # commit hashes
  s#(^| )--[A-Za-z0-9=_-]+# #g;              # --flags
  s#(^| )[~./][A-Za-z0-9_./-]{3,}# #g;       # paths
  s#(^| )[A-Za-z0-9_]+/[A-Za-z0-9_./-]+# #g; # a/b/c paths
  # filenames: speak.sh -> speak, otherwise read as "speak dot ess aitch"
  s#([A-Za-z0-9_-]+)\.(sh|py|md|json|jsonl|conf|txt|wav|raw|onnx|toml|lua|ts|js|yml|yaml|log|exe|ps1|cs|vbs)\b#\1#g;
  s#[\"“”]##g;                                # stray quotes read as nothing
  s#→# to #g; s#←# from #g; s#[–—]#, #g;      # arrows and dashes
  s/  +/ /g;
')

# Piper synthesises line by line. One 800-character line becomes a single
# breathless utterance; one sentence per line gives it natural boundaries.
clean=$(printf '%s' "$clean" | sed 's/\([.!?]\) \+/\1\n/g')

# Queue the text, then make sure a player is running. Writing to a temp name
# and moving it into place keeps the player from picking up a half-written file.
mkdir -p "$V/queue"

# Label the item with the tmux window it came from, so the player can say
# which session is speaking. Hyphens and underscores read badly aloud.
label=$(tmux display-message -p -t "${TMUX_PANE:-}" '#{window_name}' 2>/dev/null \
        | tr '_-' '  ' | tr -s ' ')
[ -z "$label" ] && label="another session"

tmp=$(mktemp "$V/queue/.pending.XXXXXX") || exit 0
{ printf '%s\n' "$label"; printf '%s\n' "$clean"; } > "$tmp"
mv "$tmp" "$V/queue/$(date +%s%N).txt"

# Harmless if one is already draining: player.sh takes a lock and exits.
setsid "$V/player.sh" >/dev/null 2>&1 &
echo $! > "$V/pid"
