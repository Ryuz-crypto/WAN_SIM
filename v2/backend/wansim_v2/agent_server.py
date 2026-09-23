from __future__ import annotations

import hmac
import os
import threading
import time
from contextlib import contextmanager
from collections.abc import Iterator

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

from .agent_auth import signature
from .models import CommandAction, TopologyConfig
from .network import ApplyError, CommandRunner, NetworkAgent


TOKEN = os.getenv("WANSIM_V2_AGENT_TOKEN", "")
if len(TOKEN) < 32:
    raise RuntimeError("WANSIM_V2_AGENT_TOKEN debe contener al menos 32 caracteres.")

agent = NetworkAgent(CommandRunner(os.getenv("WANSIM_V2_EXECUTION_MODE", "dry-run")))
app = FastAPI(title="WAN_SIM 2 Host Agent", docs_url=None, redoc_url=None, openapi_url=None)
_nonces: dict[str, int] = {}
_nonce_lock = threading.Lock()
_operation_lock = threading.Lock()


@app.middleware("http")
async def authenticate_request(request: Request, call_next):
    timestamp = request.headers.get("X-WAN-SIM-Timestamp", "")
    nonce = request.headers.get("X-WAN-SIM-Nonce", "")
    supplied = request.headers.get("X-WAN-SIM-Signature", "")
    try:
        request_time = int(timestamp)
    except ValueError:
        return JSONResponse(status_code=401, content={"detail": "Firma del agente incompleta."})
    now = int(time.time())
    if abs(now - request_time) > 30 or len(nonce) < 16:
        return JSONResponse(status_code=401, content={"detail": "Firma vencida o nonce inválido."})
    body = await request.body()
    expected = signature(TOKEN, timestamp, nonce, request.method, request.url.path, body)
    if not hmac.compare_digest(supplied, expected):
        return JSONResponse(status_code=401, content={"detail": "Firma del agente inválida."})
    with _nonce_lock:
        expired = [value for value, seen_at in _nonces.items() if now - seen_at > 60]
        for value in expired:
            _nonces.pop(value, None)
        if nonce in _nonces:
            return JSONResponse(status_code=409, content={"detail": "Solicitud repetida."})
        _nonces[nonce] = now
    return await call_next(request)


def config_from(payload: dict) -> TopologyConfig:
    return TopologyConfig.model_validate(payload["config"])


def actions_from(payload: dict, key: str = "actions") -> list[CommandAction]:
    return [CommandAction.model_validate(item) for item in payload.get(key, [])]


@contextmanager
def exclusive_operation() -> Iterator[None]:
    if not _operation_lock.acquire(blocking=False):
        raise HTTPException(status_code=423, detail="Otra operación de red está en curso.")
    try:
        yield
    finally:
        _operation_lock.release()


@app.get("/v1/health")
def health() -> dict:
    return {"ok": True, "execution_mode": agent.execution_mode}


@app.get("/v1/interfaces")
def interfaces() -> list[dict]:
    return agent.interfaces()


@app.get("/v1/snapshot")
def snapshot() -> dict:
    return agent.snapshot()


@app.post("/v1/plan")
def plan(payload: dict) -> list[dict]:
    return [item.model_dump(mode="json") for item in agent.plan(config_from(payload))]


@app.post("/v1/preflight")
def preflight(payload: dict) -> dict:
    return agent.preflight(config_from(payload))


@app.post("/v1/apply")
def apply(payload: dict) -> dict:
    config = TopologyConfig.model_validate(payload["config"]) if payload.get("config") else None
    with exclusive_operation():
        try:
            outcome = agent.apply(actions_from(payload), config)
        except ApplyError as error:
            raise HTTPException(status_code=409, detail={
                "message": str(error),
                "outcome": {
                    "results": error.outcome.results,
                    "applied_actions": [item.model_dump(mode="json") for item in error.outcome.applied_actions],
                },
            }) from error
    return {"results": outcome.results, "applied_actions": [item.model_dump(mode="json") for item in outcome.applied_actions]}


@app.post("/v1/verify")
def verify(payload: dict) -> dict:
    return agent.verify(config_from(payload))


@app.post("/v1/cleanup-conflicts")
def cleanup_conflicts(payload: dict) -> list[dict]:
    with exclusive_operation():
        return agent.cleanup_conflicts(actions_from(payload, "previous"), actions_from(payload, "current"))


@app.post("/v1/cleanup-obsolete")
def cleanup_obsolete(payload: dict) -> list[dict]:
    with exclusive_operation():
        return agent.cleanup_obsolete(actions_from(payload, "previous"), actions_from(payload, "current"))


@app.post("/v1/rollback")
def rollback(payload: dict) -> list[dict]:
    with exclusive_operation():
        return agent.rollback(actions_from(payload), payload["snapshot"], actions_from(payload, "restore_actions"))


@app.get("/v1/overview")
def overview() -> dict:
    return agent.overview()


@app.post("/v1/netem")
def netem(payload: dict) -> dict:
    with exclusive_operation():
        return agent.apply_netem(payload["interface"], payload["delay_ms"], payload["jitter_ms"], payload["loss_percent"])


@app.post("/v1/restart-service")
def restart_service(payload: dict) -> dict:
    with exclusive_operation():
        return agent.restart_service(payload["service"])
