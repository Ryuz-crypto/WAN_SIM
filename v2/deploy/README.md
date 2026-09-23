# WAN_SIM 2 Control Plane

La instalación soportada del plano de control se realiza desde la raíz del repositorio:

```bash
sudo ./install-v2.sh install
```

El instalador prepara Docker Engine, Compose, FastAPI, ReactUI, Nginx, SQLite, TLS, el agente nativo y los servicios `systemd`. FastAPI y ReactUI no reciben privilegios de red. Las operaciones se envían al agente del host mediante `/run/wansim/agent.sock`, con permisos de grupo y firma HMAC por solicitud.

## Componentes

- `docker-compose.yml`: FastAPI, ReactUI, proxy y almacenamiento persistente en `/var/lib/wansim`.
- `docker-compose.https.yml`: listener TLS y redirección HTTP a HTTPS.
- `/etc/wansim/wansim.env`: secretos y parámetros de ejecución, modo `0640`.
- `/etc/wansim/certs`: `fullchain.pem` y `privkey.pem` normalizados.
- `/opt/wansim/control-plane`: copia administrada por el instalador.

El modo inicial es `dry-run`. El modo host sólo se habilita explícitamente con `--host-apply` en un servidor de laboratorio dedicado.

## Operación Manual De Emergencia

Los servicios normales se administran con `systemd`:

```bash
sudo systemctl status wansim-agent wansim-control-plane
sudo systemctl restart wansim-agent wansim-control-plane
sudo ./install-v2.sh doctor
```

No ejecutes Compose directamente desde el repositorio: el servicio usa la copia versionada en `/opt/wansim/control-plane` y las credenciales protegidas de `/etc/wansim/wansim.env`.
