from __future__ import annotations

import os
from pathlib import Path

from fastapi import FastAPI, HTTPException, status

from . import __version__
from .models import ConfigurationCreate, ConfigurationRecord, DeploymentRecord, DeploymentRequest, NetemRequest, ServiceRestartRequest
from .network import CommandRunner, NetworkAgent
from .repository import ConfigRepository
from .service import DeploymentService


def create_app(data_dir: Path | None = None, agent: NetworkAgent | None = None) -> FastAPI:
    root = data_dir or Path(os.getenv("WANSIM_V2_DATA_DIR", "~/.wansim-v2")).expanduser()
    repository = ConfigRepository(root / "state.db")
    service = DeploymentService(repository, agent or NetworkAgent(CommandRunner()))
    app = FastAPI(title="WAN_SIM 2.0 API", version=__version__)
    app.state.repository = repository
    app.state.service = service

    @app.get("/health")
    def health() -> dict:
        return {"ok": True, "version": app.version, "execution_mode": service.agent.execution_mode}

    @app.get("/api/v2/interfaces")
    def interfaces() -> dict:
        return {"items": service.agent.interfaces(), "execution_mode": service.agent.execution_mode}

    @app.get("/api/v2/operations/overview")
    def operations_overview() -> dict:
        return {**service.agent.overview(), "active_configuration": repository.active_configuration(), "deployments": repository.list_deployments(20)}

    @app.post("/api/v2/operations/netem")
    def apply_netem(request: NetemRequest) -> dict:
        result = service.agent.apply_netem(request.interface, request.delay_ms, request.jitter_ms, request.loss_percent)
        if not result.get("ok"):
            raise HTTPException(status_code=400, detail=result.get("error", result.get("output", "No se pudo aplicar netem.")))
        return result

    @app.post("/api/v2/operations/services/restart")
    def restart_service(request: ServiceRestartRequest) -> dict:
        result = service.agent.restart_service(request.service)
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
        return service.rollback(deployment)

    return app


app = create_app()
