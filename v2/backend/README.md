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

La API publica `/docs`, `/health` y `/api/v2`. `/api/v2` exige la clave enviada en `X-WAN-SIM-API-Key`; si no se define, el backend genera `~/.wansim-v2/api.key`. Para permitir aplicación real sobre un host dedicado, instala `iproute`, `iptables`, el cliente/servidor ISC DHCP y define ambas variables antes de iniciar el servicio:

```bash
export WANSIM_V2_EXECUTION_MODE=host
export WANSIM_V2_ALLOW_HOST_APPLY=1
```

La protección de doble variable evita que un arranque ordinario de desarrollo cambie una interfaz, NAT, DHCP o Bridge por accidente. En modo host el proceso necesita privilegios para `ip`, `tc`, `iptables`, `dhclient`, `dhcpd`, `systemctl` y escritura de `/etc/dhcp/dhcpd.conf`; úsalo únicamente en una VM o servidor de laboratorio dedicado.
