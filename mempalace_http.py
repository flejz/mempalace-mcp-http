#!/usr/bin/env python3
import asyncio
import os
import threading

import uvicorn
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.responses import JSONResponse, Response

from mempalace.mcp_server import handle_request
from mempalace.version import __version__ as _mp_version

_lock = threading.Lock()
_token = os.environ.get("MEMPALACE_HTTP_TOKEN")

app = FastAPI(docs_url=None, redoc_url=None)


def _check_auth(request: Request) -> None:
    if not _token:
        return
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer ") or auth[7:] != _token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")


def _call(body: dict):
    with _lock:
        return handle_request(body)


@app.post("/mcp")
async def mcp(request: Request):
    _check_auth(request)
    try:
        body = await request.json()
    except Exception:
        return JSONResponse(
            {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}}
        )
    loop = asyncio.get_running_loop()
    response = await loop.run_in_executor(None, lambda: _call(body))
    if response is None:
        return Response(status_code=202)
    return JSONResponse(response)


@app.get("/health")
async def health():
    return {"status": "ok", "mempalace": _mp_version}


if __name__ == "__main__":
    port = int(os.environ.get("MEMPALACE_HTTP_PORT", 8765))
    host = os.environ.get("MEMPALACE_HTTP_HOST", "0.0.0.0")
    uvicorn.run(app, host=host, port=port)
