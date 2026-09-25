# Ryuz WAN Simulator

[![Versión estable](https://img.shields.io/badge/versi%C3%B3n-v2.0.13--stable-00b388?style=flat-square)](https://github.com/Ryuz-crypto/WAN_SIM/releases/tag/v2.0.13-stable)
[![Plataformas Linux](https://img.shields.io/badge/Linux-Ubuntu%2024.04%2F26.04%20%7C%20Debian%2012%20%7C%20Fedora%2042%20%7C%20Rocky%209-f58220?style=flat-square&logo=linux&logoColor=white)](#sistemas-soportados)
[![Licencia CC0 1.0](https://img.shields.io/badge/licencia-CC0%201.0-00739d?style=flat-square)](LICENSE)
[![WAN_SIM checks](https://github.com/Ryuz-crypto/WAN_SIM/actions/workflows/checks.yml/badge.svg?branch=main)](https://github.com/Ryuz-crypto/WAN_SIM/actions/workflows/checks.yml)
[![Matriz Linux](https://github.com/Ryuz-crypto/WAN_SIM/actions/workflows/linux-matrix.yml/badge.svg?branch=main)](https://github.com/Ryuz-crypto/WAN_SIM/actions/workflows/linux-matrix.yml)

Simulador WAN para Linux con soporte L3/NAT, Bridge L2, VLAN, puertos LAN sin etiqueta, DHCP, `tc/netem`, HTTPS, Telegram y panel web.

**Versión estable recomendada y más actual:** [`v2.0.13-stable`](https://github.com/Ryuz-crypto/WAN_SIM/tree/v2.0.13-stable)

**Versión estable anterior:** [`v1.119-stable`](https://github.com/Ryuz-crypto/WAN_SIM/tree/v1.119-stable)

**Autor:** decameru@outlook.com

| Uso | Versión | Instalador |
| --- | --- | --- |
| Instalación recomendada con FastAPI, ReactUI y rollback | `v2.0.13-stable` | `sudo ./install-v2.sh install` |
| Compatibilidad con el dashboard clásico | `v1.119-stable` | `./WANsim2.sh` |

V2 comienza en modo seguro `dry-run`. Si conservas V1, instala cada versión en un directorio o máquina diferente.

## Funciones Principales

- L3/NAT con hasta dos pares WAN/LAN.
- WAN por DHCP o configuración manual de IP, CIDR y gateway.
- LAN con VLANs etiquetadas o acceso sin etiqueta.
- Bridge L2 con hasta tres pares de interfaces.
- Inyección de latencia, jitter y pérdida con `tc/netem`.
- DHCP, NAT, detección de IP pública/privada y estimación de ancho de banda.
- HTTPS con certificados PEM, PFX/PKCS12 o DER.
- Telegram con botones operativos.
- V2 agrega FastAPI, ReactUI, SQLite, Docker Compose, rollback y CLI administrativo.

## Sistemas Soportados

La matriz de V2 cubre estas versiones; la corrección de Bridge V2.0.13 se enfoca en Ubuntu:

- Ubuntu Server o Workstation 24.04 y 26.04 LTS.
- Debian 12.
- Fedora 42.
- Rocky Linux 9.

El instalador acepta arquitecturas `x86_64` y `aarch64`; la matriz automática publicada actualmente se ejecuta en `x86_64`.

> **Importante:** V2 requiere Python 3.9 a 3.14. Ubuntu 20.04 con Python 3.8, Debian 10 y Rocky Linux 8 no forman parte de la matriz certificada. Para esos sistemas conserva V1.119 o actualiza primero el sistema operativo.

Se requiere Linux con `systemd`, acceso a Internet y un usuario con permisos `sudo`.

## Instalar V1.119 Stable Anterior

V1 se conserva para compatibilidad con el dashboard clásico. Ejecuta `WANsim2.sh` como usuario normal; el script solicitará `sudo` cuando sea necesario.

### Ubuntu Server, Ubuntu Workstation o Debian

```bash
sudo apt-get update
sudo apt-get install -y git sudo
git clone --branch v1.119-stable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git WAN_SIM-v1
cd WAN_SIM-v1
chmod +x WANsim2.sh
./WANsim2.sh
```

### Fedora

```bash
sudo dnf makecache -y
sudo dnf install -y git sudo
git clone --branch v1.119-stable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git WAN_SIM-v1
cd WAN_SIM-v1
chmod +x WANsim2.sh
./WANsim2.sh
```

### Rocky Linux o CentOS Stream

```bash
sudo dnf makecache -y
sudo dnf install -y git sudo
git clone --branch v1.119-stable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git WAN_SIM-v1
cd WAN_SIM-v1
chmod +x WANsim2.sh
./WANsim2.sh
```

Al finalizar, abre:

```text
http://<IP_DEL_SERVIDOR>:5000
```

El asistente permite elegir L3/NAT o Bridge L2, interfaces, VLAN/acceso, direccionamiento WAN, DHCP, Telegram y HTTPS.

## Instalar V2.0.13 Stable

V2 es la versión recomendada. Su instalador incorpora Docker, FastAPI, ReactUI, proxy HTTPS, agente de red, base de datos y servicios `systemd`.

### Ubuntu 24.04, Ubuntu 26.04 o Debian 12

```bash
sudo apt-get update
sudo apt-get install -y git sudo
git clone --branch v2.0.13-stable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git WAN_SIM-v2
cd WAN_SIM-v2
chmod +x install-v2.sh
sudo ./install-v2.sh install
```

### Fedora 42

```bash
sudo dnf makecache -y
sudo dnf install -y git sudo
git clone --branch v2.0.13-stable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git WAN_SIM-v2
cd WAN_SIM-v2
chmod +x install-v2.sh
sudo ./install-v2.sh install
```

### Rocky Linux 9

```bash
sudo dnf makecache -y
sudo dnf install -y git sudo
git clone --branch v2.0.13-stable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git WAN_SIM-v2
cd WAN_SIM-v2
chmod +x install-v2.sh
sudo ./install-v2.sh install
```

Comprueba que instalaste la etiqueta correcta:

```bash
git describe --tags --exact-match
# Debe mostrar: v2.0.13-stable
```

Consulta el estado y la clave inicial:

```bash
sudo wansim status
sudo wansim doctor
sudo sed -n 's/^WANSIM_V2_API_KEY="\(.*\)"$/\1/p' /etc/wansim/wansim.env
```

El instalador muestra al final la URL de ReactUI. HTTPS autofirmado está habilitado de forma predeterminada.

## Operación Básica De V2

```bash
sudo wansim status
sudo wansim restart
sudo wansim logs
sudo wansim doctor --export /tmp/wansim-doctor.txt
sudo wansim backup
sudo wansim restore /var/backups/wansim/ARCHIVO.tar.gz
sudo wansim upgrade v2.0.13-stable
sudo wansim rollback-version
sudo wansim support-bundle
```

V2 utiliza `dry-run` de forma predeterminada. Para permitir cambios reales en un servidor de laboratorio:

```bash
sudo wansim enable-host-apply --confirm
```

ReactUI exige además escribir `APLICAR <ID_CONFIGURACION>` antes de modificar la red. Para regresar al modo seguro:

```bash
sudo wansim disable-host-apply
```

Desinstalación:

```bash
sudo wansim uninstall          # Conserva configuración y datos
sudo wansim uninstall --purge  # Elimina configuración y datos
```

Docker no se elimina porque puede ser utilizado por otras aplicaciones.

## Instalación Desatendida De V2

Edita una copia de `installer.example.yaml` y ejecuta:

```bash
sudo ./install-v2.sh install --config installer.example.yaml --non-interactive
```

No guardes contraseñas directamente en YAML. Utiliza `adminKeyFile` y `tlsPasswordFile` con archivos accesibles únicamente por `root`.

## Primer Acceso V2

La clave generada durante la instalación se usa una sola vez para crear el primer administrador:

```bash
sudo sed -n 's/^WANSIM_V2_API_KEY="\(.*\)"$/\1/p' /etc/wansim/wansim.env
```

En ReactUI selecciona **Clave heredada**, entra a **Acceso**, crea un usuario `admin`, cierra sesión y vuelve a ingresar con usuario y contraseña. Después podrás crear roles `viewer`, `operator` y `admin`.

## Correcciones De V2.0.13 En Ubuntu

- Bridge L2 conserva el forwarding IPv4 global que Docker necesita para publicar ReactUI. Ping y SSH podían seguir funcionando mientras la web quedaba inaccesible.
- Las solicitudes de despliegue y estado dejan de esperar indefinidamente. Si se pierde la respuesta, revisa `sudo wansim doctor` y el historial antes de volver a enviar la configuración.
- Para actualizar una instalación V2 existente en Ubuntu: `sudo wansim backup` y después `sudo wansim upgrade v2.0.13-stable`. Conserva acceso por consola durante el primer despliegue Bridge.

V2.0.12-rev1 incorporó:

- Corrige el rechazo `422 String should have at least 1 character` que impedía finalizar el asistente cuando la topología no activa conservaba interfaces sin seleccionar.
- El asistente ReactUI ahora envía únicamente la sección de la topología elegida (L3 o Bridge) y exige interfaces seleccionadas antes de revisar.
- Los errores de validación del API se muestran traducidos y accionables en ReactUI.

V2.0.11 incorporó:

- Agente nativo compatible con Python 3.14 en Ubuntu 26.04.
- Pydantic Core y Cryptography se instalan desde wheels, sin compilar Rust o C.
- Dependencias del agente separadas de las del backend Docker.
- Entorno virtual preparado de forma atómica y arranque portable con `python -m uvicorn`.
- Validación previa de Python y matriz automática adicional para Ubuntu 26.04.

V2.0.10 incorporó:

- Asistente ReactUI de cuatro pasos con detección y recomendación de interfaces.
- Preflight con errores, advertencias y recomendaciones antes de desplegar.
- Comparación entendible entre la topología activa y la propuesta.
- Protección de la interfaz administrativa mediante doble confirmación.
- Watchdog que revierte el cambio si ReactUI no confirma conectividad a tiempo.
- Centro de recuperación con snapshots versionados, checksum y restauración desde ReactUI.
- Doctor visual, exportación de soporte y reinicios controlados.
- Usuarios, sesiones, roles y auditoría por operador.
- Paquetes `.deb`/`.rpm`, checksums, procedencia y nuevos comandos de mantenimiento.
- Pruebas de Bridge, `netem`, recuperación, disco crítico e interrupción de SQLite.

La suite general, la matriz Linux y la aceptación integral Vagrant aprobaron para esta versión:

- [WAN_SIM checks](https://github.com/Ryuz-crypto/WAN_SIM/actions/workflows/checks.yml)
- [Ubuntu, Debian, Fedora y Rocky](https://github.com/Ryuz-crypto/WAN_SIM/actions/workflows/linux-matrix.yml)
- [Instalador integral con Vagrant](https://github.com/Ryuz-crypto/WAN_SIM/actions/workflows/vagrant-matrix.yml)

La aceptación Vagrant ejecuta instalación, fallo inducido y rollback, reparación, TLS, control de acceso, secretos Telegram cifrados, red, backup/restore, reinstalación y purga sobre las cuatro distribuciones.

## Documentación

- [Instalador V2](docs/V2_INSTALLER.md)
- [Operación V2](docs/V2_OPERATIONS.md)
- [Migración de V1.119 a V2](docs/MIGRATION_V1_TO_V2.md)
- [Matriz de integración](v2/integration/README.md)
- [Criterios para V2 estable](docs/V2_STABILITY.md)

## Seguridad

WAN_SIM modifica interfaces, rutas, DHCP, NAT, firewall y `tc/netem`. Utilízalo en un host dedicado y conserva acceso por consola durante las primeras pruebas. V2 debe permanecer en `dry-run` hasta revisar y aprobar el plan mostrado por ReactUI.

## Licencia

Proyecto distribuido bajo los términos definidos en [LICENSE](LICENSE).
