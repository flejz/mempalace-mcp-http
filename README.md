# mempalace-mcp-http

HTTP transport for [mempalace-mcp](https://github.com/MemPalace/mempalace). One palace, many machines.

## Prerequisites

mempalace must already be installed on the target machine:

```bash
uv tool install mempalace   # or: pip install mempalace
```

This tool extends mempalace — does not replace or install it.

## Setup

```bash
curl -fsSL https://raw.githubusercontent.com/flejz/mempalace-mcp-http/master/setup.sh | bash
```

Or clone and run:

```bash
git clone https://github.com/flejz/mempalace-mcp-http
cd mempalace-mcp-http
./setup.sh
```

Detects mempalace, installs HTTP deps, configures systemd service. If `~/.claude/settings.json` exists, prompts to add (or replace existing mempalace entry with) the HTTP MCP config automatically.

## Token management

`mempalace-token` is installed to `~/.local/bin/` during setup:

```bash
mempalace-token show      # masked preview
mempalace-token reveal    # full token
mempalace-token rotate    # new token + restart service
mempalace-token remove    # invalidate token — blocks all clients
```

`remove` replaces the token with an unguessable value (server stays auth-required, no valid token exists). Use `rotate` to recover access.

## Claude Code config

Setup auto-configures `~/.claude/settings.json` with a confirmation prompt. Manual config:

```json
{
  "mcpServers": {
    "mempalace": {
      "type": "http",
      "url": "http://<palace-host>:8765/mcp",
      "headers": {
        "Authorization": "Bearer <token>"
      }
    }
  }
}
```

Replaces the standard stdio entry (`python -m mempalace.mcp_server`) — setup.sh detects it and prompts automatically.

## Env vars

| Var | Default | Purpose |
|-----|---------|---------|
| `MEMPALACE_HTTP_PORT` | `8765` | Listen port |
| `MEMPALACE_HTTP_HOST` | `0.0.0.0` | Bind address |
| `MEMPALACE_HTTP_TOKEN` | _(unset = open)_ | Bearer auth token |

## How it works

- Calls `mempalace.mcp_server.handle_request()` directly — no subprocess, no protocol proxying
- `threading.Lock` serializes all calls — sqlite-safe under concurrent clients
- 1:1 tool mapping — all mempalace tools available, auto-updated when mempalace upgrades

## Health check

```bash
curl http://localhost:8765/health
# {"status":"ok","mempalace":"3.x.x"}
```
