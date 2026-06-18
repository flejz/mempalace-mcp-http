#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${HOME}/.local/lib/mempalace-mcp-http"
BIN_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.config/mempalace-mcp-http"
ENV_FILE="${CONFIG_DIR}/env"
SERVICE_NAME="mempalace-mcp-http"
PORT="${MEMPALACE_HTTP_PORT:-8765}"
REPO_RAW="https://raw.githubusercontent.com/flejz/mempalace-mcp-http/master"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
err()  { echo -e "${RED}ERROR: $*${NC}" >&2; }
ok()   { echo -e "${GREEN}✓ $*${NC}"; }
info() { echo -e "${YELLOW}→ $*${NC}"; }
warn() { echo -e "${YELLOW}WARNING: $*${NC}"; }

# $0 is "bash" when piped (curl|bash); a file path when run directly
if [ -f "$0" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
else
    SCRIPT_DIR="$(mktemp -d)"
    trap 'rm -rf "${SCRIPT_DIR}"' EXIT
    info "Downloading files from GitHub..."
    curl -fsSL "${REPO_RAW}/mempalace_http.py" -o "${SCRIPT_DIR}/mempalace_http.py"
    curl -fsSL "${REPO_RAW}/token.sh"          -o "${SCRIPT_DIR}/token.sh"
fi

# 1. Require mempalace — no install, fail fast
info "Checking mempalace..."
if ! (mempalace --version >/dev/null 2>&1 || python3 -c "import mempalace" 2>/dev/null); then
    err "mempalace not found. Install it first:"
    echo "  uv tool install mempalace"
    echo "  # or: pip install mempalace"
    exit 1
fi
ok "mempalace found"

# 2. Find mempalace Python, inject HTTP deps into its env
info "Setting up HTTP deps..."
mkdir -p "${INSTALL_DIR}"

# Find the Python that runs mempalace (system, pipx, uv tool, or manual venv)
_mp_python=""

for _py in python3 python; do
    if command -v "${_py}" >/dev/null 2>&1 && "${_py}" -c "import mempalace" 2>/dev/null; then
        _mp_python="$(command -v "${_py}")"
        break
    fi
done

# Shebang of the mempalace binary — works for pipx, uv tool, any venv-backed install
if [ -z "${_mp_python}" ] && command -v mempalace >/dev/null 2>&1; then
    _shebang_py="$(head -1 "$(command -v mempalace)" 2>/dev/null | sed 's|^#! *||' | awk '{print $1}')"
    if [ -x "${_shebang_py:-}" ] && "${_shebang_py}" -c "import mempalace" 2>/dev/null; then
        _mp_python="${_shebang_py}"
    fi
fi

# uv tool dir fallback
if [ -z "${_mp_python}" ] && command -v uv >/dev/null 2>&1; then
    _tool_base="$(uv tool dir 2>/dev/null || true)"
    if [ -n "${_tool_base}" ]; then
        for _candidate in "${_tool_base}/mempalace/bin/python3" "${_tool_base}/mempalace/bin/python"; do
            if [ -f "${_candidate}" ] && "${_candidate}" -c "import mempalace" 2>/dev/null; then
                _mp_python="${_candidate}"
                break
            fi
        done
    fi
fi

if [ -z "${_mp_python}" ]; then
    err "Cannot find a Python that can import mempalace."
    err "Tried: system python3, shebang of '$(command -v mempalace 2>/dev/null || echo mempalace)', uv tool dir"
    exit 1
fi

# Install fastapi + uvicorn into the same env as mempalace
# pipx: use pipx inject (keeps env clean); otherwise pip install into that Python's env
VENV_PY="${_mp_python}"
if ! "${_mp_python}" -c "import fastapi, uvicorn" 2>/dev/null; then
    if command -v pipx >/dev/null 2>&1 && pipx list 2>/dev/null | grep -q "mempalace"; then
        info "Installing fastapi and uvicorn via pipx inject..."
        pipx inject mempalace fastapi "uvicorn[standard]" --quiet
    else
        info "Installing fastapi and uvicorn..."
        "${_mp_python}" -m pip install fastapi "uvicorn[standard]" --quiet
    fi
fi
ok "HTTP deps ready (using ${VENV_PY})"

# 3. Install server script and mempalace-token CLI
info "Installing to ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}" "${BIN_DIR}"
cp "${SCRIPT_DIR}/mempalace_http.py" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/token.sh" "${INSTALL_DIR}/mempalace-token"
chmod +x "${INSTALL_DIR}/mempalace-token"
ln -sf "${INSTALL_DIR}/mempalace-token" "${BIN_DIR}/mempalace-token"
ok "Installed (mempalace-token available in PATH if ${BIN_DIR} is in \$PATH)"

# 4. Generate config (skip if exists)
mkdir -p "${CONFIG_DIR}"
if [ -f "${ENV_FILE}" ]; then
    info "Config exists at ${ENV_FILE} — skipping (use mempalace-token rotate to rotate)"
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
    mkdir -p "${SYSTEMD_DIR}"
    cat > "${SYSTEMD_DIR}/${SERVICE_NAME}.service" <<SVCEOF
[Unit]
Description=MemPalace MCP HTTP Server
After=network.target

[Service]
Type=simple
EnvironmentFile=${ENV_FILE}
ExecStart=${VENV_PY} ${INSTALL_DIR}/mempalace_http.py
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
    echo "  source ${ENV_FILE} && ${VENV_PY} ${INSTALL_DIR}/mempalace_http.py"
fi

HOSTNAME_VAL="$(hostname -f 2>/dev/null || hostname)"

# 6. Claude Code MCP config
configure_claude_mcp() {
    local url="http://${HOSTNAME_VAL}:${PORT}/mcp"
    echo ""

    if command -v claude >/dev/null 2>&1; then
        # Preferred: use the official CLI
        local has_existing=false
        claude mcp list 2>/dev/null | grep -q "^mempalace" && has_existing=true

        if [ "${has_existing}" = true ]; then
            warn "Existing mempalace MCP config found (claude mcp list)."
            read -rp "Replace with HTTP config? [y/N] " confirm
            [[ "${confirm}" =~ ^[yY]$ ]] || { info "Skipped — update manually if needed."; return; }
            claude mcp remove mempalace 2>/dev/null || true
        else
            read -rp "Add mempalace HTTP MCP config via claude CLI? [Y/n] " confirm
            [[ "${confirm}" =~ ^[nN]$ ]] && { info "Skipped."; return; }
        fi
        claude mcp add --transport http mempalace "${url}" \
            --header "Authorization: Bearer ${TOKEN}"
        ok "Claude MCP configured: mempalace → ${url}"
    else
        # Fallback: direct JSON edit of settings.json
        local settings_file="${HOME}/.claude/settings.json"
        [ -f "${settings_file}" ] || { info "claude CLI not found and ~/.claude/settings.json not found — skipping"; return; }

        local existing
        existing="$(${VENV_PY} -c "
import json
with open('${settings_file}') as f:
    cfg = json.load(f)
mp = cfg.get('mcpServers', {}).get('mempalace')
if mp:
    print(json.dumps(mp, indent=2))
" 2>/dev/null || echo "")"

        if [ -n "${existing}" ]; then
            warn "Existing mempalace MCP config found in ${settings_file}:"
            echo "${existing}"
            echo ""
            read -rp "Replace with HTTP config? [y/N] " confirm
            [[ "${confirm}" =~ ^[yY]$ ]] || { info "Skipped — update manually if needed."; return; }
        else
            read -rp "Add mempalace HTTP MCP config to ${settings_file}? [Y/n] " confirm
            [[ "${confirm}" =~ ^[nN]$ ]] && { info "Skipped."; return; }
        fi

        ${VENV_PY} -c "
import json
with open('${settings_file}') as f:
    cfg = json.load(f)
cfg.setdefault('mcpServers', {})['mempalace'] = {
    'type': 'http',
    'url': '${url}',
    'headers': {'Authorization': 'Bearer ${TOKEN}'}
}
with open('${settings_file}', 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
"
        ok "Claude MCP config updated in ${settings_file}"
    fi
}

configure_claude_mcp

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Manual MCP setup (other machines / clients):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  claude mcp add --transport http mempalace \\"
echo "    http://${HOSTNAME_VAL}:${PORT}/mcp \\"
echo "    --header \"Authorization: Bearer ${TOKEN}\""
echo ""
echo "  # or for other clients, settings.json entry:"
cat <<CFGEOF
  {
    "mcpServers": {
      "mempalace": {
        "type": "http",
        "url": "http://${HOSTNAME_VAL}:${PORT}/mcp",
        "headers": { "Authorization": "Bearer ${TOKEN}" }
      }
    }
  }
CFGEOF
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Token management: mempalace-token [show|rotate|reveal|remove]"
