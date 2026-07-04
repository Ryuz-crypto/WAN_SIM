# Ryuz WAN Simulator

**Version 1.115** | **Autor**: decameru@outlook.com

Ryuz WAN Simulator es una herramienta para simular condiciones WAN en Linux. Permite aplicar latencia, jitter y perdida de paquetes sobre interfaces fisicas, VLANs o bridges L2, con un dashboard Flask para control operativo.

Esta rama se mantiene como la base principal del simulador. La evolucion FastAPI + React + Docker Compose queda reservada para una segunda base futura, despues de estabilizar esta version.

## Funcionalidades

- Modo L3/NAT con hasta dos pares WAN/LAN y multiples VLANs por LAN.
- Deteccion por WAN de IP privada, IP publica y estimacion de ancho de banda disponible.
- Modo Bridge L2 con 1 a 3 pares de interfaces entrada/salida.
- Control de latencia, jitter y perdida por interfaz usando `tc/netem`.
- Dashboard web Flask en el puerto `5000`, con administracion HTTPS desde la interfaz web.
- Seccion `Pre-beta ReactUI` para preparar la evolucion grafica de configuracion L3/L2, Telegram multi-bot, daemons y leases DHCP.
- DHCP automatico para VLANs.
- Persistencia L2 mediante `wansim-l2-persist.service`.
- Integracion opcional con Telegram, botones de presets y fallback HTTP API si falla la libreria legacy.
- Configuracion persistente en el home del usuario que ejecuta el script.

## Sistemas Soportados

La version 1.115 detecta el gestor de paquetes y ajusta dependencias para:

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

## Instalacion Rapida

### Ubuntu Server / Ubuntu Workstation / Debian

```bash
sudo apt-get update
sudo apt-get install -y git sudo
git clone https://github.com/Ryuz-crypto/WAN_SIM.git
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
git clone https://github.com/Ryuz-crypto/WAN_SIM.git
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
git clone https://github.com/Ryuz-crypto/WAN_SIM.git
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

- `L3 / NAT`: uno o dos pares WAN/LAN, cada LAN con VLANs + DHCP + NAT hacia su WAN.
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

## Pre-beta ReactUI

La version estable sigue siendo el dashboard principal. Para revisar la evolucion, abre el dashboard y usa el boton `Pre-beta ReactUI`.

En esa vista puedes:

- Preparar cambios de topologia L3/NAT o Bridge L2L sin romper la configuracion estable.
- Guardar un draft persistente en `~/.wansim/reactui_prebeta.json`.
- Ver interfaces detectadas con IP, estado y MAC.
- Ver daemons relevantes y enviar restart controlado.
- Ver leases DHCP con IP, host, MAC y estado.
- Preparar multiples bots de Telegram y validar sincronizacion contra Telegram API.
- Revisar un diagrama conceptual de los cambios propuestos para L2 o L3.

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
| `~/.wansim/reactui_prebeta.json` | Draft guardado desde `Pre-beta ReactUI` |

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
