# CLIProxyAPI — GPT models inside Claude Code

Runs a local Anthropic-compatible proxy so ChatGPT (Codex) models show up in
Claude Code's `/model` picker alongside Claude models, switchable mid-conversation.
Uses OAuth subscription logins, no API keys.

Upstream: https://github.com/router-for-me/CLIProxyAPI

## Files

| File | Role |
| --- | --- |
| `config.example.yaml` | Local-only proxy config with placeholders for the generated key. |
| `cliproxyapi.service` | systemd user service that starts the proxy at login. |
| `statusline-usage.sh` | Claude Code status line that shows the active Claude or ChatGPT subscription limits. |

## Restore

1. Download the release binary into `~/cliproxyapi/`:

       gh release download -R router-for-me/CLIProxyAPI \
         -p 'CLIProxyAPI_*_linux_aarch64.tar.gz' && tar -xzf CLIProxyAPI_*.tar.gz

2. Generate a key and write the config:

       mkdir -p ~/.cli-proxy-api
       echo "claudex-$(openssl rand -hex 16)" > ~/.cli-proxy-api/.claudex-key
       chmod 600 ~/.cli-proxy-api/.claudex-key
       sed "s|REPLACE_WITH_GENERATED_KEY|$(cat ~/.cli-proxy-api/.claudex-key)|" \
         config.example.yaml > ~/cliproxyapi/config.yaml

3. Install the service:

       cp cliproxyapi.service ~/.config/systemd/user/
       systemctl --user daemon-reload
       systemctl --user enable --now cliproxyapi.service

4. Log in to each provider (credentials land in `~/.cli-proxy-api/*.json`):

       cd ~/cliproxyapi
       ./cli-proxy-api -config ~/cliproxyapi/config.yaml -codex-device-login
       ./cli-proxy-api -config ~/cliproxyapi/config.yaml -claude-login -no-browser

   On WSL the browser callback on port 1455 does not reach the Linux side, so use
   `-codex-device-login` for Codex. For `-claude-login` there is no device flow —
   copy the full `?code=...&state=...` URL from the address bar and paste it at
   the prompt instead of pressing Enter.

5. Install the subscription usage status line without replacing other Claude
   Code settings:

       mkdir -p ~/.claude
       install -m 755 statusline-usage.sh ~/.claude/statusline-usage.sh
       [ -s ~/.claude/settings.json ] || printf '{}\n' > ~/.claude/settings.json
       tmp=$(mktemp)
       jq '.statusLine = {type: "command", command: "~/.claude/statusline-usage.sh"}' \
         ~/.claude/settings.json > "$tmp" && mv "$tmp" ~/.claude/settings.json

6. The `claudex` shell function lives in `bashrc_backup/.bash_aliases`.

## Notes

- `~/cliproxyapi/config.yaml`, `~/.cli-proxy-api/`, `~/.claude/settings.json`,
  and status-line cache files are live state and are never copied here.
- The generated key fills both `api-keys` and `remote-management.secret-key`.
  Management stays bound to localhost. CLIProxyAPI replaces the management key
  with a bcrypt hash on first start; never copy the live config back over the
  example file.
- The status line reads the key at runtime, fetches only quota percentages, and
  caches those percentages for 60 seconds under `~/.claude/cache/`.
- The status line requires `bash`, `curl`, `jq`, `awk`, and `flock`.
- Plain `claude` is untouched and still talks straight to Anthropic. Only
  `claudex` routes through the proxy.
- Routing the Anthropic OAuth token through a third-party proxy is what got
  accounts flagged in early 2026. If Claude models start failing, drop the
  `-claude-login` credential and use `claudex` for GPT only.
