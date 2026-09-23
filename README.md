# Ryuz WAN Simulator

Simulador WAN para Linux con soporte L3/NAT, Bridge L2, VLAN, puertos LAN sin etiqueta, DHCP, `tc/netem`, HTTPS, Telegram y panel web.

**Versión estable recomendada:** [`v1.119-stable`](https://github.com/Ryuz-crypto/WAN_SIM/tree/v1.119-stable)

**Versión más actual:** [`v2.0.8-prestable`](https://github.com/Ryuz-crypto/WAN_SIM/tree/v2.0.8-prestable)

**Autor:** decameru@outlook.com

| Uso | Versión | Instalador |
| --- | --- | --- |
| Producción, centros de datos y laboratorios operativos | `v1.119-stable` | `./WANsim2.sh` |
| Evaluación de FastAPI, ReactUI y administración centralizada | `v2.0.8-prestable` | `sudo ./install-v2.sh install` |

V1 y V2 deben probarse en directorios o máquinas diferentes. V2 sigue siendo pre-estable y comienza en modo seguro `dry-run`.

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

- Ubuntu Server y Workstation 20.04 o superior.
- Debian 10 o superior.
- Fedora Server y Workstation.
- Rocky Linux 8/9 y CentOS Stream.
- Arquitecturas `x86_64` y `aarch64` para V2.

Se requiere Linux con `systemd`, acceso a Internet y un usuario con permisos `sudo`.

## Instalar V1.119 Stable

V1 es la versión recomendada para operación. Ejecuta `WANsim2.sh` como usuario normal; el script solicitará `sudo` cuando sea necesario.

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

## Instalar V2.0.8 Pre-Stable

V2 es para laboratorio. Su instalador incorpora Docker, FastAPI, ReactUI, proxy HTTPS, agente de red, base de datos y servicios `systemd`.

### Ubuntu Server, Ubuntu Workstation o Debian

```bash
sudo apt-get update
sudo apt-get install -y git sudo
git clone --branch v2.0.8-prestable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git WAN_SIM-v2
cd WAN_SIM-v2
chmod +x install-v2.sh
sudo ./install-v2.sh install
```

### Fedora

```bash
sudo dnf makecache -y
sudo dnf install -y git sudo
git clone --branch v2.0.8-prestable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git WAN_SIM-v2
cd WAN_SIM-v2
chmod +x install-v2.sh
sudo ./install-v2.sh install
```

### Rocky Linux

```bash
sudo dnf makecache -y
sudo dnf install -y git sudo
git clone --branch v2.0.8-prestable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git WAN_SIM-v2
cd WAN_SIM-v2
chmod +x install-v2.sh
sudo ./install-v2.sh install
```

Comprueba que instalaste la etiqueta correcta:

```bash
git describe --tags --exact-match
# Debe mostrar: v2.0.8-prestable
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
sudo wansim update v2.0.8-prestable
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

## Novedades De V2.0.8

- Asistente ReactUI de cuatro pasos con detección y recomendación de interfaces.
- Preflight con errores, advertencias y recomendaciones antes de desplegar.
- Comparación entendible entre la topología activa y la propuesta.
- Protección de la interfaz administrativa mediante doble confirmación.
- Watchdog que revierte el cambio si ReactUI no confirma conectividad a tiempo.
- Validación de gateways, interfaces, subredes y parámetros L2/L3.

La suite general y la matriz automática Linux aprobaron para esta etiqueta:

- [WAN_SIM checks](https://github.com/Ryuz-crypto/WAN_SIM/actions/workflows/checks.yml)
- [Ubuntu, Debian, Fedora y Rocky](https://github.com/Ryuz-crypto/WAN_SIM/actions/workflows/linux-matrix.yml)

La matriz Vagrant completa no fue ejecutada en el host Windows de desarrollo por no disponer de Vagrant/VirtualBox. V2 conserva por ello su estado **pre-stable**.

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
