# Ryuz WAN Simulator

**Version 1.109** | **Autor**: decameru@outlook.com

Ryuz WAN Simulator es una herramienta para simular condiciones WAN en Linux. Permite aplicar latencia, jitter y perdida de paquetes sobre interfaces fisicas, VLANs o bridges L2, con un dashboard Flask para control operativo.

Esta rama se mantiene como la base principal del simulador. La evolucion FastAPI + React + Docker Compose queda reservada para una segunda base futura, despues de estabilizar esta version.

## Funcionalidades

- Modo L3/NAT con multiples VLANs sobre una interfaz LAN.
- Modo Bridge L2 con 1 a 3 pares de interfaces entrada/salida.
- Control de latencia, jitter y perdida por interfaz usando `tc/netem`.
- Dashboard web Flask en el puerto `5000`.
- DHCP automatico para VLANs.
- Persistencia L2 mediante `wansim-l2-persist.service`.
- Integracion opcional con Telegram.
- Configuracion persistente en el home del usuario que ejecuta el script.

## Sistemas Soportados

La version 1.109 detecta el gestor de paquetes y ajusta dependencias para:

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

- `L3 / NAT`: VLANs + DHCP + NAT hacia una interfaz WAN.
- `Bridge L2`: bridges entre pares de interfaces fisicas.
- Integracion opcional con Telegram.

Al finalizar, el dashboard queda disponible en:

```text
http://<IP_DEL_SERVIDOR>:5000
```

## Archivos Generados

Los archivos operativos se crean en el home del usuario que ejecuta el script:

| Archivo | Descripcion |
| --- | --- |
| `~/emix_abundix.conf` | Configuracion principal |
| `~/wansim_dashboard.py` | Dashboard Flask generado |
| `~/api_tokens.json` | Tokens locales de API |
| `~/emix_abundix.log` | Log principal |
| `~/wansim_netem_state.json` | Estado tc/netem |

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

## Release Notes

### Version 1.109

- Se preaprueba la instalacion de `iptables-persistent` en Ubuntu/Debian para evitar la pantalla interactiva YES/NO.
- Se ejecuta `apt-get` con `DEBIAN_FRONTEND=noninteractive`.
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
