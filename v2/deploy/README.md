# WAN_SIM 2.0 Docker Compose

Compose empaqueta ReactUI, FastAPI, el volumen SQLite y un proxy Nginx. No ejecuta el agente de red con privilegios: por diseño inicia en `dry-run` y no monta `/run`, `/sys`, `NET_ADMIN` ni la red del host.

Genera el secreto y prepara el archivo de entorno:

```bash
cd v2/deploy
cp .env.example .env
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

Coloca el valor generado en `WANSIM_V2_SECRET_KEY` dentro de `.env`, luego inicia HTTP:

```bash
docker compose up --build -d
docker compose ps
```

Abre `http://<IP_DEL_SERVIDOR>:8080`. Para usar TLS, coloca `fullchain.pem` y `privkey.pem` en un directorio restringido, define `WANSIM_TLS_DIR` con su ruta absoluta y usa el override:

```bash
docker compose -f docker-compose.yml -f docker-compose.https.yml up --build -d
```

El plano de control persiste SQLite y la llave de cifrado en el volumen `wansim_state`. Respáldalo antes de actualizar. La aplicación real de red permanece fuera de Compose, en un host Linux dedicado; no habilites `WANSIM_V2_EXECUTION_MODE=host` dentro del contenedor.

Para recibir botones de Telegram, inicia el override HTTPS, configura una URL pública que Telegram pueda alcanzar y regístrala desde la pestaña **Telegram** de ReactUI. El proxy debe presentar un certificado válido; Telegram no acepta HTTP para webhooks.
