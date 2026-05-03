#!/bin/bash

# Ryuz WAN Simulator - Versión 2.2 (Modo L2L con 3 interfaces individuales)
# Solución Empresarial para Simulación de Redes WAN (L2)
# Créditos: decameru@outlook.com

# Colores para salida en consola
COLOR_OK="\033[1;32m"
COLOR_ERROR="\033[1;31m"
COLOR_WARN="\033[1;33m"
COLOR_RESET="\033[0m"

# Variables globales
CURRENT_USER=\$(whoami)
USER_HOME="/home/\$CURRENT_USER"
LOG_FILE="/tmp/wansim_debug.log"
CONFIG_FILE="/home/axis/emix_abundix.conf"
WANSIM_DASHBOARD="/home/axis/wansim_dashboard.py"
SERVICE_FILE="/etc/systemd/system/wansim.service"
DASHBOARD_PORT=5000

# Arrays para almacenar interfaces L2L
declare -a L2L_NAMES=("L2L1" "L2L2" "L2L3")
declare -a L2L_IFACES=()

# Función para registrar mensajes en el log
log_message() {
    local level="\$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [\$level] \$message" | tee -a "\$LOG_FILE"
    chmod 640 "\$LOG_FILE" 2>/dev/null
}

# Función para limpiar instalación anterior
clean_previous_installation() {
    log_message "INFO" "Limpieza de instalación anterior..."

    # Eliminar archivos de configuración
    files_to_clean=("\$CONFIG_FILE" "\$LOG_FILE" "\$SERVICE_FILE" "$WANSIM_DASHBOARD" "/tmp/wansim_dashboard.log")
    for file in "${files_to_clean[@]}"; do
        if [ -f "\$file" ]; then
            sudo rm -f "\$file" && log_message "OK" "Eliminado \$file." || {
                log_message "ERROR" "Fallo al eliminar $file."
                echo -e "${COLOR_ERROR}No se pudo eliminar \$file. Revisa permisos con 'ls -l $file'.${COLOR_RESET}"
            }
        fi
    done

    # Eliminar reglas de iptables
    sudo iptables -F 2>/dev/null
    sudo iptables -t nat -F 2>/dev/null
    sudo iptables -X 2>/dev/null
    sudo iptables -t nat -X 2>/dev/null
    log_message "OK" "Reglas de iptables limpiadas."

    # Eliminar configuraciones de tc qdisc en todas las interfaces
    for iface in \$(ip link show | awk -F': ' '{print \$2}' | grep -v "lo"); do
        sudo tc qdisc del dev "\$iface" root 2>/dev/null
        sudo tc qdisc del dev "\$iface" ingress 2>/dev/null
        log_message "OK" "Configuraciones de tc qdisc eliminadas en \$iface."
    done

    # Detener y eliminar servicio systemd
    sudo systemctl stop wansim.service 2>/dev/null
    sudo systemctl disable wansim.service 2>/dev/null
    sudo rm -f "\$SERVICE_FILE" 2>/dev/null
    sudo systemctl daemon-reload 2>/dev/null
    log_message "OK" "Servicio systemd detenido y eliminado."

    # Matar procesos de Flask
    pkill -f wansim_dashboard.py 2>/dev/null
    pkill -f "python3 $WANSIM_DASHBOARD" 2>/dev/null
    log_message "OK" "Procesos de Flask terminados."

    echo -e "${COLOR_OK}✔ Limpieza de instalación anterior completada.\${COLOR_RESET}"
}

# SECCIÓN 1: Limpieza Inicial
# --------------------------
echo -e "\n┌─────────────────── Limpieza Inicial ───────────────────────┐"
echo "│ ¿Deseas realizar una limpieza completa de instalaciones       │"
echo "│ anteriores? (s/n) [predeterminado s]                       │"
echo "└───────────────────────────────────────────────────────────┘"
read -p "Selecciona: " clean_choice
clean_choice=\${clean_choice:-s}

if [ "\$clean_choice" = "s" ]; then
    clean_previous_installation
else
    log_message "INFO" "No se realizó limpieza de instalación anterior."
fi

# SECCIÓN 2: Verificación de Permisos y Dependencias
# -----------------------------------------------
log_message "DEBUG" "Verificando permisos de usuario..."
if [ "$CURRENT_USER" != "axis" ]; then
    log_message "ERROR" "Este script debe ejecutarse como usuario axis."
    echo -e "${COLOR_ERROR}Por favor, ejecuta como usuario axis.${COLOR_RESET}"
    exit 1
fi
log_message "OK" "Ejecutando como usuario axis."

log_message "DEBUG" "Verificando privilegios sudo sin contraseña..."
if ! sudo -n true 2>/tmp/sudo_error.log; then
    sudo_error=$(cat /tmp/sudo_error.log 2>/dev/null || echo "No se pudo leer el error")
    log_message "ERROR" "Se requiere sudo sin contraseña: $sudo_error"
    echo -e "${COLOR_ERROR}Configura sudo sin contraseña con 'sudo visudo'.\${COLOR_RESET}"
    exit 1
fi
log_message "OK" "sudo sin contraseña confirmado."

log_message "DEBUG" "Verificando estado de AppArmor..."
if command -v aa-status >/dev/null 2>&1; then
    aa_output=\$(sudo aa-status 2>/tmp/aa_error.log)
    aa_status=\$?
    if [ $aa_status -eq 0 ]; then
        aa_summary=$(echo "\$aa_output" | head -n 1)
        log_message "DEBUG" "Estado de AppArmor: $aa_summary"
    else
        aa_error=$(cat /tmp/aa_error.log 2>/dev/null || echo "No se pudo leer el error")
        log_message "WARN" "Error ejecutando aa-status: \$aa_error"
    fi
else
    log_message "DEBUG" "aa-status no instalado. Instala con 'sudo apt install apparmor-utils'."
fi

log_message "DEBUG" "Verificando e instalando dependencias..."
echo -e "\n┌─────────────────── Instalando Dependencias ────────────────┐"
echo "│ Instalando paquetes requeridos...                         │"
echo "└───────────────────────────────────────────────────────────┘"

dependencies=("python3" "python3-pip" "iproute2" "ifstat" "net-tools" "sudo" "lsof" "iptables-persistent" "tc")
for dep in "\${dependencies[@]}"; do
    echo -n "Instalando \$dep..."
    if dpkg -s "\$dep" >/dev/null 2>&1; then
        echo -e "[OK] \$dep ya está instalado.\n [✔]"
        log_message "OK" "\$dep ya está instalado."
    else
        sudo apt-get update && sudo apt-get install -y "\$dep" >/dev/null 2>&1
        [ \$? -eq 0 ] && log_message "OK" "\$dep instalado." || {
            log_message "ERROR" "Fallo al instalar $dep."
            echo -e "${COLOR_ERROR}Fallo al instalar \$dep. Revisa con 'sudo apt-get install $dep'.${COLOR_RESET}"
            exit 1
        }
        echo -e "[OK] \$dep instalado.\n [✔]"
    fi
done

log_message "DEBUG" "Instalando dependencias de Python..."
echo "Instalando dependencias de Python..."
pip3 install --user flask requests python-telegram-bot==20.7 pyOpenSSL jq >/dev/null 2>&1
[ \$? -eq 0 ] && log_message "OK" "Dependencias de Python instaladas." || {
    log_message "ERROR" "Fallo al instalar dependencias de Python."
    echo -e "${COLOR_ERROR}Fallo al instalar dependencias de Python. Revisa con 'pip3 install flask requests python-telegram-bot==20.7 pyOpenSSL jq'.${COLOR_RESET}"
    exit 1
}
echo -e "${COLOR_OK}✔ Dependencias de Python instaladas${COLOR_RESET}"

# SECCIÓN 3: Configuración Interactiva (Modo L2L con 3 interfaces)
# -----------------------------------
log_message "DEBUG" "Iniciando configuración interactiva..."
echo -e "\n┌─────────────────── Configuración de Interfaces L2L ──────────┐"
echo "│ Configuraremos 3 interfaces individuales para simular enlaces  │"
echo "│ L2L1, L2L2 y L2L3. Cada una podrá manipularse independientemente.│"
echo "└───────────────────────────────────────────────────────────┘"

# Mostrar interfaces disponibles
echo -e "\n┌─────────────────── Interfaces de Red Disponibles ───────────┐"
echo "│ Interfaces físicas detectadas:                           │"
ip -o link show | awk -F': ' '{print \$2}' | grep -v "lo" | while read -r iface; do
    iface=\${iface%@*}
    ip_addr=\$(ip addr show "\$iface" | grep -o 'inet [0-9.]\+/[0-9]\+' | awk '{print \$2}' | head -n1)
    mac=\$(ip link show "\$iface" | grep -o 'link/ether [0-9a-f:]\+' | awk '{print \$2}')
    status=\$(ip link show "\$iface" | grep -o 'state [A-Z]\+' | awk '{print \$2}')
    echo "│  - \$iface (IP: \${ip_addr:-Sin IP}, MAC: \${mac:-}, Estado: \${status:-}) │"
done
echo "└───────────────────────────────────────────────────────────┘"

# Configurar las 3 interfaces L2L
for ((i=0; i<3; i++)); do
    while true; do
        echo -e "\n┌─────────────────── \${L2L_NAMES[\$i]} ──────────────────────────┐"
        read -p "│ Selecciona interfaz para \${L2L_NAMES[\$i]}: " selected_iface

        # Validar que la interfaz exista
        if ! ip link show "\$selected_iface" >/dev/null 2>&1; then
            echo -e "\${COLOR_ERROR}Interfaz $selected_iface no válida.${COLOR_RESET}"
            continue
        fi

        # Validar que la interfaz no esté ya seleccionada
        duplicate=false
        for ((j=0; j<i; j++)); do
            if [ "$selected_iface" = "${L2L_IFACES[\$j]}" ]; then
                duplicate=true
                break
            fi
        done

        if [ "$duplicate" = true ]; then
            echo -e "${COLOR_ERROR}La interfaz $selected_iface ya está asignada a otro L2L.${COLOR_RESET}"
            continue
        fi

        # Validar que no sea loopback
        if [ "$selected_iface" = "lo" ]; then
            echo -e "${COLOR_ERROR}No puedes seleccionar la interfaz loopback (lo).\${COLOR_RESET}"
            continue
        fi

        L2L_IFACES+=("$selected_iface")
        break
    done
    echo "└───────────────────────────────────────────────────────────┘"
    echo -e "${COLOR_OK}✔ \${L2L_NAMES[\$i]} asignado a $selected_iface${COLOR_RESET}"
done

# Mostrar diagrama de configuración
echo -e "\n┌─────────────────── Diagrama de Configuración L2L ───────────────────┐"
echo "│                                                                   │"
for ((i=0; i<3; i++)); do
    echo "│  \${L2L_NAMES[\$i]}: [\${L2L_IFACES[\$i]}]                                      │"
done
echo "│                                                                   │"
echo "│ Cada interfaz puede configurarse independientemente con:        │"
echo "│ - Latencia (delay)                                               │"
echo "│ - Jitter (variación de latencia)                                │"
echo "│ - Pérdida de paquetes (loss)                                     │"
echo "└───────────────────────────────────────────────────────────────────┘"

# Integración con Telegram
echo -e "\n┌─────────────────── Integración con Telegram ───────────────┐"
echo "│ Configura la integración con Telegram (opcional):         │"
read -p "[ENTRADA] ¿Integrar con Telegram Bot? (s/n) [predeterminado n]: " telegram_choice
telegram_choice=\${telegram_choice:-n}
if [ "\$telegram_choice" = "s" ]; then
    read -p "[ENTRADA] Ingresa el token del Bot de Telegram: " TELEGRAM_TOKEN
    if [ -z "$TELEGRAM_TOKEN" ]; then
        log_message "ERROR" "Token de Telegram no proporcionado."
        echo -e "${COLOR_ERROR}Se requiere un token de Telegram válido.\${COLOR_RESET}"
        exit 1
    fi
    read -p "[ENTRADA] Ingresa el Chat ID (deja vacío para obtenerlo automáticamente): " TELEGRAM_CHAT_ID
    if [ -z "\$TELEGRAM_CHAT_ID" ]; then
        log_message "INFO" "Chat ID no proporcionado. Configura manualmente en \$CONFIG_FILE."
        TELEGRAM_CHAT_ID=""
    fi
    TELEGRAM_ENABLED=true
    log_message "DEBUG" "Telegram habilitado: Token=\$TELEGRAM_TOKEN, Chat ID=\$TELEGRAM_CHAT_ID"
else
    TELEGRAM_ENABLED=false
    TELEGRAM_TOKEN=""
    TELEGRAM_CHAT_ID=""
    log_message "DEBUG" "Telegram deshabilitado."
fi

# SECCIÓN 4: Configuración de Reglas de Red
# -------------------------------------
log_message "INFO" "Configurando reglas de red..."
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
log_message "OK" "IP forwarding habilitado."

# Limpiar reglas anteriores
sudo iptables -F
sudo iptables -t nat -F
log_message "OK" "Reglas de iptables limpiadas."

# Configurar reglas básicas de forwarding entre todas las interfaces L2L
for ((i=0; i<3; i++)); do
    for ((j=0; j<3; j++)); do
        if [ \$i -ne $j ]; then
            sudo iptables -A FORWARD -i "${L2L_IFACES[\$i]}" -o "\${L2L_IFACES[\$j]}" -j ACCEPT
            sudo iptables -A FORWARD -i "\${L2L_IFACES[\$j]}" -o "\${L2L_IFACES[\$i]}" -m state --state RELATED,ESTABLISHED -j ACCEPT
        fi
    done
done

# Guardar reglas de iptables
sudo iptables-save > /etc/iptables/rules.v4 2>/dev/null
log_message "OK" "Reglas de red configuradas y guardadas."

# SECCIÓN 5: Guardar Configuración
# --------------------------------
log_message "INFO" "Guardando configuración localmente..."
cat > "$CONFIG_FILE" <<EOF
TOPOLOGY=bridge_l2l
L2L_COUNT=3
EOF

for ((i=0; i<3; i++)); do
    echo "${L2L_NAMES[\$i]}=\${L2L_IFACES[\$i]}" >> "\$CONFIG_FILE"
done

cat >> "\$CONFIG_FILE" <<EOF
TELEGRAM_ENABLED=\$TELEGRAM_ENABLED
TELEGRAM_TOKEN=\$TELEGRAM_TOKEN
TELEGRAM_CHAT_ID=\$TELEGRAM_CHAT_ID
EOF

if [ \$? -eq 0 ]; then
    chmod 640 "\$CONFIG_FILE"
    log_message "OK" "Configuración guardada en \$CONFIG_FILE."
else
    log_message "ERROR" "Fallo al guardar configuración en $CONFIG_FILE."
    echo -e "${COLOR_ERROR}Fallo al guardar configuración. Revisa permisos en $USER_HOME.${COLOR_RESET}"
    exit 1
fi

# SECCIÓN 6: Despliegue del Dashboard Flask
# ----------------------------------------
log_message "INFO" "Instalando y configurando el Dashboard Flask..."
rm -f "\$WANSIM_DASHBOARD" || {
    log_message "ERROR" "No se pudo eliminar el archivo existente $WANSIM_DASHBOARD. Verifica permisos."
    echo -e "${COLOR_ERROR}No se pudo eliminar \$WANSIM_DASHBOARD. Revisa permisos con 'ls -l $WANSIM_DASHBOARD'.${COLOR_RESET}"
    exit 1
}

# Función para encontrar un puerto libre
free_port() {
    local puertos=(5000 5001 5002)
    local max_attempts=3

    for puerto in "\${puertos[@]}"; do
        DASHBOARD_PORT=\$puerto
        log_message "INFO" "Verificando puerto \$DASHBOARD_PORT..."

        for attempt in \$(seq 1 \$max_attempts); do
            log_message "DEBUG" "Intento \$attempt/\$max_attempts para puerto \$DASHBOARD_PORT..."

            local port_free=1
            if command -v lsof >/dev/null 2>&1; then
                if sudo -n lsof -i :\$DASHBOARD_PORT >/dev/null 2>&1; then
                    port_free=0
                fi
            elif command -v ss >/dev/null 2>&1; then
                if ss -tuln | grep -q ":\$DASHBOARD_PORT"; then
                    port_free=0
                fi
            elif command -v netstat >/dev/null 2>&1; then
                if netstat -tuln | grep -q ":\$DASHBOARD_PORT"; then
                    port_free=0
                fi
            fi

            if [ \$port_free -eq 1 ]; then
                log_message "OK" "Puerto \$DASHBOARD_PORT está libre."
                return 0
            else
                log_message "WARN" "Puerto $DASHBOARD_PORT en uso. Intentando liberar..."
                pids=$(sudo -n lsof -t -i :\$DASHBOARD_PORT 2>/dev/null || echo "")
                if [ -n "\$pids" ]; then
                    for pid in \$pids; do
                        sudo kill -15 "\$pid" 2>/dev/null
                        sleep 1
                        if kill -0 "\$pid" 2>/dev/null; then
                            sudo kill -9 "\$pid" 2>/dev/null
                            sleep 1
                        fi
                    done
                fi
                if [ \$attempt -eq \$max_attempts ]; then
                    log_message "DEBUG" "No se detectó actividad tras $max_attempts intentos. Asumiendo puerto libre."
                    return 0
                fi
                sleep 1
            fi
        done
    done

    log_message "ERROR" "No hay puertos disponibles (5000-5002)."
    echo -e "${COLOR_ERROR}No hay puertos disponibles. Revisa con 'sudo lsof -i :5000' y AppArmor con 'sudo aa-status'.\${COLOR_RESET}"
    exit 1
}

# Mitigar restricciones de AppArmor para lsof
log_message "DEBUG" "Mitigando restricciones de AppArmor para lsof..."
if command -v aa-complain >/dev/null 2>&1; then
    sudo aa-complain /usr/bin/lsof >/tmp/aa_error.log 2>&1
    [ \$? -eq 0 ] && log_message "DEBUG" "AppArmor en modo complain para lsof." || {
        aa_error=\$(cat /tmp/aa_error.log 2>/dev/null || echo "No se pudo leer el error")
        log_message "WARN" "Error configurando AppArmor: $aa_error"
        echo -e "${COLOR_ERROR}Fallo al configurar AppArmor. Considera deshabilitarlo con 'sudo systemctl stop apparmor'.\${COLOR_RESET}"
    }
else
    log_message "DEBUG" "aa-complain no instalado. Instala con 'sudo apt install apparmor-utils'."
fi

# Ejecutar free_port
log_message "DEBUG" "Iniciando verificación de puertos..."
free_port
log_message "DEBUG" "Puerto asignado: \$DASHBOARD_PORT"

# Generar el archivo Python para el dashboard
log_message "INFO" "Generando wansim_dashboard.py..."

# Preparar la lista de interfaces L2L para Python
PYTHON_L2L_IFACES="["
for ((i=0; i<3; i++)); do
    if [ $i -gt 0 ]; then
        PYTHON_L2L_IFACES="${PYTHON_L2L_IFACES},"
    fi
    PYTHON_L2L_IFACES="\${PYTHON_L2L_IFACES}{\n    \"name\": \"\${L2L_NAMES[\$i]}\",\n    \"iface\": \"\${L2L_IFACES[\$i]}\"\n  }"
done
PYTHON_L2L_IFACES="\${PYTHON_L2L_IFACES}\n]"

# Escribir el archivo Python del dashboard
cat > "\$WANSIM_DASHBOARD" <<EOF
# -*- coding: utf-8 -*-
from flask import Flask, request, jsonify, render_template_string
import subprocess
import time
import re
import threading
import os
import json
import logging
from OpenSSL import crypto
import ssl
import tempfile
from functools import wraps
import signal
import sys

app = Flask(__name__)
app.config['DEBUG'] = False
app.config['UPLOAD_FOLDER'] = '/tmp'
app.config['CERT_FILE'] = '/tmp/server.crt'
app.config['KEY_FILE'] = '/tmp/server.key'
app.config['TOKENS_FILE'] = '/home/axis/api_tokens.json'
SSL_ENABLED = False

# Configurar logging
logging.basicConfig(filename='/tmp/wansim_dashboard.log', level=logging.DEBUG, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

def run_command(command):
    logger.debug(f"Ejecutando comando: {command}")
    try:
        result = subprocess.run(f"sudo {command}", shell=True, check=True, capture_output=True, text=True)
        logger.debug(f"Comando exitoso: {result.stdout}")
        return True, result.stdout.strip()
    except subprocess.CalledProcessError as e:
        logger.error(f"Error en comando: {e.stderr}")
        return False, e.stderr.strip() if e.stderr else str(e)

def convert_pfx_to_pem(pfx_path, password):
    logger.debug(f"Convirtiendo PFX: {pfx_path}")
    try:
        with open(pfx_path, 'rb') as pfx_file:
            pfx_data = pfx_file.read()
        pfx = crypto.load_pkcs12(pfx_data, password.encode())
        cert = pfx.get_certificate()
        key = pfx.get_privatekey()
        with open(app.config['CERT_FILE'], 'wb') as cert_file:
            cert_file.write(crypto.dump_certificate(crypto.FILETYPE_PEM, cert))
        with open(app.config['KEY_FILE'], 'wb') as key_file:
            key_file.write(crypto.dump_privatekey(crypto.FILETYPE_PEM, key))
        logger.debug("PFX convertido exitosamente")
        return True, ""
    except crypto.Error:
        logger.error("Contraseña incorrecta o archivo PFX corrupto")
        return False, "Contraseña incorrecta o archivo PFX corrupto"
    except Exception as e:
        logger.error(f"Error convirtiendo PFX: {str(e)}")
        return False, str(e)

def get_traffic_stats(iface):
    logger.debug(f"Obteniendo estadísticas de tráfico para interfaz: {iface}")
    try:
        result = subprocess.run(f"ip -s link show {iface}", shell=True, capture_output=True, text=True)
        lines = result.stdout.splitlines()
        rx_bytes = 0
        tx_bytes = 0
        for line in lines:
            if "RX:" in line:
                rx_match = re.search(r'(\d+)\s*bytes', line)
                if rx_match:
                    rx_bytes = int(rx_match.group(1))
            if "TX:" in line:
                tx_match = re.search(r'(\d+)\s*bytes', line)
                if tx_match:
                    tx_bytes = int(tx_match.group(1))

        rx_kbps = (rx_bytes * 8) / 1000
        tx_kbps = (tx_bytes * 8) / 1000
        return {
            "kbps_in": rx_kbps,
            "kbps_out": tx_kbps,
            "mbps_in": rx_kbps / 1000,
            "mbps_out": tx_kbps / 1000,
            "kb_in": rx_bytes / 1000,
            "kb_out": tx_bytes / 1000,
            "mb_in": (rx_bytes / 1000) / 1000,
            "mb_out": (tx_bytes / 1000) / 1000
        }
    except Exception as e:
        logger.error(f"Error obteniendo estadísticas de tráfico para {iface}: {str(e)}")
        return {
            "kbps_in": 0,
            "kbps_out": 0,
            "mbps_in": 0,
            "mbps_out": 0,
            "kb_in": 0,
            "kb_out": 0,
            "mb_in": 0,
            "mb_out": 0
        }

def parse_qdisc(output):
    delay = 0
    jitter = 0
    loss = 0
    delayRegex = r'delay\s+(\d+\.?\d*)ms\s+(\d+\.?\d*)ms'
    lossRegex = r'loss\s+(\d+\.?\d*)%'
    delayMatch = re.search(delayRegex, output)
    if delayMatch:
        delay = float(delayMatch.group(1))
        jitter = float(delayMatch.group(2))
    lossMatch = re.search(lossRegex, output)
    if lossMatch:
        loss = float(lossMatch.group(1))
    logger.debug(f"Qdisc parseado: delay={delay}, jitter={jitter}, loss={loss}")
    return {"delay": delay, "jitter": jitter, "loss": loss}

def load_config():
    config = {}
    try:
        with open('/home/axis/emix_abundix.conf', 'r') as f:
            for line in f:
                if '=' in line:
                    key, value = line.strip().split('=', 1)
                    config[key] = value
        return config
    except Exception as e:
        logger.error(f"Error cargando configuración: {str(e)}")
        return {}

def load_tokens():
    try:
        with open(app.config['TOKENS_FILE'], 'r') as f:
            return json.load(f).get('tokens', [])
    except Exception as e:
        logger.error(f"Error cargando tokens: {str(e)}")
        return []

def require_api_token(required_role=None):
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            token = request.headers.get('X-API-Token')
            if not token:
                logger.error("Falta token de API")
                return jsonify({"status": "error", "message": "Falta token de API"}), 401
            tokens = load_tokens()
            user_token = next((t for t in tokens if t['token'] == token), None)
            if not user_token:
                logger.error("Token de API inválido")
                return jsonify({"status": "error", "message": "Token de API inválido"}), 401
            if required_role and user_token['role'] != required_role:
                logger.error(f"Acceso denegado: se requiere rol {required_role}")
                return jsonify({"status": "error", "message": f"Acceso denegado: se requiere rol {required_role}"}), 403
            return f(*args, **kwargs)
        return decorated_function
    return decorator

def restart_server():
    logger.info("Reiniciando servidor Flask...")
    try:
        subprocess.run("sudo systemctl restart wansim.service", shell=True, check=True)
        logger.info("Servicio systemd reiniciado exitosamente")
    except subprocess.CalledProcessError as e:
        logger.error(f"Falló el reinicio del servicio systemd: {e}")
        os.kill(os.getpid(), signal.SIGTERM)

# Cargar configuración de interfaces L2L
config = load_config()
TOPOLOGY = config.get("TOPOLOGY", "bridge_l2l")
TELEGRAM_TOKEN = config.get("TELEGRAM_TOKEN", "")
TELEGRAM_CHAT_ID = config.get("TELEGRAM_CHAT_ID", "")
TELEGRAM_ENABLED = config.get("TELEGRAM_ENABLED", "false").lower() == "true"

# Cargar interfaces L2L
L2L_INTERFACES = []
l2l_count = int(config.get("L2L_COUNT", "0"))
for i in range(1, 4):  # L2L1, L2L2, L2L3
    iface = config.get(f"L2L{i}", "")
    if iface:
        L2L_INTERFACES.append({
            "name": f"L2L{i}",
            "iface": iface
        })

# Inicializar bot de Telegram si está habilitado
if TELEGRAM_ENABLED:
    from telegram.ext import Application, CommandHandler, MessageHandler, filters
    telegram_app = Application.builder().token(TELEGRAM_TOKEN).build()
    app.telegram_bot = telegram_app

    # Comando /start
    async def start(update, context):
        await update.message.reply_text(
            "🌐 *Ryuz WAN Simulator - Bot de Control L2L*\n\n"
            "Comandos disponibles:\n"
            "/list - Lista las interfaces L2L configuradas\n"
            "/status <iface> - Muestra el estado de una interfaz (ej: /status eth1)\n"
            "/set <iface> <delay> <jitter> <loss> - Configura parámetros (ej: /set eth1 100 50 5)\n"
            "/reset <iface> - Restablece la configuración de una interfaz (ej: /reset eth1)\n"
            "/reset_all - Restablece todas las interfaces\n"
            "/help - Muestra esta ayuda"
        )

    # Comando /list
    async def list_interfaces(update, context):
        if not L2L_INTERFACES:
            await update.message.reply_text("❌ No hay interfaces L2L configuradas.")
            return
        message = "📋 *Interfaces L2L configuradas:*\n"
        for l2l in L2L_INTERFACES:
            message += f"• {l2l['name']}: {l2l['iface']}\n"
        await update.message.reply_text(message)

    # Comando /status
    async def status_interface(update, context):
        if not context.args:
            await update.message.reply_text("❌ Uso: /status <interfaz>")
            return
        iface = context.args[0]
        # Verificar si la interfaz pertenece a L2L
        l2l_found = None
        for l2l in L2L_INTERFACES:
            if l2l['iface'] == iface:
                l2l_found = l2l
                break
        if not l2l_found:
            await update.message.reply_text(f"❌ Interfaz {iface} no encontrada en la configuración L2L.")
            return

        # Obtener estado de tc qdisc
        success, output = run_command(f"tc qdisc show dev {iface}")
        if success:
            stats = parse_qdisc(output)
            message = f"📊 *Estado de {l2l_found['name']} ({iface}):*\n"
            message += f"• Latencia: {stats['delay']}ms\n"
            message += f"• Jitter: {stats['jitter']}ms\n"
            message += f"• Pérdida: {stats['loss']}%\n"
            await update.message.reply_text(message)
        else:
            await update.message.reply_text(f"❌ Error al obtener el estado de {iface}: {output}")

    # Comando /set
    async def set_params(update, context):
        if len(context.args) != 4:
            await update.message.reply_text("❌ Uso: /set <interfaz> <delay> <jitter> <loss>")
            return
        iface = context.args[0]
        try:
            delay = float(context.args[1])
            jitter = float(context.args[2])
            loss = float(context.args[3])
        except ValueError:
            await update.message.reply_text("❌ Los parámetros deben ser numéricos.")
            return

        # Verificar si la interfaz pertenece a L2L
        l2l_found = None
        for l2l in L2L_INTERFACES:
            if l2l['iface'] == iface:
                l2l_found = l2l
                break
        if not l2l_found:
            await update.message.reply_text(f"❌ Interfaz {iface} no encontrada en la configuración L2L.")
            return

        # Aplicar configuración
        run_command(f"tc qdisc del dev {iface} root netem")
        success, output = run_command(f"tc qdisc add dev {iface} root netem delay {delay}ms {jitter}ms loss {loss}%")
        if success:
            await update.message.reply_text(
                f"✅ *Configuración aplicada a {l2l_found['name']} ({iface}):*\n"
                f"• Latencia: {delay}ms\n"
                f"• Jitter: {jitter}ms\n"
                f"• Pérdida: {loss}%"
            )
        else:
            await update.message.reply_text(f"❌ Error al aplicar configuración en {iface}: {output}")

    # Comando /reset
    async def reset_interface(update, context):
        if not context.args:
            await update.message.reply_text("❌ Uso: /reset <interfaz>")
            return
        iface = context.args[0]

        # Verificar si la interfaz pertenece a L2L
        l2l_found = None
        for l2l in L2L_INTERFACES:
            if l2l['iface'] == iface:
                l2l_found = l2l
                break
        if not l2l_found:
            await update.message.reply_text(f"❌ Interfaz {iface} no encontrada en la configuración L2L.")
            return

        success, output = run_command(f"tc qdisc del dev {iface} root netem")
        if success:
            await update.message.reply_text(f"✅ Interfaz {l2l_found['name']} ({iface}) restablecida.")
        else:
            await update.message.reply_text(f"❌ Error al restablecer {iface}: {output}")

    # Comando /reset_all
    async def reset_all_interfaces(update, context):
        for l2l in L2L_INTERFACES:
            iface = l2l['iface']
            run_command(f"tc qdisc del dev {iface} root netem")
        await update.message.reply_text("✅ Todas las interfaces L2L han sido restablecidas.")

    # Comando /help
    async def help_command(update, context):
        await start(update, context)

    # Registrar comandos
    telegram_app.add_handler(CommandHandler("start", start))
    telegram_app.add_handler(CommandHandler("list", list_interfaces))
    telegram_app.add_handler(CommandHandler("status", status_interface))
    telegram_app.add_handler(CommandHandler("set", set_params))
    telegram_app.add_handler(CommandHandler("reset", reset_interface))
    telegram_app.add_handler(CommandHandler("reset_all", reset_all_interfaces))
    telegram_app.add_handler(CommandHandler("help", help_command))

    # Iniciar el bot en un hilo separado
    def run_telegram_bot():
        telegram_app.run_polling(poll_interval=1)

    telegram_thread = threading.Thread(target=run_telegram_bot, daemon=True)
    telegram_thread.start()
    logger.info("Bot de Telegram iniciado en segundo plano.")

@app.route('/api/v1/config', methods=['GET'])
@require_api_token()
def get_config():
    logger.debug("GET /api/v1/config")
    return jsonify({"status": "ok", "config": load_config()})

@app.route('/api/v1/interfaces', methods=['GET'])
@require_api_token()
def get_interfaces():
    logger.debug("GET /api/v1/interfaces")
    interfaces = []
    for l2l in L2L_INTERFACES:
        iface = l2l['iface']
        ip_result = subprocess.run(f"ip addr show {iface}", shell=True, capture_output=True, text=True)
        ip_match = re.search(r'inet (\d+\.\d+\.\d+\.\d+/\d+)', ip_result.stdout)
        ip = ip_match.group(1).split('/')[0] if ip_match else "Sin IP"
        mac = re.search(r'link/ether ([0-9a-f:]+)', ip_result.stdout)
        mac = mac.group(1) if mac else "Desconocido"
        state = re.search(r'state ([A-Z]+)', ip_result.stdout)
        state = state.group(1) if state else "UNKNOWN"
        interfaces.append({
            "name": l2l['name'],
            "interface": iface,
            "ip": ip,
            "mac": mac,
            "state": state
        })
    return jsonify({"status": "ok", "interfaces": interfaces})

@app.route('/api/v1/traffic/<iface>', methods=['GET'])
@require_api_token()
def get_traffic(iface):
    logger.debug(f"GET /api/v1/traffic/{iface}")
    # Verificar si la interfaz pertenece a L2L
    l2l_found = None
    for l2l in L2L_INTERFACES:
        if l2l['iface'] == iface:
            l2l_found = l2l
            break
    if not l2l_found:
        logger.error(f"Interfaz {iface} no encontrada en la configuración L2L.")
        return jsonify({"status": "error", "message": f"Interfaz {iface} no encontrada"}), 400

    stats = get_traffic_stats(iface)
    qdisc_success, qdisc_output = run_command(f"tc qdisc show dev {iface}")
    qdisc_stats = parse_qdisc(qdisc_output) if qdisc_success else {"delay": 0, "jitter": 0, "loss": 0}
    stats.update(qdisc_stats)
    return jsonify({"status": "ok", "stats": stats})

@app.route('/api/v1/qdisc/<iface>', methods=['POST'])
@require_api_token('admin')
def api_apply_qdisc(iface):
    logger.debug(f"POST /api/v1/qdisc/{iface}")
    data = request.json
    delay = float(data.get("delay", 0))
    jitter = float(data.get("jitter", 0))
    loss = float(data.get("loss", 0))
    if not all(isinstance(x, (int, float)) for x in [delay, jitter, loss]):
        logger.error(f"Parámetros inválidos para interfaz {iface}")
        return jsonify({"status": "error", "message": "Los parámetros deben ser numéricos"}), 400

    # Verificar si la interfaz pertenece a L2L
    l2l_found = None
    for l2l in L2L_INTERFACES:
        if l2l['iface'] == iface:
            l2l_found = l2l
            break
    if not l2l_found:
        logger.error(f"Interfaz {iface} no encontrada en la configuración L2L.")
        return jsonify({"status": "error", "message": f"Interfaz {iface} no encontrada"}), 400

    run_command(f"tc qdisc del dev {iface} root netem")
    retries = 3
    success = False
    output = ""
    for attempt in range(retries):
        success, output = run_command(f"tc qdisc add dev {iface} root netem delay {delay}ms {jitter}ms loss {loss}%")
        if success:
            break
        time.sleep(1)
    if success:
        stats = parse_qdisc(output)
        if TELEGRAM_ENABLED:
            try:
                async def send_telegram_message():
                    await app.telegram_bot.bot.send_message(
                        chat_id=TELEGRAM_CHAT_ID,
                        text=f"✅ *Configuración aplicada a {l2l_found['name']} ({iface}):*\n"
                             f"• Latencia: {delay}ms\n"
                             f"• Jitter: {jitter}ms\n"
                             f"• Pérdida: {loss}%"
                    )
                app.telegram_bot.run_async(send_telegram_message())
                logger.debug(f"Notificación de Telegram enviada para {iface}")
            except Exception as e:
                logger.error(f"Falló el envío de notificación de Telegram: {e}")
        return jsonify({"status": "ok", "stats": stats})
    logger.error(f"Error aplicando qdisc en {iface}: {output}")
    return jsonify({"status": "error", "message": f"Error aplicando qdisc en {iface}: {output}"}), 500

@app.route('/api/v1/reset/<iface>', methods=['POST'])
@require_api_token('admin')
def api_reset_qdisc(iface):
    logger.debug(f"POST /api/v1/reset/{iface}")
    # Verificar si la interfaz pertenece a L2L
    l2l_found = None
    for l2l in L2L_INTERFACES:
        if l2l['iface'] == iface:
            l2l_found = l2l
            break
    if not l2l_found:
        logger.error(f"Interfaz {iface} no encontrada en la configuración L2L.")
        return jsonify({"status": "error", "message": f"Interfaz {iface} no encontrada"}), 400

    success, output = run_command(f"tc qdisc del dev {iface} root netem")
    if success:
        if TELEGRAM_ENABLED:
            try:
                async def send_telegram_message():
                    await app.telegram_bot.bot.send_message(
                        chat_id=TELEGRAM_CHAT_ID,
                        text=f"✅ Interfaz {l2l_found['name']} ({iface}) restablecida."
                    )
                app.telegram_bot.run_async(send_telegram_message())
                logger.debug(f"Notificación de Telegram enviada para restablecimiento de {iface}")
            except Exception as e:
                logger.error(f"Falló el envío de notificación de Telegram: {e}")
        return jsonify({"status": "ok", "stats": {"delay": 0, "jitter": 0, "loss": 0}})
    return jsonify({"status": "error", "message": output}), 500

@app.route('/api/v1/reset_all', methods=['POST'])
@require_api_token('admin')
def api_reset_all():
    logger.debug("POST /api/v1/reset_all")
    messages = {}
    for l2l in L2L_INTERFACES:
        iface = l2l['iface']
        s, o = run_command(f"tc qdisc del dev {iface} root netem")
        messages[iface] = o
        if s and TELEGRAM_ENABLED:
            try:
                async def send_telegram_message():
                    await app.telegram_bot.bot.send_message(
                        chat_id=TELEGRAM_CHAT_ID,
                        text=f"✅ Interfaz {l2l['name']} ({iface}) restablecida."
                    )
                app.telegram_bot.run_async(send_telegram_message())
                logger.debug(f"Notificación de Telegram enviada para restablecimiento de {iface}")
            except Exception as e:
                logger.error(f"Falló el envío de notificación de Telegram: {e}")
    return jsonify({"status": "ok", "messages": messages})

@app.route('/get_qdisc', methods=['GET'])
def get_qdisc():
    iface = request.args.get("iface")
    logger.debug(f"GET /get_qdisc para interfaz: {iface}")
    # Verificar si la interfaz pertenece a L2L
    l2l_found = None
    for l2l in L2L_INTERFACES:
        if l2l['iface'] == iface:
            l2l_found = l2l
            break
    if not l2l_found:
        logger.error(f"Interfaz {iface} no encontrada en la configuración L2L.")
        return jsonify({"status": "error", "message": f"Interfaz {iface} no encontrada"}), 400

    success, output = run_command(f"tc qdisc show dev {iface}")
    if success:
        stats = parse_qdisc(output)
        return jsonify({"status": "ok", "stats": stats})
    return jsonify({"status": "error", "message": output}), 500

@app.route('/traffic_stats', methods=['GET'])
def traffic_stats():
    iface = request.args.get("iface")
    logger.debug(f"GET /traffic_stats para interfaz: {iface}")
    # Verificar si la interfaz pertenece a L2L
    l2l_found = None
    for l2l in L2L_INTERFACES:
        if l2l['iface'] == iface:
            l2l_found = l2l
            break
    if not l2l_found:
        logger.error(f"Interfaz {iface} no encontrada en la configuración L2L.")
        return jsonify({"status": "error", "message": f"Interfaz {iface} no encontrada"}), 400

    stats = get_traffic_stats(iface)
    qdisc_success, qdisc_output = run_command(f"tc qdisc show dev {iface}")
    qdisc_stats = parse_qdisc(qdisc_output) if qdisc_success else {"delay": 0, "jitter": 0, "loss": 0}
    stats.update(qdisc_stats)
    return jsonify({"status": "ok", "stats": stats})

@app.route('/apply_qdisc', methods=['POST'])
def apply_qdisc():
    data = request.json
    iface = data.get("iface")
    delay = float(data.get("delay", 0))
    jitter = float(data.get("jitter", 0))
    loss = float(data.get("loss", 0))
    logger.debug(f"POST /apply_qdisc para interfaz: {iface}, delay={delay}, jitter={jitter}, loss={loss}")
    if not all(isinstance(x, (int, float)) for x in [delay, jitter, loss]):
        logger.error(f"Parámetros inválidos para interfaz {iface}")
        return jsonify({"status": "error", "message": "Los parámetros deben ser numéricos"}), 400

    # Verificar si la interfaz pertenece a L2L
    l2l_found = None
    for l2l in L2L_INTERFACES:
        if l2l['iface'] == iface:
            l2l_found = l2l
            break
    if not l2l_found:
        logger.error(f"Interfaz {iface} no encontrada en la configuración L2L.")
        return jsonify({"status": "error", "message": f"Interfaz {iface} no encontrada"}), 400

    run_command(f"tc qdisc del dev {iface} root netem")
    retries = 3
    success = False
    output = ""
    for attempt in range(retries):
        success, output = run_command(f"tc qdisc add dev {iface} root netem delay {delay}ms {jitter}ms loss {loss}%")
        if success:
            break
        time.sleep(1)
    if success:
        stats = parse_qdisc(output)
        if TELEGRAM_ENABLED:
            try:
                async def send_telegram_message():
                    await app.telegram_bot.bot.send_message(
                        chat_id=TELEGRAM_CHAT_ID,
                        text=f"✅ *Configuración aplicada a {l2l_found['name']} ({iface}):*\n"
                             f"• Latencia: {delay}ms\n"
                             f"• Jitter: {jitter}ms\n"
                             f"• Pérdida: {loss}%"
                    )
                app.telegram_bot.run_async(send_telegram_message())
                logger.debug(f"Notificación de Telegram enviada para {iface}")
            except Exception as e:
                logger.error(f"Falló el envío de notificación de Telegram: {e}")
        return jsonify({"status": "ok", "stats": stats})
    logger.error(f"Error aplicando qdisc en {iface}: {output}")
    return jsonify({"status": "error", "message": f"Error aplicando qdisc en {iface}: {output}"}), 500

@app.route('/reset_qdisc', methods=['POST'])
def reset_qdisc():
    data = request.json
    iface = data.get("iface")
    logger.debug(f"POST /reset_qdisc para interfaz: {iface}")
    # Verificar si la interfaz pertenece a L2L
    l2l_found = None
    for l2l in L2L_INTERFACES:
        if l2l['iface'] == iface:
            l2l_found = l2l
            break
    if not l2l_found:
        logger.error(f"Interfaz {iface} no encontrada en la configuración L2L.")
        return jsonify({"status": "error", "message": f"Interfaz {iface} no encontrada"}), 400

    success, output = run_command(f"tc qdisc del dev {iface} root netem")
    if success:
        if TELEGRAM_ENABLED:
            try:
                async def send_telegram_message():
                    await app.telegram_bot.bot.send_message(
                        chat_id=TELEGRAM_CHAT_ID,
                        text=f"✅ Interfaz {l2l_found['name']} ({iface}) restablecida."
                    )
                app.telegram_bot.run_async(send_telegram_message())
                logger.debug(f"Notificación de Telegram enviada para restablecimiento de {iface}")
            except Exception as e:
                logger.error(f"Falló el envío de notificación de Telegram: {e}")
        return jsonify({"status": "ok", "stats": {"delay": 0, "jitter": 0, "loss": 0}})
    return jsonify({"status": "error", "message": output}), 500

@app.route('/reset_all', methods=['POST'])
def reset_all():
    logger.debug("POST /reset_all")
    messages = {}
    for l2l in L2L_INTERFACES:
        iface = l2l['iface']
        s, o = run_command(f"tc qdisc del dev {iface} root netem")
        messages[iface] = o
        if s and TELEGRAM_ENABLED:
            try:
                async def send_telegram_message():
                    await app.telegram_bot.bot.send_message(
                        chat_id=TELEGRAM_CHAT_ID,
                        text=f"✅ Interfaz {l2l['name']} ({iface}) restablecida."
                    )
                app.telegram_bot.run_async(send_telegram_message())
                logger.debug(f"Notificación de Telegram enviada para restablecimiento de {iface}")
            except Exception as e:
                logger.error(f"Falló el envío de notificación de Telegram: {e}")
    return jsonify({"status": "ok", "messages": messages})

@app.route('/upload_pfx', methods=['GET', 'POST'])
def upload_pfx():
    global SSL_ENABLED
    if request.method == 'POST':
        logger.debug("POST /upload_pfx recibido")
        if 'pfx_file' not in request.files or 'password' not in request.form:
            logger.error("Falta archivo PFX o contraseña")
            return render_template_string("""
                <div class='alert alert-danger'>Falta archivo PFX o contraseña.</div>
                <a href='/upload_pfx'>Volver</a>
            """), 400
        pfx_file = request.files['pfx_file']
        password = request.form['password']
        if pfx_file.filename == '':
            logger.error("No se seleccionó archivo PFX")
            return render_template_string("""
                <div class='alert alert-danger'>No se seleccionó archivo.</div>
                <a href='/upload_pfx'>Volver</a>
            """), 400
        if pfx_file:
            pfx_path = os.path.join(app.config['UPLOAD_FOLDER'], 'server.pfx')
            pfx_file.save(pfx_path)
            success, result = convert_pfx_to_pem(pfx_path, password)
            os.remove(pfx_path)
            if success:
                SSL_ENABLED = True
                logger.info("Certificado PFX cargado exitosamente")
                threading.Timer(2, restart_server).start()
                return render_template_string("""
                    <!DOCTYPE html>
                    <html lang='es'>
                    <head>
                        <meta charset='UTF-8'>
                        <meta name='viewport' content='width=device-width, initial-scale=1.0'>
                        <title>Certificado Cargado - Ryuz WAN Simulator</title>
                        <link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'>
                        <style>
                            body { background: linear-gradient(135deg, #1e3c72, #2a5298); color: white; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; font-family: 'Arial', sans-serif; }
                            .container { text-align: center; background: rgba(255, 255, 255, 0.1); padding: 40px; border-radius: 15px; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2); backdrop-filter: blur(10px); }
                            .spinner { border: 4px solid rgba(255, 255, 255, 0.3); border-top: 4px solid #ffffff; border-radius: 50%; width: 40px; height: 40px; animation: spin 1s linear infinite; margin: 20px auto; }
                            @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
                        </style>
                    </head>
                    <body>
                        <div class='container'>
                            <h1 class='mb-4'>Certificado PFX Cargado</h1>
                            <p>El servidor se está reiniciando para habilitar SSL...</p>
                            <div class='spinner'></div>
                            <p>Redirigiendo al dashboard HTTPS en 5 segundos...</p>
                            <a href='https://{{ host }}:{{ port }}/' class='btn btn-primary mt-3'>Ir al Dashboard</a>
                        </div>
                        <script src='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js'></script>
                        <script>
                            setTimeout(() => {
                                window.location.href = 'https://{{ host }}:{{ port }}/';
                            }, 5000);
                        </script>
                    </body>
                    </html>
                """, host=request.host.split(':')[0], port=DASHBOARD_PORT)
            else:
                logger.error(f"Error procesando PFX: {result}")
                return render_template_string("""
                    <div class='alert alert-danger'>Error procesando PFX: {{ result }}</div>
                    <a href='/upload_pfx'>Volver</a>
                """, result=result), 400
    return render_template_string("""
        <!DOCTYPE html>
        <html lang='es'>
        <head>
            <meta charset='UTF-8'>
            <meta name='viewport' content='width=device-width, initial-scale=1.0'>
            <title>Cargar Certificado PFX - Ryuz WAN Simulator</title>
            <link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'>
            <style>
                body { background: linear-gradient(135deg, #1e3c72, #2a5298); color: white; min-height: 100vh; display: flex; align-items: center; font-family: 'Arial', sans-serif; }
                .container { background: rgba(255, 255, 255, 0.1); padding: 40px; border-radius: 15px; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2); backdrop-filter: blur(10px); max-width: 600px; }
                .form-control, .btn { transition: all 0.3s ease; }
                .btn-primary:hover { background-color: #0056b3; transform: translateY(-2px); }
                .form-label { font-weight: bold; }
            </style>
        </head>
        <body>
            <div class='container'>
                <h1 class='text-center mb-4'>Cargar Certificado PFX</h1>
                <form method='post' enctype='multipart/form-data'>
                    <div class='mb-3'>
                        <label for='pfx_file' class='form-label'>Seleccionar archivo PFX:</label>
                        <input type='file' class='form-control' id='pfx_file' name='pfx_file' accept='.pfx'>
                    </div>
                    <div class='mb-3'>
                        <label for='password' class='form-label'>Contraseña PFX:</label>
                        <input type='password' class='form-control' id='password' name='password'>
                    </div>
                    <button type='submit' class='btn btn-primary w-100'>Cargar Certificado</button>
                </form>
                <a href='/' class='btn btn-secondary w-100 mt-3'>Volver al Dashboard</a>
            </div>
            <script src='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js'></script>
        </body>
        </html>
    """)

@app.route('/')
def dashboard():
    global SSL_ENABLED
    protocol = 'https' if SSL_ENABLED else 'http'
    logger.debug(f"Renderizando dashboard, protocolo: {protocol}")

    return render_template_string("""
    <!DOCTYPE html>
    <html lang='es'>
    <head>
        <meta charset='UTF-8'>
        <meta name='viewport' content='width=device-width, initial-scale=1.0'>
        <title>Ryuz WAN Simulator - Dashboard (Modo L2L)</title>
        <link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'>
        <script src='https://cdn.jsdelivr.net/npm/chart.js'></script>
        <style>
            body {
                background: linear-gradient(135deg, #1e3c72, #2a5298);
                color: white;
                min-height: 100vh;
                font-family: 'Arial', sans-serif;
            }
            .container {
                max-width: 1200px;
                padding: 20px;
            }
            .card {
                background: rgba(255, 255, 255, 0.1);
                border: none;
                border-radius: 15px;
                box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
                backdrop-filter: blur(10px);
                transition: transform 0.3s ease;
                margin-bottom: 20px;
            }
            .card:hover {
                transform: translateY(-5px);
            }
            .btn {
                transition: all 0.3s ease;
                margin: 5px;
            }
            .btn:hover {
                transform: translateY(-2px);
            }
            .form-control, .form-select {
                background: rgba(255, 255, 255, 0.2);
                color: white;
                border: none;
            }
            .form-control:focus, .form-select:focus {
                background: rgba(255, 255, 255, 0.3);
                color: white;
                box-shadow: none;
            }
            .chart-container {
                position: relative;
                height: 200px;
            }
            .output {
                background: rgba(0, 0, 0, 0.3);
                padding: 10px;
                border-radius: 5px;
            }
            .l2l-header {
                background: rgba(0, 0, 0, 0.3);
                padding: 15px;
                border-radius: 10px;
                margin-bottom: 15px;
                text-align: center;
                font-weight: bold;
                font-size: 1.2em;
            }
            .diagram-container {
                background: rgba(0, 0, 0, 0.2);
                padding: 20px;
                border-radius: 10px;
                margin-bottom: 20px;
                text-align: center;
            }
            .diagram-box {
                background: rgba(255, 255, 255, 0.2);
                padding: 10px 20px;
                border-radius: 5px;
                margin: 10px;
                min-width: 120px;
                text-align: center;
                display: inline-block;
            }
            @media (max-width: 576px) {
                .container {
                    padding: 10px;
                }
                .card {
                    margin-bottom: 15px;
                }
                .btn {
                    font-size: 0.9rem;
                }
                .form-control, .form-select {
                    font-size: 0.9rem;
                }
            }
        </style>
    </head>
    <body>
        <div class='container'>
            <h1 class='text-center mb-4'>Ryuz WAN Simulator (Modo L2L)</h1>

            <!-- Diagrama de configuración -->
            <div class='diagram-container'>
                <h3>Interfaces L2L Configuradas</h3>
                {% for l2l in interfaces %}
                <div class='diagram-box'>{{ l2l.name }}: {{ l2l.iface }}</div>
                {% endfor %}
            </div>

            <!-- Información de Telegram -->
            {% if telegram_enabled %}
            <div class='alert alert-info' role='alert'>
                <h4 class='alert-heading'>Bot de Telegram Activo</h4>
                <p>Puedes controlar las interfaces L2L con el bot de Telegram. Usa los siguientes comandos:</p>
                <ul>
                    <li><code>/list</code> - Lista las interfaces L2L configuradas</li>
                    <li><code>/status &lt;iface&gt;</code> - Muestra el estado de una interfaz (ej: /status eth1)</li>
                    <li><code>/set &lt;iface&gt; &lt;delay&gt; &lt;jitter&gt; &lt;loss&gt;</code> - Configura parámetros (ej: /set eth1 100 50 5)</li>
                    <li><code>/reset &lt;iface&gt;</code> - Restablece una interfaz (ej: /reset eth1)</li>
                    <li><code>/reset_all</code> - Restablece todas las interfaces</li>
                </ul>
            </div>
            {% endif %}

            <div class='d-flex justify-content-center mb-4'>
                <button class='btn btn-primary mx-2' onclick='resetAll()'>Restablecer Todas las Interfaces</button>
                <a href='/upload_pfx' class='btn btn-secondary mx-2'>Cargar Certificado PFX</a>
                <select id='unit-select' class='form-select w-auto mx-2' onchange='updateUnit()'>
                    <option value='mbps'>Mbps</option>
                    <option value='kbps'>Kbps</option>
                    <option value='mb'>MB</option>
                    <option value='kb'>KB</option>
                </select>
            </div>

            {% for l2l in interfaces %}
            <div class='l2l-header'>
                {{ l2l.name }}: Interfaz {{ l2l.iface }}
            </div>
            <div class='row'>
                <div class='col-md-12 mb-4'>
                    <div class='card p-4'>
                        <div class='mb-3'>
                            <label class='form-label'>Latencia (ms):</label>
                            <input type='number' class='form-control' id='delay-{{ l2l.iface }}' value='0' min='0' step='0.1'>
                        </div>
                        <div class='mb-3'>
                            <label class='form-label'>Jitter (ms):</label>
                            <input type='number' class='form-control' id='jitter-{{ l2l.iface }}' value='0' min='0' step='0.1'>
                        </div>
                        <div class='mb-3'>
                            <label class='form-label'>Pérdida (%):</label>
                            <input type='number' class='form-control' id='loss-{{ l2l.iface }}' value='0' min='0' max='100' step='0.1'>
                        </div>
                        <div class='d-flex justify-content-center mb-3'>
                            <button class='btn btn-primary btn-sm' onclick='applyQdisc("{{ l2l.iface }}")'>Aplicar</button>
                            <button class='btn btn-warning btn-sm' onclick='resetQdisc("{{ l2l.iface }}")'>Restablecer</button>
                            <button class='btn btn-info btn-sm' onclick='getQdisc("{{ l2l.iface }}")'>Obtener</button>
                        </div>
                        <div class='mb-3'>
                            <label class='form-label'>Latencia Rápida:</label>
                            <div class='d-flex'>
                                <button class='btn btn-outline-light btn-sm mx-1' onclick='quickDelay("{{ l2l.iface }}", 100)'>100ms</button>
                                <button class='btn btn-outline-light btn-sm mx-1' onclick='quickDelay("{{ l2l.iface }}", 300)'>300ms</button>
                                <button class='btn btn-outline-light btn-sm mx-1' onclick='quickDelay("{{ l2l.iface }}", 500)'>500ms</button>
                            </div>
                        </div>
                        <div class='mb-3'>
                            <label class='form-label'>Jitter Rápido:</label>
                            <div class='d-flex'>
                                <button class='btn btn-outline-light btn-sm mx-1' onclick='quickJitter("{{ l2l.iface }}", 50)'>50ms</button>
                                <button class='btn btn-outline-light btn-sm mx-1' onclick='quickJitter("{{ l2l.iface }}", 100)'>100ms</button>
                                <button class='btn btn-outline-light btn-sm mx-1' onclick='quickJitter("{{ l2l.iface }}", 200)'>200ms</button>
                            </div>
                        </div>
                        <div class='mb-3'>
                            <label class='form-label'>Pérdida Rápida:</label>
                            <div class='d-flex'>
                                <button class='btn btn-outline-light btn-sm mx-1' onclick='quickLoss("{{ l2l.iface }}", 1)'>1%</button>
                                <button class='btn btn-outline-light btn-sm mx-1' onclick='quickLoss("{{ l2l.iface }}", 5)'>5%</button>
                                <button class='btn btn-outline-light btn-sm mx-1' onclick='quickLoss("{{ l2l.iface }}", 10)'>10%</button>
                            </div>
                        </div>
                        <div class='chart-container'>
                            <canvas id='traffic-chart-{{ l2l.iface }}'></canvas>
                        </div>
                        <pre class='output mt-3' id='output-{{ l2l.iface }}'></pre>
                    </div>
                </div>
            </div>
            {% endfor %}
        </div>
        <script>
            const charts = {};
            let currentUnit = 'mbps';
            const baseUrl = window.location.origin;
            const telegramEnabled = {{ 'true' if telegram_enabled else 'false' }};

            function updateUnit() {
                currentUnit = document.getElementById('unit-select').value;
                {% for l2l in interfaces %}
                updateTrafficChart('{{ l2l.iface }}');
                {% endfor %}
            }

            function getTrafficStats(iface) {
                fetch(baseUrl + '/traffic_stats?iface=' + iface)
                .then(r => r.json())
                .then(data => {
                    if (data.status === 'ok') {
                        const stats = data.stats;
                        document.getElementById('delay-' + iface).value = stats.delay;
                        document.getElementById('jitter-' + iface).value = stats.jitter;
                        document.getElementById('loss-' + iface).value = stats.loss;
                        document.getElementById('output-' + iface).innerText =
                            'Ancho de Banda Entrada: ' + stats[currentUnit + '_in'].toFixed(2) + ' ' + currentUnit + '\\n' +
                            'Ancho de Banda Salida: ' + stats[currentUnit + '_out'].toFixed(2) + ' ' + currentUnit + '\\n' +
                            'Latencia: ' + stats.delay.toFixed(2) + ' ms\\n' +
                            'Jitter: ' + stats.jitter.toFixed(2) + ' ms\\n' +
                            'Pérdida: ' + stats.loss.toFixed(2) + ' %';
                        updateTrafficChart(iface, stats);
                    } else {
                        console.error('Error en traffic_stats:', data.message);
                        document.getElementById('output-' + iface).innerText = data.message;
                    }
                })
                .catch(err => console.error('Error obteniendo estadísticas de tráfico:', err));
            }

            function updateTrafficChart(iface, stats) {
                const ctx = document.getElementById('traffic-chart-' + iface).getContext('2d');
                const labels = ['Entrada', 'Salida', 'Latencia', 'Jitter', 'Pérdida'];
                const data = [
                    stats[currentUnit + '_in'],
                    stats[currentUnit + '_out'],
                    stats.delay,
                    stats.jitter,
                    stats.loss
                ];
                const units = currentUnit === 'mbps' || currentUnit === 'kbps' ? ' (' + currentUnit.toUpperCase() + ')' : ' (' + currentUnit.toUpperCase() + '/s)';
                if (charts[iface]) {
                    charts[iface].data.datasets[0].data = data;
                    charts[iface].data.labels = labels.map(label => label + (label.includes('Entrada') || label.includes('Salida') ? units : label.includes('Latencia') || label.includes('Jitter') ? ' (ms)' : ' (%)'));
                    charts[iface].update();
                } else {
                    charts[iface] = new Chart(ctx, {
                        type: 'bar',
                        data: {
                            labels: labels.map(label => label + (label.includes('Entrada') || label.includes('Salida') ? units : label.includes('Latencia') || label.includes('Jitter') ? ' (ms)' : ' (%)')),
                            datasets: [{
                                label: iface,
                                data: data,
                                backgroundColor: [
                                    'rgba(255, 99, 132, 0.4)',
                                    'rgba(54, 162, 235, 0.4)',
                                    'rgba(255, 206, 86, 0.4)',
                                    'rgba(75, 192, 192, 0.4)',
                                    'rgba(153, 102, 255, 0.4)'
                                ],
                                borderColor: [
                                    'rgba(255, 99, 132, 1)',
                                    'rgba(54, 162, 235, 1)',
                                    'rgba(255, 206, 86, 1)',
                                    'rgba(75, 192, 192, 1)',
                                    'rgba(153, 102, 255, 1)'
                                ],
                                borderWidth: 1
                            }]
                        },
                        options: {
                            scales: {
                                y: {
                                    beginAtZero: true
                                }
                            },
                            animation: {
                                duration: 1000,
                                easing: 'easeInOutQuad'
                            }
                        }
                    });
                }
            }

            function getQdisc(iface) {
                fetch(baseUrl + '/get_qdisc?iface=' + iface)
                .then(r => r.json())
                .then(data => {
                    if (data.status === 'ok') {
                        const stats = data.stats;
                        document.getElementById('delay-' + iface).value = stats.delay;
                        document.getElementById('jitter-' + iface).value = stats.jitter;
                        document.getElementById('loss-' + iface).value = stats.loss;
                        document.getElementById('output-' + iface).innerText =
                            'Latencia: ' + stats.delay.toFixed(2) + ' ms\\n' +
                            'Jitter: ' + stats.jitter.toFixed(2) + ' ms\\n' +
                            'Pérdida: ' + stats.loss.toFixed(2) + ' %';
                        getTrafficStats(iface);
                    } else {
                        console.error('Error en get_qdisc:', data.message);
                        document.getElementById('output-' + iface).innerText = data.message;
                    }
                })
                .catch(err => console.error('Error obteniendo qdisc:', err));
            }

            function applyQdisc(iface) {
                const delay = parseFloat(document.getElementById('delay-' + iface).value) || 0;
                const jitter = parseFloat(document.getElementById('jitter-' + iface).value) || 0;
                const loss = parseFloat(document.getElementById('loss-' + iface).value) || 0;
                fetch(baseUrl + '/apply_qdisc', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({ iface, delay, jitter, loss })
                })
                .then(r => r.json())
                .then(data => {
                    if (data.status === 'ok') {
                        alert('Configuración aplicada en ' + iface + ': Latencia=' + data.stats.delay + 'ms, Jitter=' + data.stats.jitter + 'ms, Pérdida=' + data.stats.loss + '%');
                        getTrafficStats(iface);
                    } else {
                        alert('Error aplicando en ' + iface + ': ' + data.message);
                    }
                })
                .catch(err => console.error('Error aplicando qdisc:', err));
            }

            function resetQdisc(iface) {
                fetch(baseUrl + '/reset_qdisc', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({ iface })
                })
                .then(r => r.json())
                .then(data => {
                    if (data.status === 'ok') {
                        alert('Interfaz restablecida en ' + iface + ': Latencia=' + data.stats.delay + 'ms, Jitter=' + data.stats.jitter + 'ms, Pérdida=' + data.stats.loss + '%');
                        document.getElementById('output-' + iface).innerText = '';
                        document.getElementById('delay-' + iface).value = data.stats.delay;
                        document.getElementById('jitter-' + iface).value = data.stats.jitter;
                        document.getElementById('loss-' + iface).value = data.stats.loss;
                        getTrafficStats(iface);
                    } else {
                        alert('Error restableciendo en ' + iface + ': ' + data.message);
                    }
                })
                .catch(err => console.error('Error restableciendo qdisc:', err));
            }

            function resetAll() {
                fetch(baseUrl + '/reset_all', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'}
                })
                .then(r => r.json())
                .then(data => {
                    alert('Restablecimiento de todas las interfaces completado.');
                    {% for l2l in interfaces %}
                    document.getElementById('output-{{ l2l.iface }}').innerText = '';
                    document.getElementById('delay-{{ l2l.iface }}').value = 0;
                    document.getElementById('jitter-{{ l2l.iface }}').value = 0;
                    document.getElementById('loss-{{ l2l.iface }}').value = 0;
                    getTrafficStats('{{ l2l.iface }}');
                    {% endfor %}
                })
                .catch(err => console.error('Error restableciendo todo:', err));
            }

            function quickDelay(iface, value) {
                document.getElementById('delay-' + iface).value = value;
                applyQdisc(iface);
            }
            function quickJitter(iface, value) {
                document.getElementById('jitter-' + iface).value = value;
                applyQdisc(iface);
            }
            function quickLoss(iface, value) {
                document.getElementById('loss-' + iface).value = value;
                applyQdisc(iface);
            }

            window.onload = function() {
                {% for l2l in interfaces %}
                getTrafficStats('{{ l2l.iface }}');
                {% endfor %}
            };

            setInterval(() => {
                {% for l2l in interfaces %}
                getTrafficStats('{{ l2l.iface }}');
                {% endfor %}
            }, 1000);
        </script>
    </body>
    </html>
    """, interfaces=L2L_INTERFACES, telegram_enabled=TELEGRAM_ENABLED, protocol=protocol)

if __name__ == "__main__":
    logger.info("Iniciando servidor Flask...")
    if SSL_ENABLED and os.path.exists(app.config['CERT_FILE']) and os.path.exists(app.config['KEY_FILE']):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(app.config['CERT_FILE'], app.config['KEY_FILE'])
        logger.info("Iniciando en modo HTTPS")
        app.run(host="0.0.0.0", port=DASHBOARD_PORT, ssl_context=context)
    else:
        logger.info("Iniciando en modo HTTP")
        app.run(host="0.0.0.0", port=DASHBOARD_PORT)
EOF

# Configurar permisos
log_message "DEBUG" "Configurando permisos para \$WANSIM_DASHBOARD..."
chmod 640 "\$WANSIM_DASHBOARD" || {
    log_message "ERROR" "No se pudo establecer permisos para $WANSIM_DASHBOARD."
    echo -e "${COLOR_ERROR}No se pudo establecer permisos. Revisa con 'ls -l $WANSIM_DASHBOARD'.${COLOR_RESET}"
    exit 1
}
chown "\$CURRENT_USER:\$CURRENT_USER" "\$WANSIM_DASHBOARD" || {
    log_message "ERROR" "No se pudo cambiar propietario de $WANSIM_DASHBOARD."
    echo -e "${COLOR_ERROR}No se pudo cambiar propietario. Revisa con 'ls -l $WANSIM_DASHBOARD'.${COLOR_RESET}"
    exit 1
}
log_message "OK" "wansim_dashboard.py generado."

# Configurar servicio systemd
log_message "DEBUG" "Configurando servicio systemd..."
sudo bash -c "cat > \$SERVICE_FILE" <<EOF
[Unit]
Description=Ryuz WAN Simulator Dashboard (L2L)
After=network.target

[Service]
User=\$CURRENT_USER
WorkingDirectory=\$USER_HOME
ExecStart=/usr/bin/python3 \$WANSIM_DASHBOARD
Restart=always

[Install]
WantedBy=multi-user.target
EOF
[ \$? -eq 0 ] || {
    log_message "ERROR" "No se pudo crear $SERVICE_FILE."
    echo -e "${COLOR_ERROR}No se pudo crear $SERVICE_FILE. Revisa permisos en /etc/systemd/system/.${COLOR_RESET}"
    exit 1
}

# Intentar iniciar con systemd
log_message "INFO" "Intentando iniciar wansim.service con systemd..."
sudo systemctl daemon-reload && sudo systemctl enable wansim.service && sudo systemctl start wansim.service
systemd_status=\$?
if [ \$systemd_status -eq 0 ]; then
    log_message "OK" "wansim.service iniciado con systemd."
else
    log_message "WARN" "Fallo al iniciar wansim.service con systemd (status: \$systemd_status). Intentando nohup..."
    # Fallback a nohup
    nohup python3 "\$WANSIM_DASHBOARD" >> /tmp/wansim_dashboard.log 2>&1 &
    nohup_pid=\$!
    sleep 2
    if kill -0 \$nohup_pid 2>/dev/null; then
        log_message "OK" "Flask iniciado con nohup (PID: \$nohup_pid)."
    else
        log_message "WARN" "Fallo al iniciar con nohup. Intentando flask run..."
        # Fallback a flask run
        export FLASK_APP="\$WANSIM_DASHBOARD"
        nohup flask run --host=0.0.0.0 --port=\$DASHBOARD_PORT >> /tmp/wansim_dashboard.log 2>&1 &
        flask_pid=\$!
        sleep 2
        if kill -0 \$flask_pid 2>/dev/null; then
            log_message "OK" "Flask iniciado con flask run (PID: $flask_pid)."
        else
            log_message "ERROR" "No se pudo iniciar Flask con flask run."
            echo -e "${COLOR_ERROR}Fallo al iniciar Flask. Revisa /tmp/wansim_dashboard.log:\${COLOR_RESET}"
