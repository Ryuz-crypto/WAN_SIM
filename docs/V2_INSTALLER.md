# Instalador Integral WAN_SIM 2

## Alcance

`install-v2.sh` instala WAN_SIM 2 en Ubuntu, Debian, Fedora o Rocky Linux sobre `x86_64` o `aarch64`. Requiere `systemd`, conexión a los repositorios y al menos 3 GiB libres. La instalación inicial no cambia interfaces: utiliza `dry-run` salvo que el operador solicite `--host-apply` explícitamente.

## Instalación

```bash
git clone --branch v2.0.13-stable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git WAN_SIM-v2
cd WAN_SIM-v2
chmod +x install-v2.sh
sudo ./install-v2.sh install
```

El asistente pregunta publicación, HTTPS, modo de ejecución y firewall, muestra un resumen y sólo entonces inicia la transacción. La opción recomendada es conservar `dry-run` durante la primera validación.

Instalación automatizada con parámetros:

```bash
sudo ./install-v2.sh install \
  --non-interactive \
  --bind-address 0.0.0.0 \
  --https self-signed \
  --http-port 8080 \
  --https-port 443
```

También puede utilizarse un archivo de respuestas:

```bash
cp installer.example.yaml /tmp/wansim-installer.yaml
sudo ./install-v2.sh install --config /tmp/wansim-installer.yaml --non-interactive
```

El parser acepta únicamente las claves documentadas. `adminKeyFile` y `tlsPasswordFile` leen secretos desde archivos; no se recomienda ponerlos directamente en YAML ni en la línea de comandos.

Formatos TLS aceptados durante la instalación:

```bash
# PEM
sudo ./install-v2.sh install --https pem --tls-cert fullchain.pem --tls-key privkey.pem

# PFX / PKCS12
sudo WANSIM_TLS_PASSWORD='contraseña' ./install-v2.sh install --https pfx --tls-cert certificado.pfx

# DER
sudo ./install-v2.sh install --https der --tls-cert certificado.der --tls-key clave.der
```

## Modos

```bash
sudo ./install-v2.sh update       # conserva /etc/wansim y /var/lib/wansim
sudo ./install-v2.sh repair       # reinstala dependencias, archivos y servicios
sudo ./install-v2.sh doctor       # diagnóstico sin cambios
sudo ./install-v2.sh uninstall    # conserva configuración y datos
sudo ./install-v2.sh uninstall --purge
```

La desinstalación no elimina Docker porque puede pertenecer a otras aplicaciones.

Después de instalar, la administración se realiza mediante `sudo wansim`. Consulta [V2_OPERATIONS.md](V2_OPERATIONS.md) para diagnóstico, logs, actualización, respaldo, restauración y desinstalación.

## Transacción Y Rollback

Antes de modificar una instalación, el instalador registra estado de servicios, reglas `iptables`, usuario de servicio y un archivo comprimido de todos los directorios administrados. Si cualquier fase falla, detiene los componentes parciales, restaura el snapshot y devuelve el estado previo de los servicios. La evidencia queda en `/var/lib/wansim-installer/transactions`.

La actualización profesional se hace desde una etiqueta publicada y crea un respaldo adicional:

```bash
sudo wansim upgrade v2.0.13-stable
sudo wansim rollback-version
sudo wansim support-bundle
```

No se aceptan ramas ni etiquetas ajenas a las publicaciones V2 permitidas.

Las publicaciones etiquetadas también generan `.deb` y `.rpm`, `SHA256SUMS` y procedencia verificable en GitHub. Después de instalar el paquete correspondiente, ejecuta `sudo wansim-install install`; utiliza el mismo instalador transaccional.

## Aplicación Real

La instalación inicia en `dry-run`. Para habilitar cambios reales posteriormente:

```bash
sudo wansim enable-host-apply --confirm
```

En una instalación desatendida, deben coincidir `executionMode: host` y `confirmHostApply: true`. ReactUI mantiene una segunda barrera: antes de desplegar exige escribir exactamente `APLICAR <ID_CONFIGURACION>`. Para volver al modo seguro:

```bash
sudo wansim disable-host-apply
```

## Seguridad

- FastAPI se ejecuta como usuario no privilegiado dentro de su contenedor.
- El agente nativo es el único componente autorizado para cambiar red y sólo expone operaciones tipadas.
- El socket Unix pertenece a `root:wansim`, usa modo `0660` y cada solicitud lleva una firma HMAC, timestamp y nonce antirrepetición.
- La clave de operador, la llave de cifrado y el token del agente se guardan en `/etc/wansim/wansim.env` con modo `0640`.
- Los certificados se normalizan en `/etc/wansim/certs` y sus claves privadas no se imprimen.
- El firewall sólo se modifica al usar `--configure-firewall`; nunca se habilita un firewall que estuviera inactivo.

## Directorios Y Servicios

```text
/etc/wansim/                 Configuración, secretos y certificados
/opt/wansim/agent/           Agente Python nativo
/opt/wansim/control-plane/   FastAPI, ReactUI y Compose
/var/lib/wansim/             SQLite, borradores, estado y snapshots
/var/log/wansim/             Logs del agente y del plano de control
/run/wansim/agent.sock       Socket efímero del agente
```

```text
wansim-agent.service
wansim-control-plane.service
```

Para consultar la clave inicial sin exponer otros secretos:

```bash
sudo sed -n 's/^WANSIM_V2_API_KEY="\(.*\)"$/\1/p' /etc/wansim/wansim.env
```
