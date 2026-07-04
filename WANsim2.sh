#!/bin/bash

## SECCIÓN 1: Comienzo
# -----------------------------------------------

set -e
exec > >(tee -a /tmp/wansim_debug.log) 2>&1

# SECCIÓN 1: Configuración Inicial y Funciones Auxiliares
# -----------------------------------------------
# Variables de configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WANSIM_VERSION="$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "1.109")"
USER_HOME="${HOME:-$(getent passwd "$(whoami)" | cut -d: -f6)}"
LOGFILE="$USER_HOME/emix_abundix.log"
CONFIG_FILE="$USER_HOME/emix_abundix.conf"
WANSIM_DASHBOARD="$USER_HOME/wansim_dashboard.py"
API_TOKENS="$USER_HOME/api_tokens.json"
SERVICE_FILE="/etc/systemd/system/wansim.service"
PERSIST_SCRIPT="/usr/local/sbin/wansim_l2_persist.sh"
PERSIST_SERVICE="/etc/systemd/system/wansim-l2-persist.service"
NETEM_STATE_FILE="$USER_HOME/wansim_netem_state.json"
CURRENT_USER=$(whoami)
DASHBOARD_PORT=5000
HOST_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
IS_RASPBERRY=$(grep -qi "Raspberry Pi" /proc/cpuinfo && echo "si" || echo "no")
OS_FAMILY=""
PKG_MANAGER=""
DHCP_SERVICE=""
DHCP_DEFAULT_FILE=""
IPTABLES_SAVE_FILE="/etc/iptables/rules.v4"

# Colores para la salida en consola
COLOR_INFO=$(tput setaf 6)
COLOR_OK=$(tput setaf 2)
COLOR_ERROR=$(tput setaf 1)
COLOR_WARN=$(tput setaf 3)
COLOR_DEBUG=$(tput setaf 4)
COLOR_GREEN=$(tput setaf 2)
COLOR_CYAN=$(tput setaf 6)
COLOR_RESET=$(tput sgr0)

# Asegurar permisos del archivo de log principal
log_message() {
    local tipo_msg="$1"
    local contenido_msg="$2"
    local marca_tiempo=$(date '+%Y-%m-%d %H:%M:%S')
    local linea=$(caller 0 | awk '{print $1}')
    local mensaje_completo="[$marca_tiempo] [$tipo_msg] Línea $linea: $contenido_msg"
    echo "$mensaje_completo" >> "/tmp/wansim_debug.log"  # Escribir temporalmente en debug log
    case "$tipo_msg" in
        INFO) echo "${COLOR_INFO}[INFO] $contenido_msg${COLOR_RESET}" ;;
        OK) echo "${COLOR_OK}[OK] $contenido_msg${COLOR_RESET}" ;;
        ERROR) echo "${COLOR_ERROR}[ERROR] $contenido_msg${COLOR_RESET}" ;;
        ADVERTENCIA) echo "${COLOR_WARN}[ADVERTENCIA] $contenido_msg${COLOR_RESET}" ;;
        DEBUG) echo "${COLOR_DEBUG}[DEBUG] $contenido_msg${COLOR_RESET}" ;;
    esac
}

if [ -f "$LOGFILE" ]; then
    if ! sudo rm -f "$LOGFILE"; then
        log_message "ERROR" "No se pudo eliminar el archivo de log existente $LOGFILE."
        echo "${COLOR_ERROR}No se pudo eliminar $LOGFILE. Revisa permisos con 'ls -l $LOGFILE'.${COLOR_RESET}"
        exit 1
    fi
fi
touch "$LOGFILE" || {
    log_message "ERROR" "No se pudo crear el archivo de log $LOGFILE."
    echo "${COLOR_ERROR}No se pudo crear $LOGFILE. Revisa permisos con 'ls -ld $USER_HOME'.${COLOR_RESET}"
    exit 1
}
chmod 640 "$LOGFILE"
chown "$CURRENT_USER:$CURRENT_USER" "$LOGFILE"

# Redefinir log_message para usar LOGFILE ahora que existe
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

detect_platform() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID_LIKE:-$ID}" in
            *debian*|*ubuntu*)
                OS_FAMILY="debian"
                ;;
            *rhel*|*fedora*|*centos*|*rocky*)
                OS_FAMILY="rhel"
                ;;
            *)
                OS_FAMILY="${ID:-unknown}"
                ;;
        esac
    fi

    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt"
        OS_FAMILY="debian"
        DHCP_SERVICE="isc-dhcp-server"
        DHCP_DEFAULT_FILE="/etc/default/isc-dhcp-server"
        IPTABLES_SAVE_FILE="/etc/iptables/rules.v4"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        [ -z "$OS_FAMILY" ] && OS_FAMILY="rhel"
        DHCP_SERVICE="dhcpd"
        DHCP_DEFAULT_FILE="/etc/sysconfig/dhcpd"
        IPTABLES_SAVE_FILE="/etc/sysconfig/iptables"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        [ -z "$OS_FAMILY" ] && OS_FAMILY="rhel"
        DHCP_SERVICE="dhcpd"
        DHCP_DEFAULT_FILE="/etc/sysconfig/dhcpd"
        IPTABLES_SAVE_FILE="/etc/sysconfig/iptables"
    else
        log_message "ERROR" "No se encontró apt-get, dnf ni yum."
        echo "${COLOR_ERROR}Sistema no soportado: se requiere apt-get, dnf o yum.${COLOR_RESET}"
        exit 1
    fi

    log_message "OK" "Plataforma detectada: familia=$OS_FAMILY gestor=$PKG_MANAGER dhcp=$DHCP_SERVICE"
}

pkg_installed() {
    local dep="$1"
    case "$PKG_MANAGER" in
        apt) dpkg -l | grep -qw "$dep" ;;
        dnf|yum) rpm -q "$dep" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

pkg_update() {
    case "$PKG_MANAGER" in
        apt) sudo DEBIAN_FRONTEND=noninteractive apt-get update ;;
        dnf) sudo dnf makecache -y ;;
        yum) sudo yum makecache -y ;;
    esac
}

preseed_debian_package() {
    local dep="$1"
    case "$dep" in
        iptables-persistent|netfilter-persistent)
            if command -v debconf-set-selections >/dev/null 2>&1; then
                log_message "INFO" "Preaprobando dialogos de $dep para instalacion no interactiva..."
                {
                    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true"
                    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true"
                } | sudo debconf-set-selections || true
            fi
            ;;
    esac
}

pkg_install() {
    local dep="$1"
    case "$PKG_MANAGER" in
        apt)
            preseed_debian_package "$dep"
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
                -o Dpkg::Options::="--force-confdef" \
                -o Dpkg::Options::="--force-confold" \
                "$dep"
            ;;
        dnf) sudo dnf install -y "$dep" ;;
        yum) sudo yum install -y "$dep" ;;
    esac
}

set_dependency_list() {
    if [ "$PKG_MANAGER" = "apt" ]; then
        DEPENDENCIES=("python3" "python3-pip" "iproute2" "ifstat" "qrencode" "net-tools" "vlan" "sudo" "lsof" "isc-dhcp-server" "iptables-persistent")
        LOCK_FILES=("/var/lib/dpkg/lock-frontend" "/var/lib/apt/lists/lock" "/var/cache/apt/archives/lock")
    else
        DEPENDENCIES=("python3" "python3-pip" "iproute" "ifstat" "qrencode" "net-tools" "sudo" "lsof" "dhcp-server" "iptables-services")
        LOCK_FILES=()
    fi
}

# Rutina robusta para deshacer bridges L2 generados por WAN Simulator
cleanup_bridges() {
    log_message "INFO" "Restaurando bridges L2 generados por WAN Simulator..."
    local bridge_list=""
    bridge_list=$(ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2}' | cut -d'@' -f1 | grep '^br_wan' || true)
    if [ -z "$bridge_list" ]; then
        log_message "DEBUG" "No se encontraron bridges br_wan* existentes."
        return 0
    fi
    while IFS= read -r br; do
        [ -z "$br" ] && continue
        log_message "INFO" "Deshaciendo bridge $br..."
        local members=""
        members=$(find /sys/class/net/"$br"/brif -maxdepth 1 -mindepth 1 -printf '%f\n' 2>/dev/null || true)
        while IFS= read -r iface; do
            [ -z "$iface" ] && continue
            log_message "INFO" "Liberando interfaz $iface de $br y limpiando qdisc..."
            sudo tc qdisc del dev "$iface" root >/dev/null 2>&1 || true
            sudo ip link set "$iface" nomaster >/dev/null 2>&1 || true
            sudo ip link set "$iface" up >/dev/null 2>&1 || true
        done <<< "$members"
        sudo ip link set "$br" down >/dev/null 2>&1 || true
        sudo ip link delete "$br" type bridge >/dev/null 2>&1 || true
        if ip link show "$br" >/dev/null 2>&1; then
            log_message "ADVERTENCIA" "No se pudo eliminar completamente $br. Verifica con 'ip link show type bridge'."
        else
            log_message "OK" "Bridge $br eliminado y miembros restaurados."
        fi
    done <<< "$bridge_list"
}

# Función de limpieza
cleanup() {
    cleanup_bridges
    log_message "INFO" "Iniciando limpieza de archivos generados..."
    local archivos=("$CONFIG_FILE" "$WANSIM_DASHBOARD" "$API_TOKENS" "$LOGFILE" "/tmp/wansim_debug.log" "/tmp/server.crt" "/tmp/server.key")
    for archivo in "${archivos[@]}"; do
        if [ -f "$archivo" ]; then
            shred -u "$archivo" 2>/dev/null || rm -f "$archivo" 2>/dev/null
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
    sudo systemctl disable --now wansim-l2-persist.service >/dev/null 2>&1 || true
    sudo rm -f "$PERSIST_SERVICE" "$PERSIST_SCRIPT" "$NETEM_STATE_FILE" 2>/dev/null || true
    sudo rm -f "$SERVICE_FILE" 2>/dev/null && log_message "OK" "Eliminado $SERVICE_FILE" || log_message "ERROR" "No se pudo eliminar $SERVICE_FILE"
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
echo "Intentando liberar el puerto 5000..."
for attempt in {1..20}; do
    pid=$(sudo fuser 5000/tcp 2>/dev/null | awk '{print $1}')
    if [ -n "$pid" ]; then
        echo "Terminando proceso $pid en puerto 5000..."
        sudo kill -9 "$pid" 2>/dev/null
        sleep 1
    else
        echo "Puerto 5000 liberado."
        break
    fi
    if [ "$attempt" -eq 20 ]; then
        echo "ERROR: No se pudo liberar el puerto 5000 después de 20 intentos."
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
detect_platform
set_dependency_list

# Configurar permisos de sudo para el usuario actual
log_message "DEBUG" "Configurando permisos de sudo para $CURRENT_USER..."
SUDOERS_FILE="/etc/sudoers.d/wansim"
SUDOERS_CONTENT="$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/dnf, /usr/bin/yum, /usr/sbin/tc, /usr/bin/tc, /usr/sbin/ip, /usr/bin/ip, /usr/sbin/iptables, /usr/sbin/iptables-save, /usr/sbin/sysctl, /usr/sbin/dhcpd, /usr/bin/systemctl, /usr/bin/systemctl stop unattended-upgrades, /usr/bin/systemctl restart wansim.service, /usr/bin/fuser, /usr/bin/kill, /usr/bin/rm, /usr/sbin/dpkg, /usr/bin/tee, /usr/bin/mv, /usr/bin/chmod, /usr/bin/chown"
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
if ! pkg_update; then
    log_message "ERROR" "No se pudo actualizar la lista de paquetes."
    echo "${COLOR_ERROR}No se pudo conectar con los servidores de paquetes. Verifica tu conexión a internet.${COLOR_RESET}"
    exit 1
fi
log_message "OK" "Lista de paquetes actualizada."

# Verificar e instalar dependencias del sistema
log_message "DEBUG" "Verificando e instalando dependencias..."
for dep in "${DEPENDENCIES[@]}"; do
    if ! pkg_installed "$dep"; then
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
            sudo systemctl stop unattended-upgrades 2>/dev/null || true
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
            if ! pkg_update; then
                log_message "ERROR" "No se pudo actualizar la lista de paquetes tras liberar bloqueos."
                echo "${COLOR_ERROR}Fallo al preparar el sistema. Intenta de nuevo más tarde.${COLOR_RESET}"
                exit 1
            fi
            log_message "OK" "Sistema preparado tras liberar bloqueos."
        fi
        if ! pkg_install "$dep"; then
            log_message "ERROR" "No se pudo instalar $dep."
            echo "${COLOR_ERROR}No se pudo instalar $dep. Verifica tu conexión a internet o intenta de nuevo.${COLOR_RESET}"
            exit 1
        fi
        log_message "OK" "$dep instalado."
    else
        log_message "OK" "$dep ya está instalado."
    fi
done

# Asegurar que pip3 esté en el PATH
export PATH="$HOME/.local/bin:$PATH"

# Verificar que pip3 esté disponible
if ! command -v pip3 >/dev/null 2>&1; then
    log_message "ERROR" "No se encontró pip3 tras instalar python3-pip."
    echo "${COLOR_ERROR}No se pudo configurar el instalador de paquetes de Python. Intenta reinstalar python3-pip con tu gestor de paquetes.${COLOR_RESET}"
    exit 1
fi
log_message "OK" "pip3 encontrado en $(which pip3)."

# Instalando dependencias de Python
log_message "DEBUG" "Instalando dependencias de Python..."
PYTHON_DEPS=("flask" "requests" "pyOpenSSL")
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
log_message "INFO" "Instalando versión compatible de python-telegram-bot (13.15)..."
if ! pip3 install --user --force-reinstall "python-telegram-bot==13.15" --no-warn-script-location; then
    log_message "ERROR" "Falló la instalación de python-telegram-bot==13.15."
    echo "${COLOR_ERROR}No se pudo instalar python-telegram-bot==13.15.${COLOR_RESET}"
    exit 1
fi
log_message "OK" "Dependencias de Python instaladas."

# Mostrar banner
log_message "DEBUG" "Iniciando configuración interactiva de Ryuz WAN Simulator..."
clear
cat << EOF
┌═════════════════════════════════════════════════════════════┐
│                                                             │
│  Ryuz WAN Simulator - Versión $WANSIM_VERSION                         │
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
    echo "${COLOR_CYAN}│  1) L3 / NAT único (VLANs + DHCP + salida a Internet)     │${COLOR_RESET}"
    echo "${COLOR_CYAN}│  2) Bridge (intervenir interfaces físicas, 1 a 3)         │${COLOR_RESET}"
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

    echo "${COLOR_CYAN}┌─────────────────── Interfaces de Red ─────────────────────┐${COLOR_RESET}"
    echo "${COLOR_CYAN}│ Interfaces de red disponibles en el sistema local:       │${COLOR_RESET}"
    DEFAULT_IF=$(ip route | awk '/default/ {print $5; exit}')
    VALID_INTERFACES=()
    while IFS= read -r iface; do
        if ip link show "$iface" >/dev/null 2>&1; then
            VALID_INTERFACES+=("$iface")
            IP_ADDR=$(ip -o -4 addr show "$iface" 2>/dev/null | awk '{print $4}' | cut -d'/' -f1 | head -n 1)
            MAC_ADDR=$(cat "/sys/class/net/$iface/address" 2>/dev/null || echo "N/A")
            STATE=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo "unknown")
            if [ -n "$IP_ADDR" ]; then
                echo "${COLOR_GREEN}  - $iface (IP: $IP_ADDR, MAC: $MAC_ADDR, Estado: $STATE)${COLOR_RESET}"
            else
                echo "${COLOR_GREEN}  - $iface (Sin IP, MAC: $MAC_ADDR, Estado: $STATE)${COLOR_RESET}"
            fi
            if [ "$iface" = "$DEFAULT_IF" ]; then
                echo "${COLOR_CYAN}    Salida a Internet detectada${COLOR_RESET}"
            fi
        fi
    done < <(find /sys/class/net -maxdepth 1 -type l -printf '%f\n' | grep -Ev '^(lo|docker.*|br-[a-f0-9]+|veth.*|virbr.*|tun.*|tap.*)$' | sort)
    echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"

    if [ "$TOPOLOGY_MODE" = "bridge" ]; then
        echo "${COLOR_CYAN}┌─────────────────── Modo Bridge L2 ────────────────────────┐${COLOR_RESET}"
        echo "${COLOR_CYAN}│ Define de 1 a 3 bridges. Cada bridge usa 2 interfaces:    │${COLOR_RESET}"
        echo "${COLOR_CYAN}│ una de ENTRADA y una de SALIDA.                           │${COLOR_RESET}"
        echo "${COLOR_CYAN}│ Flask y Telegram controlarán cada puerto físico del par.   │${COLOR_RESET}"
        echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] ¿Cuántos bridges L2 deseas crear? [1-3, predeterminado 1]: ${COLOR_RESET}" NUM_BRIDGE_PAIRS
            NUM_BRIDGE_PAIRS=${NUM_BRIDGE_PAIRS:-1}
            if [[ "$NUM_BRIDGE_PAIRS" =~ ^[1-3]$ ]]; then break; else log_message "ERROR" "Ingresa un número válido entre 1 y 3."; fi
        done
        BRIDGE_IN_IFS=(); BRIDGE_OUT_IFS=(); BRIDGE_INTERFACES=()
        for (( idx=1; idx<=NUM_BRIDGE_PAIRS; idx++ )); do
            while true; do
                read -p "${COLOR_INFO}[ENTRADA] Bridge #$idx - interfaz de ENTRADA: ${COLOR_RESET}" in_iface
                if [[ -n "$in_iface" && " ${VALID_INTERFACES[*]} " =~ " $in_iface " && ! " ${BRIDGE_INTERFACES[*]} " =~ " $in_iface " ]]; then break; fi
                log_message "ERROR" "Interfaz $in_iface inválida o ya seleccionada."
            done
            while true; do
                read -p "${COLOR_INFO}[ENTRADA] Bridge #$idx - interfaz de SALIDA: ${COLOR_RESET}" out_iface
                if [[ -n "$out_iface" && " ${VALID_INTERFACES[*]} " =~ " $out_iface " && "$out_iface" != "$in_iface" && ! " ${BRIDGE_INTERFACES[*]} " =~ " $out_iface " ]]; then break; fi
                log_message "ERROR" "Interfaz $out_iface inválida, duplicada o igual a la entrada."
            done
            BRIDGE_IN_IFS+=("$in_iface"); BRIDGE_OUT_IFS+=("$out_iface"); BRIDGE_INTERFACES+=("$in_iface" "$out_iface")
            in_mac=$(cat "/sys/class/net/$in_iface/address" 2>/dev/null || echo "N/A")
            out_mac=$(cat "/sys/class/net/$out_iface/address" 2>/dev/null || echo "N/A")
            log_message "OK" "Bridge #$idx: entrada=$in_iface/$in_mac salida=$out_iface/$out_mac"
        done
        LAN_IF="${BRIDGE_IN_IFS[0]}"; WAN_IF=""; DEST_IF="${BRIDGE_OUT_IFS[0]}"; CONFIG_TC="s"; CONFIG_DHCP="n"
        NUM_VLANS=0; START_VLAN=0; SEGMENT_PREFIX="192.168"; BASE_OCTET=0
    else
        echo "${COLOR_CYAN}┌─────────────────── Configuración L3 / VLANs ──────────────┐${COLOR_RESET}"
        echo "${COLOR_CYAN}│ En este contexto, cada VLAN representa un enlace simulado │${COLOR_RESET}"
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] ¿Cuántos enlaces (VLANs) simular? [predeterminado 10]: ${COLOR_RESET}" NUM_VLANS
            NUM_VLANS=${NUM_VLANS:-10}
            if [[ "$NUM_VLANS" =~ ^[1-9][0-9]*$ ]]; then break; else log_message "ERROR" "Ingresa un número válido."; fi
        done
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] Ingresa el ID inicial para las VLANs (1-4094): ${COLOR_RESET}" START_VLAN
            if [[ "$START_VLAN" =~ ^[0-9]+$ && "$START_VLAN" -ge 1 && "$START_VLAN" -le 4094 ]]; then break; else log_message "ERROR" "ID inválido. Debe estar entre 1 y 4094."; fi
        done
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] ¿Configurar DHCP? (s/n) [predeterminado s]: ${COLOR_RESET}" CONFIG_DHCP
            CONFIG_DHCP=${CONFIG_DHCP:-s}
            if [[ "$CONFIG_DHCP" =~ ^[sSnN]$ ]]; then CONFIG_DHCP=$(echo "$CONFIG_DHCP" | tr '[:upper:]' '[:lower:]'); break; else log_message "ERROR" "Ingresa 's' o 'n'."; fi
        done
        if [ "$CONFIG_DHCP" = "s" ]; then
            echo "${COLOR_CYAN}┌─────────────────── Segmento de Red ────────────────────────┐${COLOR_RESET}"
            echo "${COLOR_CYAN}│  1) 10.254.X.0/24                                        │${COLOR_RESET}"
            echo "${COLOR_CYAN}│  2) 172.16.X.0/24                                        │${COLOR_RESET}"
            echo "${COLOR_CYAN}│  3) 192.168.X.0/24                                       │${COLOR_RESET}"
            echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"
            while true; do
                read -p "${COLOR_INFO}[ENTRADA] Opción [1-3, predeterminado 3]: ${COLOR_RESET}" SEGMENT_OPTION
                SEGMENT_OPTION=${SEGMENT_OPTION:-3}
                case "$SEGMENT_OPTION" in 1) SEGMENT_PREFIX="10.254"; break ;; 2) SEGMENT_PREFIX="172.16"; break ;; 3) SEGMENT_PREFIX="192.168"; break ;; *) log_message "ERROR" "Opción inválida. Ingresa 1, 2 o 3." ;; esac
            done
            while true; do
                read -p "${COLOR_INFO}[ENTRADA] Ingresa el tercer octeto inicial para las VLANs (1-254) [predeterminado 10]: ${COLOR_RESET}" BASE_OCTET
                BASE_OCTET=${BASE_OCTET:-10}
                if [[ "$BASE_OCTET" =~ ^[0-9]+$ && "$BASE_OCTET" -ge 1 && "$BASE_OCTET" -le 254 ]]; then break; else log_message "ERROR" "Ingresa un número válido entre 1 y 254."; fi
            done
        else
            SEGMENT_PREFIX="192.168"
            BASE_OCTET=10
        fi
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] Ingresa la interfaz WAN: ${COLOR_RESET}" WAN_IF
            if [[ -n "$WAN_IF" && " ${VALID_INTERFACES[*]} " =~ " $WAN_IF " ]]; then log_message "OK" "Interfaz $WAN_IF válida en el sistema local."; break; else log_message "ERROR" "Interfaz $WAN_IF no encontrada o inválida. Selecciona una interfaz válida."; fi
        done
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] Ingresa la interfaz LAN (para VLANs y DHCP): ${COLOR_RESET}" LAN_IF
            if [[ -n "$LAN_IF" && " ${VALID_INTERFACES[*]} " =~ " $LAN_IF " && "$LAN_IF" != "$WAN_IF" ]]; then log_message "OK" "Interfaz $LAN_IF válida en el sistema local."; break; else log_message "ERROR" "Interfaz $LAN_IF no encontrada, inválida o igual a WAN ($WAN_IF)."; fi
        done
        BRIDGE_INTERFACES=(); BRIDGE_IN_IFS=(); BRIDGE_OUT_IFS=()
        NUM_BRIDGE_IFACES=0; NUM_BRIDGE_PAIRS=0; BRIDGE_PAIRS_CSV=""
    fi

    echo "${COLOR_CYAN}┌─────────────────── Integración con Telegram ───────────────┐${COLOR_RESET}"
    echo "${COLOR_CYAN}│ Configura la integración con Telegram (opcional):         │${COLOR_RESET}"
    while true; do
        read -p "${COLOR_INFO}[ENTRADA] ¿Integrar con Telegram Bot para actualizaciones de parámetros? (s/n) [predeterminado n]: ${COLOR_RESET}" INTEGRATE_TELEGRAM
        INTEGRATE_TELEGRAM=${INTEGRATE_TELEGRAM:-n}
        if [[ "$INTEGRATE_TELEGRAM" =~ ^[sSnN]$ ]]; then INTEGRATE_TELEGRAM=$(echo "$INTEGRATE_TELEGRAM" | tr '[:upper:]' '[:lower:]'); break; else log_message "ERROR" "Ingresa 's' o 'n'."; fi
    done
    if [ "$INTEGRATE_TELEGRAM" = "s" ]; then
        read -p "${COLOR_INFO}[ENTRADA] Ingresa el token del Bot de Telegram: ${COLOR_RESET}" TELEGRAM_TOKEN
        read -p "${COLOR_INFO}[ENTRADA] Ingresa el Chat ID (deja vacío para obtenerlo automáticamente): ${COLOR_RESET}" TELEGRAM_CHAT_ID
        if [ -z "$TELEGRAM_CHAT_ID" ]; then get_telegram_chat_id "$TELEGRAM_TOKEN"; fi
    else
        TELEGRAM_TOKEN=""
        TELEGRAM_CHAT_ID=""
    fi
    echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"
fi


# SECCIÓN 5: Configuración de Red
# -------------------------------

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
                    changes_made=1
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

            sudo tee "$DHCP_DEFAULT_FILE" > /dev/null <<EOF
INTERFACESv4="${VALID_VLANS[*]}"
DHCPDARGS="${VALID_VLANS[*]}"
EOF

            log_message "INFO" "Validando configuración DHCP..."
            if dhcpd -t -cf /etc/dhcp/dhcpd.conf >/dev/null 2>&1; then
                log_message "OK" "Configuración DHCP válida."
                sudo systemctl enable "$DHCP_SERVICE" >/dev/null 2>&1
                if sudo systemctl restart "$DHCP_SERVICE" >/dev/null 2>&1; then
                    sleep 2
                    if systemctl is-active "$DHCP_SERVICE" >/dev/null; then
                        log_message "OK" "DHCP configurado correctamente."
                        echo "DHCP - Configurado correctamente."
                    else
                        log_message "ERROR" "Error al iniciar el servicio DHCP. Revisando logs..."
                        dhcp_error=$(journalctl -u "$DHCP_SERVICE" -n 50 --no-pager 2>&1)
                        log_message "ERROR" "Error DHCP: $dhcp_error"
                        echo "  [ERROR] DHCP no configurado. Revisa los logs in $LOGFILE."
                    fi
                else
                    log_message "ERROR" "Error al reiniciar el servicio DHCP. Revisando logs..."
                    dhcp_error=$(journalctl -u "$DHCP_SERVICE" -n 50 --no-pager 2>&1)
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

    # Verificar permisos del directorio de reglas persistentes.
    IPTABLES_SAVE_DIR="$(dirname "$IPTABLES_SAVE_FILE")"
    if [ ! -d "$IPTABLES_SAVE_DIR" ]; then
        log_message "INFO" "Creando directorio $IPTABLES_SAVE_DIR..."
        sudo mkdir -p "$IPTABLES_SAVE_DIR" >/dev/null 2>&1
        sudo chmod 755 "$IPTABLES_SAVE_DIR" >/dev/null 2>&1
    fi
    if [ ! -w "$IPTABLES_SAVE_DIR" ]; then
        log_message "INFO" "Ajustando permisos del directorio $IPTABLES_SAVE_DIR..."
        sudo chmod 755 "$IPTABLES_SAVE_DIR" >/dev/null 2>&1
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
        sudo iptables-save > "$temp_rules" 2>/tmp/iptables_error.log
        if [ $? -eq 0 ]; then
            sudo mv "$temp_rules" "$IPTABLES_SAVE_FILE" >/tmp/iptables_error.log 2>&1
            if [ $? -eq 0 ]; then
                sudo chmod 644 "$IPTABLES_SAVE_FILE" >/dev/null 2>&1
                if [ "$OS_FAMILY" = "rhel" ]; then
                    sudo systemctl enable iptables >/dev/null 2>&1 || true
                fi
                log_message "OK" "Reglas de NAT guardadas correctamente en $IPTABLES_SAVE_FILE."
                echo "NAT - Configurado y guardado correctamente."
                rm -f /tmp/iptables_error.log
                break
            else
                iptables_error=$(cat /tmp/iptables_error.log)
                log_message "ERROR" "Error al mover reglas de NAT a $IPTABLES_SAVE_FILE: $iptables_error"
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
        echo "${COLOR_ERROR}No se pudo configurar NAT. Revisa los logs en $LOGFILE y verifica permisos en $IPTABLES_SAVE_DIR.${COLOR_RESET}"
        exit 1
    fi
elif [ "$TOPOLOGY_MODE" = "bridge" ]; then
    log_message "INFO" "Configurando modo Bridge L2 por pares entrada/salida..."
    if [ ${#BRIDGE_IN_IFS[@]} -eq 0 ] && [ -n "${BRIDGE_PAIRS_CSV:-}" ]; then
        BRIDGE_IN_IFS=(); BRIDGE_OUT_IFS=(); BRIDGE_INTERFACES=()
        IFS=';' read -r -a __pairs <<< "$BRIDGE_PAIRS_CSV"
        for pair in "${__pairs[@]}"; do
            [ -z "$pair" ] && continue
            IFS=':' read -r __br __in __out <<< "$pair"
            [ -n "$__in" ] && [ -n "$__out" ] || continue
            BRIDGE_IN_IFS+=("$__in"); BRIDGE_OUT_IFS+=("$__out"); BRIDGE_INTERFACES+=("$__in" "$__out")
        done
        NUM_BRIDGE_PAIRS=${#BRIDGE_IN_IFS[@]}
    fi
    if [ ${#BRIDGE_IN_IFS[@]} -lt 1 ] || [ ${#BRIDGE_IN_IFS[@]} -gt 3 ]; then
        log_message "ERROR" "Modo Bridge requiere entre 1 y 3 pares entrada/salida."
        echo "${COLOR_ERROR}Modo Bridge requiere entre 1 y 3 pares entrada/salida válidos.${COLOR_RESET}"; exit 1
    fi
    cleanup_bridges
    VALID_BRIDGE_INTERFACES=(); PYTHON_VLAN_LIST="[]"; PYTHON_INTERFACE_META="{}"; BRIDGE_PAIRS_CSV=""
    META_TSV="/tmp/wansim_bridge_meta.tsv"
    : > "$META_TSV"
    for idx in "${!BRIDGE_IN_IFS[@]}"; do
        bridge_num=$((idx + 1)); br_name="br_wan${bridge_num}"; in_iface="${BRIDGE_IN_IFS[$idx]}"; out_iface="${BRIDGE_OUT_IFS[$idx]}"
        for iface in "$in_iface" "$out_iface"; do
            if ! ip link show "$iface" >/dev/null 2>&1; then log_message "ERROR" "La interfaz $iface no existe."; echo "${COLOR_ERROR}La interfaz $iface no está disponible.${COLOR_RESET}"; exit 1; fi
            sudo tc qdisc del dev "$iface" root >/dev/null 2>&1 || true
            sudo ip link set "$iface" nomaster >/dev/null 2>&1 || true
            sudo ip link set "$iface" up >/dev/null 2>&1 || true
        done
        log_message "INFO" "Creando $br_name con entrada=$in_iface y salida=$out_iface..."
        sudo ip link add name "$br_name" type bridge >/tmp/bridge_error.log 2>&1 || { bridge_error=$(cat /tmp/bridge_error.log); log_message "ERROR" "No se pudo crear $br_name: $bridge_error"; exit 1; }
        sudo ip link set "$in_iface" master "$br_name" >/dev/null 2>&1
        sudo ip link set "$out_iface" master "$br_name" >/dev/null 2>&1
        sudo ip link set "$br_name" up >/dev/null 2>&1; sudo ip link set "$in_iface" up >/dev/null 2>&1; sudo ip link set "$out_iface" up >/dev/null 2>&1
        for role_idx in 0 1; do
            if [ "$role_idx" -eq 0 ]; then iface="$in_iface"; role="entrada"; peer="$out_iface"; else iface="$out_iface"; role="salida"; peer="$in_iface"; fi
            VALID_BRIDGE_INTERFACES+=("$iface")
            label="Bridge ${bridge_num} - ${role} (${iface})"
            mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null || echo "N/A")
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$iface" "$label" "$br_name" "$role" "$peer" "$mac" >> "$META_TSV"
            log_message "OK" "$label / peer=$peer / MAC=$mac"
        done
        [ -n "$BRIDGE_PAIRS_CSV" ] && BRIDGE_PAIRS_CSV+=";"; BRIDGE_PAIRS_CSV+="$br_name:$in_iface:$out_iface"
    done
    BRIDGE_INTERFACES=("${VALID_BRIDGE_INTERFACES[@]}"); BRIDGE_INTERFACES_CSV=$(IFS=,; echo "${BRIDGE_INTERFACES[*]}")
    export BRIDGE_INTERFACES_CSV META_TSV
    PYTHON_VLAN_LIST=$(python3 - <<'PYJSON'
import json, os
items=[x for x in os.environ.get('BRIDGE_INTERFACES_CSV','').split(',') if x]
print(json.dumps(items, ensure_ascii=False))
PYJSON
)
    PYTHON_INTERFACE_META=$(python3 - <<'PYJSON'
import json, os
meta={}
path=os.environ.get('META_TSV','')
try:
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line=line.rstrip('\n')
            if not line:
                continue
            parts=line.split('\t')
            if len(parts) != 6:
                continue
            iface,label,bridge,role,peer,mac=parts
            meta[iface]={"label":label,"bridge":bridge,"role":role,"peer":peer,"mac":mac}
except FileNotFoundError:
    pass
print(json.dumps(meta, ensure_ascii=False))
PYJSON
)
    python3 - <<'PYVALID' "$PYTHON_VLAN_LIST" "$PYTHON_INTERFACE_META" || { log_message "ERROR" "No se pudo generar JSON válido para Flask Bridge."; exit 1; }
import json, sys
json.loads(sys.argv[1]); json.loads(sys.argv[2])
PYVALID
    NUM_BRIDGE_IFACES=${#BRIDGE_INTERFACES[@]}; CONFIG_TC="s"
    log_message "OK" "Modo Bridge L2 configurado. Pares: $BRIDGE_PAIRS_CSV"
fi
PYTHON_INTERFACE_META=${PYTHON_INTERFACE_META:-{}}

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
NUM_BRIDGE_IFACES=${NUM_BRIDGE_IFACES:-0}
NUM_BRIDGE_PAIRS=${NUM_BRIDGE_PAIRS:-0}
BRIDGE_INTERFACES_CSV=${BRIDGE_INTERFACES_CSV:-}
BRIDGE_PAIRS_CSV=${BRIDGE_PAIRS_CSV:-}
EOF
    chmod 640 "$CONFIG_FILE"
    chown "$CURRENT_USER:$CURRENT_USER" "$CONFIG_FILE"
    log_message "OK" "Configuración guardada en $CONFIG_FILE."
fi


# SECCIÓN 5.1: Persistencia de Bridges L2 y estado Netem
# ------------------------------------------------------
configure_l2_persistence() {
    if [ "${TOPOLOGY_MODE:-}" != "bridge" ]; then
        log_message "INFO" "Persistencia L2 no aplica para topología ${TOPOLOGY_MODE:-nat}."
        return 0
    fi
    if [ -z "${BRIDGE_PAIRS_CSV:-}" ]; then
        log_message "ADVERTENCIA" "No hay BRIDGE_PAIRS_CSV; no se configurará persistencia L2."
        return 0
    fi

    log_message "INFO" "Configurando persistencia systemd para bridges L2, enlaces físicos y estado tc/netem..."

    sudo mkdir -p "$(dirname "$PERSIST_SCRIPT")" >/dev/null 2>&1 || true
    if [ ! -f "$NETEM_STATE_FILE" ]; then
        echo '{}' | sudo tee "$NETEM_STATE_FILE" >/dev/null
        sudo chmod 664 "$NETEM_STATE_FILE" >/dev/null 2>&1 || true
        sudo chown "$CURRENT_USER:$CURRENT_USER" "$NETEM_STATE_FILE" >/dev/null 2>&1 || true
    fi

    sudo tee "$PERSIST_SCRIPT" >/dev/null <<'PERSIST_EOF'
#!/bin/bash
set -euo pipefail

BRIDGE_PAIRS_CSV="__BRIDGE_PAIRS_CSV__"
NETEM_STATE_FILE="__NETEM_STATE_FILE__"
LOG_FILE="/tmp/wansim_l2_persist.log"

echo "[$(date '+%F %T')] Iniciando persistencia L2 WAN Simulator" >> "$LOG_FILE"

sleep 8

# Deshacer bridges WAN Simulator previos sin tocar bridges ajenos.
for br in $(ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2}' | cut -d'@' -f1 | grep '^br_wan' || true); do
    echo "[$(date '+%F %T')] Eliminando bridge previo $br" >> "$LOG_FILE"
    for port in $(bridge link 2>/dev/null | awk -v br="$br" '$0 ~ "master "br {print $2}' | sed 's/://'); do
        ip link set "$port" nomaster 2>/dev/null || true
    done
    ip link set "$br" down 2>/dev/null || true
    ip link delete "$br" type bridge 2>/dev/null || true
done

IFS=';' read -r -a PAIRS <<< "$BRIDGE_PAIRS_CSV"
for pair in "${PAIRS[@]}"; do
    [ -z "$pair" ] && continue
    IFS=':' read -r br in_if out_if <<< "$pair"
    [ -n "${br:-}" ] && [ -n "${in_if:-}" ] && [ -n "${out_if:-}" ] || continue

    echo "[$(date '+%F %T')] Recreando $br entrada=$in_if salida=$out_if" >> "$LOG_FILE"

    for iface in "$in_if" "$out_if"; do
        if ip link show "$iface" >/dev/null 2>&1; then
            tc qdisc del dev "$iface" root 2>/dev/null || true
            ip link set "$iface" nomaster 2>/dev/null || true
            ip link set "$iface" up 2>/dev/null || true
        else
            echo "[$(date '+%F %T')] WARN: interfaz $iface no existe" >> "$LOG_FILE"
        fi
    done

    ip link add name "$br" type bridge 2>/dev/null || true
    ip link set "$in_if" master "$br" 2>/dev/null || true
    ip link set "$out_if" master "$br" 2>/dev/null || true
    ip link set "$br" up 2>/dev/null || true
    ip link set "$in_if" up 2>/dev/null || true
    ip link set "$out_if" up 2>/dev/null || true
done

# Reaplicar el último estado tc/netem guardado por Flask o Telegram.
if [ -s "$NETEM_STATE_FILE" ]; then
    python3 - "$NETEM_STATE_FILE" <<'PY' | while IFS= read -r cmd; do
import json, re, sys
path=sys.argv[1]
try:
    data=json.load(open(path, 'r', encoding='utf-8'))
except Exception:
    data={}

def num(v):
    try:
        f=float(v)
    except Exception:
        f=0.0
    if f.is_integer():
        return str(int(f))
    return (f'{f:.3f}').rstrip('0').rstrip('.')

for iface, st in data.items():
    if not re.match(r'^[A-Za-z0-9_.:@-]+$', iface or ''):
        continue
    d=float(st.get('delay',0) or 0)
    j=float(st.get('jitter',0) or 0)
    l=float(st.get('loss',0) or 0)
    if d == 0 and j == 0 and l == 0:
        print(f'tc qdisc del dev {iface} root 2>/dev/null || true')
        continue
    parts=[]
    if d > 0 or j > 0:
        parts.append(f'delay {num(d)}ms')
        if j > 0:
            parts.append(f'{num(j)}ms')
    if l > 0:
        parts.append(f'loss {num(l)}%')
    print(f'tc qdisc replace dev {iface} root netem ' + ' '.join(parts))
PY
        echo "[$(date '+%F %T')] Ejecutando: $cmd" >> "$LOG_FILE"
        eval "$cmd" >> "$LOG_FILE" 2>&1 || true
    done
fi

echo "[$(date '+%F %T')] Persistencia L2 completada" >> "$LOG_FILE"
exit 0
PERSIST_EOF

    sudo sed -i "s|__BRIDGE_PAIRS_CSV__|$BRIDGE_PAIRS_CSV|g" "$PERSIST_SCRIPT"
    sudo sed -i "s|__NETEM_STATE_FILE__|$NETEM_STATE_FILE|g" "$PERSIST_SCRIPT"
    sudo chmod 755 "$PERSIST_SCRIPT"

    sudo tee "$PERSIST_SERVICE" >/dev/null <<EOF
[Unit]
Description=Ryuz WAN Simulator L2 Bridge Persistence
After=network-online.target
Wants=network-online.target
Before=wansim.service

[Service]
Type=oneshot
ExecStart=$PERSIST_SCRIPT
RemainAfterExit=yes
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable wansim-l2-persist.service >/dev/null 2>&1
    sudo systemctl restart wansim-l2-persist.service
    log_message "OK" "Persistencia L2 configurada. Servicio: wansim-l2-persist.service. Estado netem: $NETEM_STATE_FILE"
}

configure_l2_persistence


# SECCIÓN 6.1A: Liberación de Puerto y Verificación de Dependencias
# ----------------------------------------------------------------
log_message "INFO" "Liberando puerto y verificando dependencias..."

# Liberar puerto para Flask
free_port

# Configurar PYTHONPATH antes de la verificación
export PYTHONPATH="$HOME/.local/lib/python3.8/site-packages:/usr/local/lib/python3.8/dist-packages:$PYTHONPATH"

# Verificar dependencias de Python
log_message "INFO" "Verificando dependencias de Python..."
for module in flask requests OpenSSL telegram; do
    if ! python3 -c "import $module" 2>/dev/null; then
        log_message "ERROR" "Módulo Python $module no encontrado. Instalando dependencias compatibles..."
        if ! pip3 install --user flask requests pyOpenSSL "python-telegram-bot==13.15" --no-warn-script-location; then
            log_message "ERROR" "No se pudieron instalar dependencias Python."
            echo "${COLOR_ERROR}Fallo al instalar dependencias Python. Revisa con 'pip3 list'.${COLOR_RESET}"
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
import os, re, json, logging, subprocess, threading, sys
from flask import Flask, request, render_template_string, redirect, url_for, flash
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s', handlers=[logging.StreamHandler(sys.stdout)])
logger=logging.getLogger(__name__)
try:
    from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
    from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, ConversationHandler, MessageHandler, Filters
except ImportError as e:
    logger.error(f"Telegram no disponible: {e}"); Updater=None
app=Flask(__name__)
app.secret_key=os.environ.get('WANSIM_SECRET_KEY','ryuz-wansim-local-secret')
app.config['PORT']=int(__DASHBOARD_PORT__)
NETEM_STATE_FILE='__NETEM_STATE_FILE__'
def load_json_literal(raw, fallback):
    try:
        return json.loads(raw)
    except Exception as e:
        logger.error(f"JSON inválido inyectado en dashboard: {e}. Valor recibido: {raw[:200]}")
        return fallback
CONTROL_INTERFACES=load_json_literal(__PYTHON_VLAN_LIST_LITERAL__, [])
VLAN_INTERFACES=CONTROL_INTERFACES
INTERFACE_META=load_json_literal(__PYTHON_INTERFACE_META_LITERAL__, {})
TELEGRAM_TOKEN=__TELEGRAM_TOKEN_LITERAL__
TELEGRAM_CHAT_ID=__TELEGRAM_CHAT_ID_LITERAL__
TELEGRAM_ENABLED=bool(int(__TELEGRAM_ENABLED__))
def iface_ok(i):
    if not re.match(r'^[A-Za-z0-9_.:@-]+$', i or ''): raise ValueError(f'Interfaz inválida: {i}')
    return i
def run(cmd):
    try:
        r=subprocess.run(cmd,shell=True,capture_output=True,text=True,timeout=10)
        return r.returncode==0,(r.stdout or r.stderr or '')
    except Exception as e: return False,str(e)
def parse_qdisc(out):
    d=j=l=0.0
    m=re.search(r'delay\s+(\d+\.?\d*)ms\s*(\d+\.?\d*)ms',out,re.I)
    if m: d=float(m.group(1)); j=float(m.group(2))
    else:
        m=re.search(r'delay\s+(\d+\.?\d*)ms',out,re.I)
        if m: d=float(m.group(1))
    m=re.search(r'loss\s+(\d+\.?\d*)%',out,re.I)
    if m: l=float(m.group(1))
    return {'delay':d,'jitter':j,'loss':l}
def traffic(i):
    try:
        i=iface_ok(i); r=subprocess.run(f'ifstat -i {i} 0.1 1',shell=True,capture_output=True,text=True,timeout=5)
        lines=[x for x in r.stdout.splitlines() if x.strip()]
        vals=lines[-1].split() if len(lines)>=2 else []
        kin=float(vals[0]) if len(vals)>1 and vals[0].replace('.','',1).isdigit() else 0.0
        kout=float(vals[1]) if len(vals)>1 and vals[1].replace('.','',1).isdigit() else 0.0
    except Exception: kin=kout=0.0
    return {'kbps_in':kin,'kbps_out':kout,'mbps_in':kin/1000,'mbps_out':kout/1000,'kb_in':kin/8,'kb_out':kout/8,'mb_in':kin/8000,'mb_out':kout/8000}
def collect():
    s={}
    for i in CONTROL_INTERFACES:
        ok,out=run(f'tc qdisc show dev {iface_ok(i)}'); s[i]=parse_qdisc(out) if ok else {'delay':0,'jitter':0,'loss':0}
        s[i].update(traffic(i)); meta=INTERFACE_META.get(i,{}) if isinstance(INTERFACE_META,dict) else {}
        s[i].update({'label':meta.get('label',i),'bridge':meta.get('bridge',''),'role':meta.get('role',''),'peer':meta.get('peer',''),'mac':meta.get('mac','')})
    return s
def to_number(value, name, min_value=0.0, max_value=None):
    try:
        text=str(value).strip().replace(',', '.')
        number=float(text)
    except Exception:
        raise ValueError(f'{name} debe ser numérico')
    if number < min_value:
        raise ValueError(f'{name} debe ser mayor o igual a {min_value}')
    if max_value is not None and number > max_value:
        raise ValueError(f'{name} debe ser menor o igual a {max_value}')
    return number

def tc_num(value):
    value=float(value)
    if value.is_integer():
        return str(int(value))
    return (f'{value:.3f}').rstrip('0').rstrip('.')

def load_netem_state():
    try:
        with open(NETEM_STATE_FILE, 'r', encoding='utf-8') as f:
            data=json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}

def save_netem_state(iface, delay, jitter, loss):
    try:
        data=load_netem_state()
        data[iface]={'delay':float(delay),'jitter':float(jitter),'loss':float(loss)}
        tmp=NETEM_STATE_FILE + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        os.replace(tmp, NETEM_STATE_FILE)
        return True
    except Exception as e:
        logger.error(f'No se pudo guardar estado netem para {iface}: {e}')
        return False

def remove_netem_state(iface):
    try:
        data=load_netem_state()
        if iface in data:
            data.pop(iface, None)
            tmp=NETEM_STATE_FILE + '.tmp'
            with open(tmp, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            os.replace(tmp, NETEM_STATE_FILE)
    except Exception as e:
        logger.error(f'No se pudo limpiar estado netem para {iface}: {e}')

def clear_netem(i):
    i=iface_ok(i)
    ok,out=run(f'sudo tc qdisc del dev {i} root 2>/dev/null || true')
    remove_netem_state(i)
    return True,out

def apply_netem(i,d,j,l):
    i=iface_ok(i)
    d=to_number(d,'delay',0.0)
    j=to_number(j,'jitter',0.0)
    l=to_number(l,'pérdida',0.0,100.0)
    if d==0 and j==0 and l==0:
        return clear_netem(i)

    parts=[]
    if d>0 or j>0:
        parts.append(f'delay {tc_num(d)}ms')
        if j>0:
            parts.append(f'{tc_num(j)}ms')
    if l>0:
        parts.append(f'loss {tc_num(l)}%')

    cmd=f'sudo tc qdisc replace dev {i} root netem ' + ' '.join(parts)
    ok,out=run(cmd)
    if ok:
        save_netem_state(i,d,j,l)
        verify_ok,verify_out=run(f'tc qdisc show dev {i}')
        return True, verify_out.strip() if verify_ok else 'OK'
    return False,out
if TELEGRAM_ENABLED and Updater:
    SELECT,DELAY,JITTER,LOSS=range(1,5)
    def start(update,ctx):
        if str(update.effective_chat.id)!=TELEGRAM_CHAT_ID: update.message.reply_text('Acceso no autorizado.'); return -1
        kb=[[InlineKeyboardButton((INTERFACE_META.get(i,{}).get('label',i))[:60],callback_data=f'select_{i}')] for i in CONTROL_INTERFACES]
        update.message.reply_text('Selecciona la interfaz:',reply_markup=InlineKeyboardMarkup(kb)); return SELECT
    def sel(update,ctx):
        q=update.callback_query; q.answer(); i=q.data.split('_',1)[1]
        if i not in CONTROL_INTERFACES: q.edit_message_text('Selección inválida.'); return -1
        ctx.user_data['iface']=i; q.edit_message_text(f'Interfaz {INTERFACE_META.get(i,{}).get("label",i)}. Delay/latencia ms:'); return DELAY
    def setd(update,ctx):
        try: v=to_number(update.message.text,'delay',0.0)
        except Exception as e: update.message.reply_text(f'Número inválido para delay: {e}'); return DELAY
        ctx.user_data['delay']=v; update.message.reply_text('Jitter ms:'); return JITTER
    def setj(update,ctx):
        try: v=to_number(update.message.text,'jitter',0.0)
        except Exception as e: update.message.reply_text(f'Número inválido para jitter: {e}'); return JITTER
        ctx.user_data['jitter']=v; update.message.reply_text('Ruido/pérdida %:'); return LOSS
    def setl(update,ctx):
        try: l=to_number(update.message.text,'pérdida',0.0,100.0)
        except Exception as e: update.message.reply_text(f'Número inválido para pérdida: {e}'); return LOSS
        i=ctx.user_data['iface']
        d=ctx.user_data.get('delay',0)
        j=ctx.user_data.get('jitter',0)
        ok,out=apply_netem(i,d,j,l)
        label=INTERFACE_META.get(i,{}).get('label',i)
        if ok:
            update.message.reply_text(f'Aplicado en {label}: delay={tc_num(d)}ms, jitter={tc_num(j)}ms, pérdida={tc_num(l)}%. Verificación: {out}')
        else:
            update.message.reply_text(f'Error en {label}: {out}')
        return -1
    def cancel(update,ctx): update.message.reply_text('Cancelado.'); return -1
    def bot():
        try:
            u=Updater(TELEGRAM_TOKEN,use_context=True); dp=u.dispatcher
            dp.add_handler(ConversationHandler(entry_points=[CommandHandler('start',start),CommandHandler('config',start)],states={SELECT:[CallbackQueryHandler(sel,pattern='^select_')],DELAY:[MessageHandler(Filters.text & ~Filters.command,setd)],JITTER:[MessageHandler(Filters.text & ~Filters.command,setj)],LOSS:[MessageHandler(Filters.text & ~Filters.command,setl)]},fallbacks=[CommandHandler('cancel',cancel)]))
            u.start_polling(); u.idle()
        except Exception as e: logger.error(f'Telegram error: {e}')
    threading.Thread(target=bot,daemon=True).start()
TEMPLATE=r"""
<!doctype html><html lang='es'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Ryuz WAN Simulator</title><link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'><script src='https://cdn.jsdelivr.net/npm/chart.js'></script><style>body{background:linear-gradient(135deg,#1e3c72,#2a5298);color:white;min-height:100vh}.card{background:rgba(255,255,255,.12);border:0;border-radius:15px}.form-control,.form-select{background:rgba(255,255,255,.22);color:white;border:0}.output{background:rgba(0,0,0,.3);padding:10px;border-radius:6px;white-space:pre-wrap}.chart-container{height:200px}.badge-soft{background:rgba(255,255,255,.2);color:white}</style></head><body><div class='container py-4'><h1 class='text-center'>Ryuz WAN Simulator</h1><p class='text-center'>L3/NAT y L2 Bridge por pares entrada/salida</p>{% with messages=get_flashed_messages(with_categories=true) %}{% for c,m in messages %}<div class='alert alert-{{c}}'>{{m}}</div>{% endfor %}{% endwith %}<div class='d-flex justify-content-center gap-2 mb-4'><form method='post' action='{{url_for("configure")}}'><input type='hidden' name='action' value='reset_all'><button class='btn btn-primary'>Restablecer todas</button></form><select id='unit' class='form-select w-auto' onchange='updateCharts()'><option value='mbps'>Mbps</option><option value='kbps'>Kbps</option><option value='mb'>MB/s</option><option value='kb'>KB/s</option></select></div><div class='row'>{% for i in interfaces %}<div class='col-md-6 col-lg-4 mb-4'><div class='card p-4 h-100'><h4>{{stats[i].label}}</h4><div>{% if stats[i].bridge %}<span class='badge badge-soft'>{{stats[i].bridge}}</span>{% endif %} {% if stats[i].role %}<span class='badge badge-soft'>{{stats[i].role}}</span>{% endif %}</div><small>Interfaz: {{i}}{% if stats[i].peer %}<br>Peer: {{stats[i].peer}}{% endif %}{% if stats[i].mac %}<br>MAC: {{stats[i].mac}}{% endif %}</small><form method='post' action='{{url_for("configure")}}' class='mt-3'><input type='hidden' name='iface' value='{{i}}'><input type='hidden' name='action' value='apply'><label>Delay/latencia ms</label><input class='form-control' type='number' name='delay' step='.1' min='0' value='{{stats[i].delay}}'><label>Jitter ms</label><input class='form-control' type='number' name='jitter' step='.1' min='0' value='{{stats[i].jitter}}'><label>Ruido/Pérdida %</label><input class='form-control' type='number' name='loss' step='.1' min='0' max='100' value='{{stats[i].loss}}'><div class='mt-3 d-flex gap-2'><button class='btn btn-primary'>Aplicar</button><button class='btn btn-warning' onclick='this.form.elements["action"].value="reset"'>Restablecer</button></div></form><div class='mt-3 d-flex flex-wrap gap-1'>{% for label,d,j,l in quicks %}<form method='post' action='{{url_for("configure")}}'><input type='hidden' name='iface' value='{{i}}'><input type='hidden' name='action' value='apply'><input type='hidden' name='delay' value='{{d}}'><input type='hidden' name='jitter' value='{{j}}'><input type='hidden' name='loss' value='{{l}}'><button class='btn btn-outline-light btn-sm'>{{label}}</button></form>{% endfor %}</div><div class='chart-container mt-3'><canvas id='c{{loop.index}}'></canvas></div><pre class='output mt-2' id='o{{loop.index}}'></pre></div></div>{% endfor %}</div><div class='text-center'>Ryuz WAN Simulator - Versión __WANSIM_VERSION__</div></div><script>const data={{chart|safe}};let charts={};function updateCharts(){let u=document.getElementById('unit').value;data.forEach((x,n)=>{let s=x.stats,vals=[s[u+'_in'],s[u+'_out'],s.delay,s.jitter,s.loss],id='c'+(n+1),ctx=document.getElementById(id);if(!ctx)return;if(charts[id]){charts[id].data.datasets[0].data=vals;charts[id].update()}else{charts[id]=new Chart(ctx.getContext('2d'),{type:'bar',data:{labels:['Entrada','Salida','Delay','Jitter','Ruido/Pérdida'],datasets:[{label:x.label,data:vals,borderWidth:1}]},options:{responsive:true,maintainAspectRatio:false,scales:{y:{beginAtZero:true}}}})}document.getElementById('o'+(n+1)).innerText='Delay: '+Number(s.delay).toFixed(1)+' ms\nJitter: '+Number(s.jitter).toFixed(1)+' ms\nRuido/Pérdida: '+Number(s.loss).toFixed(1)+' %\nEntrada: '+Number(s[u+'_in']).toFixed(2)+' '+u+'\nSalida: '+Number(s[u+'_out']).toFixed(2)+' '+u})}window.onload=updateCharts;</script></body></html>
"""

@app.route('/')
def dashboard():
    s=collect(); chart=json.dumps([{'iface':i,'label':s[i].get('label',i),'stats':s[i]} for i in CONTROL_INTERFACES])
    q=[('100ms',100,0,0),('300ms',300,0,0),('500ms',500,0,0),('J50',0,50,0),('J100',0,100,0),('J200',0,200,0),('Loss1%',0,0,1),('Loss5%',0,0,5),('Loss10%',0,0,10)]
    return render_template_string(TEMPLATE,interfaces=CONTROL_INTERFACES,stats=s,chart=chart,quicks=q)

@app.route('/configure',methods=['POST'])
def configure():
    try:
        i=request.form.get('iface') or request.form.get('vlan'); a=request.form.get('action')
        if a=='reset_all':
            errs=[]
            for t in CONTROL_INTERFACES:
                ok,out=run(f'sudo tc qdisc del dev {iface_ok(t)} root 2>/dev/null || true')
                if not ok and 'No such file' not in out and 'Invalid argument' not in out: errs.append(f'{t}:{out}')
            flash('Restablecido todo.' if not errs else 'Errores: '+' | '.join(errs),'success' if not errs else 'danger'); return redirect(url_for('dashboard'))
        if i not in CONTROL_INTERFACES: flash(f'Interfaz inválida: {i}','danger'); return redirect(url_for('dashboard'))
        label=INTERFACE_META.get(i,{}).get('label',i) if isinstance(INTERFACE_META,dict) else i
        if a=='reset':
            ok,out=run(f'sudo tc qdisc del dev {iface_ok(i)} root 2>/dev/null || true'); flash(f'Restablecido {label}.' if ok or 'No such file' in out or 'Invalid argument' in out else f'Error {label}: {out}','success' if ok or 'No such file' in out or 'Invalid argument' in out else 'danger'); return redirect(url_for('dashboard'))
        if a=='apply':
            d=to_number(request.form.get('delay',0) or 0,'delay',0.0)
            j=to_number(request.form.get('jitter',0) or 0,'jitter',0.0)
            l=to_number(request.form.get('loss',0) or 0,'pérdida',0.0,100.0)
            ok,out=apply_netem(i,d,j,l); flash(f'Aplicado en {label}: delay={tc_num(d)}ms jitter={tc_num(j)}ms pérdida={tc_num(l)}%. Verificación: {out}' if ok else f'Error en {label}: {out}','success' if ok else 'danger'); return redirect(url_for('dashboard'))
        flash(f'Acción no soportada: {a}','warning'); return redirect(url_for('dashboard'))
    except Exception as e:
        logger.exception('Error en /configure'); flash(f'Error interno controlado: {e}','danger'); return redirect(url_for('dashboard'))

if __name__=='__main__': app.run(host='0.0.0.0',port=app.config['PORT'])
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

# Reemplazar placeholders en el archivo Python de forma segura
log_message "DEBUG" "Reemplazando placeholders en $WANSIM_DASHBOARD con reemplazo seguro..."
export TELEGRAM_TOKEN TELEGRAM_CHAT_ID TELEGRAM_ENABLED PYTHON_VLAN_LIST PYTHON_INTERFACE_META DASHBOARD_PORT WANSIM_VERSION NETEM_STATE_FILE
if ! python3 - "$WANSIM_DASHBOARD" <<'PYREPLACE'
import json
import os
import sys
from pathlib import Path

def normalize_json_env(name, fallback):
    value = os.environ.get(name, fallback)
    try:
        json.loads(value)
        return value
    except json.JSONDecodeError:
        # Defensa específica: corrige llaves de cierre extra al final del JSON.
        candidate = value
        while candidate.endswith('}'):
            candidate = candidate[:-1]
            try:
                json.loads(candidate)
                return candidate
            except json.JSONDecodeError:
                continue
        raise

path = Path(sys.argv[1])
text = path.read_text()
py_vlan_list = normalize_json_env("PYTHON_VLAN_LIST", "[]")
py_interface_meta = normalize_json_env("PYTHON_INTERFACE_META", "{}")
replacements = {
    "__DASHBOARD_PORT__": os.environ.get("DASHBOARD_PORT", "5000"),
    "__PYTHON_VLAN_LIST_LITERAL__": json.dumps(py_vlan_list),
    "__PYTHON_INTERFACE_META_LITERAL__": json.dumps(py_interface_meta),
    "__TELEGRAM_TOKEN_LITERAL__": json.dumps(os.environ.get("TELEGRAM_TOKEN", "")),
    "__TELEGRAM_CHAT_ID_LITERAL__": json.dumps(os.environ.get("TELEGRAM_CHAT_ID", "")),
    "__TELEGRAM_ENABLED__": os.environ.get("TELEGRAM_ENABLED", "0"),
    "__NETEM_STATE_FILE__": os.environ.get("NETEM_STATE_FILE", os.path.expanduser("~/wansim_netem_state.json")),
    "__WANSIM_VERSION__": os.environ.get("WANSIM_VERSION", "1.109"),
}
for key, value in replacements.items():
    text = text.replace(key, value)
path.write_text(text)
PYREPLACE
then
    log_message "ERROR" "No se pudieron reemplazar placeholders en $WANSIM_DASHBOARD."
    echo "${COLOR_ERROR}No se pudo modificar $WANSIM_DASHBOARD. Revisa permisos con 'ls -l $WANSIM_DASHBOARD'.${COLOR_RESET}"
    exit 1
fi

log_message "DEBUG" "Validando sintaxis final de $WANSIM_DASHBOARD después de reemplazos..."
if ! python3 -m py_compile "$WANSIM_DASHBOARD"; then
    log_message "ERROR" "Error de sintaxis final en $WANSIM_DASHBOARD después de reemplazar variables."
    echo "${COLOR_ERROR}Error de sintaxis final en $WANSIM_DASHBOARD. Revisa con 'python3 -m py_compile $WANSIM_DASHBOARD' y 'nl -ba $WANSIM_DASHBOARD | sed -n \"1,40p\"'.${COLOR_RESET}"
    exit 1
fi
log_message "OK" "Placeholders reemplazados y sintaxis final verificada en $WANSIM_DASHBOARD."

# Función para liberar puertos
free_port_single() {
    local port="$1"
    log_message "INFO" "Verificando puerto $port..."
    local pids=""
    if command -v fuser >/dev/null 2>&1; then
        pids=$(sudo fuser "${port}/tcp" 2>/dev/null || true)
    fi
    if [ -z "$pids" ] && command -v lsof >/dev/null 2>&1; then
        pids=$(sudo lsof -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
    fi
    if [ -n "$pids" ]; then
        log_message "INFO" "Puerto $port en uso por PID(s): $pids. Intentando terminar..."
        sudo kill -15 $pids 2>/dev/null || true
        sleep 1
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then sudo kill -9 "$pid" 2>/dev/null || true; fi
        done
        sleep 1
    fi
    if ss -tuln | grep -q ":$port"; then
        log_message "ERROR" "No se pudo liberar el puerto $port."
        exit 1
    fi
    log_message "OK" "Puerto $port liberado o disponible."
}

# Liberar puertos 5000 y 443
log_message "INFO" "Liberando puertos 5000 y 443..."
for port in 5000 443; do
    free_port_single $port
done

# Configurar servicio systemd
log_message "DEBUG" "Configurando servicio systemd..."
L2_UNIT_LINES=""
if [ "${TOPOLOGY_MODE:-}" = "bridge" ]; then
    L2_UNIT_LINES="After=network-online.target wansim-l2-persist.service
Wants=network-online.target
Requires=wansim-l2-persist.service"
else
    L2_UNIT_LINES="After=network-online.target
Wants=network-online.target"
fi
if ! sudo bash -c "cat > $SERVICE_FILE" <<SERVICEEOF
[Unit]
Description=Ryuz WAN Simulator Dashboard
$L2_UNIT_LINES

[Service]
User=$CURRENT_USER
WorkingDirectory=$USER_HOME
Environment=PATH=$PATH
Environment=PYTHONPATH=$HOME/.local/lib/python3.8/site-packages:/usr/local/lib/python3.8/dist-packages:$PYTHONPATH
ExecStart=/usr/bin/python3 $WANSIM_DASHBOARD
Restart=always
StandardOutput=append:/tmp/wansim_service.log
StandardError=append:/tmp/wansim_service.log

[Install]
WantedBy=multi-user.target
SERVICEEOF
then
    log_message "ERROR" "No se pudo crear el archivo de servicio systemd $SERVICE_FILE."
    echo "${COLOR_ERROR}No se pudo crear $SERVICE_FILE. Revisa permisos con 'ls -ld $(dirname $SERVICE_FILE)'.${COLOR_RESET}"
    exit 1
fi

if ! sudo systemctl daemon-reload; then
    log_message "ERROR" "No se pudo recargar la configuración de systemd."
    echo "${COLOR_ERROR}Fallo al recargar systemd. Revisa con 'sudo systemctl status'.${COLOR_RESET}"
    exit 1
fi
if ! sudo systemctl enable wansim.service; then
    log_message "ERROR" "No se pudo habilitar el servicio wansim.service."
    echo "${COLOR_ERROR}Fallo al habilitar wansim.service. Revisa con 'sudo systemctl status wansim.service'.${COLOR_RESET}"
    exit 1
fi
if ! sudo systemctl restart wansim.service; then
    log_message "ERROR" "No se pudo iniciar el servicio wansim.service."
    echo "${COLOR_ERROR}Fallo al iniciar wansim.service. Revisa con 'sudo systemctl status wansim.service'.${COLOR_RESET}"
    exit 1
fi
log_message "OK" "wansim.service configurado y iniciado."

# Verificar despliegue del servidor Flask
log_message "INFO" "Verificando despliegue de Flask..."
sleep 5
if ss -tuln | grep -q ":5000\|:443"; then
    log_message "OK" "Flask desplegado correctamente."
    echo "${COLOR_OK}Flask - Desplegado correctamente.${COLOR_RESET}"
else
    log_message "ERROR" "Flask no se desplegó. Revisa los logs en /tmp/wansim_dashboard.log y /tmp/wansim_service.log."
    echo "${COLOR_ERROR}Flask no se desplegó. Revisa con 'cat /tmp/wansim_service.log' y '/tmp/wansim_dashboard.log'.${COLOR_RESET}"
    exit 1
fi


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
if [ ${#BRIDGE_INTERFACES[@]} -eq 0 ] && [ -n "${BRIDGE_INTERFACES_CSV:-}" ]; then IFS="," read -r -a BRIDGE_INTERFACES <<< "$BRIDGE_INTERFACES_CSV"; fi
HOSTNAME=$(hostname)
echo "${COLOR_CYAN}┌════════════════════ Resumen de Configuración ═══════════┐${COLOR_RESET}"
echo "${COLOR_CYAN}│                                                        │${COLOR_RESET}"
if [ "$TOPOLOGY_MODE" = "bridge" ]; then
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}Interfaces Bridge:${COLOR_RESET} ${BRIDGE_INTERFACES_CSV:-${BRIDGE_INTERFACES[*]}}${COLOR_CYAN}         │${COLOR_RESET}"
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}Control de Tráfico:${COLOR_RESET} Habilitado${COLOR_CYAN}               │${COLOR_RESET}"
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
