# Ryuz WAN Simulator

**Instalación recomendada: [`v1.119-stable`](https://github.com/Ryuz-crypto/WAN_SIM/tree/v1.119-stable)** | **Desarrollo actual: `2.0.4-prebeta`** | **Autor**: decameru@outlook.com

Ryuz WAN Simulator es una herramienta para simular condiciones WAN en Linux. Permite aplicar latencia, jitter y perdida de paquetes sobre interfaces fisicas, VLANs o bridges L2, con un dashboard Flask para control operativo.

La última versión estable es [`v1.119-stable`](https://github.com/Ryuz-crypto/WAN_SIM/tree/v1.119-stable). Es la versión que debe instalarse en laboratorios y entornos operativos. La rama `main` contiene WAN_SIM 2.0 en estado pre-beta y no sustituye la instalación estable.

| Necesidad | Qué usar | Estado |
| --- | --- | --- |
| Simular WAN en un laboratorio | [`v1.119-stable`](https://github.com/Ryuz-crypto/WAN_SIM/tree/v1.119-stable) con `./WANsim2.sh` | Estable |
| Evaluar FastAPI y ReactUI | Rama `main`, directorios `v2/backend` y `v2/frontend` | Pre-beta, `dry-run` por defecto |

## Funcionalidades

- Modo L3/NAT con hasta dos pares WAN/LAN: cada LAN puede usar VLANs etiquetadas o acceso sin etiqueta.
- Cada WAN L3 puede configurarse por DHCP o manualmente con IP, mascara/CIDR y gateway.
- Deteccion por WAN de IP privada, IP publica y estimacion de ancho de banda disponible.
- Modo Bridge L2 con 1 a 3 pares de interfaces entrada/salida.
- Control de latencia, jitter y perdida por interfaz usando `tc/netem`.
- Dashboard web Flask en el puerto `5000`, con administracion HTTPS desde la interfaz web.
- Seccion `ReactUI pre-beta` para preparar la evolucion grafica de configuracion L3/L2, Telegram multi-bot, daemons y leases DHCP.
- API FastAPI 2.0 con configuraciones versionadas, plan de despliegue, snapshots y rollback transaccional en modo seguro `dry-run`.
- DHCP automatico para VLANs y puertos LAN de acceso sin etiqueta.
- Persistencia L2 mediante `wansim-l2-persist.service`.
- Integracion opcional con Telegram, botones de presets y fallback HTTP API si falla la libreria legacy.
- Configuracion persistente en el home del usuario que ejecuta el script.

## Sistemas Soportados

La instalación estable detecta el gestor de paquetes y ajusta dependencias para:

- Ubuntu Server 20.04 o superior.
- Ubuntu Workstation 20.04 o superior.
- Debian 10 o superior.
- Fedora Server/Workstation.
- CentOS Stream.
- Rocky Linux.

Notas por familia:

- Ubuntu/Debian usan `apt-get`, `isc-dhcp-server` e `/etc/iptables/rules.v4`.
- Fedora/CentOS/Rocky usan `dnf` o `yum`, `dhcp-server`/`dhcpd` e `/etc/sysconfig/iptables`.
- En todos los casos se requiere `systemd`, `iproute`, `tc`, `iptables`, `python3` y permisos `sudo`.
- Las dependencias Python se instalan en `~/.wansim/venv`; no se modifica el Python del sistema.

## Instalación Estable

Para un laboratorio operativo, instala siempre la última etiqueta estable. No uses `main` para instalar el simulador mientras WAN_SIM 2.0 permanezca en pre-beta:

```bash
git clone --branch v1.119-stable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git
cd WAN_SIM
chmod +x WANsim2.sh
./WANsim2.sh
```

Si ya tienes el repositorio, actualiza las etiquetas y cambia a la versión estable antes de ejecutar el instalador:

```bash
git fetch --tags
git switch --detach v1.119-stable
./WANsim2.sh
```

La etiqueta es inmutable y apunta al commit validado con L3/NAT multi-WAN, DHCP o WAN manual, LAN VLAN o acceso sin etiqueta, Bridge L2, HTTPS, Telegram y el dashboard principal. Para probar el desarrollo 2.0 sólo en un entorno dedicado: `git switch main && git pull --ff-only`.

## Instalación V2 Pre-Beta

WAN_SIM 2.0 es una plataforma separada de la instalación estable: incluye FastAPI como plano de control y ReactUI como consola de operación. Está disponible solamente en `main`, inicia en `dry-run` y debe instalarse en una VM o host de laboratorio dedicado.

No reemplaza `v1.119-stable`, no instala ni modifica la configuración creada por V1. Compose está disponible para el plano de control en `dry-run`; el agente que cambia la red sigue siendo nativo del host Linux y no se considera producción durante la pre-beta.

### 1. Obtener La Rama De Desarrollo

```bash
git clone --branch main https://github.com/Ryuz-crypto/WAN_SIM.git WAN_SIM-v2
cd WAN_SIM-v2
```

### 2. Iniciar La API FastAPI

En Ubuntu/Debian, instala los prerrequisitos si aún no están disponibles:

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip nodejs npm iproute2 iptables isc-dhcp-client isc-dhcp-server
```

En Fedora, CentOS Stream o Rocky Linux:

```bash
sudo dnf install -y python3 python3-pip nodejs npm iproute iptables dhcp-client dhcp-server
```

Después inicia el backend. Mantén esta terminal abierta:

```bash
cd v2/backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
export WANSIM_V2_API_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
printf '%s\n' "$WANSIM_V2_API_KEY" > ~/.wansim-v2-operator.key
chmod 600 ~/.wansim-v2-operator.key
uvicorn wansim_v2.api:app --host 0.0.0.0 --port 8080
```

Comprueba que responde en `http://<IP_DEL_SERVIDOR>:8080/health` y consulta el contrato en `http://<IP_DEL_SERVIDOR>:8080/docs`. ReactUI solicita la clave guardada en `~/.wansim-v2-operator.key`; se conserva solamente durante la pestaña actual del navegador.

### 3. Iniciar ReactUI

En otra terminal, desde la raíz del mismo clon:

```bash
cd v2/frontend
npm install
npm run dev -- --host 0.0.0.0
```

Abre `http://<IP_DEL_SERVIDOR>:5173`. La consola se comunica con FastAPI en el puerto `8080` mediante el proxy de Vite. Para validar su compilación sin abrir el servidor: `npm run build`.

Por seguridad, V2 simula los despliegues hasta que se habiliten explícitamente ambas variables en el host dedicado:

```bash
export WANSIM_V2_EXECUTION_MODE=host
export WANSIM_V2_ALLOW_HOST_APPLY=1
```

No actives ese modo en un servidor compartido: permite ejecutar cambios de red planificados por el agente V2.

### 4. Ejecutar V2 Con Docker Compose

Para empaquetar ReactUI, FastAPI, SQLite y el proxy Nginx sin conceder privilegios de red al contenedor:

```bash
cd v2/deploy
cp .env.example .env
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
# Copia el valor generado en WANSIM_V2_SECRET_KEY dentro de .env
# Genera WANSIM_V2_API_KEY con: python3 -c "import secrets; print(secrets.token_urlsafe(32))"
docker compose up --build -d
```

El proxy queda en `http://<IP_DEL_SERVIDOR>:8080`. Consulta [v2/deploy/README.md](v2/deploy/README.md) para habilitar HTTPS con `docker-compose.https.yml`. Compose queda en `dry-run`; las operaciones de red se validan desde el host Linux y nunca desde un contenedor privilegiado.

### Ubuntu Server / Ubuntu Workstation / Debian

```bash
sudo apt-get update
sudo apt-get install -y git sudo
git clone --branch v1.119-stable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git
cd WAN_SIM
chmod +x WANsim2.sh
sudo modprobe 8021q
echo "8021q" | sudo tee -a /etc/modules
./WANsim2.sh
```

### Fedora

```bash
sudo dnf makecache -y
sudo dnf install -y git sudo
git clone --branch v1.119-stable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git
cd WAN_SIM
chmod +x WANsim2.sh
sudo modprobe 8021q
echo "8021q" | sudo tee /etc/modules-load.d/8021q.conf
./WANsim2.sh
```

### CentOS Stream / Rocky Linux

```bash
sudo dnf makecache -y || sudo yum makecache -y
sudo dnf install -y git sudo || sudo yum install -y git sudo
git clone --branch v1.119-stable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git
cd WAN_SIM
chmod +x WANsim2.sh
sudo modprobe 8021q
echo "8021q" | sudo tee /etc/modules-load.d/8021q.conf
./WANsim2.sh
```

El script instala el resto de dependencias segun el sistema detectado.

## Uso

Ejecuta siempre como usuario normal con permisos sudo:

```bash
./WANsim2.sh
```

No lo ejecutes directamente como `root`. El script usa `sudo` para las operaciones que requieren privilegios.

Durante el asistente interactivo podras elegir:

- `L3 / NAT`: uno o dos pares WAN/LAN, con DHCP y NAT hacia su WAN.
- Modo LAN por par: `vlan` para multiples redes etiquetadas o `access` para una subred /24 sin etiqueta sobre el puerto fisico. Puedes combinar ambos modos entre pares.
- Direccionamiento WAN por par: DHCP o manual con IP, mascara/CIDR y gateway.
- `Bridge L2`: bridges entre pares de interfaces fisicas.
- Integracion opcional con Telegram.
- HTTPS opcional desde el dashboard usando PEM, PEM bundle, PFX/PKCS12 o DER.

Al finalizar, el dashboard queda disponible en:

```text
http://<IP_DEL_SERVIDOR>:5000
```

Desde el boton `HTTPS` del dashboard puedes cargar un certificado PEM, PEM bundle, PFX/PKCS12 o DER. Al activarlo, el servicio se reinicia y queda publicado con:

```text
https://<IP_DEL_SERVIDOR>:5000
```

## Desarrollo ReactUI 2.0 Pre-Beta

Esta sección no forma parte de la instalación estable. Usa una copia de laboratorio en la rama `main`; la consola ReactUI actual se ejecuta por separado desde `v2/frontend` y consume la API FastAPI en `v2/backend`.

La pre-beta permite preparar L3/NAT o Bridge L2, validar las restricciones, revisar un plan de despliegue, consultar interfaces, tráfico, leases DHCP y daemons, y probar perfiles `tc/netem`. El modo predeterminado es `dry-run`: no cambia interfaces ni servicios del host.

### LAN L3 Sin Etiqueta

En el asistente, selecciona `access` en la pregunta `modo LAN` del par deseado. Solo debes indicar el tercer octeto de su subred; no se pide cantidad ni ID de VLAN.

En la configuración L3, selecciona `Acceso sin etiqueta (sin VLAN)` en `Modo del puerto LAN` de cualquier par WAN/LAN. Los campos de cantidad e ID VLAN se ocultan. Define la subred, revisa el plan de despliegue y aplica el cambio únicamente en un host de laboratorio.

Ejemplo: WAN `ens160`, LAN `ens192`, segmento `10.254` y octeto `10` asignan `10.254.10.1/24` directamente a `ens192`. DHCP entrega `10.254.10.100-200` con gateway `10.254.10.1`; los clientes usan trafico sin etiqueta. En el segundo par puedes usar otra LAN en acceso o mantener sus VLANs, siempre con subredes diferentes.

El dashboard principal y la inyeccion en vivo muestran `Acceso sin etiqueta (ens192 -> ens160)` y controlan `ens192`. No se crea una VLAN 0. El modo y la cantidad de redes se guardan por par; las configuraciones anteriores siguen usando VLANs por defecto. Al cambiar de acceso a VLAN o Bridge se retira la IP de acceso administrada por WAN_SIM.

Para actualizar una instalación estable existente, conserva la rama estable:

```bash
git fetch --tags
git switch --detach v1.119-stable
./WANsim2.sh
```

El script regenera el dashboard; recarga el navegador después. ReactUI 2.0 continúa en pre-beta; la referencia de instalación es `v1.119-stable`.

## API 2.0: Configuracion Y Despliegue

La base de 2.0 está disponible en `v2/backend`. Su API FastAPI implementa los primeros cuatro pilares: módulos reutilizables, configuración persistente en SQLite, validación/planificación y transacciones con snapshot, verificación y rollback. La interfaz React + TypeScript que consume esa API vive en `v2/frontend`.

Por defecto funciona en `dry-run`: permite probar toda la secuencia sin cambiar ninguna interfaz del host.

```bash
cd v2/backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
uvicorn wansim_v2.api:app --host 0.0.0.0 --port 8080
```

Abre `http://<IP_DEL_SERVIDOR>:8080/docs`. El ciclo operativo es crear un borrador, consultar su plan y solicitar un despliegue. La API registra el plan, el snapshot del host, resultado, configuración activa y rollback en `~/.wansim-v2/state.db`.

La aplicación real requiere dos variables explícitas y un host dedicado: `WANSIM_V2_EXECUTION_MODE=host` y `WANSIM_V2_ALLOW_HOST_APPLY=1`. Mientras no estén las dos presentes, el agente no ejecuta comandos de red.

### ReactUI 2.0 Separada

Con la API anterior en ejecución, abre otra terminal para iniciar la consola ReactUI:

```bash
cd v2/frontend
npm install
npm run dev -- --host 0.0.0.0
```

Abre `http://<IP_DEL_SERVIDOR>:5173`. Vite redirige `/api` al backend en el puerto `8080`. La interfaz permite configurar y validar topologías L3/NAT o Bridge L2, revisar el plan antes de desplegar, aplicar o reiniciar `tc/netem`, consultar interfaces y tráfico, leases DHCP, estado/reinicio de daemons y el historial con rollback.

Para generar los archivos estáticos de la interfaz: `npm run build`. Sigue siendo una pre-beta: en modo predeterminado los despliegues se simulan mediante `dry-run` y no modifican la red del host.

### Telegram Desde FastAPI

V2 administra varios bots desde `/api/v2/telegram/bots`. Toda la API operativa exige `X-WAN-SIM-API-Key`. Cada token queda cifrado en el estado local, sólo se muestra una pista enmascarada y cada bot limita chats autorizados y permiso `read`, `operate` o `admin`. El webhook usa su secreto independiente, devuelto una única vez al crear el bot, en el header `X-Telegram-Bot-Api-Secret-Token`.

En la pestaña **Telegram** de ReactUI indica la URL pública HTTPS del proxy, crea el bot y pulsa **Sincronizar**. El sistema registra `https://<HOST>/api/v2/telegram/bots/<ID>/webhook` con Telegram. **Probar** envía un mensaje al primer chat autorizado. Los botones de Telegram usan la misma capa de operaciones que ReactUI: estado, presets `netem` y, para administradores, reinicios permitidos. No publiques el webhook sin HTTPS.

## Migración Y Estabilidad V2

- [Migración desde V1.119](docs/MIGRATION_V1_TO_V2.md)
- [Criterios para declarar V2 estable](docs/V2_STABILITY.md)
- [Matriz de VMs Ubuntu/Debian/Fedora/Rocky](v2/integration/README.md)

## Archivos Generados

Los archivos operativos se crean en el home del usuario que ejecuta el script:

| Archivo | Descripcion |
| --- | --- |
| `~/emix_abundix.conf` | Configuracion principal |
| `~/wansim_dashboard.py` | Dashboard Flask generado |
| `~/api_tokens.json` | Tokens locales de API |
| `~/emix_abundix.log` | Log principal |
| `~/wansim_netem_state.json` | Estado tc/netem |
| `~/.wansim/venv` | Entorno Python aislado del dashboard |
| `~/.wansim/tls/` | Certificado y llave normalizados para HTTPS |
| `~/.wansim/reactui_prebeta.json` | Draft guardado desde `ReactUI pre-beta` |

Archivos del sistema:

| Archivo | Ubuntu/Debian | Fedora/CentOS/Rocky |
| --- | --- | --- |
| DHCP config | `/etc/dhcp/dhcpd.conf` | `/etc/dhcp/dhcpd.conf` |
| DHCP service | `isc-dhcp-server` | `dhcpd` |
| DHCP defaults | `/etc/default/isc-dhcp-server` | `/etc/sysconfig/dhcpd` |
| iptables persistente | `/etc/iptables/rules.v4` | `/etc/sysconfig/iptables` |
| Dashboard service | `/etc/systemd/system/wansim.service` | `/etc/systemd/system/wansim.service` |
| L2 persist service | `/etc/systemd/system/wansim-l2-persist.service` | `/etc/systemd/system/wansim-l2-persist.service` |

## Validacion

En Linux o WSL/Git Bash:

```bash
bash -n WANsim2.sh
```

En un host de laboratorio:

```bash
sudo systemctl status wansim.service
sudo journalctl -u wansim.service -n 80 --no-pager
```

## Seguridad Operativa

Esta herramienta modifica interfaces, qdisc, DHCP, NAT y servicios systemd. Usala en laboratorio o en un host dedicado para simulacion WAN.

Antes de ejecutar en un servidor compartido, revisa:

- Interfaces fisicas seleccionadas.
- Reglas existentes de firewall/NAT.
- Servicios DHCP activos.
- Politicas de SELinux/firewalld en Fedora, CentOS o Rocky.

Si una ejecucion falla, el script ejecuta rollback automatico de servicios, dashboard generado, virtualenv parcial, bridges/VLANs generadas y archivos temporales. El log principal se conserva en `~/emix_abundix.log`.

## Release Notes

### Version 2.0.4-prebeta

- Protege todos los endpoints operativos con una clave de API y agrega inicio/cierre de sesión en ReactUI.
- El motor transaccional registra únicamente acciones aplicadas, restaura IP, rutas, forwarding, iptables y DHCP, y reconstruye la configuración activa anterior.
- NAT crea y enlaza su cadena administrada de forma idempotente; las colisiones de VLAN/Bridge se rechazan o migran de forma controlada.
- DHCP deja de ser una acción simulada: genera, valida y activa la configuración ISC, y la verificación comprueba interfaces, direcciones, gateways, NAT, DHCP y miembros Bridge.
- Telegram propaga fallos reales de entrega y ofrece presets de latencia, jitter, pérdida y reset.

### Version 2.0.3-prebeta

- Telegram se convierte en cliente de FastAPI con múltiples bots, tokens cifrados, chats autorizados, roles y webhook con secreto.
- Los botones de Telegram reutilizan la capa operacional de ReactUI para estado, `netem` y reinicios permitidos.
- Se agrega Docker Compose para ReactUI, API, SQLite y proxy Nginx, con override HTTPS y modo `dry-run` forzado.
- Se incorpora matriz Vagrant para Ubuntu, Debian, Fedora y Rocky, con pruebas aisladas de dos WAN, VLAN, acceso y rollback.
- Se documentan la migración desde V1.119 y los criterios explícitos para una futura etiqueta `v2.0.0-stable`.

### Version 2.0.2-prebeta

- Se completa el ciclo transaccional de la API: preflight, snapshot real de red, aplicar, verificar, rollback de acciones y restauración de la configuración activa anterior.
- Se incorpora `v2/frontend`, una ReactUI Vite + TypeScript con configurador L3/NAT y Bridge, validación, plan, despliegue y auditoría de cambios.
- El panel operativo ReactUI muestra interfaces con IP/MAC/tráfico, leases DHCP, daemons, inyección `tc/netem` y reinicio controlado de servicios permitidos.
- Se agrega la compilación de ReactUI a GitHub Actions y las pruebas de API cubren el rollback a la configuración activa anterior y endpoints operativos en `dry-run`.

### Version 2.0.1-prebeta

- Se implementan los pilares 1 a 4 de WAN_SIM 2.0: modularización inicial, estado versionado, FastAPI y transacciones de red seguras.
- El backend dispone de endpoints para crear borradores, consultar configuración activa, generar planes, desplegar y hacer rollback.
- Se agregan pruebas de contrato FastAPI y de rollback forzado, además de las regresiones de V1.

### Version 2.0.0-prebeta

- La rama `main` inicia WAN_SIM 2.0 y ReactUI 2.0 en estado pre-beta.
- `v1.119-stable` queda marcada como la última versión estable, con guía de instalación y retorno a la rama de desarrollo.
- La etiqueta estable conserva L3/NAT, Bridge L2, HTTPS, Telegram, DHCP y LAN en VLAN o acceso sin etiqueta.
- Se inicia la modularización: `WANsim2.sh` utiliza primitivas compartidas de plataforma, logging y red dentro de `lib/`.
- Se agrega FastAPI 2.0 con almacenamiento SQLite para borradores, configuración activa, snapshots y despliegues.
- El motor transaccional implementa validar, planificar, snapshot, aplicar, verificar y rollback; por defecto todo opera en `dry-run`.

### Version 1.119-stable

- LAN L3 configurable por par como trunk con VLANs o acceso sin etiqueta, desde el asistente y ReactUI.
- En acceso, IP, DHCP, NAT y `tc/netem` usan directamente la interfaz fisica, con una sola subred /24.
- Resumen y diagrama distinguen los modos; la validacion evita interfaces y subredes repetidas en pares mixtos.
- Persistencia de modo LAN y cantidad de redes por par, compatible con configuraciones previas.
- Pruebas automatizadas de configuracion, comandos runtime simulados y transiciones VLAN/acceso. El trafico real y DHCP requieren comprobacion en una VM Linux.

### Version 1.118-prebeta

- `Enviar parametros` en ReactUI aplica la topologia validada en tiempo real, actualiza interfaces controladas y refresca metadata sin reiniciar Flask.
- L3/NAT runtime crea VLANs, actualiza DHCP, configura NAT en cadena `WANSIM_POSTROUTING` y persiste la configuracion local.
- Bridge runtime crea pares `br_wan#`, actualiza interfaces controladas y limpia objetos WAN_SIM previos.
- Se agrega panel `Inyeccion en vivo` para aplicar o resetear delay, jitter y perdida desde ReactUI usando `tc/netem`.
- Los resultados de submit devuelven acciones ejecutadas, comandos y salida corta para pruebas de laboratorio.

### Version 1.117-stable

- Corrige el resumen L3/NAT cuando una WAN usa DHCP/manual para que el segmento LAN no se mezcle con modo WAN, CIDR o gateway.
- ReactUI pre-beta reorganiza los campos L3 con etiquetas, ejemplos y contexto para WAN, LAN trunk, direccionamiento, VLAN ID y octetos.
- ReactUI agrega `Enviar parametros`, que valida y guarda el draft pre-beta en backend sin aplicar cambios destructivos.
- Las credenciales Telegram se entregan ocultas por API y solo se revelan tras validar la password Linux; la validacion usa el secreto guardado aunque la pantalla muestre `__hidden__`.

### Version 1.116-stable

- Se marca la rama actual como estable para la base V1.
- En modo L3/NAT, cada WAN puede configurarse por DHCP o manualmente con IP, mascara/CIDR y gateway.
- El despliegue aplica direccionamiento WAN antes de medir IP publica/BW y antes de configurar NAT.
- ReactUI pasa a etapa 2 pre-beta con validacion server-side y boton `Plan de despliegue`; aun no aplica cambios destructivos hasta estabilizarse.
- El README documenta como revisar la version estable y la etapa ReactUI pre-beta.

### Version 1.115

- Se agrega `MAC LAN` al detalle desplegable de cada enlace L3.
- Se actualiza el branding visual del dashboard a una paleta viva profesional inspirada en HPE: verde principal, fondo claro y acentos cian/purpura.
- Se agrega boton `Pre-beta ReactUI` con una consola React embebida para preparar cambios futuros de topologia L3/NAT y Bridge L2L.
- La pre-beta permite guardar drafts, preparar Telegram multi-bot, validar sincronizacion, ver/reiniciar daemons y revisar leases DHCP.
- La version estable V1 sigue intacta y puede convivir con el draft de la pre-beta.

### Version 1.114

- La carga y activacion de HTTPS pasa del asistente de consola a la interfaz web del dashboard.
- El flujo L3/NAT ya no repregunta el octeto base global; cada par WAN/LAN define su rango y valida que no se repita.
- El resumen final de instalacion muestra todos los pares WAN/LAN configurados, no solo el primero.
- Los titulos de enlaces L3 ahora usan `VLAN <id> (LAN -> WAN)` sin el prefijo `L3#`.
- La informacion tecnica de cada enlace en el dashboard queda plegada en `Detalles del enlace`.

### Version 1.113

- Se agrega soporte L3/NAT para hasta dos pares WAN/LAN, con validacion para evitar interfaces, VLAN IDs y octetos repetidos.
- El dashboard muestra con mayor claridad que WAN/LAN/subred controla cada tarjeta de inyeccion.
- Cada WAN reporta IP privada, IP publica detectada y una estimacion de BW mediante descarga controlada en segundo plano.
- Se agrega HTTPS opcional para Flask usando certificados PEM separados, PEM bundle, PFX/PKCS12 o DER; el script convierte y valida el par antes de iniciar el servicio.
- Telegram ahora intenta varias rutinas de instalacion y, si `python-telegram-bot` no importa, opera mediante fallback HTTP API con botones de presets, reset y modo manual.

### Version 1.112

- Se asegura la dependencia `python-telegram-bot==13.15` tambien cuando se reutiliza una configuracion previa con Telegram habilitado.
- La instalacion opcional de Telegram ahora es idempotente y valida el import `telegram` despues de instalar.
- Si Telegram no puede instalarse o importarse en el Python disponible, desde 1.113 el dashboard usa el fallback HTTP API.

### Version 1.111

- Se reemplaza `pip3 install --user` por un virtualenv aislado en `~/.wansim/venv` para evitar PEP 668 (`externally-managed-environment`).
- El servicio systemd ejecuta el dashboard con el Python del virtualenv.
- Telegram se instala solo si el usuario habilita la integracion.
- Se agrega rollback automatico en errores para limpiar recursos generados y evitar redeploys de VM durante pruebas.

### Version 1.110

- Se elimina el uso de `sudo DEBIAN_FRONTEND=noninteractive`, porque algunos sudoers bloquean variables de entorno.
- Se mantiene la preaprobacion por `debconf-set-selections` para evitar el dialogo YES/NO de `iptables-persistent`.
- Se agrega `debconf-set-selections` a los comandos permitidos por sudoers.

### Version 1.109

- Se preaprueba la instalacion de `iptables-persistent` en Ubuntu/Debian para evitar la pantalla interactiva YES/NO.
- Se intento ejecutar `apt-get` con `DEBIAN_FRONTEND=noninteractive`; esto fue reemplazado en 1.110 por compatibilidad con sudoers restrictivos.
- Se conservan configuraciones existentes de paquetes con opciones `--force-confdef` y `--force-confold`.

### Version 1.108

- Se elimina la base secundaria `DashboardAPI-EC` de esta rama principal.
- Se centraliza la version en el archivo `VERSION`.
- Se reemplazan rutas fijas `/home/axis` por rutas basadas en `$HOME`.
- Se agrega deteccion de `apt-get`, `dnf` y `yum`.
- Se agregan dependencias equivalentes para Ubuntu/Debian, Fedora, CentOS y Rocky Linux.
- Se ajustan nombres de servicio DHCP por familia de sistema.
- Se evita que el dashboard en modo NAT dependa del servicio L2.
- Se actualiza README con instrucciones por sistema operativo.

### Version 1.107

- Soporte para multiples bridges L2.
- Persistencia de bridges L2 con systemd.
- Dashboard Flask con informacion de bridge, rol y peer.
- Version fija de `python-telegram-bot==13.15`.
- Mejoras de limpieza en VLANs, tc/netem e iptables.

### Version 1.100

- Version inicial con NAT, Bridge, Flask dashboard, Telegram, VLANs y DHCP.

## Licencia

Este proyecto se distribuye bajo licencia MIT. Consulta `LICENSE`.
