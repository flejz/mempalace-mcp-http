#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.local/lib/mempalace-mcp-http"
CONFIG_DIR="${HOME}/.config/mempalace-mcp-http"
ENV_FILE="${CONFIG_DIR}/env"
SERVICE_NAME="mempalace-mcp-http"
PORT="${MEMPALACE_HTTP_PORT:-8765}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
err()  { echo -e "${RED}ERROR: $*${NC}" >&2; }
ok()   { echo -e "${GREEN}✓ $*${NC}"; }
info() { echo -e "${YELLOW}→ $*${NC}"; }

# 1. Require mempalace — no install, fail fast
info "Checking mempalace..."
if ! (mempalace --version >/dev/null 2>&1 || python3 -c "import mempalace" 2>/dev/null); then
    err "mempalace not found. Install it first:"
    echo "  uv tool install mempalace"
    echo "  # or: pip install mempalace"
    exit 1
fi
ok "mempalace found"

# 2. Check HTTP deps (fastapi, uvicorn) — OK to install these
info "Checking HTTP server deps..."
if ! python3 -c "import fastapi, uvicorn" 2>/dev/null; then
    info "Installing fastapi and uvicorn..."
    pip install fastapi "uvicorn[standard]" --quiet
fi
ok "HTTP deps ready"

# 3. Install server and token scripts
info "Installing to ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}"
cp "${SCRIPT_DIR}/mempalace_http.py" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/token.sh" "${INSTALL_DIR}/"
chmod +x "${INSTALL_DIR}/token.sh"
ok "Installed"

# 4. Generate config (skip if exists)
mkdir -p "${CONFIG_DIR}"
if [ -f "${ENV_FILE}" ]; then
    info "Config exists at ${ENV_FILE} — skipping (use token.sh rotate to rotate)"
else
    TOKEN="$(openssl rand -hex 32)"
    cat > "${ENV_FILE}" <<ENVEOF
MEMPALACE_HTTP_PORT=${PORT}
MEMPALACE_HTTP_TOKEN=${TOKEN}
ENVEOF
    chmod 600 "${ENV_FILE}"
    ok "Config written"
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"
TOKEN="${MEMPALACE_HTTP_TOKEN:-}"

# 5. Systemd user service (or manual fallback)
if command -v systemctl >/dev/null 2>&1 && systemctl --user status >/dev/null 2>&1; then
    SYSTEMD_DIR="${HOME}/.config/systemd/user"
    PYTHON3="$(command -v python3)"
    mkdir -p "${SYSTEMD_DIR}"
    cat > "${SYSTEMD_DIR}/${SERVICE_NAME}.service" <<SVCEOF
[Unit]
Description=MemPalace MCP HTTP Server
After=network.target

[Service]
Type=simple
EnvironmentFile=${ENV_FILE}
ExecStart=${PYTHON3} ${INSTALL_DIR}/mempalace_http.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SVCEOF
    systemctl --user daemon-reload
    systemctl --user enable --now "${SERVICE_NAME}"
    ok "Service enabled and started"
else
    echo ""
    info "systemd not available. Start manually:"
    echo "  source ${ENV_FILE} && python3 ${INSTALL_DIR}/mempalace_http.py"
fi

HOSTNAME_VAL="$(hostname -f 2>/dev/null || hostname)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Claude Code MCP config (~/.claude/settings.json):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat <<CFGEOF
{
  "mcpServers": {
    "mempalace": {
      "type": "http",
      "url": "http://${HOSTNAME_VAL}:${PORT}/mcp",
      "headers": {
        "Authorization": "Bearer ${TOKEN}"
      }
    }
  }
}
CFGEOF
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Token management: ${INSTALL_DIR}/token.sh [show|rotate|reveal|revoke]"
