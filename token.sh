#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${HOME}/.config/mempalace-mcp-http"
ENV_FILE="${CONFIG_DIR}/env"
SERVICE_NAME="mempalace-mcp-http"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
err()  { echo -e "${RED}ERROR: $*${NC}" >&2; }
ok()   { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}WARNING: $*${NC}"; }

[ -f "${ENV_FILE}" ] || { err "No config at ${ENV_FILE}. Run setup.sh first."; exit 1; }

current_token() {
    grep "^MEMPALACE_HTTP_TOKEN=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2- || echo ""
}

set_token() {
    if grep -q "^MEMPALACE_HTTP_TOKEN=" "${ENV_FILE}"; then
        sed -i "s|^MEMPALACE_HTTP_TOKEN=.*|MEMPALACE_HTTP_TOKEN=${1}|" "${ENV_FILE}"
    else
        echo "MEMPALACE_HTTP_TOKEN=${1}" >> "${ENV_FILE}"
    fi
}

restart_service() {
    if command -v systemctl >/dev/null 2>&1 && systemctl --user is-active "${SERVICE_NAME}" >/dev/null 2>&1; then
        systemctl --user restart "${SERVICE_NAME}"
        ok "Service restarted"
    else
        warn "Service not running via systemd — restart manually to apply change"
    fi
}

cmd="${1:-help}"

case "${cmd}" in
  show)
    token="$(current_token)"
    if [ -z "${token}" ]; then
        echo "No token set (open/unauthenticated mode)"
    else
        echo "Token: ${token:0:8}..."
    fi
    ;;

  reveal)
    token="$(current_token)"
    if [ -z "${token}" ]; then
        echo "No token set"
    else
        warn "Keep secret — do not share or commit"
        echo "${token}"
    fi
    ;;

  rotate)
    new_token="$(openssl rand -hex 32)"
    set_token "${new_token}"
    restart_service
    ok "Token rotated — update all MCP configs with new token:"
    echo "${new_token}"
    ;;

  remove)
    warn "Token will be invalidated — all connected clients lose access immediately"
    warn "Server stays in auth-required mode. Use 'rotate' to generate a new usable token."
    echo ""
    read -rp "Confirm invalidation? [y/N] " confirm
    [[ "${confirm}" =~ ^[yY]$ ]] || { echo "Aborted."; exit 0; }
    dead="$(openssl rand -hex 32)"
    set_token "${dead}"
    restart_service
    ok "Token invalidated — server requires auth but no valid token exists"
    ;;

  help|*)
    echo "Usage: mempalace-token <command>"
    echo ""
    echo "  show    masked preview of current token"
    echo "  reveal  full token (keep secret)"
    echo "  rotate  generate new token, restart service"
    echo "  remove  invalidate token — blocks all clients, requires rotate to recover"
    ;;
esac
