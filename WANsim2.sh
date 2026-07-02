## SECCIÓN 1: Comienzo
# -----------------------------------------------
#!/bin/bash

set -e

# Asegurar que se use bash explícitamente
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

# Redirigir salida y errores al log (compatible con bash)
exec > >(tee -a /tmp/wansim_debug.log) 2>&1

# SECCIÓN 1: Configuración Inicial y Funciones Auxiliares
# -----------------------------------------------
# Variables de configuración
USER_HOME=$(eval echo ~$(whoami))
LOGFILE="${USER_HOME}/emix_abundix.log"
CONFIG_FILE="${USER_HOME}/emix_abundix.conf"
WANSIM_DASHBOARD="${USER_HOME}/wansim_dashboard.py"
API_TOKENS="${USER_HOME}/api_tokens.json"
SERVICE_FILE="/etc/systemd/system/wansim.service"
CURRENT_USER=$(whoami)
DASHBOARD_PORT=5000
HOST_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
IS_RASPBERRY=$(grep -qi "Raspberry Pi" /proc/cpuinfo && echo "sí" || echo "no")

# Colores para la salida en consola
COLOR_INFO=$(tput setaf 6)
COLOR_OK=$(tput setaf 2)
COLOR_ERROR=$(tput setaf 1)
COLOR_WARN=$(tput setaf 3)
COLOR_DEBUG=$(tput setaf 4)
COLOR_GREEN=$(tput setaf 2)
COLOR_CYAN=$(tput setaf 6)
COLOR_RESET=$(tput sgr0)

# Función para registrar mensajes
log_message() {
    local tipo_msg="$1"
    local contenido_msg="$2"
    local marca_tiempo=$(date '+%Y-%m-%d %H:%M:%S')
    local linea=$(caller 0 | awk '{print $1}')
    local mensaje_completo="[$marca_tiempo] [$tipo_msg] Línea $linea: $contenido_msg"
    echo "$mensaje_completo" >> "/tmp/wansim_debug.log"
    case "$tipo_msg" in
        INFO) echo "${COLOR_INFO}[INFO] $contenido_msg${COLOR_RESET}" ;;
        OK) echo "${COLOR_OK}[OK] $contenido_msg${COLOR_RESET}" ;;
        ERROR) echo "${COLOR_ERROR}[ERROR] $contenido_msg${COLOR_RESET}" ;;
        ADVERTENCIA) echo "${COLOR_WARN}[ADVERTENCIA] $contenido_msg${COLOR_RESET}" ;;
        DEBUG) echo "${COLOR_DEBUG}[DEBUG] $contenido_msg${COLOR_RESET}" ;;
    esac
}

# Configuración del archivo de log principal
if [ -f "$LOGFILE" ]; then
    if ! sudo rm -f "$LOGFILE"; then
        log_message "ERROR" "No se pudo eliminar el archivo de log existente $LOGFILE."
        echo "${COLOR_ERROR}No se pudo eliminar $LOGFILE. Revisa permisos con 'ls -l $LOGFILE'.${COLOR_RESET}"
        exit 1
    fi
fi

if ! touch "$LOGFILE"; then
    log_message "ERROR" "No se pudo crear el archivo de log $LOGFILE."
    echo "${COLOR_ERROR}No se pudo crear $LOGFILE. Revisa permisos con 'ls -ld $USER_HOME'.${COLOR_RESET}"
    exit 1
fi

if ! chmod 640 "$LOGFILE"; then
    log_message "ERROR" "No se pudieron establecer permisos para $LOGFILE."
    echo "${COLOR_ERROR}No se pudieron establecer permisos para $LOGFILE.${COLOR_RESET}"
    exit 1
fi

if ! chown "$CURRENT_USER:$CURRENT_USER" "$LOGFILE"; then
    log_message "ERROR" "No se pudo cambiar el propietario de $LOGFILE."
    echo "${COLOR_ERROR}No se pudo cambiar el propietario de $LOGFILE.${COLOR_RESET}"
    exit 1
fi

# Redefinir log_message para usar LOGFILE
log_message() {
    local tipo_msg="$1"
    local contenido_msg="$2"
    local marca_tiempo=$(date '+%Y-%m-%d %H:%M:%S')
    local linea=$(caller 0 | awk '{print $1}')
    local mensaje_completo="[$marca_tiempo] [$tipo_msg] Línea $linea: $contenido_msg"
    echo "$mensaje_completo" >> "$LOGFILE"
    chmod 640 "$LOGFILE" 2>/dev/null || true
    chown "$CURRENT_USER:$CURRENT_USER" "$LOGFILE" 2>/dev/null || true
    case "$tipo_msg" in
        INFO) echo "${COLOR_INFO}[INFO] $contenido_msg${COLOR_RESET}" ;;
        OK) echo "${COLOR_OK}[OK] $contenido_msg${COLOR_RESET}" ;;
        ERROR) echo "${COLOR_ERROR}[ERROR] $contenido_msg${COLOR_RESET}" ;;
        ADVERTENCIA) echo "${COLOR_WARN}[ADVERTENCIA] $contenido_msg${COLOR_RESET}" ;;
        DEBUG) echo "${COLOR_DEBUG}[DEBUG] $contenido_msg${COLOR_RESET}" ;;
    esac
}

# Función de limpieza
cleanup() {
    log_message "INFO" "Iniciando limpieza de archivos generados..."
    local archivos=("$CONFIG_FILE" "$WANSIM_DASHBOARD" "$API_TOKENS" "$LOGFILE" "/tmp/wansim_debug.log" "/tmp/server.crt" "/tmp/server.key")
    for archivo in "${archivos[@]}"; do
        if [ -f "$archivo" ]; then
            if ! shred -u "$archivo" 2>/dev/null; then
                rm -f "$archivo" 2>/dev/null
            fi
            [ ! -f "$archivo" ] && log_message "OK" "Eliminado $archivo" || log_message "ERROR" "No se pudo eliminar $archivo"
        fi
    done
    if [ -f "/tmp/wansim_dashboard.log" ]; then
        if ! sudo rm -f "/tmp/wansim_dashboard.log"; then
            log_message "ERROR" "No se pudo eliminar /tmp/wansim_dashboard.log."
            echo "${COLOR_ERROR}No se pudo eliminar /tmp/wansim_dashboard.log. Revisa permisos con 'ls -l /tmp/wansim_dashboard.log'.${COLOR_RESET}"
        else
            log_message "OK" "Eliminado /tmp/wansim_dashboard.log"
        fi
    fi
    if ! sudo rm -f "$SERVICE_FILE" 2>/dev/null; then
        log_message "ERROR" "No se pudo eliminar $SERVICE_FILE"
    else
        log_message "OK" "Eliminado $SERVICE_FILE"
    fi
    log_message "OK" "Limpieza completada."
    echo "${COLOR_OK}✔ Todos los archivos generados han sido eliminados${COLOR_RESET}"
}

# Función para liberar puertos
free_port() {
    local puertos=(5000 5001 5002)
    for puerto in "${puertos[@]}"; do
        DASHBOARD_PORT=$puerto
        log_message "INFO" "Verificando puerto $DASHBOARD_PORT..."
        local pid
        if command -v ss >/dev/null 2>&1; then
            pid=$(ss -tuln | grep ":$DASHBOARD_PORT" | awk '{print $NF}' | head -n 1)
        elif command -v lsof >/dev/null 2>&1; then
            pid=$(sudo lsof -t -i :$DASHBOARD_PORT 2>/dev/null)
        else
            log_message "ERROR" "No se encontraron ss ni lsof. No se puede verificar el puerto."
            return 1
        fi
        if [ -n "$pid" ]; then
            log_message "INFO" "Puerto $DASHBOARD_PORT en uso por PID $pid. Intentando terminar..."
            sudo kill -15 "$pid" 2>/dev/null
            sleep 1
            if kill -0 "$pid" 2>/dev/null; then
                log_message "ADVERTENCIA" "PID $pid no terminó. Forzando terminación..."
                sudo kill -9 "$pid" 2>/dev/null
                sleep 1
            fi
            if ! ss -tuln | grep -q ":$DASHBOARD_PORT"; then
                log_message "OK" "Puerto $DASHBOARD_PORT liberado."
                return 0
            fi
        else
            log_message "OK" "Puerto $DASHBOARD_PORT está libre."
            return 0
        fi
    done
    log_message "ERROR" "No hay puertos disponibles (5000-5002). Saliendo."
    echo "${COLOR_ERROR}No hay puertos disponibles para el dashboard.${COLOR_RESET}"
    exit 1
}

# Intentar detener cualquier proceso en el puerto 5000
log_message "INFO" "Intentando liberar el puerto 5000..."
for attempt in {1..20}; do
    pid=$(sudo fuser 5000/tcp 2>/dev/null | awk '{print $1}')
    if [ -n "$pid" ]; then
        log_message "INFO" "Terminando proceso $pid en puerto 5000..."
        sudo kill -9 "$pid" 2>/dev/null
        sleep 1
    else
        log_message "OK" "Puerto 5000 liberado."
        break
    fi
    if [ "$attempt" -eq 20 ]; then
        log_message "ERROR" "No se pudo liberar el puerto 5000 después de 20 intentos."
        echo "${COLOR_ERROR}No se pudo liberar el puerto 5000 después de 20 intentos.${COLOR_RESET}"
        echo "Intenta manualmente con 'sudo fuser -k 5000/tcp'."
        exit 1
    fi
done

# Función para obtener el Chat ID de Telegram
get_telegram_chat_id() {
    local token="$1"
    log_message "INFO" "Intentando obtener el Chat ID de Telegram automáticamente..."
    local attempts=0
    local max_attempts=5
    while [ $attempts -lt $max_attempts ]; do
        response=$(curl -s "https://api.telegram.org/bot${token}/getUpdates")
        TELEGRAM_CHAT_ID=$(python3 -c "import sys, json; data=json.load(sys.stdin); print(data['result'][-1]['message']['chat']['id']) if data.get('result') else print('')" <<< "$response")
        if [ -n "$TELEGRAM_CHAT_ID" ]; then
            log_message "OK" "Chat ID obtenido: $TELEGRAM_CHAT_ID"
            return 0
        else
            log_message "ADVERTENCIA" "No se obtuvo Chat ID, reintentando..."
            sleep 2
            attempts=$((attempts+1))
        fi
    done
    log_message "ERROR" "No se pudo obtener el Chat ID tras $max_attempts intentos."
    exit 1
}


# SECCIÓN 2: Verificaciones Iniciales y Banner
# -----------------------------------------------
log_message "DEBUG" "Verificando permisos de usuario..."
log_message "INFO" "Verificando permisos de usuario..."

# Asegurar que el script sea ejecutable
if ! chmod +x "$0"; then
    log_message "ERROR" "No se pudo hacer el script ejecutable."
    echo "${COLOR_ERROR}Fallo al establecer permisos ejecutables para $0. Revisa con 'ls -l $0'.${COLOR_RESET}"
    exit 1
fi
log_message "OK" "Permisos ejecutables establecidos para $0."

if [ "$(id -u)" -eq 0 ]; then
    log_message "ERROR" "Este script no debe ejecutarse como root."
    echo "${COLOR_ERROR}Por favor, ejecuta el script como usuario normal (e.g., axis):${COLOR_RESET}"
    echo "${COLOR_ERROR}  ./$(basename "$0")${COLOR_RESET}"
    exit 1
fi
log_message "OK" "Ejecutando como usuario $CURRENT_USER."

# Configurar permisos de sudo para el usuario actual
log_message "DEBUG" "Configurando permisos de sudo para $CURRENT_USER..."
SUDOERS_FILE="/etc/sudoers.d/wansim"
SUDOERS_CONTENT="$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/sbin/tc, /usr/bin/systemctl stop unattended-upgrades, /usr/bin/systemctl restart wansim.service, /usr/bin/fuser, /usr/bin/kill, /usr/bin/rm, /usr/sbin/dpkg"
if ! sudo -n true 2>/dev/null; then
    log_message "INFO" "Configurando permisos de sudo automáticamente..."
    # Intentar configurar sudoers usando una contraseña temporal o existente
    if ! echo "$SUDOERS_CONTENT" | sudo -S tee "$SUDOERS_FILE" >/dev/null 2>&1; then
        log_message "ERROR" "No se pudo configurar permisos de sudo. Se requiere intervención manual."
        echo "${COLOR_ERROR}Por favor, configura permisos de sudo para $CURRENT_USER en $SUDOERS_FILE con el siguiente contenido:${COLOR_RESET}"
        echo "${COLOR_ERROR}$SUDOERS_CONTENT${COLOR_RESET}"
        echo "${COLOR_ERROR}Usa 'sudo visudo -f $SUDOERS_FILE' para editar.${COLOR_RESET}"
        exit 1
    fi
    sudo chmod 440 "$SUDOERS_FILE"
    log_message "OK" "Permisos de sudo configurados automáticamente."
else
    # Verificar si el archivo sudoers ya existe y tiene el contenido correcto
    if [ -f "$SUDOERS_FILE" ] && grep -Fx "$SUDOERS_CONTENT" "$SUDOERS_FILE" >/dev/null; then
        log_message "OK" "Permisos de sudo ya configurados."
    else
        if ! echo "$SUDOERS_CONTENT" | sudo tee "$SUDOERS_FILE" >/dev/null; then
            log_message "ERROR" "No se pudo actualizar el archivo sudoers $SUDOERS_FILE."
            echo "${COLOR_ERROR}Fallo al configurar permisos de sudo. Revisa con 'sudo visudo -f $SUDOERS_FILE'.${COLOR_RESET}"
            exit 1
        fi
        sudo chmod 440 "$SUDOERS_FILE"
        log_message "OK" "Permisos de sudo actualizados."
    fi
fi

# Actualizar repositorios
log_message "INFO" "Actualizando lista de paquetes del sistema..."
if ! sudo apt-get update; then
    log_message "ERROR" "No se pudo actualizar la lista de paquetes."
    echo "${COLOR_ERROR}No se pudo conectar con los servidores de paquetes. Verifica tu conexión a internet.${COLOR_RESET}"
    exit 1
fi
log_message "OK" "Lista de paquetes actualizada."

# Verificar e instalar dependencias del sistema
# Pre-configurar respuestas para iptables-persistent para evitar ventanas de confirmación
log_message "INFO" "Pre-configurando respuestas para iptables-persistent..."
if command -v debconf-set-selections >/dev/null 2>&1; then
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | sudo debconf-set-selections 2>/dev/null
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | sudo debconf-set-selections 2>/dev/null
    log_message "OK" "Respuestas para iptables-persistent pre-configuradas."
else
    log_message "ADVERTENCIA" "debconf-set-selections no disponible. Se intentará configurar manualmente."
fi

log_message "DEBUG" "Verificando e instalando dependencias..."
DEPENDENCIES=("python3" "python3-pip" "iproute2" "ifstat" "qrencode" "net-tools" "vlan" "sudo" "lsof" "isc-dhcp-server" "iptables-persistent")
LOCK_FILES=("/var/lib/dpkg/lock-frontend" "/var/lib/apt/lists/lock" "/var/cache/apt/archives/lock")
for dep in "${DEPENDENCIES[@]}"; do
    if ! dpkg -l | grep -qw "$dep"; then
        log_message "INFO" "Instalando $dep..."
        # Intentar liberar bloqueos de apt/dpkg
        MAX_WAIT=300  # Máximo 5 minutos
        WAIT_INTERVAL=10
        ELAPSED=0
        BLOCKED=false
        for lock in "${LOCK_FILES[@]}"; do
            if [ -e "$lock" ]; then
                BLOCKED=true
                break
            fi
        done
        if [ "$BLOCKED" = true ]; then
            log_message "INFO" "Se detectó un proceso instalando actualizaciones. Preparando sistema..."
            sudo systemctl stop unattended-upgrades 2>/dev/null
            for lock in "${LOCK_FILES[@]}"; do
                if [ -e "$lock" ]; then
                    BLOCKING_PID=$(sudo fuser "$lock" 2>/dev/null | awk '{print $1}')
                    if [ -n "$BLOCKING_PID" ]; then
                        log_message "INFO" "Terminando proceso $BLOCKING_PID que bloquea $lock..."
                        sudo kill -9 "$BLOCKING_PID" 2>/dev/null
                    fi
                    sudo rm -f "$lock"
                fi
            done
            sudo dpkg --configure -a
            if ! sudo apt-get update; then
                log_message "ERROR" "No se pudo actualizar la lista de paquetes tras liberar bloqueos."
                echo "${COLOR_ERROR}Fallo al preparar el sistema. Intenta de nuevo más tarde.${COLOR_RESET}"
                exit 1
            fi
            log_message "OK" "Sistema preparado tras liberar bloqueos."
        fi
        if ! sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$dep"; then
            log_message "ERROR" "No se pudo instalar $dep."
            echo "${COLOR_ERROR}No se pudo instalar $dep. Verifica tu conexión a internet o intenta de nuevo.${COLOR_RESET}"
            exit 1
        fi
        log_message "OK" "$dep instalado."
        # Configurar iptables-persistent automáticamente si es el paquete instalado
        if [ "$dep" = "iptables-persistent" ]; then
            log_message "INFO" "Configurando iptables-persistent automáticamente..."
            sudo mkdir -p /etc/iptables
            if [ ! -f /etc/iptables/rules.v4 ]; then
                sudo touch /etc/iptables/rules.v4
                sudo chmod 644 /etc/iptables/rules.v4
            fi
            if [ ! -f /etc/iptables/rules.v6 ]; then
                sudo touch /etc/iptables/rules.v6
                sudo chmod 644 /etc/iptables/rules.v6
            fi
            sudo iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
            sudo ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
            log_message "OK" "iptables-persistent configurado automáticamente."
        fi
    else
        log_message "OK" "$dep ya está instalado."
    fi
done

# Asegurar que pip3 esté en el PATH
export PATH="$HOME/.local/bin:$PATH"

# Verificar que pip3 esté disponible
if ! command -v pip3 >/dev/null 2>&1; then
    log_message "ERROR" "No se encontró pip3 tras instalar python3-pip."
    echo "${COLOR_ERROR}No se pudo configurar el instalador de paquetes de Python. Intenta reinstalar con 'sudo apt-get install python3-pip'.${COLOR_RESET}"
    exit 1
fi
log_message "OK" "pip3 encontrado en $(which pip3)."

# Instalando dependencias de Python
log_message "DEBUG" "Instalando dependencias de Python..."
PYTHON_DEPS=("flask" "requests" "python-telegram-bot" "pyOpenSSL")
for dep in "${PYTHON_DEPS[@]}"; do
    if ! pip3 show "$dep" >/dev/null 2>&1; then
        log_message "INFO" "Instalando $dep..."
        if ! pip3 install --user "$dep" --no-warn-script-location; then
            log_message "ERROR" "Falló la instalación de $dep."
            echo "${COLOR_ERROR}No se pudo instalar $dep. Revisa con 'pip3 install $dep'.${COLOR_RESET}"
            exit 1
        fi
        log_message "OK" "$dep instalado."
    else
        log_message "OK" "$dep ya está instalado."
    fi
done
log_message "OK" "Dependencias de Python instaladas."

# Mostrar banner
log_message "DEBUG" "Iniciando configuración interactiva de Ryuz WAN Simulator..."
clear
cat << 'EOF'
┌═════════════════════════════════════════════════════════════┐
│                                                             │
│  Ryuz WAN Simulator - Versión 1.100                         │
│  Solución Empresarial para Simulación de Redes WAN          │
│  Créditos: decameru@outlook.com                             │
│  Ejecutando en Linux                                        │
│                                                             │
└═════════════════════════════════════════════════════════════┘
EOF

# Preguntar si se desea eliminar archivos generados previamente
echo "┌─────────────────── Limpieza de Archivos ───────────────────┐"
echo "│ ¿Deseas eliminar archivos generados previamente?           │"
echo "│ (s/n) [predeterminado n]                                  │"
echo "└───────────────────────────────────────────────────────────┘"
read -p "Selecciona: " limpiar
limpiar=${limpiar:-n}
if [[ "$limpiar" =~ ^[sS]$ ]]; then
    cleanup
    echo "${COLOR_OK}✔ Limpieza completada. Continuando con la configuración...${COLOR_RESET}"
fi



# SECCIÓN 3: Instalación de Dependencias
# --------------------------------------
log_message "DEBUG" "Verificando e instalando dependencias..."
echo "${COLOR_CYAN}┌─────────────────── Instalando Dependencias ────────────────┐${COLOR_RESET}"
echo "${COLOR_CYAN}│ Instalando paquetes requeridos...                         │${COLOR_RESET}"
echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"
DEPENDENCIES=("python3" "python3-pip" "iproute2" "ifstat" "qrencode" "net-tools" "vlan" "sudo" "lsof" "isc-dhcp-server" "iptables-persistent")
for dep in "${DEPENDENCIES[@]}"; do
    echo -n "${COLOR_INFO}Instalando $dep...${COLOR_RESET}"
    if ! command -v "$dep" >/dev/null 2>&1 && ! dpkg -l | grep -q "$dep"; then
        log_message "INFO" "$dep no está instalado. Instalando automáticamente..."
        if ! sudo apt-get update && sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$dep" >/tmp/install_$dep.log 2>&1; then
            log_message "ERROR" "Falló la instalación de $dep. Detalles en /tmp/install_$dep.log."
            echo "${COLOR_ERROR} [✗]${COLOR_RESET}"
            exit 1
        fi
        log_message "OK" "$dep instalado."
        echo "${COLOR_OK} [✔]${COLOR_RESET}"
    else
        log_message "OK" "$dep ya está instalado."
        echo "${COLOR_OK} [✔]${COLOR_RESET}"
    fi
done

# Instalación de dependencias de Python
log_message "DEBUG" "Instalando dependencias de Python..."
echo "${COLOR_INFO}Instalando dependencias de Python...${COLOR_RESET}"
pip3 install --user --break-system-packages flask requests python-telegram-bot==20.7 pyOpenSSL --no-warn-script-location || {
    log_message "ERROR" "Falló la instalación de dependencias de Python."
    echo "${COLOR_ERROR} [✗]${COLOR_RESET}"
    exit 1
}
log_message "OK" "Dependencias de Python instaladas."
echo "${COLOR_OK} [✔] Dependencias de Python instaladas${COLOR_RESET}"

export PATH="$HOME/.local/bin:$PATH"

# SECCIÓN 4: Configuración Interactiva
# ------------------------------------
log_message "DEBUG" "Iniciando configuración interactiva de Ryuz WAN Simulator..."
echo "${COLOR_CYAN}┌─────────────────── Configuración Interactiva ──────────────┐${COLOR_RESET}"
echo "${COLOR_CYAN}│ Por favor, ingresa los parámetros solicitados a continuación │${COLOR_RESET}"
echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"

if [ -f "$CONFIG_FILE" ] && [ -z "$FORCE_INTERACTIVE" ]; then
    echo "${COLOR_CYAN}┌─────────────────── Configuración Previa ───────────────────┐${COLOR_RESET}"
    echo "${COLOR_CYAN}│ Se detectó una configuración previa.                      │${COLOR_RESET}"
    echo "${COLOR_CYAN}│  r) Reutilizar configuración existente                    │${COLOR_RESET}"
    echo "${COLOR_CYAN}│  c) Configurar nuevo modo de operación                    │${COLOR_RESET}"
    echo "${COLOR_CYAN}│  s) Salir                                                │${COLOR_RESET}"
    echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"
    read -p "${COLOR_INFO}[ENTRADA] Selecciona una opción [r/c/s, predeterminado r]: ${COLOR_RESET}" REINSTALL_OPTION
    REINSTALL_OPTION=${REINSTALL_OPTION:-r}
    case "$REINSTALL_OPTION" in
        r) log_message "INFO" "Reutilizando configuración existente."; source "$CONFIG_FILE"; INTERACTIVE=0 ;;
        c) log_message "INFO" "Configurando nuevo modo de operación."; INTERACTIVE=1 ;;
        s) log_message "INFO" "Saliendo por elección del usuario."; echo "${COLOR_INFO}Ejecución terminada.${COLOR_RESET}"; exit 0 ;;
        *) log_message "ADVERTENCIA" "Opción inválida. Reutilizando configuración predeterminada."; source "$CONFIG_FILE"; INTERACTIVE=0 ;;
    esac
else
    INTERACTIVE=1
fi

if [ "$INTERACTIVE" -eq 1 ]; then
    echo "${COLOR_CYAN}┌─────────────────── Topología de Red ───────────────────────┐${COLOR_RESET}"
    echo "${COLOR_CYAN}│ Selecciona la topología de red:                           │${COLOR_RESET}"
    echo "${COLOR_CYAN}│  1) NAT único (salida a Internet)                        │${COLOR_RESET}"
    echo "${COLOR_CYAN}│  2) Puente LAN-to-LAN (peer-to-peer)                     │${COLOR_RESET}"
    echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"
    while true; do
        read -p "${COLOR_INFO}[ENTRADA] Opción [1-2, predeterminado 1]: ${COLOR_RESET}" TOPOLOGY
        TOPOLOGY=${TOPOLOGY:-1}
        case "$TOPOLOGY" in
            1) TOPOLOGY_MODE="nat"; break ;;
            2) TOPOLOGY_MODE="bridge"; break ;;
            *) log_message "ERROR" "Opción inválida. Ingresa 1 o 2." ;;
        esac
    done
    echo ""

    if [ "$TOPOLOGY_MODE" = "bridge" ]; then
        echo "${COLOR_CYAN}┌─────────────────── Interfaces de Red ─────────────────────┐${COLOR_RESET}"
        echo "${COLOR_CYAN}│ Interfaces de red disponibles en el sistema local:       │${COLOR_RESET}"
        DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -n 1)
        VALID_INTERFACES=()
        while IFS= read -r iface; do
            if ip link show "$iface" >/dev/null 2>&1; then
                VALID_INTERFACES+=("$iface")
                IP_ADDR=$(ip addr show "$iface" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
                MAC_ADDR=$(ip link show "$iface" | grep link/ether | awk '{print $2}')
                if [ -n "$IP_ADDR" ]; then
                    echo "${COLOR_GREEN}  - $iface (IP: $IP_ADDR, MAC: $MAC_ADDR)${COLOR_RESET}"
                else
                    echo "${COLOR_GREEN}  - $iface (Sin IP, MAC: $MAC_ADDR)${COLOR_RESET}"
                fi
                if [ "$iface" = "$DEFAULT_IF" ]; then
                    echo "${COLOR_CYAN}    Salida a Internet detectada${COLOR_RESET}"
                fi
            fi
        done < <(ip link show | grep '^[0-9]' | awk '{print $2}' | sed 's/://' | grep -v '@')
        echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] Ingresa la interfaz LAN: ${COLOR_RESET}" LAN_IF
            if [[ -n "$LAN_IF" && " ${VALID_INTERFACES[*]} " =~ " $LAN_IF " ]]; then
                log_message "OK" "Interfaz $LAN_IF válida en el sistema local."
                break
            else
                log_message "ERROR" "Interfaz $LAN_IF no encontrada o inválida. Selecciona una interfaz válida."
            fi
        done
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] Ingresa la interfaz de destino (salida): ${COLOR_RESET}" DEST_IF
            if [[ -n "$DEST_IF" && " ${VALID_INTERFACES[*]} " =~ " $DEST_IF " && "$DEST_IF" != "$LAN_IF" ]]; then
                log_message "OK" "Interfaz $DEST_IF válida en el sistema local."
                break
            else
                log_message "ERROR" "Interfaz $DEST_IF no encontrada, inválida o igual a LAN ($LAN_IF)."
            fi
        done
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] ¿Es la interfaz de destino ($DEST_IF) la interfaz de gestión con salida a Internet? (s/n) [predeterminado n]: ${COLOR_RESET}" IS_MGMT
            IS_MGMT=${IS_MGMT:-n}
            if [[ "$IS_MGMT" =~ ^[sSnN]$ ]]; then
                IS_MGMT=$(echo "$IS_MGMT" | tr '[:upper:]' '[:lower:]')
                break
            else
                log_message "ERROR" "Ingresa 's' o 'n'."
            fi
        done
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] ¿Aplicar control de tráfico (latencia, jitter, pérdida) en el puente? (s/n) [predeterminado n]: ${COLOR_RESET}" CONFIG_TC
            CONFIG_TC=${CONFIG_TC:-n}
            if [[ "$CONFIG_TC" =~ ^[sSnN]$ ]]; then
                CONFIG_TC=$(echo "$CONFIG_TC" | tr '[:upper:]' '[:lower:]')
                break
            else
                log_message "ERROR" "Ingresa 's' o 'n'."
            fi
        done
    else
        echo "${COLOR_CYAN}┌─────────────────── Configuración de VLANs ─────────────────┐${COLOR_RESET}"
        echo "${COLOR_CYAN}│ En este contexto, cada VLAN representa un enlace simulado │${COLOR_RESET}"
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] ¿Cuántos enlaces (VLANs) simular? [predeterminado 10]: ${COLOR_RESET}" NUM_VLANS
            NUM_VLANS=${NUM_VLANS:-10}
            if [[ "$NUM_VLANS" =~ ^[1-9][0-9]*$ ]]; then
                break
            else
                log_message "ERROR" "Ingresa un número válido."
            fi
        done
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] ¿Deseas definir los IDs de VLANs manualmente? (s/n) [predeterminado n]: ${COLOR_RESET}" define_vlans
            define_vlans=${define_vlans:-n}
            if [[ "$define_vlans" =~ ^[sSnN]$ ]]; then
                define_vlans=$(echo "$define_vlans" | tr '[:upper:]' '[:lower:]')
                if [[ "$define_vlans" =~ ^[sS]$ ]]; then
                    while true; do
                        read -p "${COLOR_INFO}[ENTRADA] Ingresa el ID inicial para las VLANs (1-4094): ${COLOR_RESET}" START_VLAN
                        if [[ "$START_VLAN" =~ ^[0-9]+$ && "$START_VLAN" -ge 1 && "$START_VLAN" -le 4094 ]]; then
                            break
                        else
                            log_message "ERROR" "ID inválido. Debe estar entre 1 y 4094."
                        fi
                    done
                else
                    START_VLAN=100
                    log_message "INFO" "Usando ID de VLAN predeterminado: $START_VLAN"
                fi
                break
            else
                log_message "ERROR" "Ingresa 's' o 'n'."
            fi
        done
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] ¿Configurar DHCP? (s/n) [predeterminado s]: ${COLOR_RESET}" CONFIG_DHCP
            CONFIG_DHCP=${CONFIG_DHCP:-s}
            if [[ "$CONFIG_DHCP" =~ ^[sSnN]$ ]]; then
                CONFIG_DHCP=$(echo "$CONFIG_DHCP" | tr '[:upper:]' '[:lower:]')
                break
            else
                log_message "ERROR" "Ingresa 's' o 'n'."
            fi
        done
        if [ "$CONFIG_DHCP" = "s" ]; then
            echo "${COLOR_CYAN}┌─────────────────── Segmento de Red ────────────────────────┐${COLOR_RESET}"
            echo "${COLOR_CYAN}│ Selecciona el segmento base para las VLANs:               │${COLOR_RESET}"
            echo "${COLOR_CYAN}│  1) 10.254.X.0/24                                        │${COLOR_RESET}"
            echo "${COLOR_CYAN}│  2) 172.16.X.0/24                                        │${COLOR_RESET}"
            echo "${COLOR_CYAN}│  3) 192.168.X.0/24                                       │${COLOR_RESET}"
            echo "${COLOR_CYAN}│  4) Custom (ingresar manualmente)                         │${COLOR_RESET}"
            echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"
            while true; do
                read -p "${COLOR_INFO}[ENTRADA] Opción [1-4, predeterminado 3]: ${COLOR_RESET}" SEGMENT_OPTION
                SEGMENT_OPTION=${SEGMENT_OPTION:-3}
                case "$SEGMENT_OPTION" in
                    1) SEGMENT_PREFIX="10.254"; break ;;
                    2) SEGMENT_PREFIX="172.16"; break ;;
                    3) SEGMENT_PREFIX="192.168"; break ;;
                    4)
                        while true; do
                            read -p "${COLOR_INFO}[ENTRADA] Ingresa el segmento base (ej: 192.168): ${COLOR_RESET}" custom_segment
                            if [[ "$custom_segment" =~ ^[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                                SEGMENT_PREFIX="$custom_segment"
                                log_message "OK" "Segmento base personalizado configurado: $SEGMENT_PREFIX.X.0/24"
                                break
                            else
                                log_message "ERROR" "Formato inválido. Usa el formato X.X (ej: 192.168)."
                            fi
                        done
                        break ;;
                    *) log_message "ERROR" "Opción inválida. Ingresa 1, 2, 3 o 4." ;;
                esac
            done
            echo "${COLOR_CYAN}┌─────────────────── Dirección IP ───────────────────────────┐${COLOR_RESET}"
            echo "${COLOR_CYAN}│ El tercer octeto define la subred de la VLAN en la IP.    │${COLOR_RESET}"
            echo "${COLOR_CYAN}│ Ejemplo: Para $SEGMENT_PREFIX.X.0/24, un tercer octeto de │${COLOR_RESET}"
            echo "${COLOR_CYAN}│ 10 genera direcciones como $SEGMENT_PREFIX.10.1 para la   │${COLOR_RESET}"
            echo "${COLOR_CYAN}│ primera VLAN, etc.                                        │${COLOR_RESET}"
            echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"
            while true; do

# Menú Principal
if [ "$INTERACTIVE" -eq 1 ]; then
    echo "${COLOR_CYAN}┌─────────────────── Menú Principal ───────────────────────┐${COLOR_RESET}"
    echo "${COLOR_CYAN}│ Selecciona una opción:                                  │${COLOR_RESET}"
    echo "${COLOR_CYAN}│  1) L3                                               │${COLOR_RESET}"
    echo "${COLOR_CYAN}│  2) Opción 2                                          │${COLOR_RESET}"
    echo "${COLOR_CYAN}│  3) Opción 3                                          │${COLOR_RESET}"
    echo "${COLOR_CYAN}│  4) Bridge                                            │${COLOR_RESET}"
    echo "${COLOR_CYAN}│  5) Salir                                             │${COLOR_RESET}"
    echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"
    read -p "Selecciona una opción: " main_option
    case $main_option in
        1) l3_menu ;;
        4) bridge_menu ;;
        5) exit 0 ;;
        *) echo "${COLOR_ERROR}Opción inválida${COLOR_RESET}" ;;
    esac
fi


# Función para el menú Bridge
function bridge_menu() {
    echo "${COLOR_CYAN}┌─────────────────── Interfaces de Bridge ─────────────────────┐${COLOR_RESET}"
    echo "${COLOR_CYAN}│ Interfaces disponibles:                                │${COLOR_RESET}"

    # Mostrar interfaces con MAC address
    ip -o link show | awk -F': ' '{print \$2, \$NF}' | grep -v lo | while read -r iface mac; do
        echo "${COLOR_GREEN}  - $iface (MAC: $mac)${COLOR_RESET}"
    done

    read -p "${COLOR_INFO}[ENTRADA] Selecciona la interfaz a intervenir: ${COLOR_RESET}" selected_iface

    if ! ip link show "\$selected_iface" &>/dev/null; then
        log_message "ERROR" "Interfaz $selected_iface no existe."
        return 1
    fi

    read -p "${COLOR_INFO}[ENTRADA] ¿Cuántas interfaces deseas configurar (1-3)? ${COLOR_RESET}" num_ifaces
    if [[ ! "\$num_ifaces" =~ ^[1-3]$ ]]; then
        log_message "ERROR" "Debes seleccionar entre 1 y 3 interfaces."
        return 1
    fi

    echo "$selected_iface" > /tmp/bridge_interfaces.txt
    log_message "OK" "Interfaces seleccionadas para Bridge: $(cat /tmp/bridge_interfaces.txt)"
    echo "${COLOR_OK}Espera los parámetros desde Flask o Telegram...${COLOR_RESET}"
}

                read -p "${COLOR_INFO}[ENTRADA] Ingresa el tercer octeto inicial para las VLANs (1-254) [predeterminado 10]: ${COLOR_RESET}" BASE_OCTET
                BASE_OCTET=${BASE_OCTET:-10}
                if [[ "$BASE_OCTET" =~ ^[0-9]+$ && "$BASE_OCTET" -ge 1 && "$BASE_OCTET" -le 254 ]]; then
                    break
                else
                    log_message "ERROR" "Ingresa un número válido entre 1 y 254."
                fi
            done
        fi
        echo "${COLOR_CYAN}┌─────────────────── Interfaces de Red ─────────────────────┐${COLOR_RESET}"
        echo "${COLOR_CYAN}│ Interfaces de red disponibles en el sistema local:       │${COLOR_RESET}"
        DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -n 1)
        VALID_INTERFACES=()
        while IFS= read -r iface; do
            if ip link show "$iface" >/dev/null 2>&1; then
                VALID_INTERFACES+=("$iface")
                IP_ADDR=$(ip addr show "$iface" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
                MAC_ADDR=$(ip link show "$iface" | grep link/ether | awk '{print $2}')
                if [ -n "$IP_ADDR" ]; then
                    echo "${COLOR_GREEN}  - $iface (IP: $IP_ADDR, MAC: $MAC_ADDR)${COLOR_RESET}"
                else
                    echo "${COLOR_GREEN}  - $iface (Sin IP, MAC: $MAC_ADDR)${COLOR_RESET}"
                fi
                if [ "$iface" = "$DEFAULT_IF" ]; then
                    echo "${COLOR_CYAN}    Salida a Internet detectada${COLOR_RESET}"
                fi
            fi
        done < <(ip link show | grep '^[0-9]' | awk '{print $2}' | sed 's/://' | grep -v '@')
        echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] Ingresa la interfaz WAN: ${COLOR_RESET}" WAN_IF
            if [[ -n "$WAN_IF" && " ${VALID_INTERFACES[*]} " =~ " $WAN_IF " ]]; then
                log_message "OK" "Interfaz $WAN_IF válida en el sistema local."
                break
            else
                log_message "ERROR" "Interfaz $WAN_IF no encontrada o inválida. Selecciona una interfaz válida."
            fi
        done
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] Ingresa la interfaz LAN (para VLANs y DHCP): ${COLOR_RESET}" LAN_IF
            if [[ -n "$LAN_IF" && " ${VALID_INTERFACES[*]} " =~ " $LAN_IF " && "$LAN_IF" != "$WAN_IF" ]]; then
                log_message "OK" "Interfaz $LAN_IF válida en el sistema local."
                break
            else
                log_message "ERROR" "Interfaz $LAN_IF no encontrada, inválida o igual a WAN ($WAN_IF)."
            fi
        done
    fi
    echo "${COLOR_CYAN}┌─────────────────── Integración con Telegram ───────────────┐${COLOR_RESET}"
    echo "${COLOR_CYAN}│ Configura la integración con Telegram (opcional):         │${COLOR_RESET}"
    while true; do
        read -p "${COLOR_INFO}[ENTRADA] ¿Integrar con Telegram Bot para actualizaciones de parámetros? (s/n) [predeterminado n]: ${COLOR_RESET}" INTEGRATE_TELEGRAM
        INTEGRATE_TELEGRAM=${INTEGRATE_TELEGRAM:-n}
        if [[ "$INTEGRATE_TELEGRAM" =~ ^[sSnN]$ ]]; then
            INTEGRATE_TELEGRAM=$(echo "$INTEGRATE_TELEGRAM" | tr '[:upper:]' '[:lower:]')
            break
        else
            log_message "ERROR" "Ingresa 's' o 'n'."
        fi
    done
    if [ "$INTEGRATE_TELEGRAM" = "s" ]; then
        read -p "${COLOR_INFO}[ENTRADA] Ingresa el token del Bot de Telegram: ${COLOR_RESET}" TELEGRAM_TOKEN
        read -p "${COLOR_INFO}[ENTRADA] Ingresa el Chat ID (deja vacío para obtenerlo automáticamente): ${COLOR_RESET}" TELEGRAM_CHAT_ID
        if [ -z "$TELEGRAM_CHAT_ID" ]; then
            get_telegram_chat_id "$TELEGRAM_TOKEN"
        fi
    else
        TELEGRAM_TOKEN=""
        TELEGRAM_CHAT_ID=""
    fi
    echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"
fi

# SECCIÓN 5: Configuración de Red
# -------------------------------
# Configurar VLANs, NAT, DHCP o puente según la topología seleccionada
if [ "$TOPOLOGY_MODE" = "nat" ]; then
    log_message "INFO" "Configurando VLANs en $LAN_IF..."

    # Verificar que la interfaz LAN_IF exista y esté activa
    if ! ip link show "$LAN_IF" >/dev/null 2>&1; then
        log_message "ERROR" "La interfaz $LAN_IF no existe o no está disponible."
        echo "${COLOR_ERROR}La interfaz $LAN_IF no está disponible. Revisa con 'ip link'.${COLOR_RESET}"
        exit 1
    fi
    if ! ip link show "$LAN_IF" | grep -q "UP"; then
        log_message "INFO" "La interfaz $LAN_IF no está activa. Intentando activarla..."
        sudo ip link set "$LAN_IF" up >/dev/null 2>&1
        sleep 2
        if ! ip link show "$LAN_IF" | grep -q "UP"; then
            log_message "ERROR" "No se pudo activar la interfaz $LAN_IF."
            echo "${COLOR_ERROR}No se pudo activar la interfaz $LAN_IF. Revisa con 'ip link'.${COLOR_RESET}"
            exit 1
        fi
    fi

    # Cargar el módulo 8021q para soporte de VLANs
    if ! lsmod | grep -q "8021q"; then
        log_message "INFO" "Cargando módulo 8021q para soporte de VLANs..."
        sudo modprobe 8021q >/dev/null 2>&1
        if ! lsmod | grep -q "8021q"; then
            log_message "ERROR" "No se pudo cargar el módulo 8021q. Soporte de VLANs no disponible."
            echo "${COLOR_ERROR}Soporte de VLANs no disponible. Instala el módulo 8021q.${COLOR_RESET}"
            exit 1
        fi
        log_message "OK" "Módulo 8021q cargado."
    fi

   # Función genérica y robusta para restaurar una interfaz
reset_interface() {
    local iface="$1"
    local max_attempts=3
    local attempt=1

    # Registrar estado de AppArmor
    if command -v aa-status >/dev/null 2>&1; then
        aa_status=$(sudo aa-status 2>/dev/null | head -n 1)
        log_message "DEBUG" "Estado de AppArmor: $aa_status"
    fi

    while [ $attempt -le $max_attempts ]; do
        log_message "INFO" "Intento $attempt/$max_attempts: Restaurando interfaz $iface..."
        local changes_made=0
        local errors=0

        # Eliminar VLANs asociadas
        local existing_vlans=$(ip link show | grep "@$iface" | awk '{print $2}' | cut -d':' -f1 | cut -d'@' -f1)
        if [ -n "$existing_vlans" ]; then
            for vlan in $existing_vlans; do
                if ip link show "$vlan" >/dev/null 2>&1; then
                    log_message "INFO" "Eliminando VLAN $vlan en $iface..."
                    sudo ip link delete "$vlan" >/tmp/vlan_error.log 2>&1
                    if [ $? -eq 0 ]; then
                        log_message "OK" "VLAN $vlan eliminada correctamente."
                        changes_made=1
                    else
                        vlan_error=$(cat /tmp/vlan_error.log)
                        log_message "ERROR" "No se pudo eliminar VLAN $vlan. Error: $vlan_error"
                        errors=1
                    fi
                fi
            done
        else
            log_message "DEBUG" "No se encontraron VLANs en $iface."
        fi

        # Limpiar reglas de iptables con manejo robusto de bloqueos
        log_message "INFO" "Limpiando reglas de iptables para $iface..."
        local iptables_cleared=0
        local lock_attempts=3
        local lock_attempt=1
        while [ $lock_attempt -le $lock_attempts ]; do
            if [ -f /run/xtables.lock ]; then
                log_message "INFO" "Archivo de bloqueo /run/xtables.lock encontrado. Intentando liberarlo..."
                if command -v lsof >/dev/null 2>&1; then
                    lock_pid=$(sudo lsof /run/xtables.lock | awk '{print $2}' | tail -n 1)
                    if [ -n "$lock_pid" ]; then
                        log_message "INFO" "Proceso $lock_pid bloqueando /run/xtables.lock. Intentando terminarlo..."
                        sudo kill -15 "$lock_pid" >/dev/null 2>&1
                        sleep 1
                        if kill -0 "$lock_pid" >/dev/null 2>&1; then
                            log_message "WARN" "Proceso $lock_pid no terminó. Forzando terminación..."
                            sudo kill -9 "$lock_pid" >/dev/null 2>&1
                        fi
                    fi
                fi
                sudo rm -f /run/xtables.lock >/dev/null 2>&1
                sleep 1
                if [ -f /run/xtables.lock ]; then
                    log_message "ERROR" "No se pudo liberar /run/xtables.lock en el intento $lock_attempt."
                    lock_attempt=$((lock_attempt + 1))
                    continue
                fi
            fi

            # Verificar si hay reglas para limpiar
            local nat_rules=$(sudo iptables -t nat -S POSTROUTING | grep -v "^-P" || true)
            local filter_rules=$(sudo iptables -S | grep -v "^-P" || true)
            if [ -n "$nat_rules" ] || [ -n "$filter_rules" ]; then
                if sudo iptables -t nat -F POSTROUTING >/tmp/iptables_error.log 2>&1 && sudo iptables -F >/tmp/iptables_error.log 2>&1; then
                    log_message "OK" "Reglas de iptables limpiadas correctamente."
                    changes_made=1  # Solo se activa si había reglas que limpiar
                    iptables_cleared=1
                else
                    iptables_error=$(cat /tmp/iptables_error.log)
                    log_message "ERROR" "Fallo al limpiar reglas de iptables. Error: $iptables_error"
                    errors=1
                fi
            else
                log_message "DEBUG" "No se encontraron reglas de iptables para limpiar."
                iptables_cleared=1
            fi
            break
        done

        if [ $iptables_cleared -eq 0 ]; then
            log_message "WARN" "No se pudieron limpiar las reglas de iptables tras $lock_attempts intentos."
            errors=1
        fi

        # Verificar y activar la interfaz
        if ! ip link show "$iface" | grep -q "UP"; then
            log_message "INFO" "Activando interfaz $iface..."
            sudo ip link set "$iface" up >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                log_message "OK" "Interfaz $iface activada."
                changes_made=1
            else
                log_message "ERROR" "No se pudo activar la interfaz $iface."
                errors=1
            fi
        fi

        # Limpiar configuraciones de tráfico (tc)
        log_message "INFO" "Eliminando configuraciones de tráfico (tc) en $iface..."
        if sudo tc qdisc show dev "$iface" | grep -E "tbf|netem" >/dev/null 2>&1; then
            sudo tc qdisc del dev "$iface" root >/tmp/tc_error.log 2>&1
            if [ $? -eq 0 ]; then
                log_message "OK" "Configuraciones de tráfico eliminadas."
                changes_made=1
            else
                tc_error=$(cat /tmp/tc_error.log)
                log_message "WARN" "No se pudieron eliminar configuraciones de tráfico. Error: $tc_error"
            fi
        else
            log_message "DEBUG" "No se encontraron configuraciones de tráfico configuradas por el usuario (tbf/netem) en $iface."
        fi

        # Verificar estado final
        local remaining_vlans=$(ip link show | grep "@$iface" | awk '{print $2}' | cut -d':' -f1 | cut -d'@' -f1)
        local iptables_nat=$(sudo iptables -t nat -S POSTROUTING | grep -v "^-P" || true)
        local tc_rules=$(sudo tc qdisc show dev "$iface" | grep -E "tbf|netem" | wc -l)

        log_message "DEBUG" "Estado final - VLANs: '$remaining_vlans', iptables NAT: '$iptables_nat', tc_rules: $tc_rules"

        # Salir si la interfaz está limpia
        if [ -z "$remaining_vlans" ] && [ -z "$iptables_nat" ] && [ "$tc_rules" -eq 0 ]; then
            log_message "OK" "Interfaz $iface restaurada completamente en el intento $attempt."
            rm -f /tmp/vlan_error.log /tmp/iptables_error.log /tmp/tc_error.log
            return 0
        fi

        # Reintentar solo si hubo errores críticos o cambios significativos
        if [ $errors -eq 1 ]; then
            log_message "WARN" "Errores detectados en el intento $attempt. Reintentando..."
        elif [ $changes_made -eq 1 ]; then
            log_message "INFO" "Se realizaron cambios significativos. Reintentando para asegurar limpieza completa..."
        else
            log_message "ERROR" "Estado no limpio pero no se hicieron cambios ni hubo errores. Algo está mal configurado."
            errors=1
        fi

        sleep 2
        attempt=$((attempt + 1))
    done

    log_message "ERROR" "No se pudo restaurar la interfaz $iface tras $max_attempts intentos."
    echo "No se pudo restaurar la interfaz $iface. Verifica con 'ip link', 'iptables -t nat -S', 'tc qdisc show dev $iface', 'lsof /run/xtables.lock', y 'aa-status'."
    exit 1
}


    # Restaurar la interfaz LAN_IF
    reset_interface "$LAN_IF"

    # Usar un prefijo corto para nombres de VLANs
    VLAN_PREFIX="v_"
    log_message "INFO" "Usando prefijo $VLAN_PREFIX para nombres de VLANs."

    PYTHON_VLAN_LIST="["
    VALID_VLANS=()
    max_attempts=3
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_message "INFO" "Intento $attempt/$max_attempts: Creando VLANs en $LAN_IF..."
        VALID_VLANS=()
        PYTHON_VLAN_LIST="["
        all_vlans_created=1
        for (( i=0; i<${NUM_VLANS:-0}; i++ )); do
            current_vlan_id=$(( ${START_VLAN:-100} + i ))
            subnet_octet=$(( ${BASE_OCTET:-10} + i ))
            vlan_name="${VLAN_PREFIX}${current_vlan_id}"

            # Validar longitud del nombre de la VLAN
            if [ ${#vlan_name} -gt 15 ]; then
                log_message "ERROR" "El nombre de la VLAN $vlan_name excede el límite de 15 caracteres."
                echo "${COLOR_ERROR}El nombre de la VLAN $vlan_name es demasiado largo. Usa un ID más corto.${COLOR_RESET}"
                exit 1
            fi

            # Intentar crear la VLAN
            if sudo ip link add link "$LAN_IF" name "$vlan_name" type vlan id "$current_vlan_id" >/tmp/vlan_error.log 2>&1; then
                sudo ip addr add "${SEGMENT_PREFIX:-192.168}.${subnet_octet}.1/24" dev "$vlan_name" >/tmp/ip_error.log 2>&1
                if [ $? -eq 0 ]; then
                    sudo ip link set "$vlan_name" up >/tmp/ip_error.log 2>&1
                    if [ $? -eq 0 ] && ip link show "$vlan_name" | grep -q "UP"; then
                        VALID_VLANS+=("$vlan_name")
                        if [ $i -eq $(( ${NUM_VLANS:-0} - 1 )) ]; then
                            PYTHON_VLAN_LIST+="\"$vlan_name\""
                        else
                            PYTHON_VLAN_LIST+="\"$vlan_name\", "
                        fi
                        log_message "OK" "Creada VLAN $vlan_name con IP ${SEGMENT_PREFIX:-192.168}.${subnet_octet}.1/24"
                    else
                        ip_error=$(cat /tmp/ip_error.log)
                        log_message "ERROR" "VLAN $vlan_name creada pero no activa. Error: $ip_error"
                        all_vlans_created=0
                    fi
                else
                    ip_error=$(cat /tmp/ip_error.log)
                    log_message "ERROR" "No se pudo asignar IP a VLAN $vlan_name. Error: $ip_error"
                    all_vlans_created=0
                fi
            else
                vlan_error=$(cat /tmp/vlan_error.log)
                log_message "ERROR" "No se pudo crear la VLAN $vlan_name en $LAN_IF. Error: $vlan_error"
                # Intentar con IDs alternativos
                for alt_offset in 1000 2000 3000; do
                    alt_vlan_id=$(( $current_vlan_id + $alt_offset ))
                    vlan_name="${VLAN_PREFIX}${alt_vlan_id}"
                    if [ ${#vlan_name} -gt 15 ]; then
                        log_message "ERROR" "El nombre alternativo de la VLAN $vlan_name excede el límite de 15 caracteres."
                        continue
                    fi
                    log_message "INFO" "Reintentando con ID alternativo $alt_vlan_id..."
                    if sudo ip link add link "$LAN_IF" name "$vlan_name" type vlan id "$alt_vlan_id" >/tmp/vlan_error.log 2>&1; then
                        sudo ip addr add "${SEGMENT_PREFIX:-192.168}.${subnet_octet}.1/24" dev "$vlan_name" >/tmp/ip_error.log 2>&1
                        if [ $? -eq 0 ]; then
                            sudo ip link set "$vlan_name" up >/tmp/ip_error.log 2>&1
                            if [ $? -eq 0 ] && ip link show "$vlan_name" | grep -q "UP"; then
                                VALID_VLANS+=("$vlan_name")
                                if [ $i -eq $(( ${NUM_VLANS:-0} - 1 )) ]; then
                                    PYTHON_VLAN_LIST+="\"$vlan_name\""
                                else
                                    PYTHON_VLAN_LIST+="\"$vlan_name\", "
                                fi
                                log_message "OK" "Creada VLAN $vlan_name con IP ${SEGMENT_PREFIX:-192.168}.${subnet_octet}.1/24 (ID alternativo $alt_vlan_id)"
                                break
                            else
                                ip_error=$(cat /tmp/ip_error.log)
                                log_message "ERROR" "VLAN $vlan_name (ID alternativo $alt_vlan_id) creada pero no activa. Error: $ip_error"
                            fi
                        else
                            ip_error=$(cat /tmp/ip_error.log)
                            log_message "ERROR" "No se pudo asignar IP a VLAN $vlan_name (ID alternativo $alt_vlan_id). Error: $ip_error"
                        fi
                    else
                        alt_vlan_error=$(cat /tmp/vlan_error.log)
                        log_message "ERROR" "No se pudo crear la VLAN $vlan_name con ID alternativo $alt_vlan_id. Error: $alt_vlan_error"
                    fi
                done
                if [ ! " ${VALID_VLANS[*]} " =~ " ${VLAN_PREFIX}${current_vlan_id} " ] && \
                   [ ! " ${VALID_VLANS[*]} " =~ " ${VLAN_PREFIX}$((current_vlan_id + 1000)) " ] && \
                   [ ! " ${VALID_VLANS[*]} " =~ " ${VLAN_PREFIX}$((current_vlan_id + 2000)) " ] && \
                   [ ! " ${VALID_VLANS[*]} " =~ " ${VLAN_PREFIX}$((current_vlan_id + 3000)) " ]; then
                    all_vlans_created=0
                fi
            fi
        done
        PYTHON_VLAN_LIST+="]"

        # Verificar si todas las VLANs se crearon correctamente
        if [ $all_vlans_created -eq 1 ] && [ ${#VALID_VLANS[@]} -eq ${NUM_VLANS:-0} ]; then
            log_message "OK" "Todas las VLANs creadas correctamente en el intento $attempt."
            rm -f /tmp/vlan_error.log /tmp/ip_error.log
            break
        else
            log_message "ADVERTENCIA" "No se crearon todas las VLANs en el intento $attempt. Restaurando y reintentando..."
            reset_interface "$LAN_IF"
        fi
        attempt=$((attempt + 1))
    done

    # Verificar resultado final
    if [ ${#VALID_VLANS[@]} -eq 0 ]; then
        log_message "ERROR" "No se crearon VLANs válidas tras $max_attempts intentos. Verifica la interfaz $LAN_IF y el soporte de VLANs."
        echo "${COLOR_ERROR}No se crearon VLANs válidas. Revisa los logs en $LOGFILE y verifica 'ip link' y 'lsmod | grep 8021q'.${COLOR_RESET}"
        exit 1
    elif [ ${#VALID_VLANS[@]} -lt ${NUM_VLANS:-0} ]; then
        log_message "ADVERTENCIA" "Solo se crearon ${#VALID_VLANS[@]} de ${NUM_VLANS:-0} VLANs solicitadas. Continuando con VLANs válidas."
        echo "${COLOR_WARN}Solo se crearon ${#VALID_VLANS[@]} de ${NUM_VLANS:-0} VLANs. Revisa los logs en $LOGFILE.${COLOR_RESET}"
    fi

    # Configurar DHCP si está habilitado
    if [ "$CONFIG_DHCP" = "s" ]; then
        log_message "INFO" "Configurando DHCP..."
        all_interfaces_up=1
        for vlan in "${VALID_VLANS[@]}"; do
            if ! ip link show "$vlan" | grep -q "UP"; then
                log_message "ADVERTENCIA" "Interfaz $vlan no está activa."
                all_interfaces_up=0
            fi
        done

        if [ "$all_interfaces_up" -eq 0 ]; then
            log_message "INFO" "Algunas interfaces VLAN no están activas. Intentando activarlas..."
            for vlan in "${VALID_VLANS[@]}"; do
                sudo ip link set dev "$vlan" up >/dev/null 2>&1 || true
            done
            sleep 2
            all_interfaces_up=1
            for vlan in "${VALID_VLANS[@]}"; do
                if ! ip link show "$vlan" | grep -q "UP"; then
                    log_message "ERROR" "Interfaz $vlan aún no está activa."
                    all_interfaces_up=0
                fi
            done
        fi

        if [ "$all_interfaces_up" -eq 1 ]; then
            [ -f /etc/dhcp/dhcpd.conf ] && sudo cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak
            sudo tee /etc/dhcp/dhcpd.conf > /dev/null <<EOL
default-lease-time 600;
max-lease-time 7200;
authoritative;
EOL
            for (( i=0; i<${#VALID_VLANS[@]}; i++ )); do
                subnet_octet=$(( ${BASE_OCTET:-10} + i ))
                sudo tee -a /etc/dhcp/dhcpd.conf > /dev/null <<EOF
subnet ${SEGMENT_PREFIX:-192.168}.${subnet_octet}.0 netmask 255.255.255.0 {
    range ${SEGMENT_PREFIX:-192.168}.${subnet_octet}.100 ${SEGMENT_PREFIX:-192.168}.${subnet_octet}.200;
    option routers ${SEGMENT_PREFIX:-192.168}.${subnet_octet}.1;
}
EOF
            done

            sudo tee /etc/default/isc-dhcp-server > /dev/null <<EOF
INTERFACESv4="${VALID_VLANS[*]}"
EOF

            log_message "INFO" "Validando configuración DHCP..."
            if dhcpd -t -cf /etc/dhcp/dhcpd.conf >/dev/null 2>&1; then
                log_message "OK" "Configuración DHCP válida."
                sudo systemctl enable isc-dhcp-server >/dev/null 2>&1
                if sudo systemctl restart isc-dhcp-server >/dev/null 2>&1; then
                    sleep 2
                    if systemctl is-active isc-dhcp-server >/dev/null; then
                        log_message "OK" "DHCP configurado correctamente."
                        echo "DHCP - Configurado correctamente."
                    else
                        log_message "ERROR" "Error al iniciar el servicio DHCP. Revisando logs..."
                        dhcp_error=$(journalctl -u isc-dhcp-server -n 50 --no-pager 2>&1)
                        log_message "ERROR" "Error DHCP: $dhcp_error"
                        echo "  [ERROR] DHCP no configurado. Revisa los logs in $LOGFILE."
                    fi
                else
                    log_message "ERROR" "Error al reiniciar el servicio DHCP. Revisando logs..."
                    dhcp_error=$(journalctl -u isc-dhcp-server -n 50 --no-pager 2>&1)
                    log_message "ERROR" "Error DHCP: $dhcp_error"
                    echo "  [ERROR] DHCP no configurado. Revisa los logs in $LOGFILE."
                fi
            else
                log_message "ERROR" "Configuración DHCP inválida. Revisando errores..."
                dhcp_error=$(dhcpd -t -cf /etc/dhcp/dhcpd.conf 2>&1)
                log_message "ERROR" "Error DHCP: $dhcp_error"
                echo "  [ERROR] Configuración DHCP inválida. Revisa los logs in $LOGFILE."
            fi
        else
            log_message "ERROR" "No todas las interfaces VLAN están activas. No se puede configurar DHCP."
            echo "  [ERROR] No se puede configurar DHCP porque las interfaces VLAN no están activas."
            echo "  Revisa las interfaces con 'ip link' y los logs in $LOGFILE."
        fi
    fi

    # Configurar NAT
    log_message "INFO" "Configurando NAT..."
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

    # Verificar y liberar el archivo de bloqueo xtables.lock
    max_attempts=3
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_message "INFO" "Intento $attempt/$max_attempts: Verificando archivo de bloqueo /run/xtables.lock..."
        if [ -f /run/xtables.lock ]; then
            log_message "INFO" "Archivo de bloqueo /run/xtables.lock encontrado. Intentando liberarlo..."
            if command -v lsof >/dev/null 2>&1; then
                lock_pid=$(sudo lsof /run/xtables.lock | awk '{print $2}' | tail -n 1)
                if [ -n "$lock_pid" ]; then
                    log_message "INFO" "Proceso $lock_pid bloqueando /run/xtables.lock. Intentando terminarlo..."
                    sudo kill -15 "$lock_pid" >/dev/null 2>&1
                    sleep 1
                    if kill -0 "$lock_pid" >/dev/null 2>&1; then
                        log_message "WARN" "Proceso $lock_pid no terminó. Forzando terminación..."
                        sudo kill -9 "$lock_pid" >/dev/null 2>&1
                    fi
                fi
            fi
            sudo rm -f /run/xtables.lock >/dev/null 2>&1
            sleep 1
            if [ -f /run/xtables.lock ]; then
                log_message "ERROR" "No se pudo liberar /run/xtables.lock en el intento $attempt."
                attempt=$((attempt + 1))
                continue
            fi
        fi
        log_message "OK" "Archivo de bloqueo /run/xtables.lock libre o eliminado."
        break
    done
    if [ $attempt -gt $max_attempts ]; then
        log_message "ERROR" "No se pudo liberar /run/xtables.lock tras $max_attempts intentos."
        echo "${COLOR_ERROR}No se pudo liberar el archivo de bloqueo /run/xtables.lock. Revisa permisos y procesos en ejecución.${COLOR_RESET}"
        exit 1
    fi

    # Verificar permisos del directorio /etc/iptables/
    if [ ! -d /etc/iptables ]; then
        log_message "INFO" "Creando directorio /etc/iptables..."
        sudo mkdir -p /etc/iptables >/dev/null 2>&1
        sudo chmod 755 /etc/iptables >/dev/null 2>&1
    fi
    if [ ! -w /etc/iptables ]; then
        log_message "INFO" "Ajustando permisos del directorio /etc/iptables..."
        sudo chmod 755 /etc/iptables >/dev/null 2>&1
    fi

    # Aplicar reglas de iptables y guardarlas
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_message "INFO" "Intento $attempt/$max_attempts: Aplicando reglas de NAT..."
        # Limpiar reglas existentes
        sudo iptables -t nat -F POSTROUTING >/dev/null 2>&1
        for (( i=0; i<${#VALID_VLANS[@]}; i++ )); do
            subnet_octet=$(( ${BASE_OCTET:-10} + i ))
            sudo iptables -t nat -A POSTROUTING -o "$WAN_IF" -s "${SEGMENT_PREFIX:-192.168}.${subnet_octet}.0/24" -j MASQUERADE
        done

        # Guardar reglas en un archivo temporal y moverlo
        temp_rules="/tmp/iptables_rules.v4"
        sudo timeout 30 iptables-save > "$temp_rules" 2>/tmp/iptables_error.log
        if [ $? -eq 0 ]; then
            sudo timeout 30 mv "$temp_rules" /etc/iptables/rules.v4 >/tmp/iptables_error.log 2>&1
            if [ $? -eq 0 ]; then
                sudo chmod 644 /etc/iptables/rules.v4 >/dev/null 2>&1
                log_message "OK" "Reglas de NAT guardadas correctamente en /etc/iptables/rules.v4."
                echo "NAT - Configurado y guardado correctamente."
                rm -f /tmp/iptables_error.log
                break
            else
                iptables_error=$(cat /tmp/iptables_error.log)
                log_message "ERROR" "Error al mover reglas de NAT a /etc/iptables/rules.v4: $iptables_error"
            fi
        else
            iptables_error=$(cat /tmp/iptables_error.log)
            log_message "ERROR" "Error al guardar reglas de NAT: $iptables_error"
        fi
        log_message "INFO" "Reintentando configuración de NAT..."
        attempt=$((attempt + 1))
        sleep 2
    done

    if [ $attempt -gt $max_attempts ]; then
        log_message "ERROR" "No se pudo configurar NAT tras $max_attempts intentos."
        echo "${COLOR_ERROR}No se pudo configurar NAT. Revisa los logs en $LOGFILE y verifica permisos en /etc/iptables/.${COLOR_RESET}"
        exit 1
    fi
elif [ "$TOPOLOGY_MODE" = "bridge" ]; then
    log_message "INFO" "Configurando puente entre $LAN_IF y $DEST_IF..."
    # Restaurar interfaces antes de configurar el puente
    reset_interface "$LAN_IF"
    reset_interface "$DEST_IF"
    sudo ip link add name br0 type bridge >/dev/null 2>&1
    sudo ip link set "$LAN_IF" master br0 >/dev/null 2>&1
    sudo ip link set "$DEST_IF" master br0 >/dev/null 2>&1
    sudo ip link set br0 up >/dev/null 2>&1
    sudo ip link set "$LAN_IF" up >/dev/null 2>&1
    sudo ip link set "$DEST_IF" up >/dev/null 2>&1
    if ip link show br0 >/dev/null 2>&1; then
        log_message "OK" "Puente br0 creado y configurado."
        PYTHON_VLAN_LIST="['br0']"
        if [ "$CONFIG_TC" = "s" ]; then
            sudo tc qdisc add dev "$LAN_IF" root tbf rate 10mbit burst 32kbit latency 50ms >/dev/null 2>&1
            log_message "OK" "Control de tráfico aplicado en $LAN_IF (10Mbit/s)."
        fi
    else
        log_message "ERROR" "No se pudo crear el puente br0."
        echo "${COLOR_ERROR}No se pudo crear el puente br0. Revisa los logs in $LOGFILE.${COLOR_RESET}"
        exit 1
    fi
fi

# Establecer bandera de Telegram habilitado
if [ -n "$TELEGRAM_TOKEN" ]; then
    TELEGRAM_ENABLED=1
else
    TELEGRAM_ENABLED=0
fi

# Guardar configuración
if [ "$INTERACTIVE" -eq 1 ]; then
    log_message "INFO" "Guardando configuración localmente..."
    rm -f "$CONFIG_FILE" || {
        log_message "ERROR" "No se pudo eliminar el archivo de configuración existente $CONFIG_FILE. Verifica permisos."
        exit 1
    }
    cat > "$CONFIG_FILE" <<EOF
TOPOLOGY_MODE=$TOPOLOGY_MODE
NUM_VLANS=${NUM_VLANS:-0}
START_VLAN=${START_VLAN:-0}
CONFIG_DHCP=${CONFIG_DHCP:-n}
SEGMENT_PREFIX=${SEGMENT_PREFIX:-192.168}
BASE_OCTET=${BASE_OCTET:-0}
INTEGRATE_TELEGRAM=$INTEGRATE_TELEGRAM
TELEGRAM_TOKEN=$TELEGRAM_TOKEN
TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID
WAN_IF=${WAN_IF:-}
LAN_IF=${LAN_IF:-}
DEST_IF=${DEST_IF:-}
CONFIG_TC=${CONFIG_TC:-n}
IS_MGMT=${IS_MGMT:-n}
EOF
    chmod 640 "$CONFIG_FILE"
    chown "$CURRENT_USER:$CURRENT_USER" "$CONFIG_FILE"
    log_message "OK" "Configuración guardada en $CONFIG_FILE."
fi


# SECCIÓN 6.1A: Liberación de Puerto y Verificación de Dependencias
# ----------------------------------------------------------------
log_message "INFO" "Liberando puerto y verificando dependencias..."

# Liberar puerto para Flask
free_port

# Configurar PYTHONPATH antes de la verificación
export PYTHONPATH="$HOME/.local/lib/python3.8/site-packages:/usr/local/lib/python3.8/dist-packages:$PYTHONPATH"

# Verificar dependencias de Python
log_message "INFO" "Verificando dependencias de Python..."
for module in flask requests python-telegram-bot pyOpenSSL; do
    if ! python3 -c "import $module" 2>/dev/null; then
        log_message "ERROR" "Módulo Python $module no encontrado. Instalando..."
        if ! pip3 install --user "$module" --no-warn-script-location; then
            log_message "ERROR" "No se pudo instalar $module."
            echo "${COLOR_ERROR}Fallo al instalar $module. Revisa con 'pip3 list'.${COLOR_RESET}"
            exit 1
        fi
        log_message "OK" "$module instalado."
    else
        log_message "OK" "$module ya está instalado."
    fi
done

# Asegurar PATH para Python
export PATH="$HOME/.local/bin:$PATH"
log_message "OK" "Dependencias de Python verificadas."

# SECCIÓN 6.1B: Configuración de Archivos de Log
# ---------------------------------------------
log_message "INFO" "Configurando archivo de log /tmp/wansim_dashboard.log..."
if [ -f "/tmp/wansim_dashboard.log" ]; then
    if ! sudo rm -f "/tmp/wansim_dashboard.log"; then
        log_message "ERROR" "No se pudo eliminar el archivo de log existente."
        echo "${COLOR_ERROR}No se pudo eliminar /tmp/wansim_dashboard.log. Revisa permisos con 'ls -l /tmp/wansim_dashboard.log'.${COLOR_RESET}"
        exit 1
    fi
fi
touch "/tmp/wansim_dashboard.log"
if ! chmod 664 "/tmp/wansim_dashboard.log"; then
    log_message "ERROR" "No se pudo establecer permisos para /tmp/wansim_dashboard.log."
    echo "${COLOR_ERROR}No se pudo establecer permisos para /tmp/wansim_dashboard.log. Revisa con 'ls -l /tmp/wansim_dashboard.log'.${COLOR_RESET}"
    exit 1
fi
if ! chown "$CURRENT_USER:$CURRENT_USER" "/tmp/wansim_dashboard.log"; then
    log_message "ERROR" "No se pudo cambiar propietario de /tmp/wansim_dashboard.log."
    echo "${COLOR_ERROR}No se pudo cambiar propietario de /tmp/wansim_dashboard.log. Revisa con 'ls -l /tmp/wansim_dashboard.log'.${COLOR_RESET}"
    exit 1
fi
log_message "OK" "Archivo de log configurado."

# SECCIÓN 6.1C: Generación del Script Python
# -----------------------------------------
log_message "INFO" "Generando script Python para el Dashboard Flask..."
# Generar archivo wansim_dashboard.py
log_message "DEBUG" "Generando $WANSIM_DASHBOARD..."
if [ -f "$WANSIM_DASHBOARD" ]; then
    log_message "INFO" "Eliminando $WANSIM_DASHBOARD existente..."
    if shred -u "$WANSIM_DASHBOARD" 2>/dev/null || rm -f "$WANSIM_DASHBOARD" 2>/dev/null; then
        log_message "OK" "Eliminado $WANSIM_DASHBOARD"
    else
        log_message "ERROR" "No se pudo eliminar $WANSIM_DASHBOARD"
        exit 1
    fi
fi

# Crear el archivo Python con el dashboard Flask
cat > "$WANSIM_DASHBOARD" <<'EOF'
#!/usr/bin/env python3
import os
import re
import json
import time
import logging
import subprocess
import threading
import sys
from flask import Flask, request, render_template_string
# Configurar logging básico
logging.basicConfig(
    level=logging.DEBUG,
    format='%%(asctime)s - %%(levelname)s - %%(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)
logger.debug("Iniciando wansim_dashboard.py")

# Importar módulos de Telegram (compatibilidad con v20+)
try:
    from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
    from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, ConversationHandler, MessageHandler, filters
    TELEGRAM_IMPORTED = True
except ImportError as e:
    logger.error(f"Error importando módulos de Telegram: {e}")
    TELEGRAM_IMPORTED = False

app = Flask(__name__)
app.config['PORT'] = __PYTHON_DASHBOARD_PORT__

def run_command(command):
    logger.debug(f"Ejecutando comando: {command}")
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=10)
        logger.debug(f"Resultado: returncode={result.returncode}, stdout={result.stdout}, stderr={result.stderr}")
        return result.returncode == 0, result.stdout or result.stderr
    except subprocess.TimeoutExpired:
        logger.error(f"Timeout ejecutando comando: {command}")
        return False, "Comando excedió el tiempo límite"
    except Exception as e:
        logger.error(f"Error ejecutando comando {command}: {e}")
        return False, str(e)

def parse_qdisc(output):
    logger.debug(f"Parseando qdisc output: {output}")
    delay = jitter = loss = 0
    try:
        delay_jitter_match = re.search(r'delay\s+(\d+\.?\d*)ms\s*(\d+\.?\d*)ms', output, re.IGNORECASE)
        if delay_jitter_match:
            delay = float(delay_jitter_match.group(1))
            jitter = float(delay_jitter_match.group(2))
        elif re.search(r'delay\s+(\d+\.?\d*)ms', output, re.IGNORECASE):
            delay = float(re.search(r'delay\s+(\d+\.?\d*)ms', output, re.IGNORECASE).group(1))
        loss_match = re.search(r'loss\s+(\d+\.?\d*)%', output, re.IGNORECASE)
        if loss_match:
            loss = float(loss_match.group(1))
    except Exception as e:
        logger.error(f"Error parseando qdisc: {e}")
    return {"delay": delay, "jitter": jitter, "loss": loss}

def get_traffic_stats(vlan):
    logger.debug(f"Obteniendo estadísticas de tráfico para VLAN: {vlan}")
    try:
        result = subprocess.run(f"ifstat -i {vlan} 0.1 1", shell=True, capture_output=True, text=True, timeout=5)
        lines = result.stdout.splitlines()
        logger.debug(f"ifstat output: {lines}")
        if len(lines) >= 2:
            stats = lines[-1].split()
            kbps_in = float(stats[0]) if stats[0] and stats[0].replace('.', '').isdigit() else 0.0
            kbps_out = float(stats[1]) if stats[1] and stats[1].replace('.', '').isdigit() else 0.0
            return {
                "kbps_in": kbps_in, "kbps_out": kbps_out,
                "mbps_in": kbps_in / 1000, "mbps_out": kbps_out / 1000,
                "kb_in": kbps_in / 8, "kb_out": kbps_out / 8,
                "mb_in": (kbps_in / 8) / 1000, "mb_out": (kbps_out / 8) / 1000
            }
    except Exception as e:
        logger.error(f"Error obteniendo estadísticas de tráfico para {vlan}: {e}")
    return {"kbps_in": 0, "kbps_out": 0, "mbps_in": 0, "mbps_out": 0, "kb_in": 0, "kb_out": 0, "mb_in": 0, "mb_out": 0}

VLAN_INTERFACES = __PYTHON_VLAN_LIST__
TELEGRAM_TOKEN = "__TELEGRAM_TOKEN__"
TELEGRAM_CHAT_ID = "__TELEGRAM_CHAT_ID__"
TELEGRAM_ENABLED = __TELEGRAM_ENABLED__ and TELEGRAM_IMPORTED

logger.info(f"VLAN_INTERFACES inicializado con: {VLAN_INTERFACES}")

for vlan in VLAN_INTERFACES:
    if not run_command(f"ip link show {vlan}")[0]:
        logger.warning(f"VLAN {vlan} no encontrada en el sistema.")

# Configurar bot de Telegram (solo si está habilitado y los módulos se importaron correctamente)
if TELEGRAM_ENABLED:
    SELECT_VLAN, ENTER_DELAY, ENTER_JITTER, ENTER_LOSS = range(1, 5)

    def config_start(update: Update, context):
        if str(update.effective_chat.id) != TELEGRAM_CHAT_ID:
            update.message.reply_text("Acceso no autorizado.")
            return ConversationHandler.END
        keyboard = [[InlineKeyboardButton(vlan, callback_data=f"select_{vlan}")] for vlan in VLAN_INTERFACES]
        reply_markup = InlineKeyboardMarkup(keyboard)
        update.message.reply_text("Selecciona la VLAN que deseas configurar:", reply_markup=reply_markup)
        return SELECT_VLAN

    def select_vlan(update: Update, context):
        query = update.callback_query
        query.answer()
        data = query.data
        if data.startswith("select_"):
            vlan = data.split("_", 1)[1]
            context.user_data["vlan"] = vlan
            query.edit_message_text(text=f"Has seleccionado {vlan}. Ingresa el valor de Latencia (ms):")
            return ENTER_DELAY
        else:
            query.edit_message_text(text="Selección inválida.")
            return ConversationHandler.END

    def enter_delay(update: Update, context):
        text = update.message.text
        if not text.replace('.', '').isdigit():
            update.message.reply_text("Ingresa un número válido para latencia.")
            return ENTER_DELAY
        context.user_data["delay"] = float(text)
        update.message.reply_text("Ingresa el valor de Jitter (ms):")
        return ENTER_JITTER

    def enter_jitter(update: Update, context):
        text = update.message.text
        if not text.replace('.', '').isdigit():
            update.message.reply_text("Ingresa un número válido para jitter.")
            return ENTER_JITTER
        context.user_data["jitter"] = float(text)
        update.message.reply_text("Ingresa el valor de Pérdida (%):")
        return ENTER_LOSS

    def enter_loss(update: Update, context):
        text = update.message.text
        if not text.replace('.', '').isdigit():
            update.message.reply_text("Ingresa un número válido para pérdida.")
            return ENTER_LOSS
        context.user_data["loss"] = float(text)
        vlan = context.user_data["vlan"]
        delay = context.user_data["delay"]
        jitter = context.user_data["jitter"]
        loss = context.user_data["loss"]
        run_command(f"sudo tc qdisc del dev {vlan} root netem")
        success, output = run_command(f"sudo tc qdisc add dev {vlan} root netem delay {delay}ms {jitter}ms loss {loss}%")
        if success:
            message = f"Configuración aplicada en {vlan}: {delay}ms, {jitter}ms, {loss}%."
        else:
            message = f"Error en {vlan}: {output}"
        update.message.reply_text(message)
        return ConversationHandler.END

    def cancel(update: Update, context):
        update.message.reply_text("Operación cancelada.")
        return ConversationHandler.END

    def start_telegram_bot():
        updater = Updater(TELEGRAM_TOKEN, use_context=True)
        dp = updater.dispatcher
        conv_handler = ConversationHandler(
            entry_points=[CommandHandler('start', config_start), CommandHandler('config', config_start)],
            states={
                SELECT_VLAN: [CallbackQueryHandler(select_vlan, pattern="^select_")],
                ENTER_DELAY: [MessageHandler(filters.TEXT & ~filters.COMMAND, enter_delay)],
                ENTER_JITTER: [MessageHandler(filters.TEXT & ~filters.COMMAND, enter_jitter)],
                ENTER_LOSS: [MessageHandler(filters.TEXT & ~filters.COMMAND, enter_loss)],
            },
            fallbacks=[CommandHandler('cancel', cancel)]
        )
        dp.add_handler(conv_handler)
        updater.start_polling()
        updater.idle()

    threading.Thread(target=start_telegram_bot, daemon=True).start()

@app.route('/', methods=['GET'])
def dashboard():
    logger.debug(f"Renderizando dashboard, VLANs: {VLAN_INTERFACES}")
    if not VLAN_INTERFACES:
        logger.error("No hay VLANs configuradas para mostrar en el dashboard")
        return render_template_string("""
            <div class='alert alert-warning text-center'>
                No hay VLANs configuradas. Por favor, verifica la configuración en ${USER_HOME}/emix_abundix.conf.
            </div>
        """), 400
    stats = {}
    for vlan in VLAN_INTERFACES:
        qdisc_success, qdisc_output = run_command(f"tc qdisc show dev {vlan}")
        stats[vlan] = parse_qdisc(qdisc_output) if qdisc_success else {"delay": 0, "jitter": 0, "loss": 0}
        stats[vlan].update(get_traffic_stats(vlan))
    return render_template_string("""
        <!DOCTYPE html>
        <html lang='es'>
        <head>
            <meta charset='UTF-8'>
            <meta name='viewport' content='width=device-width, initial-scale=1.0'>
            <title>WAN Simulator</title>
            <link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'>
            <script src='https://cdn.jsdelivr.net/npm/chart.js'></script>
            <style>
                body { background: linear-gradient(135deg, #1e3c72, #2a5298); color: white; min-height: 100vh; font-family: 'Arial', sans-serif; }
                .container { max-width: 1200px; padding: 20px; }
                .card { background: rgba(255, 255, 255, 0.1); border: none; border-radius: 15px; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2); backdrop-filter: blur(10px); transition: transform 0.3s ease; }
                .card:hover { transform: translateY(-5px); }
                .btn { transition: all 0.3s ease; }
                .btn:hover { transform: translateY(-2px); }
                .form-control, .form-select { background: rgba(255, 255, 255, 0.2); color: white; border: none; }
                .form-control:focus, .form-select:focus { background: rgba(255, 255, 255, 0.3); color: white; box-shadow: none; }
                .chart-container { position: relative; height: 200px; }
                .output { background: rgba(0, 0, 0, 0.3); padding: 10px; border-radius: 5px; }
                .error { color: #ff4d4d; font-weight: bold; }
                .success { color: #28a745; font-weight: bold; }
                .footer { text-align: center; padding: 20px; font-size: 0.9rem; }
                @media (max-width: 576px) {
                    .container { padding: 10px; }
                    .card { margin-bottom: 15px; }
                    .btn { font-size: 0.9rem; }
                    .form-control, .form-select { font-size: 0.9rem; }
                }
            </style>
        </head>
        <body>
            <div class='container'>
                <h1 class='text-center mb-4'>WAN Simulator</h1>
                <div class='d-flex justify-content-center mb-4'>
                    <form action='/configure' method='post' class='mx-2'>
                        <input type='hidden' name='action' value='reset_all'>
                        <button type='submit' class='btn btn-primary'>Restablecer Todas las Interfaces</button>
                    </form>
                    <select id='unit-select' class='form-select w-auto mx-2' onchange='updateCharts()'>
                        <option value='mbps'>Mbps</option>
                        <option value='kbps'>Kbps</option>
                        <option value='mb'>MB</option>
                        <option value='kb'>KB</option>
                    </select>
                </div>
                <div class='row'>
                    {% for vlan in vlans %}
                    <div class='col-md-6 col-lg-4 mb-4'>
                        <div class='card p-4'>
                            <h3 class='text-center'>Interfaz: {{ vlan }}</h3>
                            <form action='/configure' method='post' id='config-form-{{ vlan }}'>
                                <input type='hidden' name='vlan' value='{{ vlan }}'>
                                <input type='hidden' name='action' value='apply'>
                                <div class='mb-3'>
                                    <label class='form-label'>Latencia (ms):</label>
                                    <input type='number' class='form-control' name='delay' value='{{ stats[vlan].delay }}' min='0' step='0.1'>
                                </div>
                                <div class='mb-3'>
                                    <label class='form-label'>Jitter (ms):</label>
                                    <input type='number' class='form-control' name='jitter' value='{{ stats[vlan].jitter }}' min='0' step='0.1'>
                                </div>
                                <div class='mb-3'>
                                    <label class='form-label'>Pérdida (%):</label>
                                    <input type='number' class='form-control' name='loss' value='{{ stats[vlan].loss }}' min='0' max='100' step='0.1'>
                                </div>
                                <div class='d-flex justify-content-center mb-3'>
                                    <button type='submit' class='btn btn-primary mx-1'>Aplicar</button>
                                    <button type='submit' class='btn btn-warning mx-1' formaction='/configure' onclick='this.form.elements["action"].value="reset"'>Restablecer</button>
                                </div>
                            </form>
                            <div class='mb-3'>
                                <label class='form-label'>Latencia Rápida:</label>
                                <div class='d-flex'>
                                    <form action='/configure' method='post' class='mx-1'>
                                        <input type='hidden' name='vlan' value='{{ vlan }}'>
                                        <input type='hidden' name='action' value='apply'>
                                        <input type='hidden' name='delay' value='100'>
                                        <input type='hidden' name='jitter' value='0'>
                                        <input type='hidden' name='loss' value='0'>
                                        <button type='submit' class='btn btn-outline-light btn-sm'>100ms</button>
                                    </form>
                                    <form action='/configure' method='post' class='mx-1'>
                                        <input type='hidden' name='vlan' value='{{ vlan }}'>
                                        <input type='hidden' name='action' value='apply'>
                                        <input type='hidden' name='delay' value='300'>
                                        <input type='hidden' name='jitter' value='0'>
                                        <input type='hidden' name='loss' value='0'>
                                        <button type='submit' class='btn btn-outline-light btn-sm'>300ms</button>
                                    </form>
                                    <form action='/configure' method='post' class='mx-1'>
                                        <input type='hidden' name='vlan' value='{{ vlan }}'>
                                        <input type='hidden' name='action' value='apply'>
                                        <input type='hidden' name='delay' value='500'>
                                        <input type='hidden' name='jitter' value='0'>
                                        <input type='hidden' name='loss' value='0'>
                                        <button type='submit' class='btn btn-outline-light btn-sm'>500ms</button>
                                    </form>
                                </div>
                            </div>
                            <div class='mb-3'>
                                <label class='form-label'>Jitter Rápido:</label>
                                <div class='d-flex'>
                                    <form action='/configure' method='post' class='mx-1'>
                                        <input type='hidden' name='vlan' value='{{ vlan }}'>
                                        <input type='hidden' name='action' value='apply'>
                                        <input type='hidden' name='delay' value='0'>
                                        <input type='hidden' name='jitter' value='50'>
                                        <input type='hidden' name='loss' value='0'>
                                        <button type='submit' class='btn btn-outline-light btn-sm'>50ms</button>
                                    </form>
                                    <form action='/configure' method='post' class='mx-1'>
                                        <input type='hidden' name='vlan' value='{{ vlan }}'>
                                        <input type='hidden' name='action' value='apply'>
                                        <input type='hidden' name='delay' value='0'>
                                        <input type='hidden' name='jitter' value='100'>
                                        <input type='hidden' name='loss' value='0'>
                                        <button type='submit' class='btn btn-outline-light btn-sm'>100ms</button>
                                    </form>
                                    <form action='/configure' method='post' class='mx-1'>
                                        <input type='hidden' name='vlan' value='{{ vlan }}'>
                                        <input type='hidden' name='action' value='apply'>
                                        <input type='hidden' name='delay' value='0'>
                                        <input type='hidden' name='jitter' value='200'>
                                        <input type='hidden' name='loss' value='0'>
                                        <button type='submit' class='btn btn-outline-light btn-sm'>200ms</button>
                                    </form>
                                </div>
                            </div>
                            <div class='mb-3'>
                                <label class='form-label'>Pérdida Rápida:</label>
                                <div class='d-flex'>
                                    <form action='/configure' method='post' class='mx-1'>
                                        <input type='hidden' name='vlan' value='{{ vlan }}'>
                                        <input type='hidden' name='action' value='apply'>
                                        <input type='hidden' name='delay' value='0'>
                                        <input type='hidden' name='jitter' value='0'>
                                        <input type='hidden' name='loss' value='1'>
                                        <button type='submit' class='btn btn-outline-light btn-sm'>1%</button>
                                    </form>
                                    <form action='/configure' method='post' class='mx-1'>
                                        <input type='hidden' name='vlan' value='{{ vlan }}'>
                                        <input type='hidden' name='action' value='apply'>
                                        <input type='hidden' name='delay' value='0'>
                                        <input type='hidden' name='jitter' value='0'>
                                        <input type='hidden' name='loss' value='5'>
                                        <button type='submit' class='btn btn-outline-light btn-sm'>5%</button>
                                    </form>
                                    <form action='/configure' method='post' class='mx-1'>
                                        <input type='hidden' name='vlan' value='{{ vlan }}'>
                                        <input type='hidden' name='action' value='apply'>
                                        <input type='hidden' name='delay' value='0'>
                                        <input type='hidden' name='jitter' value='0'>
                                        <input type='hidden' name='loss' value='10'>
                                        <button type='submit' class='btn btn-outline-light btn-sm'>10%</button>
                                    </form>
                                </div>
                            </div>
                            <div class='chart-container'>
                                <canvas id='traffic-chart-{{ vlan }}'></canvas>
                            </div>
                            <pre class='output mt-3' id='output-{{ vlan }}'>Latencia: {{ stats[vlan].delay }} ms
Jitter: {{ stats[vlan].jitter }} ms
Pérdida: {{ stats[vlan].loss }} %
Ancho de Banda Entrada: {{ stats[vlan][current_unit + "_in"]|round(2) }} {{ current_unit }}
Ancho de Banda Salida: {{ stats[vlan][current_unit + "_out"]|round(2) }} {{ current_unit }}</pre>
                            <div class='error mt-2' id='error-{{ vlan }}'></div>
                        </div>
                    </div>
                    {% endfor %}
                </div>
                <div class='footer'>
                    <p>Ryuz WAN Simulator - Versión 1.100, Créditos: decameru@outlook.com</p>
                    <a href='mailto:decameru@outlook.com' class='btn btn-secondary'>Contacto</a>
                </div>
            </div>
            <script>
                const charts = {};
                let currentUnit = 'mbps';
                function updateCharts() {
                    currentUnit = document.getElementById('unit-select').value;
                    {% for vlan in vlans %}
                    const stats = {
                        mbps_in: {{ stats[vlan].mbps_in }},
                        mbps_out: {{ stats[vlan].mbps_out }},
                        kbps_in: {{ stats[vlan].kbps_in }},
                        kbps_out: {{ stats[vlan].kbps_out }},
                        mb_in: {{ stats[vlan].mb_in }},
                        mb_out: {{ stats[vlan].mb_out }},
                        kb_in: {{ stats[vlan].kb_in }},
                        kb_out: {{ stats[vlan].kb_out }},
                        delay: {{ stats[vlan].delay }},
                        jitter: {{ stats[vlan].jitter }},
                        loss: {{ stats[vlan].loss }}
                    };
                    const ctx = document.getElementById('traffic-chart-{{ vlan }}').getContext('2d');
                    const labels = ['Entrada', 'Salida', 'Latencia', 'Jitter', 'Pérdida'];
                    const data = [
                        stats[currentUnit + '_in'],
                        stats[currentUnit + '_out'],
                        stats.delay,
                        stats.jitter,
                        stats.loss
                    ];
                    const units = currentUnit === 'mbps' || currentUnit === 'kbps' ? ' (' + currentUnit.toUpperCase() + ')' : ' (' + currentUnit.toUpperCase() + '/s)';
                    if (charts['{{ vlan }}']) {
                        charts['{{ vlan }}'].data.datasets[0].data = data;
                        charts['{{ vlan }}'].data.labels = labels.map(label => label + (label.includes('Entrada') || label.includes('Salida') ? units : label.includes('Latencia') || label.includes('Jitter') ? ' (ms)' : ' (%)'));
                        charts['{{ vlan }}'].update();
                    } else {
                        charts['{{ vlan }}'] = new Chart(ctx, {
                            type: 'bar',
                            data: {
                                labels: labels.map(label => label + (label.includes('Entrada') || label.includes('Salida') ? units : label.includes('Latencia') || label.includes('Jitter') ? ' (ms)' : ' (%)')),
                                datasets: [{
                                    label: '{{ vlan }}',
                                    data: data,
                                    backgroundColor: [
                                        'rgba(255, 99, 132, 0.4)',
                                        'rgba(54, 162, 235, 0.4)',
                                        'rgba(255, 206, 86, 0.4)',
                                        'rgba(75, 192, 192, 0.4)',
                                        'rgba(153, 102, 255, 0.4)'
                                    ],
                                    borderColor: [
                                        'rgba(255,99,132,1)',
                                        'rgba(54,162,235,1)',
                                        'rgba(255,206,86,1)',
                                        'rgba(75,192,192,1)',
                                        'rgba(153,102,255,1)'
                                    ],
                                    borderWidth: 1
                                }]
                            },
                            options: {
                                scales: {
                                    y: { beginAtZero: true }
                                },
                                animation: {
                                    duration: 1000,
                                    easing: 'easeInOutQuad'
                                }
                            }
                        });
                    }
                    document.getElementById('output-{{ vlan }}').innerText =
                        'Latencia: ' + stats.delay.toFixed(1) + ' ms\n' +
                        'Jitter: ' + stats.jitter.toFixed(1) + ' ms\n' +
                        'Pérdida: ' + stats.loss.toFixed(1) + ' %\n' +
                        'Ancho de Banda Entrada: ' + stats[currentUnit + '_in'].toFixed(2) + ' ' + currentUnit + '\n' +
                        'Ancho de Banda Salida: ' + stats[currentUnit + '_out'].toFixed(2) + ' ' + currentUnit;
                    document.querySelector('#config-form-{{ vlan }} input[name="delay"]').value = stats.delay.toFixed(1);
                    document.querySelector('#config-form-{{ vlan }} input[name="jitter"]').value = stats.jitter.toFixed(1);
                    document.querySelector('#config-form-{{ vlan }} input[name="loss"]').value = stats.loss.toFixed(1);
                    {% endfor %}
                }
                window.onload = updateCharts;
            </script>
        </body>
        </html>
    """, vlans=VLAN_INTERFACES, stats=stats, current_unit='mbps')

@app.route('/configure', methods=['POST'])
def configure():
    logger.debug(f"POST /configure recibido con data: {request.form}")
    try:
        vlan = request.form.get('vlan')
        action = request.form.get('action')
        error_message = ""
        success_message = ""
        if not VLAN_INTERFACES:
            logger.error("VLAN_INTERFACES está vacío")
            error_message = "No hay VLANs configuradas. Verifica ${USER_HOME}/emix_abundix.conf."
        elif vlan and vlan not in VLAN_INTERFACES:
            logger.error(f"VLAN inválida: {vlan}")
            error_message = f"VLAN {vlan} no encontrada."
        else:
            if action == "apply":
                try:
                    delay = float(request.form.get('delay', 0))
                    jitter = float(request.form.get('jitter', 0))
                    loss = float(request.form.get('loss', 0))
                    if delay < 0 or jitter < 0 or loss < 0 or loss > 100:
                        logger.error(f"Parámetros inválidos para VLAN {vlan}: delay={delay}, jitter={jitter}, loss={loss}")
                        error_message = "Los parámetros deben ser no negativos y la pérdida menor o igual a 100%."
                    else:
                        run_command(f"sudo tc qdisc del dev {vlan} root netem")
                        retries = 3
                        success = False
                        output = ""
                        for attempt in range(retries):
                            success, output = run_command(f"sudo tc qdisc add dev {vlan} root netem delay {delay}ms {jitter}ms loss {loss}%")
                            if success:
                                break
                            time.sleep(1)
                        if success:
                            logger.info(f"Qdisc aplicado en {vlan}: Latencia={delay}ms, Jitter={jitter}ms, Pérdida={loss}%")
                            success_message = f"Configuración aplicada en {vlan}: Latencia={delay}ms, Jitter={jitter}ms, Pérdida={loss}%"
                        else:
                            logger.error(f"Error aplicando qdisc en {vlan}: {output}")
                            error_message = f"Error aplicando configuración: {output}"
                except ValueError as e:
                    logger.error(f"Error en parámetros para VLAN {vlan}: {e}")
                    error_message = "Los parámetros deben ser numéricos válidos."
            elif action == "reset":
                success, output = run_command(f"sudo tc qdisc del dev {vlan} root netem")
                if success:
                    logger.info(f"Qdisc restablecido en {vlan}")
                    success_message = f"Configuración restablecida en {vlan}"
                else:
                    logger.error(f"Error restableciendo qdisc en {vlan}: {output}")
                    error_message = f"Error restableciendo configuración: {output}"
            elif action == "reset_all":
                for v in VLAN_INTERFACES:
                    success, output = run_command(f"sudo tc qdisc del dev {v} root netem")
                    if not success:
                        logger.error(f"Error restableciendo qdisc en {v}: {output}")
                        error_message += f"Error en {v}: {output}\n"
                if not error_message:
                    logger.info("Restablecimiento de todas las interfaces completado")
                    success_message = "Todas las interfaces restablecidas"
        stats = {}
        for vlan in VLAN_INTERFACES:
            qdisc_success, qdisc_output = run_command(f"tc qdisc show dev {vlan}")
            stats[vlan] = parse_qdisc(qdisc_output) if qdisc_success else {"delay": 0, "jitter": 0, "loss": 0}
            stats[vlan].update(get_traffic_stats(vlan))
        return render_template_string("""
            <!DOCTYPE html>
            <html lang='es'>
            <head>
                <meta charset='UTF-8'>
                <meta name='viewport' content='width=device-width, initial-scale=1.0'>
                <title>WAN Simulator</title>
                <link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'>
                <script src='https://cdn.jsdelivr.net/npm/chart.js'></script>
                <style>
                    body { background: linear-gradient(135deg, #1e3c72, #2a5298); color: white; min-height: 100vh; font-family: 'Arial', sans-serif; }
                    .container { max-width: 1200px; padding: 20px; }
                    .card { background: rgba(255, 255, 255, 0.1); border: none; border-radius: 15px; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2); backdrop-filter: blur(10px); transition: transform 0.3s ease; }
                    .card:hover { transform: translateY(-5px); }
                    .btn { transition: all 0.3s ease; }
                    .btn:hover { transform: translateY(-2px); }
                    .form-control, .form-select { background: rgba(255, 255, 255, 0.2); color: white; border: none; }
                    .form-control:focus, .form-select:focus { background: rgba(255, 255, 255, 0.3); color: white; box-shadow: none; }
                    .chart-container { position: relative; height: 200px; }
                    .output { background: rgba(0, 0, 0, 0.3); padding: 10px; border-radius: 5px; }
                    .error { color: #ff4d4d; font-weight: bold; }
                    .success { color: #28a745; font-weight: bold; }
                    .footer { text-align: center; padding: 20px; font-size: 0.9rem; }
                    @media (max-width: 576px) {
                        .container { padding: 10px; }
                        .card { margin-bottom: 15px; }
                        .btn { font-size: 0.9rem; }
                        .form-control, .form-select { font-size: 0.9rem; }
                    }
                </style>
            </head>
            <body>
                <div class='container'>
                    <h1 class='text-center mb-4'>WAN Simulator</h1>
                    <div class='d-flex justify-content-center mb-4'>
                        <form action='/configure' method='post' class='mx-2'>
                            <input type='hidden' name='action' value='reset_all'>
                            <button type='submit' class='btn btn-primary'>Restablecer Todas las Interfaces</button>
                        </form>
                        <select id='unit-select' class='form-select w-auto mx-2' onchange='updateCharts()'>
                            <option value='mbps'>Mbps</option>
                            <option value='kbps'>Kbps</option>
                            <option value='mb'>MB</option>
                            <option value='kb'>KB</option>
                        </select>
                    </div>
                    {% if error_message %}
                    <div class='alert alert-danger'>{{ error_message }}</div>
                    {% endif %}
                    {% if success_message %}
                    <div class='alert alert-success'>{{ success_message }}</div>
                    {% endif %}
                    {% if vlans %}
                    <div class='row'>
                        {% for vlan in vlans %}
                        <div class='col-md-6 col-lg-4 mb-4'>
                            <div class='card p-4'>
                                <h3 class='text-center'>Interfaz: {{ vlan }}</h3>
                                <form action='/configure' method='post' id='config-form-{{ vlan }}'>
                                    <input type='hidden' name='vlan' value='{{ vlan }}'>
                                    <input type='hidden' name='action' value='apply'>
                                    <div class='mb-3'>
                                        <label class='form-label'>Latencia (ms):</label>
                                        <input type='number' class='form-control' name='delay' value='{{ stats[vlan].delay }}' min='0' step='0.1'>
                                    </div>
                                    <div class='mb-3'>
                                        <label class='form-label'>Jitter (ms):</label>
                                        <input type='number' class='form-control' name='jitter' value='{{ stats[vlan].jitter }}' min='0' step='0.1'>
                                    </div>
                                    <div class='mb-3'>
                                        <label class='form-label'>Pérdida (%):</label>
                                        <input type='number' class='form-control' name='loss' value='{{ stats[vlan].loss }}' min='0' max='100' step='0.1'>
                                    </div>
                                    <div class='d-flex justify-content-center mb-3'>
                                        <button type='submit' class='btn btn-primary mx-1'>Aplicar</button>
                                        <button type='submit' class='btn btn-warning mx-1' formaction='/configure' onclick='this.form.elements["action"].value="reset"'>Restablecer</button>
                                    </div>
                                </form>
                                <div class='mb-3'>
                                    <label class='form-label'>Latencia Rápida:</label>
                                    <div class='d-flex'>
                                        <form action='/configure' method='post' class='mx-1'>
                                            <input type='hidden' name='vlan' value='{{ vlan }}'>
                                            <input type='hidden' name='action' value='apply'>
                                            <input type='hidden' name='delay' value='100'>
                                            <input type='hidden' name='jitter' value='0'>
                                            <input type='hidden' name='loss' value='0'>
                                            <button type='submit' class='btn btn-outline-light btn-sm'>100ms</button>
                                        </form>
                                        <form action='/configure' method='post' class='mx-1'>
                                            <input type='hidden' name='vlan' value='{{ vlan }}'>
                                            <input type='hidden' name='action' value='apply'>
                                            <input type='hidden' name='delay' value='300'>
                                            <input type='hidden' name='jitter' value='0'>
                                            <input type='hidden' name='loss' value='0'>
                                            <button type='submit' class='btn btn-outline-light btn-sm'>300ms</button>
                                        </form>
                                        <form action='/configure' method='post' class='mx-1'>
                                            <input type='hidden' name='vlan' value='{{ vlan }}'>
                                            <input type='hidden' name='action' value='apply'>
                                            <input type='hidden' name='delay' value='500'>
                                            <input type='hidden' name='jitter' value='0'>
                                            <input type='hidden' name='loss' value='0'>
                                            <button type='submit' class='btn btn-outline-light btn-sm'>500ms</button>
                                        </form>
                                    </div>
                                </div>
                                <div class='mb-3'>
                                    <label class='form-label'>Jitter Rápido:</label>
                                    <div class='d-flex'>
                                        <form action='/configure' method='post' class='mx-1'>
                                            <input type='hidden' name='vlan' value='{{ vlan }}'>
                                            <input type='hidden' name='action' value='apply'>
                                            <input type='hidden' name='delay' value='0'>
                                            <input type='hidden' name='jitter' value='50'>
                                            <input type='hidden' name='loss' value='0'>
                                            <button type='submit' class='btn btn-outline-light btn-sm'>50ms</button>
                                        </form>
                                        <form action='/configure' method='post' class='mx-1'>
                                            <input type='hidden' name='vlan' value='{{ vlan }}'>
                                            <input type='hidden' name='action' value='apply'>
                                            <input type='hidden' name='delay' value='0'>
                                            <input type='hidden' name='jitter' value='100'>
                                            <input type='hidden' name='loss' value='0'>
                                            <button type='submit' class='btn btn-outline-light btn-sm'>100ms</button>
                                        </form>
                                        <form action='/configure' method='post' class='mx-1'>
                                            <input type='hidden' name='vlan' value='{{ vlan }}'>
                                            <input type='hidden' name='action' value='apply'>
                                            <input type='hidden' name='delay' value='0'>
                                            <input type='hidden' name='jitter' value='200'>
                                            <input type='hidden' name='loss' value='0'>
                                            <button type='submit' class='btn btn-outline-light btn-sm'>200ms</button>
                                        </form>
                                    </div>
                                </div>
                                <div class='mb-3'>
                                    <label class='form-label'>Pérdida Rápida:</label>
                                    <div class='d-flex'>
                                        <form action='/configure' method='post' class='mx-1'>
                                            <input type='hidden' name='vlan' value='{{ vlan }}'>
                                            <input type='hidden' name='action' value='apply'>
                                            <input type='hidden' name='delay' value='0'>
                                            <input type='hidden' name='jitter' value='0'>
                                            <input type='hidden' name='loss' value='1'>
                                            <button type='submit' class='btn btn-outline-light btn-sm'>1%</button>
                                        </form>
                                        <form action='/configure' method='post' class='mx-1'>
                                            <input type='hidden' name='vlan' value='{{ vlan }}'>
                                            <input type='hidden' name='action' value='apply'>
                                            <input type='hidden' name='delay' value='0'>
                                            <input type='hidden' name='jitter' value='0'>
                                            <input type='hidden' name='loss' value='5'>
                                            <button type='submit' class='btn btn-outline-light btn-sm'>5%</button>
                                        </form>
                                        <form action='/configure' method='post' class='mx-1'>
                                            <input type='hidden' name='vlan' value='{{ vlan }}'>
                                            <input type='hidden' name='action' value='apply'>
                                            <input type='hidden' name='delay' value='0'>
                                            <input type='hidden' name='jitter' value='0'>
                                            <input type='hidden' name='loss' value='10'>
                                            <button type='submit' class='btn btn-outline-light btn-sm'>10%</button>
                                        </form>
                                    </div>
                                </div>
                                <div class='chart-container'>
                                    <canvas id='traffic-chart-{{ vlan }}'></canvas>
                                </div>
                                <pre class='output mt-3' id='output-{{ vlan }}'>Latencia: {{ stats[vlan].delay }} ms
Jitter: {{ stats[vlan].jitter }} ms
Pérdida: {{ stats[vlan].loss }} %
Ancho de Banda Entrada: {{ stats[vlan][current_unit + "_in"]|round(2) }} {{ current_unit }}
Ancho de Banda Salida: {{ stats[vlan][current_unit + "_out"]|round(2) }} {{ current_unit }}</pre>
                                <div class='error mt-2' id='error-{{ vlan }}'></div>
                            </div>
                        </div>
                        {% endfor %}
                    </div>
                    <div class='footer'>
                        <p>Ryuz WAN Simulator - Versión 1.100, Créditos: decameru@outlook.com</p>
                        <a href='mailto:decameru@outlook.com' class='btn btn-secondary'>Contacto</a>
                    </div>
                </div>
                <script>
                    const charts = {};
                    let currentUnit = 'mbps';
                    function updateCharts() {
                        currentUnit = document.getElementById('unit-select').value;
                        {% for vlan in vlans %}
                        const stats = {
                            mbps_in: {{ stats[vlan].mbps_in }},
                            mbps_out: {{ stats[vlan].mbps_out }},
                            kbps_in: {{ stats[vlan].kbps_in }},
                            kbps_out: {{ stats[vlan].kbps_out }},
                            mb_in: {{ stats[vlan].mb_in }},
                            mb_out: {{ stats[vlan].mb_out }},
                            kb_in: {{ stats[vlan].kb_in }},
                            kb_out: {{ stats[vlan].kb_out }},
                            delay: {{ stats[vlan].delay }},
                            jitter: {{ stats[vlan].jitter }},
                            loss: {{ stats[vlan].loss }}
                        };
                        const ctx = document.getElementById('traffic-chart-{{ vlan }}').getContext('2d');
                        const labels = ['Entrada', 'Salida', 'Latencia', 'Jitter', 'Pérdida'];
                        const data = [
                            stats[currentUnit + '_in'],
                            stats[currentUnit + '_out'],
                            stats.delay,
                            stats.jitter,
                            stats.loss
                        ];
                        const units = currentUnit === 'mbps' || currentUnit === 'kbps' ? ' (' + currentUnit.toUpperCase() + ')' : ' (' + currentUnit.toUpperCase() + '/s)';
                        if (charts['{{ vlan }}']) {
                            charts['{{ vlan }}'].data.datasets[0].data = data;
                            charts['{{ vlan }}'].data.labels = labels.map(label => label + (label.includes('Entrada') || label.includes('Salida') ? units : label.includes('Latencia') || label.includes('Jitter') ? ' (ms)' : ' (%)'));
                            charts['{{ vlan }}'].update();
                        } else {
                            charts['{{ vlan }}'] = new Chart(ctx, {
                                type: 'bar',
                                data: {
                                    labels: labels.map(label => label + (label.includes('Entrada') || label.includes('Salida') ? units : label.includes('Latencia') || label.includes('Jitter') ? ' (ms)' : ' (%)')),
                                    datasets: [{
                                        label: '{{ vlan }}',
                                        data: data,
                                        backgroundColor: [
                                            'rgba(255, 99, 132, 0.4)',
                                            'rgba(54, 162, 235, 0.4)',
                                            'rgba(255, 206, 86, 0.4)',
                                            'rgba(75, 192, 192, 0.4)',
                                            'rgba(153, 102, 255, 0.4)'
                                        ],
                                        borderColor: [
                                            'rgba(255,99,132,1)',
                                            'rgba(54,162,235,1)',
                                            'rgba(255,206,86,1)',
                                            'rgba(75,192,192,1)',
                                            'rgba(153,102,255,1)'
                                        ],
                                        borderWidth: 1
                                    }]
                                },
                                options: {
                                    scales: {
                                        y: { beginAtZero: true }
                                    },
                                    animation: {
                                        duration: 1000,
                                        easing: 'easeInOutQuad'
                                    }
                                }
                            });
                        }
                        document.getElementById('output-{{ vlan }}').innerText =
                            'Latencia: ' + stats.delay.toFixed(1) + ' ms\n' +
                            'Jitter: ' + stats.jitter.toFixed(1) + ' ms\n' +
                            'Pérdida: ' + stats.loss.toFixed(1) + ' %\n' +
                            'Ancho de Banda Entrada: ' + stats[currentUnit + '_in'].toFixed(2) + ' ' + currentUnit + '\n' +
                            'Ancho de Banda Salida: ' + stats[currentUnit + '_out'].toFixed(2) + ' ' + currentUnit;
                        document.querySelector('#config-form-{{ vlan }} input[name="delay"]').value = stats.delay.toFixed(1);
                        document.querySelector('#config-form-{{ vlan }} input[name="jitter"]').value = stats.jitter.toFixed(1);
                        document.querySelector('#config-form-{{ vlan }} input[name="loss"]').value = stats.loss.toFixed(1);
                        {% endfor %}
                    }
                    window.onload = updateCharts;
                </script>
            </body>
            </html>
        """, vlans=VLAN_INTERFACES, stats=stats, current_unit='mbps')

if __name__ == "__main__":
    port = app.config['PORT']
    logger.info(f"Iniciando servidor Flask en 0.0.0.0:{port}...")
    try:
        app.run(host="0.0.0.0", port=port)
    except Exception as e:
        logger.error(f"Error iniciando Flask: {e}")
        sys.exit(1)
EOF

# Configurar permisos del archivo del dashboard
log_message "DEBUG" "Configurando permisos para $WANSIM_DASHBOARD..."
if ! chmod 755 "$WANSIM_DASHBOARD"; then
    log_message "ERROR" "No se pudo establecer permisos para $WANSIM_DASHBOARD."
    echo "${COLOR_ERROR}No se pudo establecer permisos para $WANSIM_DASHBOARD. Revisa con 'ls -l $WANSIM_DASHBOARD'.${COLOR_RESET}"
    exit 1
fi
if ! chown "$CURRENT_USER:$CURRENT_USER" "$WANSIM_DASHBOARD"; then
    log_message "ERROR" "No se pudo cambiar propietario de $WANSIM_DASHBOARD."
    echo "${COLOR_ERROR}No se pudo cambiar propietario de $WANSIM_DASHBOARD. Revisa con 'ls -l $WANSIM_DASHBOARD'.${COLOR_RESET}"
    exit 1
fi
log_message "OK" "wansim_dashboard.py generado."
# Verificar sintaxis del script Python
log_message "DEBUG" "Verificando sintaxis de $WANSIM_DASHBOARD..."
if ! python3 -m py_compile "$WANSIM_DASHBOARD"; then
    log_message "ERROR" "Error de sintaxis en $WANSIM_DASHBOARD."
    echo "${COLOR_ERROR}Error de sintaxis en $WANSIM_DASHBOARD. Revisa con 'python3 -m py_compile $WANSIM_DASHBOARD'.${COLOR_RESET}"
    exit 1
fi
log_message "OK" "Sintaxis de $WANSIM_DASHBOARD verificada."


# SECCIÓN 7: Finalización y Notificaciones
# ---------------------------------------
# Generar tokens de API
log_message "INFO" "Generando tokens de API..."
cat > "$API_TOKENS" <<EOF
{
    "tokens": [
        {"token": "$(openssl rand -hex 16)", "role": "admin"},
        {"token": "$(openssl rand -hex 16)", "role": "viewer"}
    ]
}
EOF
chmod 640 "$API_TOKENS"
chown "$CURRENT_USER:$CURRENT_USER" "$API_TOKENS"
log_message "OK" "Tokens de API generados en $API_TOKENS."

# Mostrar resumen de configuración
HOSTNAME=$(hostname)
echo "${COLOR_CYAN}┌════════════════════ Resumen de Configuración ═══════════┐${COLOR_RESET}"
echo "${COLOR_CYAN}│                                                        │${COLOR_RESET}"
if [ "$TOPOLOGY_MODE" = "bridge" ]; then
    echo "${COLOR_CYAN}│ ${COLOR_GREEN}LAN:${COLOR_RESET} $LAN_IF${COLOR_CYAN}                                        │${COLOR_RESET}"
    echo "${COLOR_CYAN}│       |                                                │${COLOR_RESET}"
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}$HOSTNAME${COLOR_CYAN}                                          │${COLOR_RESET}"
    echo "${COLOR_CYAN}│       |                                                │${COLOR_RESET}"
    echo "${COLOR_CYAN}│ ${COLOR_GREEN}Destino:${COLOR_RESET} $DEST_IF${COLOR_CYAN}                                  │${COLOR_RESET}"
    echo "${COLOR_CYAN}│                                                        │${COLOR_RESET}"
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}Control de Tráfico:${COLOR_RESET} $( [ "$CONFIG_TC" = "s" ] && echo "Habilitado" || echo "Deshabilitado")${COLOR_CYAN}                    │${COLOR_RESET}"
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}Gestión con Salida a Internet:${COLOR_RESET} $( [ "$IS_MGMT" = "s" ] && echo "Sí" || echo "No")${COLOR_RESET}"
else
    echo "${COLOR_CYAN}│ ${COLOR_GREEN}WAN:${COLOR_RESET} $WAN_IF${COLOR_CYAN}                                        │${COLOR_RESET}"
    echo "${COLOR_CYAN}│       |                                                │${COLOR_RESET}"
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}$HOSTNAME${COLOR_CYAN}                                          │${COLOR_RESET}"
    echo "${COLOR_CYAN}│       |                                                │${COLOR_RESET}"
    echo "${COLOR_CYAN}│ ${COLOR_GREEN}LAN:${COLOR_RESET} $LAN_IF (Trunk VLAN)${COLOR_CYAN}                         │${COLOR_RESET}"
    echo "${COLOR_CYAN}│ ┌──────────────────────────────┐                       │${COLOR_RESET}"
    for (( i=0; i<${NUM_VLANS:-0} && i<2; i++ )); do
        current_vlan_id=$(( ${START_VLAN:-100} + i ))
        subnet_octet=$(( ${BASE_OCTET:-10} + i ))
        printf "${COLOR_CYAN}│ │ ${COLOR_CYAN}vlan%-4s:${COLOR_RESET} %-16s │                       │${COLOR_RESET}\n" "$current_vlan_id" "${SEGMENT_PREFIX:-192.168}.$subnet_octet.1"
    done
    if [ ${NUM_VLANS:-0} -gt 2 ]; then
        echo "${COLOR_CYAN}│ │ ${COLOR_CYAN}... (total $NUM_VLANS VLANs)${COLOR_CYAN}                    │${COLOR_RESET}"
    fi
    echo "${COLOR_CYAN}│ └──────────────────────────────┐                       │${COLOR_RESET}"
fi
echo "${COLOR_CYAN}│                                                        │${COLOR_RESET}"
echo "${COLOR_CYAN}│ ${COLOR_CYAN}Topología:${COLOR_RESET} $TOPOLOGY_MODE${COLOR_CYAN}                              │${COLOR_RESET}"
if [ "$TOPOLOGY_MODE" = "bridge" ]; then
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}Interfaz LAN:${COLOR_RESET} $LAN_IF${COLOR_CYAN}                            │${COLOR_RESET}"
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}Interfaz Destino:${COLOR_RESET} $DEST_IF${COLOR_CYAN}                      │${COLOR_RESET}"
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}Control de Tráfico:${COLOR_RESET} $( [ "$CONFIG_TC" = "s" ] && echo "Habilitado" || echo "Deshabilitado")${COLOR_CYAN}               │${COLOR_RESET}"
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}Gestión con Salida a Internet:${COLOR_RESET} $( [ "$IS_MGMT" = "s" ] && echo "Sí" || echo "No")${COLOR_CYAN}          │${COLOR_RESET}"
else
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}VLANs:${COLOR_RESET} ${NUM_VLANS:-0} (ID inicial: ${START_VLAN:-0})${COLOR_CYAN}             │${COLOR_RESET}"
    if [ "$CONFIG_DHCP" = "s" ]; then
        echo "${COLOR_CYAN}│ ${COLOR_CYAN}DHCP:${COLOR_RESET} Sí (Segmento base: ${SEGMENT_PREFIX:-192.168}.X.0/24, Tercer octeto inicial: ${BASE_OCTET:-10})${COLOR_CYAN} │${COLOR_RESET}"
    else
        echo "${COLOR_CYAN}│ ${COLOR_CYAN}DHCP:${COLOR_RESET} No${COLOR_CYAN}                                       │${COLOR_RESET}"
    fi
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}WAN:${COLOR_RESET} $WAN_IF${COLOR_CYAN}                                        │${COLOR_RESET}"
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}LAN:${COLOR_RESET} $LAN_IF${COLOR_CYAN}                                        │${COLOR_RESET}"
fi
echo "${COLOR_CYAN}│ ${COLOR_CYAN}Bot de Telegram:${COLOR_RESET} $( [ "$INTEGRATE_TELEGRAM" = "s" ] && echo "Sí" || echo "No")${COLOR_CYAN}                        │${COLOR_RESET}"
echo "${COLOR_CYAN}│                                                        │${COLOR_RESET}"
echo "${COLOR_CYAN}└════════════════════ Configuración Completada ══════════┘${COLOR_RESET}"

# Confirmar generación de archivos
if [ "$INTERACTIVE" -eq 1 ]; then
    echo "${COLOR_CYAN}┌─────────────────── Continuar Generación ───────────────────┐${COLOR_RESET}"
    read -p "${COLOR_INFO}[ENTRADA] ¿Continuar con la generación de archivos? (s/n): ${COLOR_RESET}" CONFIRM
    echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"
    if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then
        log_message "INFO" "Generación cancelada por el usuario."
        echo "${COLOR_INFO}Ejecución terminada.${COLOR_RESET}"
        exit 0
    fi
fi

# Notificación a Telegram si está configurado
if [ "$INTEGRATE_TELEGRAM" = "s" ]; then
    log_message "INFO" "Enviando notificación a Telegram..."
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="Ryuz WAN Simulator configurado en $HOST_IP. Dashboard: http://$HOST_IP:$DASHBOARD_PORT" > /dev/null
    if [ $? -eq 0 ]; then
        log_message "OK" "Notificación enviada a Telegram."
    else
        log_message "ERROR" "Fallo al enviar notificación a Telegram."
    fi
fi

# Mostrar URL del dashboard y código QR
HTTP_URL="http://$HOST_IP:$DASHBOARD_PORT"
echo "${COLOR_INFO}Dashboard disponible en: $HTTP_URL${COLOR_RESET}"
if command -v qrencode >/dev/null 2>&1; then
    qrencode -t ANSIUTF8 "$HTTP_URL"
else
    log_message "ADVERTENCIA" "qrencode no está instalado. No se puede generar el código QR."
    echo "${COLOR_WARN}No se pudo generar el código QR. Instala qrencode para habilitar esta función.${COLOR_RESET}"
fi

# Mensaje final
echo "${COLOR_OK}Script completado. Revisa $LOGFILE para más detalles.${COLOR_RESET}"



















