# CLIProxyAPI — GPT models inside Claude Code

Runs a local Anthropic-compatible proxy so ChatGPT (Codex) models show up in
Claude Code's `/model` picker alongside Claude models, switchable mid-conversation.
Uses OAuth subscription logins, no API keys.

Upstream: https://github.com/router-for-me/CLIProxyAPI

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

5. The `claudex` shell function lives in `bashrc_backup/.bash_aliases`.

## Notes

- `~/cliproxyapi/config.yaml` and `~/.cli-proxy-api/` hold live credentials and
  are never committed here.
- Plain `claude` is untouched and still talks straight to Anthropic. Only
  `claudex` routes through the proxy.
- Routing the Anthropic OAuth token through a third-party proxy is what got
  accounts flagged in early 2026. If Claude models start failing, drop the
  `-claude-login` credential and use `claudex` for GPT only.
