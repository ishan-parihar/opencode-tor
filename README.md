# opencode-tor

Routes OpenCode through the Tor network with automatic IP rotation on every launch. Bypasses OpenCode Zen's 5 req/day per model rate limit by rotating your exit node.

## What it does

- Installs Tor, proxychains-ng, and OpenCode (`npm i -g opencode-ai`)
- Configures password-based Tor ControlPort for reliable NEWNYM signals
- Wraps `opencode` binary so every launch gets a fresh Tor exit node
- Provides `reset-opencode` for manual IP rotation mid-session

## Install

```bash
curl -sSL https://raw.githubusercontent.com/ishan-parihar/opencode-tor/master/install-opencode-tor.sh | bash
```

Or download and run:

```bash
wget https://raw.githubusercontent.com/ishan-parihar/opencode-tor/master/install-opencode-tor.sh
chmod +x install-opencode-tor.sh
./install-opencode-tor.sh
```

## Usage

```bash
# Launch OpenCode with fresh IP (auto-rotates on each launch)
opencode

# Rotate IP manually without relaunching
reset-opencode
```

## How it works

1. **Tor ControlPort** — Password auth on `127.0.0.1:9051` for NEWNYM signals
2. **proxychains-ng** — `LD_PRELOAD` hook intercepts libc `connect()` calls, routes TCP through Tor SOCKS5
3. **Wrapper script** — Sends `NEWNYM` on each `opencode` launch, then execs the real binary through proxychains
4. **Localnet exclusions** — LSP, MCP, file watchers bypass the proxy (localhost/LAN traffic stays local)

## Requirements

- Linux (tested on Arch, Ubuntu) or macOS
- npm / Node.js
- sudo access (for Tor installation)

## Uninstall

```bash
# Remove wrapper scripts
rm ~/.local/bin/opencode ~/.local/bin/reset-opencode

# Remove proxychains config
rm ~/.config/proxychains/opencode.conf

# Remove Tor ControlPort config (optional)
sudo sed -i '/# OpenCode proxy/d' /etc/tor/torrc
sudo systemctl restart tor
```
