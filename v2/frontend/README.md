# WAN_SIM ReactUI 2.0

La consola ReactUI consume la API FastAPI de `../backend`. Ejecuta primero el backend:

```bash
cd ../backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
uvicorn wansim_v2.api:app --host 0.0.0.0 --port 8080
```

En otra terminal, inicia la interfaz:

```bash
cd v2/frontend
npm install
npm run dev -- --host 0.0.0.0
```

Abre `http://<IP_DEL_SERVIDOR>:5173`. El proxy de Vite enruta `/api` y `/health` al backend local en `8080`.

Para una comprobación sin servidor de desarrollo:

```bash
npm run build
```

El backend inicia en `dry-run`. Solo se permiten cambios de red reales cuando se definen `WANSIM_V2_EXECUTION_MODE=host` y `WANSIM_V2_ALLOW_HOST_APPLY=1` en un host dedicado.
