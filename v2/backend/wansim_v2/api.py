from __future__ import annotations

import os
from ipaddress import ip_address
from pathlib import Path

from fastapi import FastAPI, Header, HTTPException, Request, status
from fastapi.responses import JSONResponse

from . import __version__
from .auth import AuthService
from .models import (ConfigurationCreate, ConfigurationRecord, DeploymentRecord, DeploymentRequest, InterfaceActionRequest, NetemRequest,
                     LoginRequest, PasswordChange, RecoveryRequest, ServiceRestartRequest, TelegramBotCreate,
                     TelegramBotCreated, TelegramBotRecord, TelegramBotUpdate, TelegramDeliveryRequest,
                     TelegramWebhookSyncRequest, UpdateApplyRequest, UserCreate, UserRole, UserUpdate)
from .agent_client import network_agent_from_environment
from .network import NetworkAgent
from .operations import OperationsService
from .repository import ConfigRepository
from .security import ApiKeyGuard
from .service import DeploymentService
from .telegram import TelegramGateway, TelegramService


def request_client_ip(request: Request) -> str | None:
    candidate = request.headers.get("X-Forwarded-For", "").split(",", 1)[0].strip()
    candidate = candidate or request.headers.get("X-Real-IP", "").strip()
    try:
        parsed = ip_address(candidate)
    except ValueError:
        return None
    return str(parsed) if parsed.version == 4 else None


def create_app(data_dir: Path | None = None, agent: NetworkAgent | None = None, telegram_gateway: TelegramGateway | None = None, api_key: str | None = None) -> FastAPI:
    root = data_dir or Path(os.getenv("WANSIM_V2_DATA_DIR", "~/.wansim-v2")).expanduser()
    repository = ConfigRepository(root / "state.db")
    service = DeploymentService(repository, agent or network_agent_from_environment())
    operations = OperationsService(repository, service.agent)
    telegram = TelegramService(repository, operations, telegram_gateway or TelegramGateway())
    auth = AuthService(repository)
    api_guard = ApiKeyGuard(root, api_key)
    app = FastAPI(title="WAN_SIM Control Plane API", version=__version__)
    app.state.repository = repository
    app.state.service = service
    app.state.operations = operations
    app.state.telegram = telegram
    app.state.auth = auth

    def bearer_token(request: Request) -> str | None:
        value = request.headers.get("Authorization", "")
        return value[7:].strip() if value.lower().startswith("bearer ") else None

    def require_role(request: Request, minimum: UserRole) -> dict:
        identity = getattr(request.state, "identity", None)
        if not identity or not auth.allowed(identity, minimum):
            raise HTTPException(status_code=403, detail=f"Esta operación requiere rol {minimum.value}.")
        return identity

    def audit(request: Request, action: str, target: str, detail: dict | None = None) -> None:
        identity = getattr(request.state, "identity", {"username": "system", "role": "system"})
        repository.audit(identity["username"], identity["role"], action, target, detail)

    @app.middleware("http")
    async def require_api_key(request: Request, call_next):
        path = request.url.path
        is_webhook = path.startswith("/api/v2/telegram/bots/") and path.endswith("/webhook")
        is_login = path == "/api/v2/auth/login"
        if path.startswith("/api/v2/") and not is_webhook and not is_login:
            if api_guard.valid(request.headers.get("X-WAN-SIM-API-Key")):
                request.state.identity = {"id": "legacy-api-key", "username": "legacy-api-key", "role": "admin", "auth": "api_key"}
            else:
                identity = auth.identity(bearer_token(request))
                if not identity:
                    return JSONResponse(status_code=401, content={"detail": "Sesión o clave de API inválida."})
                request.state.identity = identity
        return await call_next(request)

    @app.get("/health")
    def health() -> dict:
        return {"ok": True, "version": app.version, "execution_mode": service.agent.execution_mode, "users_configured": repository.has_users()}

    @app.post("/api/v2/auth/login")
    def login(payload: LoginRequest) -> dict:
        try:
            result = auth.login(payload.username, payload.password)
        except PermissionError as error:
            repository.audit(payload.username.lower(), "unknown", "auth.login_failed", "session")
            raise HTTPException(status_code=401, detail=str(error)) from error
        repository.audit(result["user"]["username"], result["user"]["role"], "auth.login", "session")
        return result

    @app.post("/api/v2/auth/logout")
    def logout(request: Request) -> dict:
        identity = require_role(request, UserRole.VIEWER)
        auth.logout(bearer_token(request))
        repository.audit(identity["username"], identity["role"], "auth.logout", "session")
        return {"ok": True}

    @app.get("/api/v2/auth/me")
    def current_identity(request: Request) -> dict:
        return require_role(request, UserRole.VIEWER)

    @app.get("/api/v2/auth/users")
    def list_users(request: Request) -> list[dict]:
        require_role(request, UserRole.ADMIN)
        return repository.list_users()

    @app.post("/api/v2/auth/users", status_code=status.HTTP_201_CREATED)
    def create_user(payload: UserCreate, request: Request) -> dict:
        require_role(request, UserRole.ADMIN)
        try:
            user = auth.create_user(payload)
        except ValueError as error:
            raise HTTPException(status_code=409, detail=str(error)) from error
        audit(request, "user.create", user["id"], {"username": user["username"], "role": user["role"]})
        return user

    @app.patch("/api/v2/auth/users/{user_id}")
    def update_user(user_id: str, payload: UserUpdate, request: Request) -> dict:
        require_role(request, UserRole.ADMIN)
        current = repository.get_user(user_id)
        if not current:
            raise HTTPException(status_code=404, detail="Usuario no encontrado.")
        removes_admin = current["role"] == "admin" and (payload.enabled is False or payload.role not in (None, UserRole.ADMIN))
        active_admins = [item for item in repository.list_users() if item["role"] == "admin" and item["enabled"]]
        if removes_admin and len(active_admins) <= 1:
            raise HTTPException(status_code=409, detail="No se puede retirar el último administrador habilitado.")
        user = auth.update_user(user_id, payload)
        audit(request, "user.update", user_id, {"role": user["role"], "enabled": bool(user["enabled"]), "password_rotated": bool(payload.password)})
        return user

    @app.delete("/api/v2/auth/users/{user_id}")
    def delete_user(user_id: str, request: Request) -> dict:
        identity = require_role(request, UserRole.ADMIN)
        current = repository.get_user(user_id)
        if not current:
            raise HTTPException(status_code=404, detail="Usuario no encontrado.")
        if identity.get("id") == user_id:
            raise HTTPException(status_code=409, detail="No puedes eliminar tu propia cuenta durante una sesión activa.")
        active_admins = [item for item in repository.list_users() if item["role"] == "admin" and item["enabled"]]
        if current["role"] == "admin" and current["enabled"] and len(active_admins) <= 1:
            raise HTTPException(status_code=409, detail="No se puede eliminar el último administrador habilitado.")
        auth.delete_user(user_id)
        audit(request, "user.delete", user_id, {"username": current["username"], "role": current["role"]})
        return {"ok": True}

    @app.post("/api/v2/auth/password")
    def change_password(payload: PasswordChange, request: Request) -> dict:
        identity = require_role(request, UserRole.VIEWER)
        if identity.get("auth") != "session":
            raise HTTPException(status_code=409, detail="La clave API heredada se rota desde /etc/wansim/wansim.env.")
        try:
            auth.change_password(identity["id"], payload.current_password, payload.new_password)
        except PermissionError as error:
            raise HTTPException(status_code=403, detail=str(error)) from error
        audit(request, "user.password_rotate", identity["id"])
        return {"ok": True, "reauthenticate": True}

    @app.get("/api/v2/interfaces")
    def interfaces() -> dict:
        return {"items": service.agent.interfaces(), "execution_mode": service.agent.execution_mode}

    @app.get("/api/v2/operations/overview")
    def operations_overview() -> dict:
        return operations.overview()

    @app.post("/api/v2/operations/netem")
    def apply_netem(payload: NetemRequest, request: Request) -> dict:
        require_role(request, UserRole.OPERATOR)
        result = operations.netem(payload.interface, payload.delay_ms, payload.jitter_ms, payload.loss_percent)
        if not result.get("ok"):
            raise HTTPException(status_code=400, detail=result.get("error", result.get("output", "No se pudo aplicar netem.")))
        audit(request, "netem.apply", payload.interface, {"delay_ms": payload.delay_ms, "jitter_ms": payload.jitter_ms, "loss_percent": payload.loss_percent})
        return result

    @app.post("/api/v2/operations/services/restart")
    def restart_service(payload: ServiceRestartRequest, request: Request) -> dict:
        require_role(request, UserRole.ADMIN)
        result = operations.restart(payload.service)
        if not result.get("ok"):
            raise HTTPException(status_code=400, detail=result.get("error", result.get("output", "No se pudo reiniciar servicio.")))
        audit(request, "service.restart", payload.service)
        return result

    @app.post("/api/v2/operations/interfaces/action")
    def interface_action(payload: InterfaceActionRequest, request: Request) -> dict:
        require_role(request, UserRole.ADMIN)
        result = operations.interface_action(payload.interface, payload.action)
        if not result.get("ok"):
            raise HTTPException(status_code=409, detail=result.get("error", "No se pudo operar la interfaz."))
        audit(request, f"interface.{payload.action}", payload.interface)
        return result

    @app.get("/api/v2/system/releases")
    def release_status(request: Request) -> dict:
        require_role(request, UserRole.ADMIN)
        return operations.release_status()

    @app.post("/api/v2/system/update", status_code=status.HTTP_202_ACCEPTED)
    def apply_update(payload: UpdateApplyRequest, request: Request) -> dict:
        require_role(request, UserRole.ADMIN)
        if payload.confirmation != f"ACTUALIZAR {payload.version}":
            raise HTTPException(status_code=409, detail="Escribe la confirmación exacta de actualización.")
        result = operations.schedule_update(payload.version)
        if not result.get("ok"):
            raise HTTPException(status_code=409, detail=result.get("error", result.get("output", "No se pudo programar la actualización.")))
        audit(request, "system.update", payload.version, {"unit": result.get("unit")})
        return result

    @app.get("/api/v2/operations/doctor")
    def doctor(request: Request) -> dict:
        require_role(request, UserRole.VIEWER)
        return operations.doctor()

    @app.post("/api/v2/configurations", response_model=ConfigurationRecord, status_code=status.HTTP_201_CREATED)
    def create_configuration(payload: ConfigurationCreate, request: Request) -> ConfigurationRecord:
        require_role(request, UserRole.OPERATOR)
        created = repository.create_configuration(payload.name, payload.config)
        audit(request, "configuration.create", created.id, {"name": created.name, "topology": created.config.topology.value})
        return created

    @app.get("/api/v2/configurations", response_model=list[ConfigurationRecord])
    def list_configurations(request: Request) -> list[ConfigurationRecord]:
        require_role(request, UserRole.VIEWER)
        return repository.list_configurations()

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
    def plan_configuration(configuration_id: str, request: Request) -> dict:
        require_role(request, UserRole.OPERATOR)
        configuration = get_configuration(configuration_id)
        return service.review(configuration, request_client_ip(request))

    @app.post("/api/v2/configurations/{configuration_id}/deploy", response_model=DeploymentRecord)
    def deploy_configuration(configuration_id: str, payload: DeploymentRequest, request: Request) -> DeploymentRecord:
        require_role(request, UserRole.OPERATOR)
        configuration = get_configuration(configuration_id)
        review = service.review(configuration, request_client_ip(request))
        if payload.apply and service.agent.execution_mode == "host" and payload.confirmation != f"APLICAR {configuration_id}":
            raise HTTPException(status_code=409, detail="El modo host requiere confirmar el identificador exacto desde ReactUI.")
        expected_risk = review["management_confirmation_phrase"]
        if payload.apply and service.agent.execution_mode == "host" and expected_risk and payload.management_confirmation != expected_risk:
            raise HTTPException(status_code=409, detail="La interfaz de administración requiere la confirmación de riesgo exacta.")
        result = service.deploy(configuration, payload.apply, request_client_ip(request))
        audit(request, "deployment.apply" if payload.apply else "deployment.plan", result.id, {"configuration_id": configuration_id, "status": result.status})
        return result

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
    def rollback_deployment(deployment_id: str, request: Request) -> DeploymentRecord:
        require_role(request, UserRole.OPERATOR)
        deployment = get_deployment(deployment_id)
        try:
            result = service.rollback(deployment)
        except ValueError as error:
            raise HTTPException(status_code=409, detail=str(error)) from error
        audit(request, "deployment.rollback", deployment_id, {"status": result.status})
        return result

    @app.post("/api/v2/deployments/{deployment_id}/confirm", response_model=DeploymentRecord)
    def confirm_management_connectivity(deployment_id: str, request: Request) -> DeploymentRecord:
        require_role(request, UserRole.OPERATOR)
        deployment = get_deployment(deployment_id)
        try:
            result = service.confirm_management(deployment)
        except ValueError as error:
            raise HTTPException(status_code=409, detail=str(error)) from error
        audit(request, "deployment.confirm", deployment_id)
        return result

    @app.get("/api/v2/recovery/snapshots")
    def list_recovery_snapshots(request: Request) -> list[dict]:
        require_role(request, UserRole.VIEWER)
        return repository.list_snapshots()

    @app.post("/api/v2/recovery/snapshots/{snapshot_id}/restore", response_model=DeploymentRecord)
    def restore_snapshot(snapshot_id: str, payload: RecoveryRequest, request: Request) -> DeploymentRecord:
        require_role(request, UserRole.ADMIN)
        if payload.confirmation != f"RESTAURAR {snapshot_id}":
            raise HTTPException(status_code=409, detail="Escribe la confirmación exacta del snapshot.")
        try:
            result = service.restore_snapshot(snapshot_id)
        except LookupError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error
        except ValueError as error:
            raise HTTPException(status_code=409, detail=str(error)) from error
        audit(request, "recovery.restore", snapshot_id, {"status": result.status})
        return result

    @app.post("/api/v2/recovery/last-known-good", response_model=DeploymentRecord)
    def restore_last_known_good(payload: RecoveryRequest, request: Request) -> DeploymentRecord:
        require_role(request, UserRole.ADMIN)
        if payload.confirmation != "RECUPERAR ULTIMA FUNCIONAL":
            raise HTTPException(status_code=409, detail="Escribe RECUPERAR ULTIMA FUNCIONAL para continuar.")
        try:
            result = service.restore_last_known_good()
        except LookupError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error
        audit(request, "recovery.last_known_good", result.id, {"status": result.status})
        return result

    @app.get("/api/v2/recovery/backups")
    def list_host_backups(request: Request) -> list[dict]:
        require_role(request, UserRole.VIEWER)
        return operations.backups()

    @app.post("/api/v2/recovery/backups/{backup_name}/restore")
    def restore_host_backup(backup_name: str, payload: RecoveryRequest, request: Request) -> dict:
        require_role(request, UserRole.ADMIN)
        if payload.confirmation != f"RESTAURAR BACKUP {backup_name}":
            raise HTTPException(status_code=409, detail="Escribe la confirmación exacta del respaldo.")
        result = operations.restore_backup(backup_name)
        if not result.get("ok"):
            raise HTTPException(status_code=409, detail=result.get("error", result.get("output", "No se pudo programar la restauración.")))
        audit(request, "recovery.backup_restore", backup_name, {"unit": result.get("unit")})
        return result

    @app.get("/api/v2/audit/events")
    def audit_events(request: Request) -> list[dict]:
        require_role(request, UserRole.VIEWER)
        return repository.list_audit_events()

    @app.get("/api/v2/telegram/bots", response_model=list[TelegramBotRecord])
    def list_telegram_bots() -> list[TelegramBotRecord]:
        return repository.list_telegram_bots()

    @app.post("/api/v2/telegram/bots", response_model=TelegramBotCreated, status_code=status.HTTP_201_CREATED)
    def create_telegram_bot(payload: TelegramBotCreate, request: Request) -> TelegramBotCreated:
        require_role(request, UserRole.ADMIN)
        created = telegram.create(payload.name, payload.token, payload.allowed_chat_ids, payload.permission, payload.webhook_secret)
        result = TelegramBotCreated.model_validate(created)
        audit(request, "telegram.create", result.bot.id, {"name": result.bot.name, "permission": result.bot.permission.value})
        return result

    @app.patch("/api/v2/telegram/bots/{bot_id}", response_model=TelegramBotRecord)
    def update_telegram_bot(bot_id: str, payload: TelegramBotUpdate, request: Request) -> TelegramBotRecord:
        require_role(request, UserRole.ADMIN)
        bot = repository.update_telegram_bot(bot_id, payload)
        if not bot:
            raise HTTPException(status_code=404, detail="Bot no encontrado.")
        audit(request, "telegram.update", bot_id, {"enabled": bot.enabled, "permission": bot.permission.value})
        return bot

    @app.post("/api/v2/telegram/bots/{bot_id}/test")
    def test_telegram_bot(bot_id: str, payload: TelegramDeliveryRequest, request: Request) -> dict:
        require_role(request, UserRole.OPERATOR)
        try:
            result = telegram.test_delivery(bot_id, payload.chat_id)
        except LookupError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error
        except PermissionError as error:
            raise HTTPException(status_code=403, detail=str(error)) from error
        except RuntimeError as error:
            raise HTTPException(status_code=502, detail=str(error)) from error
        audit(request, "telegram.test", bot_id, {"chat_id": payload.chat_id})
        return result

    @app.post("/api/v2/telegram/bots/{bot_id}/sync")
    def sync_telegram_bot(bot_id: str, payload: TelegramWebhookSyncRequest, request: Request) -> dict:
        require_role(request, UserRole.ADMIN)
        try:
            result = telegram.synchronize(bot_id, payload.public_base_url)
        except LookupError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error
        except ValueError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error
        except RuntimeError as error:
            raise HTTPException(status_code=502, detail=str(error)) from error
        audit(request, "telegram.sync", bot_id, {"webhook_url": result.get("webhook_url", "")})
        return result

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
