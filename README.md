# Ryuz WAN Simulator (WANsim2.sh)

**Versión 1.100** | **Autor**: decameru@outlook.com

---

## 📌 Descripción General

**Ryuz WAN Simulator** es una herramienta empresarial para **simular redes WAN** en entornos Linux. Permite emular **latencia, jitter (variación de latencia) y pérdida de paquetes** en interfaces de red, ideal para probar aplicaciones en condiciones de red controladas.

### 🎯 Funcionalidades Principales
- Simulación de **VLANs** en una sola interfaz física.
- Control de tráfico (**latencia**, **jitter**, **pérdida de paquetes**) en tiempo real.
- Dos modos de operación:
  - **NAT único**: Simula una salida a Internet con NAT para múltiples VLANs.
  - **Puente LAN-to-LAN**: Conecta dos interfaces de red en modo puente (bridge).
- **Servidor DHCP automático** para asignar IPs a las VLANs.
- **Dashboard web funcional** basado en Flask para monitorear y configurar parámetros.
- **Base ReactUI/FastAPI** incluida como evolución del dashboard sin retirar la funcionalidad actual.
- **Integración con Telegram** para controlar el simulador mediante un bot.
- **Persistencia de configuración** (guarda los parámetros para futuras ejecuciones).

---

## 📥 Requisitos del Sistema

### ✅ Sistemas Operativos Compatibles
- Ubuntu Server (20.04 LTS o superior)
- Ubuntu Workstation (20.04 LTS o superior)
- Debian (10 o superior)
- Raspberry Pi OS (con soporte para VLANs)

### 🔧 Requisitos Mínimos
- **Usuario no root**: El script **no debe ejecutarse como root** (lo verifica automáticamente).
- **Conexión a Internet**: Necesaria para instalar dependencias.
- **Permisos de sudo**: El script configura automáticamente los permisos necesarios.

---

## 🛠️ Instalación y Ejecución

El script **incluye un motor de instalación robusto** que se encarga de todo: dependencias del sistema, dependencias de Python, permisos de sudo y configuraciones iniciales.

### 1️⃣ Descargar el repositorio en Ubuntu Server
En Ubuntu Server usa el repositorio completo. No ejecutes el script sin cambiar permisos primero.

```bash
git clone https://github.com/Ryuz-crypto/WAN_SIM.git
cd WAN_SIM
chmod +x WANsim2.sh
```

### 2️⃣ Habilitar el Módulo 8021q (VLANs)
Ejecuta este comando **una sola vez** (el script no lo hace automáticamente):
```bash
sudo modprobe 8021q
echo "8021q" | sudo tee -a /etc/modules
```

### 3️⃣ Ejecutar el Script
```bash
./WANsim2.sh
```

**El script se encargará de:**
✅ Configurar permisos de sudo automáticamente.
✅ Actualizar los repositorios de paquetes.
✅ Instalar todas las dependencias del sistema (python3, iproute2, vlan, etc.).
✅ Instalar dependencias de Python obligatorias (flask, requests, pyOpenSSL), usando APT primero y pip como respaldo.
✅ Instalar `python-telegram-bot` solo si eliges activar Telegram.
✅ Verificar que todo esté listo antes de continuar.

---

## 🎮 Menús y Configuración

El script te guiará paso a paso con menús interactivos. A continuación, se describen las opciones principales:

---

### 📋 Menú Principal
```
┌─────────────────────────────────────────────────────────────┐
│                     Menú Principal                            │
│ Selecciona una opción:                                      │
│  1) L3                                                     │
│  2) Opción 2                                                │
│  3) Opción 3                                                │
│  4) Bridge                                                  │
│  5) Salir                                                   │
└─────────────────────────────────────────────────────────────┘
```

| Opción | Descripción |
|--------|-------------|
| **1**  | Modo **L3 (NAT)**: Simula una salida a Internet con NAT para múltiples VLANs. |
| **4**  | Modo **Bridge**: Crea un puente entre dos interfaces de red (LAN-to-LAN). |
| **5**  | **Salir**: Termina la ejecución del script. |

---

### 🌐 Menú de Topología de Red
Si seleccionas el modo **NAT (Opción 1)**, el script preguntará:
```
┌─────────────────────────────────────────────────────────────┐
│ Selecciona la topología de red:                             │
│  1) NAT único (salida a Internet)                            │
│  2) Puente LAN-to-LAN (peer-to-peer)                         │
└─────────────────────────────────────────────────────────────┘
[ENTRADA] Opción [1-2, predeterminado 1]: 
```

| Opción | Descripción |
|--------|-------------|
| **1**  | **NAT único**: Ideal para simular una conexión a Internet. |
| **2**  | **Puente LAN-to-LAN**: Conecta dos interfaces de red directamente. |

---

### 🔧 Parámetros para Modo NAT

#### 1️⃣ Configuración de VLANs
- **Número de VLANs**: ¿Cuántos enlaces simular? (Predeterminado: `10`).
- **IDs de VLANs**: ¿Definir manualmente? (s/n). Si seleccionas `s`, ingresa el ID inicial (1-4094).

#### 2️⃣ Configuración de DHCP
- **¿Configurar DHCP?** (s/n, predeterminado: `s`).
- **Segmento de red**: Selecciona entre:
  - 1) `10.254.X.0/24`
  - 2) `172.16.X.0/24`
  - 3) `192.168.X.0/24` (predeterminado)
  - 4) Personalizado (ingresa manualmente, ej: `192.168`).
- **Tercer octeto**: Ingresa el tercer octeto inicial para las VLANs (1-254, predeterminado: `10`).

#### 3️⃣ Interfaces de Red
- **Interfaz WAN**: Ingresa la interfaz con salida a Internet (ej: `eth0`).
- **Interfaz LAN**: Ingresa la interfaz donde se crearán las VLANs (ej: `eth1`).

#### 4️⃣ Integración con Telegram (Opcional)
- **¿Integrar con Telegram?** (s/n, predeterminado: `n`).
- **Token del bot**: Ingresa el token de tu bot de Telegram.
- **Chat ID**: Ingresa el ID del chat (o déjalo vacío para obtenerlo automáticamente).

---

### 🌉 Parámetros para Modo Bridge

#### 1️⃣ Configuración de Interfaces
- **Interfaz LAN**: Ingresa la interfaz local (ej: `eth0`).
- **Interfaz de destino**: Ingresa la interfaz de salida (ej: `eth1`).
- **¿Es interfaz de gestión?** (s/n, predeterminado: `n`): Indica si la interfaz de destino tiene salida a Internet.
- **¿Aplicar control de tráfico?** (s/n, predeterminado: `n`): Aplica un límite de 10Mbit/s en el puente.

#### 2️⃣ Integración con Telegram (Opcional)
Igual que en el modo NAT.

---

### 🔄 Configuración Previa
Si el script detecta una configuración guardada, mostrará:
```
┌─────────────────────────────────────────────────────────────┐
│  r) Reutilizar configuración existente                         │
│  c) Configurar nuevo modo de operación                         │
│  s) Salir                                                     │
└─────────────────────────────────────────────────────────────┘
[ENTRADA] Selecciona una opción [r/c/s, predeterminado r]: 
```

---

## 📊 Dashboard Web

Una vez configurado, el script iniciará automáticamente un **dashboard web** en el puerto `5000`. Accede desde tu navegador:
```
http://<IP_DEL_SERVIDOR>:5000
```

### 🎨 Interfaz del Dashboard
- **Tarjetas para cada VLAN/interfaz**:
  - Campos para configurar **latencia (ms)**, **jitter (ms)** y **pérdida (%)**.
  - Botones para **Aplicar** o **Restablecer** la configuración.
  - Botones rápidos para valores predefinidos (latencia: 100ms, 300ms, 500ms; jitter: 50ms, 100ms, 200ms; pérdida: 1%, 5%, 10%).
  - Gráficos de barras con estadísticas de tráfico.
  - Estadísticas en tiempo real de ancho de banda (Mbps, Kbps, MB, KB).
- **Selector de unidades**: Cambia entre Mbps, Kbps, MB o KB.
- **Botón global**: Restablecer todas las interfaces.

---

## 🧭 ReactUI/FastAPI

La base de la interfaz React solicitada vive en [`DashboardAPI-EC/`](DashboardAPI-EC/README.md). Incluye frontend React + TypeScript + Material UI, backend FastAPI, PostgreSQL/TimescaleDB, Redis, Celery y Nginx para una evolución modular del dashboard.

Importante: `WANsim2.sh` conserva el dashboard Flask como interfaz operativa completa porque ahí viven hoy las acciones de control de latencia, jitter, pérdida, VLANs, métricas y Telegram. ReactUI debe usarse como evolución paralela hasta que consuma los mismos endpoints y alcance paridad funcional. No reemplaces Flask por ReactUI si necesitas mantener todas las funciones actuales.

Arranque local:
```bash
cd DashboardAPI-EC
cp .env.example .env
docker compose up --build
```

URLs principales:
- UI React: `http://localhost:8080`
- API: `http://localhost:8080/api/v1`
- Swagger: `http://localhost:8080/api/v1/docs`

---

## 🤖 Integración con Telegram

Si configuraste Telegram, podrás controlar el simulador mediante un bot:

1. **Inicia el bot** en Telegram (ej: `@MiWANSimBot`).
2. **Envía `/start` o `/config`** para comenzar.
3. **Selecciona una VLAN** del menú.
4. **Ingresa los parámetros** en orden:
   - Latencia (ms)
   - Jitter (ms)
   - Pérdida (%)

---

## 📁 Archivos Generados

El script genera los siguientes archivos:

| Archivo | Descripción |
|--------|-------------|
| `~/emix_abundix.conf` | Configuración guardada. |
| `~/wansim_dashboard.py` | Script del dashboard web. |
| `~/api_tokens.json` | Tokens de API (si usas Telegram). |
| `~/emix_abundix.log` | Log principal. |
| `/etc/iptables/rules.v4` | Reglas de iptables (para NAT). |
| `/etc/dhcp/dhcpd.conf` | Configuración del servidor DHCP. |

---

## 🔌 Puertos Utilizados

| Puerto | Descripción |
|--------|-------------|
| **5000** | Dashboard web (Flask). |

---

## 🛑 Solución de Problemas

### ❌ Error: "No se pudo cargar el módulo 8021q"
**Solución:**
```bash
sudo modprobe 8021q
sudo apt install -y vlan
```

### ❌ Error: "No se pudo activar la interfaz"
**Solución:**
```bash
ip link show  # Verifica que la interfaz exista
sudo ip link set <interfaz> up
```

### ❌ Error: "Puerto 5000 en uso"
**Solución:**
```bash
sudo fuser -k 5000/tcp
```

### ❌ Error: "No se pudo instalar <paquete>"
**Solución:**
```bash
sudo apt update
sudo apt install -y <paquete>
```

### ❌ Error: timeout al instalar Flask desde PyPI
El instalador de `WANsim2.sh` intenta instalar Flask, requests y pyOpenSSL desde APT primero (`python3-flask`, `python3-requests`, `python3-openssl`). Si APT no puede resolverlos, usa pip con reintentos, `--prefer-binary`, timeout de 300 segundos y `--break-system-packages` solo cuando tu versión de pip lo soporta.

Si ves `Connection reset by peer` o tu red sigue cortando la descarga de PyPI, normalmente el script continuará usando APT para Flask. Para forzar más margen en pip:
```bash
PIP_TIMEOUT=600 PIP_RETRIES=15 ./WANsim2.sh
```

Si no usas Telegram, puedes continuar sin `python-telegram-bot`; el dashboard base no depende de ese paquete.

### ❌ Error: "No se pudo obtener el Chat ID de Telegram"
**Solución:**
1. Asegúrate de que el token del bot sea correcto.
2. Envía un mensaje al bot desde el chat donde deseas recibir notificaciones.
3. Reintenta la configuración.

---

## 📜 Ejemplo de Configuración

### Ejemplo 1: Modo NAT con 5 VLANs
1. **Topología**: NAT único.
2. **Número de VLANs**: `5`.
3. **Segmento de red**: `192.168.X.0/24`.
4. **Tercer octeto**: `10`.
5. **DHCP**: Sí.
6. **Interfaz WAN**: `eth0`.
7. **Interfaz LAN**: `eth1`.

**Resultado:**
- Se crearán 5 VLANs (`v_100` a `v_104`) en `eth1` con IPs desde `192.168.10.1/24` hasta `192.168.14.1/24`.
- Cada VLAN tendrá un servidor DHCP configurado.
- Las VLANs tendrán acceso a Internet a través de NAT en `eth0`.

### Ejemplo 2: Modo Bridge con Control de Tráfico
1. **Topología**: Puente LAN-to-LAN.
2. **Interfaz LAN**: `eth0`.
3. **Interfaz de destino**: `eth1`.
4. **Control de tráfico**: Sí.

**Resultado:**
- Se creará un puente (`br0`) entre `eth0` y `eth1`.
- Se aplicará un control de tráfico de **10Mbit/s** en `eth0`.

---

## 🚀 Uso Avanzado

### Ejecutar en Segundo Plano
```bash
nohup ./WANsim2.sh > /dev/null 2>&1 &
```

### Crear un Servicio Systemd
1. Crea el archivo de servicio:
   ```bash
   sudo nano /etc/systemd/system/wansim.service
   ```
2. Agrega el siguiente contenido (ajusta las rutas):
   ```ini
   [Unit]
   Description=Ryuz WAN Simulator
   After=network.target

   [Service]
   User=tu_usuario
   WorkingDirectory=/ruta/al/script
   ExecStart=/ruta/al/script/WANsim2.sh
   Restart=always
   RestartSec=10

   [Install]
   WantedBy=multi-user.target
   ```
3. Habilita e inicia el servicio:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable wansim.service
   sudo systemctl start wansim.service
   ```

---

## 📞 Soporte y Contacto
- **Autor**: [decameru@outlook.com](mailto:decameru@outlook.com)
- **Repositorio**: [Ryuz-crypto/WAN_SIM](https://github.com/Ryuz-crypto/WAN_SIM)
- **Versión**: 1.100

---

## 📝 Licencia
Este proyecto se distribuye bajo la **Licencia MIT**. Consulta el archivo `LICENSE` para más detalles.

---

**¡Gracias por usar Ryuz WAN Simulator!** 🚀
