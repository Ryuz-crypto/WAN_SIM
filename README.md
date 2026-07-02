# Ryuz WAN Simulator (WANsim2.sh)

**Versión 1.107** | **Autor**: decameru@outlook.com

---

## 📌 Descripción General

**Ryuz WAN Simulator** es una herramienta empresarial para **simular redes WAN** en entornos Linux. Permite emular **latencia, jitter (variación de latencia) y pérdida de paquetes** en interfaces de red, ideal para probar aplicaciones en condiciones de red controladas.

### 🎯 Funcionalidades Principales
- Simulación de **VLANs** en una sola interfaz física (modo NAT)
- Control de tráfico (**latencia**, **jitter**, **pérdida de paquetes**) en tiempo real
- Dos modos de operación:
  - **L3 / NAT único**: Simula una salida a Internet con NAT para múltiples VLANs + DHCP
  - **Bridge L2**: Crea de 1 a 3 bridges por pares de interfaces físicas (entrada/salida)
- **Servidor DHCP automático** para asignar IPs a las VLANs
- **Dashboard web funcional** basado en Flask para monitorear y configurar parámetros
- **Persistencia de bridges L2** mediante servicio systemd (wansim-l2-persist.service)
- **Integración con Telegram** para controlar el simulador mediante un bot
- **Persistencia de configuración** (guarda los parámetros para futuras ejecuciones)
- **Base ReactUI/FastAPI** incluida como evolución del dashboard

---

## 📥 Requisitos del Sistema

### ✅ Sistemas Operativos Compatibles
- Ubuntu Server (20.04 LTS o superior)
- Ubuntu Workstation (20.04 LTS o superior)
- Debian (10 o superior)
- Raspberry Pi OS (con soporte para VLANs)

### 🔧 Requisitos Mínimos
- **Usuario no root**: El script **no debe ejecutarse como root** (lo verifica automáticamente)
- **Conexión a Internet**: Necesaria para instalar dependencias
- **Permisos de sudo**: El script configura automáticamente los permisos necesarios

---

## 🚀 Instalación Rápida

### Método más simple (recomendado):

```bash
# 1. Clonar el repositorio
git clone https://github.com/Ryuz-crypto/WAN_SIM.git
cd WAN_SIM

# 2. Dar permisos de ejecución
chmod +x WANsim2.sh

# 3. Habilitar módulo 8021q (VLANs) - SOLO UNA VEZ
sudo modprobe 8021q
echo "8021q" | sudo tee -a /etc/modules

# 4. Ejecutar el script
./WANsim2.sh
```

**¡Eso es todo!** El script se encargará automáticamente de:
✅ Configurar permisos de sudo
✅ Actualizar repositorios de paquetes
✅ Instalar todas las dependencias del sistema
✅ Instalar dependencias de Python
✅ Configurar la red según tus preferencias
✅ Iniciar el dashboard web

---

## 📋 Instalación Manual (Alternativa)

Si prefieres más control sobre el proceso:

```bash
# Instalar dependencias manualmente
sudo apt update
sudo apt install -y git python3 python3-pip iproute2 ifstat qrencode net-tools vlan sudo lsof isc-dhcp-server iptables-persistent

# Instalar dependencias Python
pip3 install --user flask requests pyOpenSSL "python-telegram-bot==13.15" --no-warn-script-location

# Clonar y ejecutar
git clone https://github.com/Ryuz-crypto/WAN_SIM.git
cd WAN_SIM
chmod +x WANsim2.sh
sudo modprobe 8021q
echo "8021q" | sudo tee -a /etc/modules
./WANsim2.sh
```

---

## 🎮 Configuración Interactiva

El script te guiará paso a paso con menús interactivos.

### Selección de Topología

```
┌─────────────────── Topología de Red ───────────────────────┐
│ Selecciona la topología de red:                           │
│  1) L3 / NAT único (VLANs + DHCP + salida a Internet)     │
│  2) Bridge (intervenir interfaces físicas, 1 a 3)         │
└───────────────────────────────────────────────────────────┘
```

| Opción | Descripción |
|--------|-------------|
| **1**  | Modo **L3/NAT**: Crea múltiples VLANs en una interfaz LAN con NAT hacia WAN. Ideal para simular múltiples enlaces WAN con salida a Internet |
| **2**  | Modo **Bridge L2**: Crea de 1 a 3 bridges entre pares de interfaces físicas (entrada/salida). Ideal para conectar redes locales |

### Modo L3/NAT

Configura:
- **Número de VLANs**: Cuántos enlaces simular (predeterminado: 10)
- **ID inicial de VLANs**: ID base para las VLANs (1-4094, predeterminado: 100)
- **DHCP**: Activar/desactivar servidor DHCP
- **Segmento de red**: 10.254.X.0/24, 172.16.X.0/24 o 192.168.X.0/24
- **Tercer octeto**: Octeto inicial para las subredes (1-254, predeterminado: 10)
- **Interfaz WAN**: Interfaz con salida a Internet
- **Interfaz LAN**: Interfaz donde se crearán las VLANs

### Modo Bridge L2

Configura:
- **Número de bridges**: De 1 a 3 (predeterminado: 1)
- Para cada bridge:
  - **Interfaz de ENTRADA**: Interfaz física de entrada
  - **Interfaz de SALIDA**: Interfaz física de salida
- **Control de tráfico**: Aplicar tc/netem en las interfaces (predeterminado: sí)

### Integración con Telegram (Opcional)

- **Token del Bot**: Token de tu bot de Telegram
- **Chat ID**: ID del chat (puede obtenerse automáticamente)

---

## 📊 Dashboard Web

Una vez configurado, el dashboard estará disponible en:
```
http://<IP_DEL_SERVIDOR>:5000
```

### Características del Dashboard:
- **Tarjetas para cada interfaz/VLAN** con:
  - Campos para configurar latencia (ms), jitter (ms) y pérdida (%)
  - Botones para Aplicar o Restablecer
  - Botones rápidos para valores predefinidos
  - Gráficos de barras con estadísticas
  - Estadísticas en tiempo real de ancho de banda
- **Selector de unidades**: Mbps, Kbps, MB/s, KB/s
- **Botón global**: Restablecer todas las interfaces
- **Información detallada**: MAC, peer, bridge, rol

---

## 🔄 Persistencia

### Persistencia de Bridges L2
La versión 1.107 incluye un servicio systemd (`wansim-l2-persist.service`) que:
- Recrea automáticamente los bridges L2 al reiniciar el sistema
- Restaura el estado de tc/netem (latencia, jitter, pérdida)
- Se ejecuta antes del servicio principal de WAN Simulator

### Persistencia de Configuración
Todos los parámetros se guardan en:
- `~/emix_abundix.conf` - Configuración principal
- `~/wansim_netem_state.json` - Estado de tc/netem

---

## 📁 Archivos Generados

| Archivo | Descripción |
|--------|-------------|
| `~/emix_abundix.conf` | Configuración guardada |
| `~/wansim_dashboard.py` | Script del dashboard web |
| `~/api_tokens.json` | Tokens de API |
| `~/emix_abundix.log` | Log principal |
| `/etc/iptables/rules.v4` | Reglas de iptables (para NAT) |
| `/etc/dhcp/dhcpd.conf` | Configuración del servidor DHCP |
| `/usr/local/sbin/wansim_l2_persist.sh` | Script de persistencia L2 |
| `/etc/systemd/system/wansim-l2-persist.service` | Servicio de persistencia L2 |

---

## 🔌 Puertos Utilizados

| Puerto | Descripción |
|--------|-------------|
| **5000** | Dashboard web (Flask) |

---

## 📜 Release Notes

### Versión 1.107 (Actual)
**Fecha**: 2024

✨ **Nuevas funcionalidades:**
- **Soporte para múltiples bridges L2**: Ahora puedes crear de 1 a 3 bridges, cada uno con su par de interfaces entrada/salida
- **Persistencia de bridges L2**: Servicio systemd que recrea bridges y restaura estado tc/netem al reiniciar
- **Mejor manejo de interfaces**: Detección y validación mejorada de interfaces de red
- **Dashboard mejorado**: Muestra información de bridge, rol y peer para cada interfaz
- **Versión específica de python-telegram-bot**: 13.15 para mayor compatibilidad

🔧 **Mejoras:**
- Función `reset_interface()` más robusta con manejo de AppArmor y bloqueos de iptables
- Manejo mejorado de VLANs con IDs alternativos (1000, 2000, 3000) si hay conflictos
- Validación de longitud de nombres de VLANs (< 15 caracteres)
- Liberación robusta de puertos (5000, 5001, 5002)
- Manejo mejorado de bloqueos de apt/dpkg
- Configuración automática de iptables-persistent

🐛 **Correcciones:**
- Problemas con archivo de bloqueo `/run/xtables.lock`
- Errores al eliminar VLANs existentes
- Problemas de permisos en archivos de log
- Manejo de errores en configuración DHCP

### Versión 1.100
**Fecha**: 2024

- Versión inicial con soporte básico para NAT y Bridge
- Dashboard Flask funcional
- Integración con Telegram
- Configuración de VLANs y DHCP

---

## 🛑 Solución de Problemas

### ❌ Error: "No se pudo cargar el módulo 8021q"
**Solución:**
```bash
sudo modprobe 8021q
sudo apt install -y vlan
echo "8021q" | sudo tee -a /etc/modules
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
# o
sudo lsof -i :5000
sudo kill -9 <PID>
```

### ❌ Error: "No se pudo instalar <paquete>"
**Solución:**
```bash
sudo apt update
sudo apt install -y <paquete>
```

### ❌ Error: "No se pudo obtener el Chat ID de Telegram"
**Solución:**
1. Asegúrate de que el token del bot sea correcto
2. Envía un mensaje al bot desde el chat donde deseas recibir notificaciones
3. Reintenta la configuración

### ❌ Error: "Sintaxis de wansim_dashboard.py"
**Solución:**
```bash
# Verifica la sintaxis
python3 -m py_compile ~/wansim_dashboard.py

# Si hay errores, revisa los logs
cat /tmp/wansim_debug.log
```

---

## 🚀 Uso Avanzado

### Ejecutar en Segundo Plano
```bash
nohup ./WANsim2.sh > /dev/null 2>&1 &
```

### Crear un Servicio Systemd Personalizado
```bash
sudo nano /etc/systemd/system/wansim-custom.service
```

Contenido:
```ini
[Unit]
Description=Ryuz WAN Simulator Custom
After=network-online.target
Wants=network-online.target

[Service]
User=tu_usuario
WorkingDirectory=/home/tu_usuario/WAN_SIM
ExecStart=/home/tu_usuario/WAN_SIM/WANsim2.sh
Restart=always
RestartSec=10
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/tu_usuario/.local/bin

[Install]
WantedBy=multi-user.target
```

Luego:
```bash
sudo systemctl daemon-reload
sudo systemctl enable wansim-custom.service
sudo systemctl start wansim-custom.service
```

---

## 📞 Soporte y Contacto
- **Autor**: [decameru@outlook.com](mailto:decameru@outlook.com)
- **Repositorio**: [Ryuz-crypto/WAN_SIM](https://github.com/Ryuz-crypto/WAN_SIM)
- **Versión**: 1.107

---

## 📝 Licencia
Este proyecto se distribuye bajo la **Licencia MIT**. Consulta el archivo `LICENSE` para más detalles.

---

**¡Gracias por usar Ryuz WAN Simulator!** 🚀
