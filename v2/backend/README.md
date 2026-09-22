# WAN_SIM 2.0 Control Plane

El backend FastAPI inicia en modo `dry-run`; valida, guarda el plan y prueba el ciclo de despliegue sin modificar interfaces del host.

```bash
cd v2/backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
uvicorn wansim_v2.api:app --host 0.0.0.0 --port 8080
```

La API publica `/docs`, `/health` y `/api/v2`. Para permitir aplicación real sobre un host dedicado, instala el agente en el host y define ambas variables antes de iniciar el servicio:

```bash
export WANSIM_V2_EXECUTION_MODE=host
export WANSIM_V2_ALLOW_HOST_APPLY=1
```

La protección de doble variable evita que un arranque ordinario de desarrollo cambie una interfaz, NAT, DHCP o Bridge por accidente. La aplicación real requiere el agente y sus permisos mínimos; esa instalación será la siguiente entrega de 2.0.
