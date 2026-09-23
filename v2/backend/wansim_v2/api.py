from __future__ import annotations

import os
from pathlib import Path

from fastapi import FastAPI, Header, HTTPException, Request, status
from fastapi.responses import JSONResponse

from . import __version__
from .models import (ConfigurationCreate, ConfigurationRecord, DeploymentRecord, DeploymentRequest, NetemRequest,
                     ServiceRestartRequest, TelegramBotCreate, TelegramBotCreated, TelegramBotRecord,
                     TelegramBotUpdate, TelegramDeliveryRequest, TelegramWebhookSyncRequest)
from .agent_client import network_agent_from_environment
from .network import NetworkAgent
from .operations import OperationsService
from .repository import ConfigRepository
from .security import ApiKeyGuard
from .service import DeploymentService
from .telegram import TelegramGateway, TelegramService


def create_app(data_dir: Path | None = None, agent: NetworkAgent | None = None, telegram_gateway: TelegramGateway | None = None, api_key: str | None = None) -> FastAPI:
    root = data_dir or Path(os.getenv("WANSIM_V2_DATA_DIR", "~/.wansim-v2")).expanduser()
    repository = ConfigRepository(root / "state.db")
    service = DeploymentService(repository, agent or network_agent_from_environment())
    operations = OperationsService(repository, service.agent)
    telegram = TelegramService(repository, operations, telegram_gateway or TelegramGateway())
    api_guard = ApiKeyGuard(root, api_key)
    app = FastAPI(title="WAN_SIM 2.0 API", version=__version__)
    app.state.repository = repository
    app.state.service = service
    app.state.operations = operations
    app.state.telegram = telegram

    @app.middleware("http")
    async def require_api_key(request: Request, call_next):
        path = request.url.path
        is_webhook = path.startswith("/api/v2/telegram/bots/") and path.endswith("/webhook")
        if path.startswith("/api/v2/") and not is_webhook and not api_guard.valid(request.headers.get("X-WAN-SIM-API-Key")):
            return JSONResponse(status_code=401, content={"detail": "Clave de API inválida o ausente."})
        return await call_next(request)

    @app.get("/health")
    def health() -> dict:
        return {"ok": True, "version": app.version, "execution_mode": service.agent.execution_mode}

    @app.get("/api/v2/interfaces")
    def interfaces() -> dict:
        return {"items": service.agent.interfaces(), "execution_mode": service.agent.execution_mode}

    @app.get("/api/v2/operations/overview")
    def operations_overview() -> dict:
        return operations.overview()

    @app.post("/api/v2/operations/netem")
    def apply_netem(request: NetemRequest) -> dict:
        result = operations.netem(request.interface, request.delay_ms, request.jitter_ms, request.loss_percent)
        if not result.get("ok"):
            raise HTTPException(status_code=400, detail=result.get("error", result.get("output", "No se pudo aplicar netem.")))
        return result

    @app.post("/api/v2/operations/services/restart")
    def restart_service(request: ServiceRestartRequest) -> dict:
        result = operations.restart(request.service)
        if not result.get("ok"):
            raise HTTPException(status_code=400, detail=result.get("error", result.get("output", "No se pudo reiniciar servicio.")))
        return result

    @app.post("/api/v2/configurations", response_model=ConfigurationRecord, status_code=status.HTTP_201_CREATED)
    def create_configuration(request: ConfigurationCreate) -> ConfigurationRecord:
        return repository.create_configuration(request.name, request.config)

    @app.get("/api/v2/configurations/{configuration_id}", response_model=ConfigurationRecord)
    def get_configuration(configuration_id: str) -> ConfigurationRecord:
        configuration = repository.get_configuration(configuration_id)
        if not configuration:
            raise HTTPException(status_code=404, detail="Configuración no encontrada.")
        return configuration

    @app.get("/api/v2/configurations/active/current", response_model=ConfigurationRecord | None)
    def active_configuration() -> ConfigurationRecord | None:
        return repository.active_configuration()

    @app.post("/api/v2/configurations/{configuration_id}/plan")
    def plan_configuration(configuration_id: str) -> dict:
        configuration = get_configuration(configuration_id)
        return {"configuration_id": configuration_id, "execution_mode": service.agent.execution_mode, "actions": service.plan(configuration)}

    @app.post("/api/v2/configurations/{configuration_id}/deploy", response_model=DeploymentRecord)
    def deploy_configuration(configuration_id: str, request: DeploymentRequest) -> DeploymentRecord:
        configuration = get_configuration(configuration_id)
        if request.apply and service.agent.execution_mode == "host" and request.confirmation != f"APLICAR {configuration_id}":
            raise HTTPException(status_code=409, detail="El modo host requiere confirmar el identificador exacto desde ReactUI.")
        return service.deploy(configuration, request.apply)

    @app.get("/api/v2/deployments/{deployment_id}", response_model=DeploymentRecord)
    def get_deployment(deployment_id: str) -> DeploymentRecord:
        deployment = repository.get_deployment(deployment_id)
        if not deployment:
            raise HTTPException(status_code=404, detail="Despliegue no encontrado.")
        return deployment

    @app.get("/api/v2/deployments", response_model=list[DeploymentRecord])
    def list_deployments() -> list[DeploymentRecord]:
        return repository.list_deployments()

    @app.post("/api/v2/deployments/{deployment_id}/rollback", response_model=DeploymentRecord)
    def rollback_deployment(deployment_id: str) -> DeploymentRecord:
        deployment = get_deployment(deployment_id)
        try:
            return service.rollback(deployment)
        except ValueError as error:
            raise HTTPException(status_code=409, detail=str(error)) from error

    @app.get("/api/v2/telegram/bots", response_model=list[TelegramBotRecord])
    def list_telegram_bots() -> list[TelegramBotRecord]:
        return repository.list_telegram_bots()

    @app.post("/api/v2/telegram/bots", response_model=TelegramBotCreated, status_code=status.HTTP_201_CREATED)
    def create_telegram_bot(request: TelegramBotCreate) -> TelegramBotCreated:
        created = telegram.create(request.name, request.token, request.allowed_chat_ids, request.permission, request.webhook_secret)
        return TelegramBotCreated.model_validate(created)

    @app.patch("/api/v2/telegram/bots/{bot_id}", response_model=TelegramBotRecord)
    def update_telegram_bot(bot_id: str, request: TelegramBotUpdate) -> TelegramBotRecord:
        bot = repository.update_telegram_bot(bot_id, request)
        if not bot:
            raise HTTPException(status_code=404, detail="Bot no encontrado.")
        return bot

    @app.post("/api/v2/telegram/bots/{bot_id}/test")
    def test_telegram_bot(bot_id: str, request: TelegramDeliveryRequest) -> dict:
        try:
            return telegram.test_delivery(bot_id, request.chat_id)
        except LookupError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error
        except PermissionError as error:
            raise HTTPException(status_code=403, detail=str(error)) from error
        except RuntimeError as error:
            raise HTTPException(status_code=502, detail=str(error)) from error

    @app.post("/api/v2/telegram/bots/{bot_id}/sync")
    def sync_telegram_bot(bot_id: str, request: TelegramWebhookSyncRequest) -> dict:
        try:
            return telegram.synchronize(bot_id, request.public_base_url)
        except LookupError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error
        except ValueError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error
        except RuntimeError as error:
            raise HTTPException(status_code=502, detail=str(error)) from error

    @app.post("/api/v2/telegram/bots/{bot_id}/webhook")
    def telegram_webhook(bot_id: str, update: dict, x_telegram_bot_api_secret_token: str | None = Header(default=None)) -> dict:
        try:
            return telegram.process_update(bot_id, x_telegram_bot_api_secret_token, update)
        except LookupError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error
        except PermissionError as error:
            raise HTTPException(status_code=403, detail=str(error)) from error
        except ValueError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error
        except RuntimeError as error:
            raise HTTPException(status_code=502, detail=str(error)) from error

    return app


app = create_app()
