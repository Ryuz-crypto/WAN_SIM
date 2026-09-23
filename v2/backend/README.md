# WAN_SIM 2.0 Control Plane

El backend FastAPI inicia en modo `dry-run`; valida, guarda el plan y prueba el ciclo de despliegue sin modificar interfaces del host.

```bash
cd v2/backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
export WANSIM_V2_API_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
uvicorn wansim_v2.api:app --host 0.0.0.0 --port 8080
```

La API publica `/docs`, `/health` y `/api/v2`. `/api/v2` exige la clave enviada en `X-WAN-SIM-API-Key`; si no se define, el backend genera `~/.wansim-v2/api.key`. Este arranque manual es únicamente para desarrollo en `dry-run`.

```bash
sudo ./install-v2.sh install
```

La instalación completa mantiene FastAPI sin privilegios y ejecuta las operaciones de red en `wansim-agent.service`. Ambos componentes se comunican por `/run/wansim/agent.sock` con permisos de grupo, firma HMAC, timestamp y nonce. `--host-apply` debe usarse únicamente en una VM o servidor de laboratorio dedicado.
