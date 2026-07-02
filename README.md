# Ryuz WAN Simulator (WANsim2.sh)

**Versión 1.100** | **Autor**: decameru@outlook.com

---

## 📌 Descripción General

**Ryuz WAN Simulator** es una herramienta empresarial para **simular redes WAN** en entornos Linux, diseñada para probar y optimizar el rendimiento de aplicaciones en condiciones de red controladas. Permite emular **latencia, jitter (variación de latencia) y pérdida de paquetes** en interfaces de red, ya sea en topologías **NAT** (para salida a Internet) o **Puente LAN-to-LAN** (peer-to-peer).

### 🎯 Funcionalidades Principales
- **Simulación de VLANs**: Crea múltiples redes virtuales (VLANs) en una sola interfaz física.
- **Control de Tráfico (TC)**: Aplica **latencia**, **jitter** y **pérdida de paquetes** en tiempo real.
- **Modos de Operación**:
  - **NAT Único**: Simula una salida a Internet con NAT para múltiples VLANs.
  - **Puente LAN-to-LAN**: Conecta dos interfaces de red en modo puente (bridge).
- **Servidor DHCP**: Configura automáticamente un servidor DHCP para asignar IPs a las VLANs.
- **Dashboard Web**: Interfaz gráfica basada en **Flask** para monitorear y configurar parámetros en tiempo real.
- **Integración con Telegram**: Permite controlar el simulador mediante un bot de Telegram.
- **Persistencia de Configuración**: Guarda la configuración en un archivo para reutilizarla en futuras ejecuciones.

---

## 📥 Requisitos del Sistema

### ✅ Sistemas Operativos Compatibles
- **Ubuntu Server** (20.04 LTS o superior)
- **Ubuntu Workstation** (20.04 LTS o superior)
- **Debian** (10 o superior)
- **Raspberry Pi OS** (con soporte para VLANs)

### 🔧 Dependencias Obligatorias
| Tipo | Paquete | Descripción |
|------|---------|-------------|
| **Sistema** | `python3` | Lenguaje de programación Python 3 |
| **Sistema** | `python3-pip` | Gestor de paquetes de Python |
| **Sistema** | `iproute2` | Herramientas de red (ip, tc, etc.) |
| **Sistema** | `ifstat` | Monitor de tráfico de red |
| **Sistema** | `qrencode` | Generador de códigos QR (opcional) |
| **Sistema** | `net-tools` | Herramientas de red tradicionales (ifconfig, etc.) |
| **Sistema** | `vlan` | Soporte para VLANs en Linux |
| **Sistema** | `sudo` | Permisos de superusuario |
| **Sistema** | `lsof` | Lista de archivos abiertos (para liberar puertos) |
| **Sistema** | `isc-dhcp-server` | Servidor DHCP para asignar IPs |
| **Sistema** | `iptables-persistent` | Persistencia de reglas iptables |
| **Python** | `flask` | Framework web para el dashboard |
| **Python** | `requests` | Biblioteca HTTP para peticiones |
| **Python** | `python-telegram-bot==20.7` | Integración con Telegram Bot API |
| **Python** | `pyOpenSSL` | Soporte para SSL/TLS |

---

## 🛠️ Instalación

### 1️⃣ Descargar el Script
Clona este repositorio o descarga el archivo `WANsim2.sh`:
```bash
# Clonar el repositorio
git clone https://github.com/Ryuz-crypto/WAN_SIM.git
cd WAN_SIM

# O descargar solo el script
wget https://raw.githubusercontent.com/Ryuz-crypto/WAN_SIM/main/WANsim2.sh
chmod +x WANsim2.sh
```

---

### 2️⃣ Instalación en Ubuntu Server / Workstation

#### 🔹 Paso 1: Actualizar el Sistema
```bash
sudo apt update && sudo apt upgrade -y
```

#### 🔹 Paso 2: Instalar Dependencias del Sistema
```bash
sudo apt install -y python3 python3-pip iproute2 ifstat qrencode net-tools vlan sudo lsof isc-dhcp-server iptables-persistent
```

#### 🔹 Paso 3: Instalar Dependencias de Python
```bash
pip3 install --user flask requests python-telegram-bot==20.7 pyOpenSSL --no-warn-script-location
```

#### 🔹 Paso 4: Añadir Python al PATH
Agrega la siguiente línea a tu archivo `~/.bashrc`:
```bash
export PATH="$HOME/.local/bin:$PATH"
```
Luego, aplica los cambios:
```bash
source ~/.bashrc
```

#### 🔹 Paso 5: Configurar Permisos de Sudo
El script requiere permisos de `sudo` para ejecutar comandos de red. Ejecuta:
```bash
sudo visudo
```
Y agrega la siguiente línea al final del archivo (reemplaza `tu_usuario` con tu nombre de usuario):
```
tu_usuario ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/sbin/tc, /usr/bin/systemctl stop unattended-upgrades, /usr/bin/systemctl restart wansim.service, /usr/bin/fuser, /usr/bin/kill, /usr/bin/rm, /usr/sbin/dpkg
```
Guarda y cierra el archivo (`Ctrl + X`, luego `Y` y `Enter`).

#### 🔹 Paso 6: Habilitar el Módulo 8021q (VLANs)
```bash
sudo modprobe 8021q
```
Para cargarlo automáticamente al iniciar:
```bash
echo "8021q" | sudo tee -a /etc/modules
```

#### 🔹 Paso 7: Habilitar IP Forwarding (para NAT)
Edita el archivo `/etc/sysctl.conf`:
```bash
sudo nano /etc/sysctl.conf
```
Descomenta o agrega la siguiente línea:
```
net.ipv4.ip_forward=1
```
Aplica los cambios:
```bash
sudo sysctl -p
```

---

### 3️⃣ Ejecutar el Script

#### 🔹 Modo Interactivo (Recomendado)
Ejecuta el script como usuario normal (no como root):
```bash
./WANsim2.sh
```

#### 🔹 Modo con Configuración Previa
Si ya has ejecutado el script antes, puedes reutilizar la configuración guardada:
```bash
./WANsim2.sh
```
El script detectará automáticamente la configuración existente y te preguntará si deseas reutilizarla.

---

## 🎮 Menús y Opciones

El script presenta varios menús interactivos para configurar el simulador. A continuación, se detallan los menús y los parámetros que debes ingresar.

---

### 📋 Menú Principal
El primer menú que aparecerá es el **Menú Principal**, donde podrás seleccionar el modo de operación:

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
Selecciona una opción: 
```

| Opción | Descripción |
|--------|-------------|
| **1** | Modo **L3 (NAT)**: Simula una salida a Internet con NAT para múltiples VLANs. |
| **4** | Modo **Bridge**: Crea un puente entre dos interfaces de red (LAN-to-LAN). |
| **5** | **Salir**: Termina la ejecución del script. |

---

### 🌐 Menú de Topología de Red
Si seleccionas el modo **NAT (Opción 1)**, el script te preguntará por la topología de red:

```
┌─────────────────────────────────────────────────────────────┐
│                     Topología de Red                           │
│ Selecciona la topología de red:                             │
│  1) NAT único (salida a Internet)                            │
│  2) Puente LAN-to-LAN (peer-to-peer)                         │
└─────────────────────────────────────────────────────────────┘
[ENTRADA] Opción [1-2, predeterminado 1]: 
```

| Opción | Descripción |
|--------|-------------|
| **1** | **NAT Único**: Ideal para simular una conexión a Internet. Las VLANs tendrán acceso a la red externa a través de NAT. |
| **2** | **Puente LAN-to-LAN**: Conecta dos interfaces de red directamente, útil para pruebas peer-to-peer. |

---

### 🔧 Parámetros para Modo NAT (Opción 1)

#### 1️⃣ Configuración de VLANs
```
┌─────────────────────────────────────────────────────────────┐
│                     Configuración de VLANs                     │
│ En este contexto, cada VLAN representa un enlace simulado     │
└─────────────────────────────────────────────────────────────┘
[ENTRADA] ¿Cuántos enlaces (VLANs) simular? [predeterminado 10]: 
```
- **Parámetro**: Número de VLANs a crear (ejemplo: `10`).
- **Valor predeterminado**: `10`.

```
[ENTRADA] ¿Deseas definir los IDs de VLANs manualmente? (s/n) [predeterminado n]: 
```
- **Parámetro**: `s` (sí) o `n` (no).
- **Si seleccionas `s`**:
  ```
  [ENTRADA] Ingresa el ID inicial para las VLANs (1-4094): 
  ```
  - **Parámetro**: ID de la primera VLAN (ejemplo: `100`).
  - **Rango válido**: `1-4094`.
- **Si seleccionas `n`**: Se usará el ID predeterminado `100`.

#### 2️⃣ Configuración de DHCP
```
[ENTRADA] ¿Configurar DHCP? (s/n) [predeterminado s]: 
```
- **Parámetro**: `s` (sí) o `n` (no).
- **Si seleccionas `s`**:
  ```
  ┌─────────────────────────────────────────────────────────────┐
  │                     Segmento de Red                           │
  │ Selecciona el segmento base para las VLANs:                 │
  │  1) 10.254.X.0/24                                           │
  │  2) 172.16.X.0/24                                           │
  │  3) 192.168.X.0/24                                          │
  │  4) Custom (ingresar manualmente)                           │
  └─────────────────────────────────────────────────────────────┘
  [ENTRADA] Opción [1-4, predeterminado 3]: 
  ```
  - **Opciones**:
    | Opción | Segmento Base |
    |--------|---------------|
    | **1** | `10.254.X.0/24` |
    | **2** | `172.16.X.0/24` |
    | **3** | `192.168.X.0/24` (predeterminado) |
    | **4** | Personalizado (ejemplo: `192.168`).

  - **Si seleccionas `4`**:
    ```
    [ENTRADA] Ingresa el segmento base (ej: 192.168): 
    ```
    - **Parámetro**: Primeros dos octetos de la red (ejemplo: `192.168`).

  ```
  ┌─────────────────────────────────────────────────────────────┐
  │                     Dirección IP                              │
  │ El tercer octeto define la subred de la VLAN en la IP.       │
  │ Ejemplo: Para 192.168.X.0/24, un tercer octeto de 10 genera    │
  │ direcciones como 192.168.10.1 para la primera VLAN, etc.      │
  └─────────────────────────────────────────────────────────────┘
  [ENTRADA] Ingresa el tercer octeto inicial para las VLANs (1-254) [predeterminado 10]: 
  ```
  - **Parámetro**: Tercer octeto de la red (ejemplo: `10`).
  - **Valor predeterminado**: `10`.
  - **Rango válido**: `1-254`.

#### 3️⃣ Configuración de Interfaces de Red
```
┌─────────────────────────────────────────────────────────────┐
│                     Interfaces de Red                           │
│ Interfaces de red disponibles en el sistema local:            │
│  - eth0 (IP: 192.168.1.100, MAC: 00:11:22:33:44:55)            │
│    Salida a Internet detectada                                 │
│  - eth1 (Sin IP, MAC: aa:bb:cc:dd:ee:ff)                       │
└─────────────────────────────────────────────────────────────┘
[ENTRADA] Ingresa la interfaz WAN: 
```
- **Parámetro**: Nombre de la interfaz de red que tiene salida a Internet (ejemplo: `eth0`).

```
[ENTRADA] Ingresa la interfaz LAN (para VLANs y DHCP): 
```
- **Parámetro**: Nombre de la interfaz de red donde se crearán las VLANs (ejemplo: `eth1`).
- **Nota**: Debe ser diferente a la interfaz WAN.

#### 4️⃣ Integración con Telegram (Opcional)
```
┌─────────────────────────────────────────────────────────────┐
│                     Integración con Telegram                     │
│ Configura la integración con Telegram Bot para actualizaciones │
│ de parámetros:                                                │
└─────────────────────────────────────────────────────────────┘
[ENTRADA] ¿Integrar con Telegram Bot para actualizaciones de parámetros? (s/n) [predeterminado n]: 
```
- **Parámetro**: `s` (sí) o `n` (no).
- **Si seleccionas `s`**:
  ```
  [ENTRADA] Ingresa el token del Bot de Telegram: 
  ```
  - **Parámetro**: Token del bot de Telegram (ejemplo: `123456789:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`).
  - **Cómo obtenerlo**: Crea un bot con [@BotFather](https://t.me/BotFather) en Telegram.

  ```
  [ENTRADA] Ingresa el Chat ID (deja vacío para obtenerlo automáticamente): 
  ```
  - **Parámetro**: ID del chat de Telegram (ejemplo: `123456789`).
  - **Cómo obtenerlo**: Si lo dejas vacío, el script intentará obtenerlo automáticamente.

---

### 🌉 Parámetros para Modo Bridge (Opción 4)

#### 1️⃣ Configuración de Interfaces
```
┌─────────────────────────────────────────────────────────────┐
│                     Interfaces de Bridge                        │
│ Interfaces disponibles:                                       │
│  - eth0 (MAC: 00:11:22:33:44:55)                              │
│  - eth1 (MAC: aa:bb:cc:dd:ee:ff)                              │
└─────────────────────────────────────────────────────────────┘
[ENTRADA] Ingresa la interfaz LAN: 
```
- **Parámetro**: Nombre de la interfaz LAN (ejemplo: `eth0`).

```
[ENTRADA] Ingresa la interfaz de destino (salida): 
```
- **Parámetro**: Nombre de la interfaz de destino (ejemplo: `eth1`).
- **Nota**: Debe ser diferente a la interfaz LAN.

```
[ENTRADA] ¿Es la interfaz de destino (eth1) la interfaz de gestión con salida a Internet? (s/n) [predeterminado n]: 
```
- **Parámetro**: `s` (sí) o `n` (no).
- **Descripción**: Indica si la interfaz de destino tiene salida a Internet.

```
[ENTRADA] ¿Aplicar control de tráfico (latencia, jitter, pérdida) en el puente? (s/n) [predeterminado n]: 
```
- **Parámetro**: `s` (sí) o `n` (no).
- **Descripción**: Si seleccionas `s`, se aplicará un control de tráfico predeterminado (10Mbit/s) en el puente.

#### 2️⃣ Integración con Telegram (Opcional)
Igual que en el modo NAT (ver [Integración con Telegram](#4️⃣-integración-con-telegram-opcional)).

---

### 🔄 Menú de Configuración Previa
Si el script detecta una configuración guardada anteriormente, mostrará el siguiente menú:

```
┌─────────────────────────────────────────────────────────────┐
│                     Configuración Previa                        │
│ Se detectó una configuración previa.                         │
│  r) Reutilizar configuración existente                         │
│  c) Configurar nuevo modo de operación                         │
│  s) Salir                                                     │
└─────────────────────────────────────────────────────────────┘
[ENTRADA] Selecciona una opción [r/c/s, predeterminado r]: 
```

| Opción | Descripción |
|--------|-------------|
| **r** | Reutiliza la configuración guardada en `~/emix_abundix.conf`. |
| **c** | Configura un nuevo modo de operación desde cero. |
| **s** | Sale del script. |

---

### 🧹 Limpieza de Archivos
Al inicio del script, se te preguntará si deseas eliminar archivos generados previamente:

```
┌──────────────────────────────────── Limpieza de Archivos ┐
│ ¿Deseas eliminar archivos generados previamente?           │
│ (s/n) [predeterminado n]                                  │
└─────────────────────────────────────────────────────────────┘
Selecciona: 
```
- **Parámetro**: `s` (sí) o `n` (no).
- **Descripción**: Elimina archivos como `~/emix_abundix.conf`, `~/wansim_dashboard.py`, `~/api_tokens.json`, y logs temporales.

---

## 📊 Dashboard Web

Una vez configurado el simulador, se iniciará automáticamente un **dashboard web** basado en **Flask** en el puerto `5000`. Puedes acceder a él desde tu navegador:

```
http://<IP_DEL_SERVIDOR>:5000
```

### 🎨 Interfaz del Dashboard
El dashboard muestra:
1. **Tarjetas para cada VLAN/Interfaz**:
   - Nombre de la interfaz.
   - Campos para configurar **latencia (ms)**, **jitter (ms)** y **pérdida (%)**.
   - Botones para **Aplicar** o **Restablecer** la configuración.
   - Botones rápidos para valores predefinidos de latencia (100ms, 300ms, 500ms), jitter (50ms, 100ms, 200ms) y pérdida (1%, 5%, 10%).
   - Gráfico de barras con estadísticas de tráfico (entrada, salida, latencia, jitter, pérdida).
   - Estadísticas en tiempo real de ancho de banda (en Mbps, Kbps, MB o KB).

2. **Selector de Unidades**:
   - Permite cambiar entre **Mbps**, **Kbps**, **MB** o **KB** para visualizar el ancho de banda.

3. **Botón de Restablecimiento Global**:
   - **Restablecer Todas las Interfaces**: Elimina todas las configuraciones de tráfico (TC) en todas las VLANs.

4. **Pie de Página**:
   - Información del autor y enlace de contacto.

---

## 🤖 Integración con Telegram

Si configuraste la integración con Telegram, podrás controlar el simulador mediante un bot. Sigue estos pasos:

### 1️⃣ Iniciar el Bot
1. Abre Telegram y busca tu bot (ejemplo: `@MiWANSimBot`).
2. Inicia una conversación con el bot y envía el comando `/start` o `/config`.

### 2️⃣ Menú de Telegram
El bot te mostrará un menú con las VLANs disponibles:
```
Selecciona la VLAN que deseas configurar:
[Botón: v_100]
[Botón: v_101]
...
```

### 3️⃣ Configurar Parámetros
1. Selecciona una VLAN.
2. El bot te pedirá los siguientes parámetros en orden:
   - **Latencia (ms)**: Ejemplo: `200`.
   - **Jitter (ms)**: Ejemplo: `50`.
   - **Pérdida (%)**: Ejemplo: `5`.
3. El bot aplicará la configuración y te notificará el resultado.

---

## 📁 Archivos Generados

El script genera los siguientes archivos en tu directorio de usuario (`~`):

| Archivo | Descripción |
|--------|-------------|
| `emix_abundix.conf` | Archivo de configuración con los parámetros seleccionados. |
| `wansim_dashboard.py` | Script Python del dashboard web (Flask). |
| `api_tokens.json` | Archivo con tokens de API (si se usa Telegram). |
| `emix_abundix.log` | Log principal del script. |
| `/tmp/wansim_debug.log` | Log de depuración temporal. |
| `/etc/iptables/rules.v4` | Reglas de iptables (para NAT). |
| `/etc/dhcp/dhcpd.conf` | Configuración del servidor DHCP. |
| `/etc/default/isc-dhcp-server` | Interfaces para el servidor DHCP. |

---

## 🔌 Puertos Utilizados

| Puerto | Descripción |
|--------|-------------|
| **5000** | Dashboard web (Flask). |
| **5001** | Puerto alternativo para el dashboard. |
| **5002** | Puerto alternativo para el dashboard. |

---

## 🛑 Solución de Problemas

### ❌ Error: "No se pudo cargar el módulo 8021q"
**Solución**:
```bash
sudo modprobe 8021q
sudo apt install -y vlan
```

### ❌ Error: "No se pudo activar la interfaz"
**Solución**:
1. Verifica que la interfaz exista:
   ```bash
   ip link show
   ```
2. Actívala manualmente:
   ```bash
   sudo ip link set <interfaz> up
   ```

### ❌ Error: "No se pudo instalar <paquete>"
**Solución**:
1. Actualiza la lista de paquetes:
   ```bash
   sudo apt update
   ```
2. Instala el paquete manualmente:
   ```bash
   sudo apt install -y <paquete>
   ```

### ❌ Error: "Puerto 5000 en uso"
**Solución**:
1. Libera el puerto manualmente:
   ```bash
   sudo fuser -k 5000/tcp
   ```
2. Verifica que el puerto esté libre:
   ```bash
   ss -tuln | grep 5000
   ```

### ❌ Error: "No se pudo obtener el Chat ID de Telegram"
**Solución**:
1. Asegúrate de que el token del bot sea correcto.
2. Envía un mensaje al bot desde el chat donde deseas recibir las notificaciones.
3. Reintenta la configuración.

### ❌ Error: "VLAN no encontrada"
**Solución**:
1. Verifica que el módulo `8021q` esté cargado:
   ```bash
   lsmod | grep 8021q
   ```
2. Verifica las interfaces disponibles:
   ```bash
   ip link show
   ```

---

## 📜 Ejemplo de Configuración

### 🔹 Ejemplo 1: Modo NAT con 5 VLANs
1. **Topología**: NAT único.
2. **Número de VLANs**: `5`.
3. **IDs de VLANs**: Predeterminado (100, 101, 102, 103, 104).
4. **Segmento de Red**: `192.168.X.0/24`.
5. **Tercer Octeto**: `10`.
6. **DHCP**: Sí.
7. **Interfaz WAN**: `eth0`.
8. **Interfaz LAN**: `eth1`.
9. **Integración con Telegram**: No.

**Resultado**:
- Se crearán 5 VLANs (`v_100` a `v_104`) en `eth1` con IPs desde `192.168.10.1/24` hasta `192.168.14.1/24`.
- Cada VLAN tendrá un servidor DHCP configurado.
- Las VLANs tendrán acceso a Internet a través de NAT en `eth0`.

### 🔹 Ejemplo 2: Modo Bridge con Control de Tráfico
1. **Topología**: Puente LAN-to-LAN.
2. **Interfaz LAN**: `eth0`.
3. **Interfaz de Destino**: `eth1`.
4. **¿Es interfaz de gestión?**: No.
5. **Control de Tráfico**: Sí.
6. **Integración con Telegram**: Sí (token: `123456789:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`, Chat ID: `123456789`).

**Resultado**:
- Se creará un puente (`br0`) entre `eth0` y `eth1`.
- Se aplicará un control de tráfico de **10Mbit/s** en `eth0`.
- Podrás controlar el puente desde Telegram.

---

## 🚀 Uso Avanzado

### 🔹 Ejecutar en Segundo Plano
Para ejecutar el script en segundo plano y mantener el dashboard activo:
```bash
nohup ./WANsim2.sh > /dev/null 2>&1 &
```

### 🔹 Crear un Servicio Systemd
1. Crea el archivo de servicio:
   ```bash
   sudo nano /etc/systemd/system/wansim.service
   ```
2. Agrega el siguiente contenido (ajusta las rutas según tu sistema):
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
3. Habilita y inicia el servicio:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable wansim.service
   sudo systemctl start wansim.service
   ```
4. Verifica el estado:
   ```bash
   sudo systemctl status wansim.service
   ```

### 🔹 Reiniciar el Dashboard
Si el dashboard se detiene, puedes reiniciarlo manualmente:
```bash
pkill -f wansim_dashboard.py
python3 ~/wansim_dashboard.py &
```

---

## 📞 Soporte y Contacto

- **Autor**: decameru@outlook.com
- **Repositorio**: [Ryuz-crypto/WAN_SIM](https://github.com/Ryuz-crypto/WAN_SIM)
- **Versión**: 1.100

---

## 📝 Licencia

Este proyecto es de código abierto y se distribuye bajo los términos de la **Licencia MIT**. Consulta el archivo `LICENSE` para más detalles.

---

## 🔗 Recursos Adicionales

- [Documentación de Flask](https://flask.palletsprojects.com/)
- [Documentación de python-telegram-bot](https://python-telegram-bot.org/)
- [Guía de TC (Traffic Control)](https://man7.org/linux/man-pages/man8/tc.8.html)
- [Guía de VLANs en Linux](https://www.kernel.org/doc/html/latest/networking/vlan.html)

---

**¡Gracias por usar Ryuz WAN Simulator!** 🚀
