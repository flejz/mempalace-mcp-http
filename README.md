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
git clone https://github.com/flejz/mempalace-mcp-http
cd mempalace-mcp-http
./setup.sh
```

Detects mempalace, installs HTTP deps, configures systemd service, prints MCP config to paste.

## Token management

```bash
token.sh show      # masked preview
token.sh reveal    # full token
token.sh rotate    # new token + restart service
token.sh revoke    # remove token (open mode)
```

Located at `~/.local/lib/mempalace-mcp-http/token.sh` after setup.

## Claude Code config

Add to `~/.claude/settings.json`:

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
