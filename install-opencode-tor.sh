#!/bin/bash
set -euo pipefail

TOR_CONTROL_PASS="opencode-proxy"
INSTALL_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.config"

detect_nc_binary() {
    if command -v nc.openbsd &>/dev/null; then echo "nc.openbsd"
    elif command -v nc &>/dev/null; then echo "nc"
    else echo "nc"
    fi
}

NC_BIN=$(detect_nc_binary)

detect_pkg_manager() {
    if command -v pacman &>/dev/null; then echo "pacman"
    elif command -v apt &>/dev/null; then echo "apt"
    elif command -v dnf &>/dev/null; then echo "dnf"
    elif command -v brew &>/dev/null; then echo "brew"
    else echo "unknown"
    fi
}

PKG_MGR=$(detect_pkg_manager)
echo "📦 Package manager: $PKG_MGR"

install_deps() {
    case "$PKG_MGR" in
        pacman) sudo pacman -S --noconfirm tor proxychains-ng npm ;;
        apt)
            sudo apt update
            # Install netcat-openbsd for -N flag support (needed for NEWNYM)
            sudo apt install -y tor proxychains4 npm netcat-openbsd
            ;;
        dnf) sudo dnf install -y tor proxychains-ng npm ;;
        brew) brew install tor proxychains-ng node ;;
        *) echo "❌ Install manually: tor, proxychains-ng, npm"; exit 1 ;;
    esac
}

echo "📥 Installing dependencies..."
install_deps

TORRC="/etc/tor/torrc"
sudo cp "$TORRC" "${TORRC}.bak.$(date +%s)" 2>/dev/null || true
sudo sed -i '/^ControlPort/d;/^CookieAuthentication/d;/^HashedControlPassword/d;/^# OpenCode proxy/d' "$TORRC" 2>/dev/null || true

HASHED_PASS=$(tor --hash-password "$TOR_CONTROL_PASS" 2>/dev/null | tail -1)
sudo bash -c "printf '\n# OpenCode proxy\nControlPort 9051\nHashedControlPassword %s\n' >> '$TORRC'" "$HASHED_PASS"

[ ! -d /var/lib/tor ] && sudo mkdir -p /var/lib/tor && sudo chown -R tor:tor /var/lib/tor 2>/dev/null || true

sudo systemctl enable tor 2>/dev/null || true
sudo systemctl restart tor 2>/dev/null || sudo service tor restart 2>/dev/null || sudo tor &
sleep 3

nc -z 127.0.0.1 9050 2>/dev/null && echo "  → Tor SOCKS active" || echo "⚠️  Tor SOCKS not responding"
nc -z 127.0.0.1 9051 2>/dev/null && echo "  → ControlPort active" || echo "⚠️  ControlPort not responding"

echo "📥 Installing OpenCode..."
npm install -g opencode-ai
REAL_OPENCODE=$(which opencode 2>/dev/null || echo "")
[ -z "$REAL_OPENCODE" ] && echo "❌ opencode not found" && exit 1
echo "  → Binary: $REAL_OPENCODE"

mkdir -p "$CONFIG_DIR/proxychains"
cat > "$CONFIG_DIR/proxychains/opencode.conf" <<'EOF'
dynamic_chain
proxy_dns
tcp_read_time_out 30000
tcp_connect_time_out 15000
localnet 127.0.0.0/255.0.0.0
localnet ::1/128
localnet 10.0.0.0/255.0.0.0
localnet 172.16.0.0/255.240.0.0
localnet 192.168.0.0/255.255.0.0
[ProxyList]
socks5 127.0.0.1 9050
EOF

mkdir -p "$INSTALL_DIR"
cat > "$INSTALL_DIR/opencode" <<WRAPPER
#!/bin/bash
TOR_CONTROL="127.0.0.1:9051"
TOR_CONTROL_PASS="$TOR_CONTROL_PASS"
NC_BIN="$NC_BIN"
if \$NC_BIN -z "\${TOR_CONTROL%%:*}" "\${TOR_CONTROL##*:}" 2>/dev/null; then
    (echo -e "AUTHENTICATE \\"\$TOR_CONTROL_PASS\\"\\r"; sleep 1; echo -e "SIGNAL NEWNYM\\r"; sleep 1; echo -e "QUIT\\r") | \$NC_BIN -N "\${TOR_CONTROL%%:*}" "\${TOR_CONTROL##*:}" 2>/dev/null >/dev/null
    sleep 1
fi
exec proxychains4 -f "$CONFIG_DIR/proxychains/opencode.conf" "$REAL_OPENCODE" "\$@"
WRAPPER
chmod +x "$INSTALL_DIR/opencode"

cat > "$INSTALL_DIR/reset-opencode" <<RESET
#!/bin/bash
set -euo pipefail
TOR_CONTROL="127.0.0.1:9051"
TOR_CONTROL_PASS="$TOR_CONTROL_PASS"
TOR_SOCKS="127.0.0.1:9050"
NC_BIN="$NC_BIN"
echo "🔄 Rotating Tor circuit..."
if \$NC_BIN -z "\${TOR_CONTROL%%:*}" "\${TOR_CONTROL##*:}" 2>/dev/null; then
    (echo -e "AUTHENTICATE \\"\$TOR_CONTROL_PASS\\"\\r"; sleep 1; echo -e "SIGNAL NEWNYM\\r"; sleep 1; echo -e "QUIT\\r") | \$NC_BIN -N "\${TOR_CONTROL%%:*}" "\${TOR_CONTROL##*:}" 2>/dev/null | grep -q "250 OK" && echo "  → Sent NEWNYM" || echo "  → NEWNYM sent"
    sleep 3
else
    echo "  → ControlPort unavailable, using SIGHUP"
    sudo kill -HUP \$(pgrep -x tor) 2>/dev/null || sudo systemctl start tor
    sleep 3
fi
NEW_IP=\$(curl -s --max-time 10 --socks5-hostname "\$TOR_SOCKS" https://api.ipify.org 2>/dev/null || echo "failed")
[[ "\$NEW_IP" != "failed" ]] && echo "✅ New IP: \$NEW_IP" || echo "⚠️  Tor may be bootstrapping, wait 30s"
RESET
chmod +x "$INSTALL_DIR/reset-opencode"

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "⚠️  Add to ~/.bashrc: export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "✅ Installed!"
echo "  opencode        → Launch with auto-rotating Tor IP"
echo "  reset-opencode  → Manual IP rotation"
