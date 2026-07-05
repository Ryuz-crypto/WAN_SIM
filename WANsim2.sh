#!/bin/bash

## SECCIÓN 1: Comienzo
# -----------------------------------------------

set -e
exec > >(tee -a /tmp/wansim_debug.log) 2>&1

# SECCIÓN 1: Configuración Inicial y Funciones Auxiliares
# -----------------------------------------------
# Variables de configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WANSIM_VERSION="$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "1.116-stable")"
USER_HOME="${HOME:-$(getent passwd "$(whoami)" | cut -d: -f6)}"
WANSIM_HOME="$USER_HOME/.wansim"
PYTHON_VENV="$WANSIM_HOME/venv"
PYTHON_BIN="$PYTHON_VENV/bin/python"
PIP_BIN="$PYTHON_VENV/bin/pip"
LOGFILE="$USER_HOME/emix_abundix.log"
CONFIG_FILE="$USER_HOME/emix_abundix.conf"
WANSIM_DASHBOARD="$USER_HOME/wansim_dashboard.py"
API_TOKENS="$USER_HOME/api_tokens.json"
SERVICE_FILE="/etc/systemd/system/wansim.service"
PERSIST_SCRIPT="/usr/local/sbin/wansim_l2_persist.sh"
PERSIST_SERVICE="/etc/systemd/system/wansim-l2-persist.service"
NETEM_STATE_FILE="$USER_HOME/wansim_netem_state.json"
PREBETA_STATE_FILE="$WANSIM_HOME/reactui_prebeta.json"
TLS_DIR="$WANSIM_HOME/tls"
TLS_CERT_FILE="$TLS_DIR/wansim.crt"
TLS_KEY_FILE="$TLS_DIR/wansim.key"
TLS_ENABLE_FILE="$TLS_DIR/enabled"
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
        apt) sudo apt-get update ;;
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
            sudo apt-get install -y \
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
        DEPENDENCIES=("python3" "python3-venv" "python3-pip" "iproute2" "ifstat" "qrencode" "net-tools" "vlan" "sudo" "lsof" "isc-dhcp-server" "isc-dhcp-client" "iptables-persistent")
        LOCK_FILES=("/var/lib/dpkg/lock-frontend" "/var/lib/apt/lists/lock" "/var/cache/apt/archives/lock")
    else
        DEPENDENCIES=("python3" "python3-pip" "iproute" "ifstat" "qrencode" "net-tools" "sudo" "lsof" "dhcp-server" "dhcp-client" "iptables-services")
        LOCK_FILES=()
    fi
}

cleanup_vlan_links() {
    if [ -z "${LAN_IF:-}" ]; then
        return 0
    fi
    local vlan_links=""
    vlan_links=$(ip -o link show 2>/dev/null | awk -F': ' -v parent="$LAN_IF" '$2 ~ ("@" parent "$") {print $2}' | cut -d'@' -f1 || true)
    while IFS= read -r vlan; do
        [ -z "$vlan" ] && continue
        case "$vlan" in
            vlan*|"$LAN_IF".*)
                log_message "INFO" "Eliminando VLAN generada $vlan..."
                sudo tc qdisc del dev "$vlan" root >/dev/null 2>&1 || true
                sudo ip link delete "$vlan" >/dev/null 2>&1 || true
                ;;
        esac
    done <<< "$vlan_links"
}

cleanup_failed_run() {
    local line="${1:-unknown}"
    local cmd="${2:-unknown}"
    trap - ERR
    set +e
    log_message "ERROR" "Fallo controlado en linea $line durante: $cmd"
    log_message "INFO" "Ejecutando rollback automatico de recursos generados por WAN Simulator..."
    sudo systemctl disable --now wansim.service >/dev/null 2>&1 || true
    sudo systemctl disable --now wansim-l2-persist.service >/dev/null 2>&1 || true
    cleanup_bridges
    cleanup_vlan_links
    sudo rm -f "$SERVICE_FILE" "$PERSIST_SERVICE" "$PERSIST_SCRIPT" >/dev/null 2>&1 || true
    rm -f "$CONFIG_FILE" "$WANSIM_DASHBOARD" "$API_TOKENS" "$NETEM_STATE_FILE" >/dev/null 2>&1 || true
    rm -rf "$PYTHON_VENV" >/dev/null 2>&1 || true
    rm -f /tmp/wansim_dashboard.log /tmp/wansim_service.log /tmp/server.crt /tmp/server.key \
        /tmp/vlan_error.log /tmp/ip_error.log /tmp/iptables_error.log /tmp/tc_error.log \
        /tmp/bridge_error.log >/dev/null 2>&1 || true
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    log_message "OK" "Rollback completado. Log conservado en $LOGFILE"
    echo "${COLOR_ERROR}La ejecucion fallo y se limpiaron los recursos generados. Revisa $LOGFILE.${COLOR_RESET}"
}

trap 'cleanup_failed_run "$LINENO" "$BASH_COMMAND"' ERR

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
SUDOERS_CONTENT="$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/dnf, /usr/bin/yum, /usr/bin/debconf-set-selections, /usr/sbin/tc, /usr/bin/tc, /usr/sbin/ip, /usr/bin/ip, /usr/sbin/iptables, /usr/sbin/iptables-save, /usr/sbin/sysctl, /usr/sbin/dhcpd, /usr/sbin/dhclient, /sbin/dhclient, /usr/bin/systemctl, /usr/bin/systemctl stop unattended-upgrades, /usr/bin/systemctl restart wansim.service, /usr/bin/systemctl restart wansim-l2-persist.service, /usr/bin/systemctl restart isc-dhcp-server, /usr/bin/systemctl restart dhcpd, /usr/bin/systemctl restart iptables, /usr/bin/fuser, /usr/bin/kill, /usr/bin/rm, /usr/sbin/dpkg, /usr/bin/tee, /usr/bin/mv, /usr/bin/chmod, /usr/bin/chown"
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

# Crear runtime Python aislado para evitar PEP 668 / externally-managed-environment.
log_message "DEBUG" "Preparando entorno Python aislado en $PYTHON_VENV..."
mkdir -p "$WANSIM_HOME"
if [ ! -x "$PYTHON_BIN" ]; then
    rm -rf "$PYTHON_VENV"
    if ! python3 -m venv "$PYTHON_VENV"; then
        log_message "ERROR" "No se pudo crear el virtualenv en $PYTHON_VENV."
        echo "${COLOR_ERROR}No se pudo crear el entorno Python. En Debian/Ubuntu instala python3-venv.${COLOR_RESET}"
        exit 1
    fi
fi
if [ ! -x "$PIP_BIN" ]; then
    log_message "ERROR" "pip no está disponible dentro del virtualenv $PYTHON_VENV."
    echo "${COLOR_ERROR}El virtualenv no tiene pip. Revisa python3-venv/python3-pip.${COLOR_RESET}"
    exit 1
fi
log_message "OK" "Python aislado listo: $PYTHON_BIN"

log_message "DEBUG" "Instalando dependencias Python dentro del virtualenv..."
"$PIP_BIN" install --upgrade pip setuptools wheel >/tmp/wansim_pip_bootstrap.log 2>&1 || {
    log_message "ERROR" "No se pudo actualizar pip/setuptools/wheel. Detalle: $(cat /tmp/wansim_pip_bootstrap.log)"
    exit 1
}
PYTHON_DEPS=("flask" "requests" "pyOpenSSL")
for dep in "${PYTHON_DEPS[@]}"; do
    log_message "INFO" "Asegurando dependencia Python $dep en virtualenv..."
    "$PIP_BIN" install "$dep" --no-warn-script-location >/tmp/wansim_pip_install.log 2>&1 || {
        log_message "ERROR" "Falló la instalación de $dep en virtualenv. Detalle: $(cat /tmp/wansim_pip_install.log)"
        exit 1
    }
done
log_message "OK" "Dependencias Python base instaladas en $PYTHON_VENV."

ensure_telegram_runtime() {
    if [ "${INTEGRATE_TELEGRAM:-n}" != "s" ]; then
        return 0
    fi
    if "$PYTHON_BIN" -c "import telegram" >/dev/null 2>&1; then
        log_message "OK" "Dependencia opcional Telegram disponible en virtualenv."
        return 0
    fi

    log_message "INFO" "Preparando Telegram con rutinas alternativas dentro del virtualenv..."
    "$PIP_BIN" install "standard-imghdr" --no-warn-script-location >/tmp/wansim_pip_telegram.log 2>&1 || true

    log_message "INFO" "Telegram intento 1/4: instalacion legacy completa."
    if "$PIP_BIN" install "python-telegram-bot==13.15" "standard-imghdr" --no-warn-script-location >>/tmp/wansim_pip_telegram.log 2>&1 \
        && "$PYTHON_BIN" -c "import telegram" >/dev/null 2>&1; then
        log_message "OK" "Telegram listo con python-telegram-bot==13.15."
        return 0
    fi

    log_message "INFO" "Telegram intento 2/4: dependencias modernas y paquete sin dependencias fijadas."
    if "$PIP_BIN" install "tornado>=6.4" "APScheduler<4" "cachetools" "pytz" "certifi" "standard-imghdr" --no-warn-script-location >>/tmp/wansim_pip_telegram.log 2>&1 \
        && "$PIP_BIN" install --force-reinstall --no-deps "python-telegram-bot==13.15" --no-warn-script-location >>/tmp/wansim_pip_telegram.log 2>&1 \
        && "$PYTHON_BIN" -c "import telegram" >/dev/null 2>&1; then
        log_message "OK" "Telegram listo con dependencias compatibles."
        return 0
    fi

    log_message "INFO" "Telegram intento 3/4: reinstalacion sin cache."
    if "$PIP_BIN" install --no-cache-dir --force-reinstall "python-telegram-bot==13.15" "standard-imghdr" --no-warn-script-location >>/tmp/wansim_pip_telegram.log 2>&1 \
        && "$PYTHON_BIN" -c "import telegram" >/dev/null 2>&1; then
        log_message "OK" "Telegram listo con reinstalacion sin cache."
        return 0
    fi

    log_message "INFO" "Telegram intento 4/4: fallback HTTP API con requests."
    if "$PYTHON_BIN" -c "import requests" >/dev/null 2>&1; then
        log_message "ADVERTENCIA" "No se pudo importar python-telegram-bot. Se usara fallback HTTP API; detalle: $(tail -n 20 /tmp/wansim_pip_telegram.log 2>/dev/null)"
        return 0
    fi

    log_message "ERROR" "Telegram no quedo disponible: fallo python-telegram-bot y tambien requests. Detalle: $(cat /tmp/wansim_pip_telegram.log 2>/dev/null)"
    return 1
}

iface_private_ip() {
    local iface="$1"
    ip -o -4 addr show "$iface" 2>/dev/null | awk '{print $4}' | cut -d'/' -f1 | head -n 1
}

normalize_ipv4_cidr() {
    local ip_addr="$1"
    local mask="$2"
    python3 - "$ip_addr" "$mask" <<'PYCIDR' 2>/dev/null
import ipaddress, sys
ip_addr=sys.argv[1].strip()
mask=sys.argv[2].strip().lstrip("/")
iface=ipaddress.ip_interface(f"{ip_addr}/{mask}")
print(iface.with_prefixlen)
PYCIDR
}

valid_ipv4() {
    local ip_addr="$1"
    python3 - "$ip_addr" <<'PYIP' >/dev/null 2>&1
import ipaddress, sys
ipaddress.ip_address(sys.argv[1].strip())
PYIP
}

wan_cidr_overlaps_lan_range() {
    local wan_cidr="$1"
    local segment_prefix="$2"
    local base_octet="$3"
    local vlan_count="$4"
    python3 - "$wan_cidr" "$segment_prefix" "$base_octet" "$vlan_count" <<'PYOVERLAP' >/dev/null 2>&1
import ipaddress, sys
wan=ipaddress.ip_interface(sys.argv[1]).network
prefix=sys.argv[2]
base=int(sys.argv[3])
count=int(sys.argv[4])
for octet in range(base, base+count):
    lan=ipaddress.ip_network(f"{prefix}.{octet}.0/24")
    if wan.overlaps(lan):
        raise SystemExit(1)
PYOVERLAP
}

configure_wan_addressing() {
    local iface="$1"
    local mode="$2"
    local cidr="$3"
    local gateway="$4"
    local link_idx="${5:-1}"
    local metric=$((200 + link_idx))

    sudo ip link set "$iface" up >/dev/null 2>&1 || true
    if [ "$mode" = "manual" ]; then
        log_message "INFO" "Configurando WAN $iface en modo manual: $cidr gateway=$gateway metric=$metric"
        sudo ip addr flush dev "$iface" >/tmp/wansim_wan_ip.log 2>&1 || true
        sudo ip addr add "$cidr" dev "$iface" >/tmp/wansim_wan_ip.log 2>&1 || {
            log_message "ERROR" "No se pudo asignar $cidr a $iface: $(cat /tmp/wansim_wan_ip.log)"
            exit 1
        }
        sudo ip route del default via "$gateway" dev "$iface" >/dev/null 2>&1 || true
        sudo ip route add default via "$gateway" dev "$iface" metric "$metric" >/tmp/wansim_wan_route.log 2>&1 || {
            log_message "ERROR" "No se pudo agregar gateway $gateway para $iface: $(cat /tmp/wansim_wan_route.log)"
            exit 1
        }
    else
        log_message "INFO" "Configurando WAN $iface en modo DHCP o conservando lease existente."
        if command -v dhclient >/dev/null 2>&1; then
            sudo dhclient -r "$iface" >/dev/null 2>&1 || true
            sudo dhclient "$iface" >/tmp/wansim_wan_dhcp.log 2>&1 || {
                log_message "ADVERTENCIA" "dhclient no pudo renovar $iface. Se conserva configuracion actual. Detalle: $(cat /tmp/wansim_wan_dhcp.log)"
            }
        elif [ -z "$(iface_private_ip "$iface")" ]; then
            log_message "ADVERTENCIA" "dhclient no esta disponible y $iface no tiene IPv4. Instala cliente DHCP o usa modo manual."
        fi
    fi
}

validate_tls_chain() {
    local cert="$1"
    local key="$2"
    "$PYTHON_BIN" - "$cert" "$key" <<'PYTLSVALID' >/tmp/wansim_tls_validate.log 2>&1
import ssl, sys
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(sys.argv[1], sys.argv[2])
PYTLSVALID
}

install_pem_tls_pair() {
    local cert_src="$1"
    local key_src="$2"
    mkdir -p "$TLS_DIR"
    chmod 700 "$TLS_DIR"
    cp "$cert_src" "$TLS_CERT_FILE"
    cp "$key_src" "$TLS_KEY_FILE"
    chmod 600 "$TLS_CERT_FILE" "$TLS_KEY_FILE"
    chown "$CURRENT_USER:$CURRENT_USER" "$TLS_CERT_FILE" "$TLS_KEY_FILE" 2>/dev/null || true
    validate_tls_chain "$TLS_CERT_FILE" "$TLS_KEY_FILE"
}

install_pfx_tls_pair() {
    local pfx_src="$1"
    local pfx_pass="$2"
    mkdir -p "$TLS_DIR"
    chmod 700 "$TLS_DIR"
    openssl pkcs12 -in "$pfx_src" -clcerts -nokeys -out "$TLS_CERT_FILE" -passin "pass:$pfx_pass" >/tmp/wansim_tls_convert.log 2>&1
    openssl pkcs12 -in "$pfx_src" -nocerts -nodes -out "$TLS_KEY_FILE" -passin "pass:$pfx_pass" >>/tmp/wansim_tls_convert.log 2>&1
    chmod 600 "$TLS_CERT_FILE" "$TLS_KEY_FILE"
    chown "$CURRENT_USER:$CURRENT_USER" "$TLS_CERT_FILE" "$TLS_KEY_FILE" 2>/dev/null || true
    validate_tls_chain "$TLS_CERT_FILE" "$TLS_KEY_FILE"
}

install_der_tls_pair() {
    local cert_src="$1"
    local key_src="$2"
    mkdir -p "$TLS_DIR"
    chmod 700 "$TLS_DIR"
    openssl x509 -inform DER -in "$cert_src" -out "$TLS_CERT_FILE" >/tmp/wansim_tls_convert.log 2>&1
    openssl rsa -inform DER -in "$key_src" -out "$TLS_KEY_FILE" >>/tmp/wansim_tls_convert.log 2>&1
    chmod 600 "$TLS_CERT_FILE" "$TLS_KEY_FILE"
    chown "$CURRENT_USER:$CURRENT_USER" "$TLS_CERT_FILE" "$TLS_KEY_FILE" 2>/dev/null || true
    validate_tls_chain "$TLS_CERT_FILE" "$TLS_KEY_FILE"
}

iface_public_ip() {
    local iface="$1"
    local public_ip=""
    for endpoint in "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
        public_ip=$(curl --interface "$iface" -fsS --max-time 6 "$endpoint" 2>/dev/null | tr -d '\r\n ' || true)
        if [[ "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$public_ip"
            return 0
        fi
    done
    echo "N/D"
}

iface_bw_probe() {
    local iface="$1"
    local bytes_per_sec=""
    bytes_per_sec=$(curl --interface "$iface" -LfsS --max-time 12 -o /dev/null \
        -w '%{speed_download}' "https://speed.cloudflare.com/__down?bytes=10000000" 2>/dev/null || true)
    if [[ "$bytes_per_sec" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        awk -v bps="$bytes_per_sec" 'BEGIN { printf "%.2f Mbps", (bps*8)/1000000 }'
    else
        echo "N/D"
    fi
}

append_json_item() {
    local current="$1"
    local value="$2"
    if [ "$current" = "[" ]; then
        printf '%s"%s"' "$current" "$value"
    else
        printf '%s, "%s"' "$current" "$value"
    fi
}

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
            read -p "${COLOR_INFO}[ENTRADA] ¿Cuántos pares WAN/LAN L3 deseas configurar? [1-2, predeterminado 1]: ${COLOR_RESET}" NUM_L3_LINKS
            NUM_L3_LINKS=${NUM_L3_LINKS:-1}
            if [[ "$NUM_L3_LINKS" =~ ^[1-2]$ ]]; then break; else log_message "ERROR" "Ingresa 1 o 2."; fi
        done
        while true; do
            read -p "${COLOR_INFO}[ENTRADA] ¿Cuántas VLANs simular por par WAN/LAN? [predeterminado 10]: ${COLOR_RESET}" NUM_VLANS
            NUM_VLANS=${NUM_VLANS:-10}
            if [[ "$NUM_VLANS" =~ ^[1-9][0-9]*$ ]]; then break; else log_message "ERROR" "Ingresa un número válido."; fi
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
            BASE_OCTET=10
            echo "${COLOR_INFO}El tercer octeto se definira por cada par WAN/LAN para evitar rangos repetidos.${COLOR_RESET}"
        else
            SEGMENT_PREFIX="192.168"
            BASE_OCTET=10
        fi
        L3_LINKS_CSV=""; USED_INTERFACES=""; USED_VLAN_RANGES=""; USED_OCTET_RANGES=""
        for (( link_idx=1; link_idx<=NUM_L3_LINKS; link_idx++ )); do
            echo "${COLOR_CYAN}--- Par L3 #$link_idx ---${COLOR_RESET}"
            while true; do
                read -p "${COLOR_INFO}[ENTRADA] Par #$link_idx - interfaz WAN: ${COLOR_RESET}" wan_iface
                if [[ -n "$wan_iface" && " ${VALID_INTERFACES[*]} " =~ " $wan_iface " && ! " $USED_INTERFACES " =~ " $wan_iface " ]]; then log_message "OK" "WAN $wan_iface válida."; break; else log_message "ERROR" "WAN inválida o ya seleccionada."; fi
            done
            while true; do
                read -p "${COLOR_INFO}[ENTRADA] Par #$link_idx - interfaz LAN/trunk VLAN: ${COLOR_RESET}" lan_iface
                if [[ -n "$lan_iface" && " ${VALID_INTERFACES[*]} " =~ " $lan_iface " && "$lan_iface" != "$wan_iface" && ! " $USED_INTERFACES " =~ " $lan_iface " ]]; then log_message "OK" "LAN $lan_iface válida."; break; else log_message "ERROR" "LAN inválida, duplicada o igual a WAN."; fi
            done
            while true; do
                read -p "${COLOR_INFO}[ENTRADA] Par #$link_idx - ID inicial VLAN (1-4094): ${COLOR_RESET}" start_vlan
                if [[ "$start_vlan" =~ ^[0-9]+$ && "$start_vlan" -ge 1 && "$start_vlan" -le 4094 && $((start_vlan + NUM_VLANS - 1)) -le 4094 ]]; then
                    overlap=0
                    for range in $USED_VLAN_RANGES; do
                        IFS='-' read -r r_start r_end <<< "$range"
                        if [ "$start_vlan" -le "$r_end" ] && [ $((start_vlan + NUM_VLANS - 1)) -ge "$r_start" ]; then overlap=1; fi
                    done
                    [ "$overlap" -eq 0 ] && break
                fi
                log_message "ERROR" "Rango VLAN inválido o repetido. Debe caber en 1-4094 y no solaparse."
            done
            while true; do
                default_octet=$(( BASE_OCTET + (link_idx - 1) * NUM_VLANS ))
                read -p "${COLOR_INFO}[ENTRADA] Par #$link_idx - tercer octeto inicial [predeterminado $default_octet]: ${COLOR_RESET}" base_octet_link
                base_octet_link=${base_octet_link:-$default_octet}
                if [[ "$base_octet_link" =~ ^[0-9]+$ && "$base_octet_link" -ge 1 && $((base_octet_link + NUM_VLANS - 1)) -le 254 ]]; then
                    overlap=0
                    for range in $USED_OCTET_RANGES; do
                        IFS='-' read -r r_start r_end <<< "$range"
                        if [ "$base_octet_link" -le "$r_end" ] && [ $((base_octet_link + NUM_VLANS - 1)) -ge "$r_start" ]; then overlap=1; fi
                    done
                    [ "$overlap" -eq 0 ] && break
                fi
                log_message "ERROR" "Rango de octetos inválido o repetido. Debe caber en 1-254 y no solaparse."
            done
            while true; do
                read -p "${COLOR_INFO}[ENTRADA] Par #$link_idx - direccionamiento WAN para $wan_iface (dhcp/manual) [predeterminado dhcp]: ${COLOR_RESET}" wan_addr_mode
                wan_addr_mode=${wan_addr_mode:-dhcp}
                wan_addr_mode=$(echo "$wan_addr_mode" | tr '[:upper:]' '[:lower:]')
                case "$wan_addr_mode" in
                    dhcp)
                        wan_cidr=""
                        wan_gateway=""
                        break
                        ;;
                    manual|static|estatico)
                        wan_addr_mode="manual"
                        while true; do
                            read -p "${COLOR_INFO}[ENTRADA] Par #$link_idx - IP WAN de $wan_iface: ${COLOR_RESET}" wan_ip
                            valid_ipv4 "$wan_ip" && break
                            log_message "ERROR" "IP WAN invalida."
                        done
                        while true; do
                            read -p "${COLOR_INFO}[ENTRADA] Par #$link_idx - mascara o prefijo WAN (ej. 24 o 255.255.255.0): ${COLOR_RESET}" wan_mask
                            wan_cidr=$(normalize_ipv4_cidr "$wan_ip" "$wan_mask" || true)
                            [ -n "$wan_cidr" ] && break
                            log_message "ERROR" "Mascara/prefijo invalido."
                        done
                        while true; do
                            read -p "${COLOR_INFO}[ENTRADA] Par #$link_idx - gateway WAN: ${COLOR_RESET}" wan_gateway
                            valid_ipv4 "$wan_gateway" && break
                            log_message "ERROR" "Gateway invalido."
                        done
                        if ! wan_cidr_overlaps_lan_range "$wan_cidr" "$SEGMENT_PREFIX" "$base_octet_link" "$NUM_VLANS"; then
                            log_message "ERROR" "La red WAN $wan_cidr se solapa con las VLAN LAN ${SEGMENT_PREFIX}.${base_octet_link}.0/24..."
                            continue
                        fi
                        break
                        ;;
                    *)
                        log_message "ERROR" "Ingresa dhcp o manual."
                        ;;
                esac
            done
            USED_INTERFACES="$USED_INTERFACES $wan_iface $lan_iface"
            USED_VLAN_RANGES="$USED_VLAN_RANGES $start_vlan-$((start_vlan + NUM_VLANS - 1))"
            USED_OCTET_RANGES="$USED_OCTET_RANGES $base_octet_link-$((base_octet_link + NUM_VLANS - 1))"
            [ -n "$L3_LINKS_CSV" ] && L3_LINKS_CSV+=";"
            L3_LINKS_CSV+="$link_idx:$wan_iface:$lan_iface:$start_vlan:$base_octet_link:$SEGMENT_PREFIX:$wan_addr_mode:$wan_cidr:$wan_gateway"
        done
        IFS=':' read -r __idx WAN_IF LAN_IF START_VLAN BASE_OCTET SEGMENT_PREFIX <<< "${L3_LINKS_CSV%%;*}"
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
        ensure_telegram_runtime
        if [ "$INTEGRATE_TELEGRAM" = "s" ]; then
            read -p "${COLOR_INFO}[ENTRADA] Ingresa el token del Bot de Telegram: ${COLOR_RESET}" TELEGRAM_TOKEN
            read -p "${COLOR_INFO}[ENTRADA] Ingresa el Chat ID (deja vacío para obtenerlo automáticamente): ${COLOR_RESET}" TELEGRAM_CHAT_ID
            if [ -z "$TELEGRAM_CHAT_ID" ]; then get_telegram_chat_id "$TELEGRAM_TOKEN"; fi
        fi
    else
        TELEGRAM_TOKEN=""
        TELEGRAM_CHAT_ID=""
    fi
    echo "${COLOR_CYAN}└───────────────────────────────────────────────────────────┘${COLOR_RESET}"
fi

ensure_telegram_runtime


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
    NUM_L3_LINKS=${NUM_L3_LINKS:-1}
    if [ -z "${L3_LINKS_CSV:-}" ]; then
        L3_LINKS_CSV="1:${WAN_IF}:${LAN_IF}:${START_VLAN:-100}:${BASE_OCTET:-10}:${SEGMENT_PREFIX:-192.168}:dhcp::"
    fi
    log_message "INFO" "Configurando modo L3/NAT con $NUM_L3_LINKS par(es) WAN/LAN..."

    if ! lsmod | grep -q "8021q"; then
        log_message "INFO" "Cargando módulo 8021q para soporte de VLANs..."
        sudo modprobe 8021q >/dev/null 2>&1
        lsmod | grep -q "8021q" || { log_message "ERROR" "No se pudo cargar 8021q."; exit 1; }
    fi

    PYTHON_VLAN_LIST="["
    PYTHON_INTERFACE_META="{}"
    VALID_VLANS=()
    DHCP_INTERFACES=()
    META_TSV="/tmp/wansim_nat_meta.tsv"
    DHCP_TSV="/tmp/wansim_dhcp.tsv"
    NAT_TSV="/tmp/wansim_nat.tsv"
    : > "$META_TSV"; : > "$DHCP_TSV"; : > "$NAT_TSV"

    IFS=';' read -r -a L3_LINKS <<< "$L3_LINKS_CSV"
    for link in "${L3_LINKS[@]}"; do
        [ -z "$link" ] && continue
        IFS=':' read -r link_idx wan_iface lan_iface start_vlan base_octet_link segment_prefix_link wan_addr_mode wan_cidr wan_gateway <<< "$link"
        segment_prefix_link=${segment_prefix_link:-192.168}
        wan_addr_mode=${wan_addr_mode:-dhcp}
        log_message "INFO" "Preparando L3#$link_idx WAN=$wan_iface LAN=$lan_iface VLAN_START=$start_vlan OCTETO=$base_octet_link..."
        ip link show "$wan_iface" >/dev/null 2>&1 || { log_message "ERROR" "WAN $wan_iface no existe."; exit 1; }
        ip link show "$lan_iface" >/dev/null 2>&1 || { log_message "ERROR" "LAN $lan_iface no existe."; exit 1; }
        sudo ip link set "$wan_iface" up >/dev/null 2>&1 || true
        sudo ip link set "$lan_iface" up >/dev/null 2>&1 || true
        reset_interface "$lan_iface"
        if [ "$wan_addr_mode" = "manual" ]; then
            if [ -z "$wan_cidr" ] || [ -z "$wan_gateway" ] || ! valid_ipv4 "$wan_gateway"; then
                log_message "ERROR" "WAN $wan_iface esta en modo manual pero faltan CIDR o gateway validos."
                exit 1
            fi
            if ! wan_cidr_overlaps_lan_range "$wan_cidr" "$segment_prefix_link" "$base_octet_link" "$NUM_VLANS"; then
                log_message "ERROR" "La red WAN $wan_cidr se solapa con las VLAN LAN del par #$link_idx."
                exit 1
            fi
        fi
        configure_wan_addressing "$wan_iface" "$wan_addr_mode" "$wan_cidr" "$wan_gateway" "$link_idx"
        wan_private=$(iface_private_ip "$wan_iface"); wan_private=${wan_private:-N/D}
        wan_public=$(iface_public_ip "$wan_iface")
        wan_bw=$(iface_bw_probe "$wan_iface")
        wan_mac=$(cat "/sys/class/net/$wan_iface/address" 2>/dev/null || echo "N/D")
        lan_mac=$(cat "/sys/class/net/$lan_iface/address" 2>/dev/null || echo "N/D")
        log_message "OK" "L3#$link_idx WAN $wan_iface privada=$wan_private publica=$wan_public bw=$wan_bw"

        for (( i=0; i<${NUM_VLANS:-0}; i++ )); do
            current_vlan_id=$(( start_vlan + i ))
            subnet_octet=$(( base_octet_link + i ))
            vlan_name="v${link_idx}_${current_vlan_id}"
            [ ${#vlan_name} -le 15 ] || { log_message "ERROR" "Nombre VLAN $vlan_name excede 15 caracteres."; exit 1; }
            sudo ip link add link "$lan_iface" name "$vlan_name" type vlan id "$current_vlan_id" >/tmp/vlan_error.log 2>&1 || {
                log_message "ERROR" "No se pudo crear $vlan_name: $(cat /tmp/vlan_error.log)"
                exit 1
            }
            sudo ip addr add "${segment_prefix_link}.${subnet_octet}.1/24" dev "$vlan_name" >/tmp/ip_error.log 2>&1 || {
                log_message "ERROR" "No se pudo asignar IP a $vlan_name: $(cat /tmp/ip_error.log)"
                exit 1
            }
            sudo ip link set "$vlan_name" up >/dev/null 2>&1
            VALID_VLANS+=("$vlan_name")
            DHCP_INTERFACES+=("$vlan_name")
            PYTHON_VLAN_LIST=$(append_json_item "$PYTHON_VLAN_LIST" "$vlan_name")
            subnet="${segment_prefix_link}.${subnet_octet}.0/24"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$vlan_name" "VLAN $current_vlan_id ($lan_iface -> $wan_iface)" "" "L3/NAT" "$wan_iface" "$wan_mac" \
                "$wan_iface" "$lan_iface" "$wan_private" "$wan_public" "$wan_bw" "$subnet" "$lan_mac" "$wan_addr_mode" "$wan_cidr" "$wan_gateway" >> "$META_TSV"
            printf '%s\t%s\t%s\n' "$segment_prefix_link" "$subnet_octet" "$vlan_name" >> "$DHCP_TSV"
            printf '%s\t%s.%s.0/24\n' "$wan_iface" "$segment_prefix_link" "$subnet_octet" >> "$NAT_TSV"
            log_message "OK" "Creada $vlan_name VLAN=$current_vlan_id subnet=${segment_prefix_link}.${subnet_octet}.0/24 WAN=$wan_iface"
        done
    done
    PYTHON_VLAN_LIST+="]"

    if [ ${#VALID_VLANS[@]} -eq 0 ]; then
        log_message "ERROR" "No se creó ninguna VLAN válida en modo L3."
        exit 1
    fi

    if [ "$CONFIG_DHCP" = "s" ]; then
        log_message "INFO" "Configurando DHCP para ${#DHCP_INTERFACES[@]} VLAN(s)..."
        [ -f /etc/dhcp/dhcpd.conf ] && sudo cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak
        sudo tee /etc/dhcp/dhcpd.conf > /dev/null <<EOL
default-lease-time 600;
max-lease-time 7200;
authoritative;
EOL
        while IFS=$'\t' read -r segment_prefix_link subnet_octet vlan_name; do
            [ -z "$segment_prefix_link" ] && continue
            sudo tee -a /etc/dhcp/dhcpd.conf > /dev/null <<EOF
subnet ${segment_prefix_link}.${subnet_octet}.0 netmask 255.255.255.0 {
    range ${segment_prefix_link}.${subnet_octet}.100 ${segment_prefix_link}.${subnet_octet}.200;
    option routers ${segment_prefix_link}.${subnet_octet}.1;
}
EOF
        done < "$DHCP_TSV"
        sudo tee "$DHCP_DEFAULT_FILE" > /dev/null <<EOF
INTERFACESv4="${DHCP_INTERFACES[*]}"
DHCPDARGS="${DHCP_INTERFACES[*]}"
EOF
        dhcpd -t -cf /etc/dhcp/dhcpd.conf >/tmp/wansim_dhcp_validate.log 2>&1 || {
            log_message "ERROR" "Configuración DHCP inválida: $(cat /tmp/wansim_dhcp_validate.log)"
            exit 1
        }
        sudo systemctl enable "$DHCP_SERVICE" >/dev/null 2>&1
        sudo systemctl restart "$DHCP_SERVICE" >/dev/null 2>&1 || {
            log_message "ERROR" "No se pudo iniciar $DHCP_SERVICE: $(journalctl -u "$DHCP_SERVICE" -n 50 --no-pager 2>&1)"
            exit 1
        }
        log_message "OK" "DHCP configurado para modo L3 multi enlace."
    fi

    log_message "INFO" "Configurando NAT multi WAN..."
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
    IPTABLES_SAVE_DIR="$(dirname "$IPTABLES_SAVE_FILE")"
    sudo mkdir -p "$IPTABLES_SAVE_DIR" >/dev/null 2>&1
    sudo iptables -t nat -F POSTROUTING >/dev/null 2>&1
    while IFS=$'\t' read -r wan_iface subnet; do
        [ -z "$wan_iface" ] && continue
        sudo iptables -t nat -A POSTROUTING -o "$wan_iface" -s "$subnet" -j MASQUERADE
    done < "$NAT_TSV"
    temp_rules="/tmp/iptables_rules.v4"
    sudo iptables-save > "$temp_rules" 2>/tmp/iptables_error.log || {
        log_message "ERROR" "Error al guardar reglas NAT: $(cat /tmp/iptables_error.log)"
        exit 1
    }
    sudo mv "$temp_rules" "$IPTABLES_SAVE_FILE"
    sudo chmod 644 "$IPTABLES_SAVE_FILE" >/dev/null 2>&1
    [ "$OS_FAMILY" = "rhel" ] && sudo systemctl enable iptables >/dev/null 2>&1 || true

    export META_TSV
    PYTHON_INTERFACE_META=$(python3 - <<'PYJSON'
import json, os
meta={}
path=os.environ.get('META_TSV','')
try:
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            parts=line.rstrip('\n').split('\t')
            if len(parts) < 12:
                continue
            iface,label,bridge,role,peer,mac,wan,lan,wan_private,wan_public,wan_bw,subnet=parts[:12]
            lan_mac=parts[12] if len(parts) > 12 else ""
            wan_addr_mode=parts[13] if len(parts) > 13 else "dhcp"
            wan_cidr=parts[14] if len(parts) > 14 else ""
            wan_gateway=parts[15] if len(parts) > 15 else ""
            meta[iface]={
                "label":label,"bridge":bridge,"role":role,"peer":peer,"mac":mac,
                "wan":wan,"lan":lan,"wan_private":wan_private,"wan_public":wan_public,
                "wan_bw":wan_bw,"subnet":subnet,"lan_mac":lan_mac,
                "wan_addr_mode":wan_addr_mode,"wan_cidr":wan_cidr,"wan_gateway":wan_gateway
            }
except FileNotFoundError:
    pass
print(json.dumps(meta, ensure_ascii=False))
PYJSON
)
    log_message "OK" "Modo L3/NAT multi enlace configurado. Interfaces controladas: ${VALID_VLANS[*]}"
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
NUM_L3_LINKS=${NUM_L3_LINKS:-1}
L3_LINKS_CSV=${L3_LINKS_CSV:-}
NUM_VLANS=${NUM_VLANS:-0}
START_VLAN=${START_VLAN:-0}
CONFIG_DHCP=${CONFIG_DHCP:-n}
SEGMENT_PREFIX=${SEGMENT_PREFIX:-192.168}
BASE_OCTET=${BASE_OCTET:-0}
INTEGRATE_TELEGRAM=$INTEGRATE_TELEGRAM
TELEGRAM_TOKEN=$TELEGRAM_TOKEN
TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID
ENABLE_HTTPS=${ENABLE_HTTPS:-n}
TLS_MODE=${TLS_MODE:-none}
TLS_CERT_FILE=$(printf '%q' "${TLS_CERT_FILE:-$TLS_DIR/wansim.crt}")
TLS_KEY_FILE=$(printf '%q' "${TLS_KEY_FILE:-$TLS_DIR/wansim.key}")
TLS_ENABLE_FILE=$(printf '%q' "${TLS_ENABLE_FILE:-$TLS_DIR/enabled}")
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

# Verificar dependencias de Python dentro del virtualenv.
log_message "INFO" "Verificando dependencias de Python en $PYTHON_VENV..."
for module in flask requests OpenSSL; do
    "$PYTHON_BIN" -c "import $module" >/dev/null 2>&1 || {
        log_message "ERROR" "Módulo Python $module no encontrado en $PYTHON_VENV."
        echo "${COLOR_ERROR}El runtime Python aislado no contiene $module. Se limpiará el despliegue parcial.${COLOR_RESET}"
        exit 1
    }
    log_message "OK" "$module disponible en virtualenv."
done
if [ "${INTEGRATE_TELEGRAM:-n}" = "s" ]; then
    ensure_telegram_runtime
fi
log_message "OK" "Dependencias de Python verificadas en virtualenv."

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
import os, re, json, logging, subprocess, threading, sys, time
import requests
from flask import Flask, request, render_template_string, redirect, url_for, flash, jsonify
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
HTTPS_ENABLED=bool(int(__HTTPS_ENABLED__))
TLS_CERT_FILE=__TLS_CERT_FILE_LITERAL__
TLS_KEY_FILE=__TLS_KEY_FILE_LITERAL__
TLS_DIR=__TLS_DIR_LITERAL__
TLS_ENABLE_FILE=__TLS_ENABLE_FILE_LITERAL__
CONFIG_FILE=__CONFIG_FILE_LITERAL__
PREBETA_STATE_FILE=__PREBETA_STATE_FILE_LITERAL__
DHCP_SERVICE=__DHCP_SERVICE_LITERAL__
TOPOLOGY_MODE=__TOPOLOGY_MODE_LITERAL__
def tls_is_ready():
    if not (TLS_CERT_FILE and TLS_KEY_FILE and TLS_ENABLE_FILE):
        return False
    if not (os.path.exists(TLS_ENABLE_FILE) and os.path.exists(TLS_CERT_FILE) and os.path.exists(TLS_KEY_FILE)):
        return False
    try:
        import ssl
        ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(TLS_CERT_FILE,TLS_KEY_FILE)
        return True
    except Exception as e:
        logger.error(f'TLS no valido: {e}')
        return False
HTTPS_ENABLED=HTTPS_ENABLED or tls_is_ready()
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
        s[i].update({
            'label':meta.get('label',i),
            'bridge':meta.get('bridge',''),
            'role':meta.get('role',''),
            'peer':meta.get('peer',''),
            'mac':meta.get('mac',''),
            'wan':meta.get('wan',''),
            'lan':meta.get('lan',''),
            'wan_private':meta.get('wan_private',''),
            'wan_public':meta.get('wan_public',''),
            'wan_bw':meta.get('wan_bw',''),
            'subnet':meta.get('subnet',''),
            'lan_mac':meta.get('lan_mac',''),
            'wan_addr_mode':meta.get('wan_addr_mode',''),
            'wan_cidr':meta.get('wan_cidr',''),
            'wan_gateway':meta.get('wan_gateway','')
        })
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
        ctx.user_data['iface']=i
        label=INTERFACE_META.get(i,{}).get("label",i)
        kb=[
            [InlineKeyboardButton('100ms',callback_data=f'quick|{i}|100|0|0'), InlineKeyboardButton('300ms',callback_data=f'quick|{i}|300|0|0'), InlineKeyboardButton('500ms',callback_data=f'quick|{i}|500|0|0')],
            [InlineKeyboardButton('Jitter 50',callback_data=f'quick|{i}|0|50|0'), InlineKeyboardButton('Jitter 100',callback_data=f'quick|{i}|0|100|0')],
            [InlineKeyboardButton('Loss 1%',callback_data=f'quick|{i}|0|0|1'), InlineKeyboardButton('Loss 5%',callback_data=f'quick|{i}|0|0|5'), InlineKeyboardButton('Loss 10%',callback_data=f'quick|{i}|0|0|10')],
            [InlineKeyboardButton('Manual',callback_data=f'manual|{i}'), InlineKeyboardButton('Reset',callback_data=f'quick|{i}|0|0|0')]
        ]
        q.edit_message_text(f'Interfaz {label}. Elige preset o modo manual:',reply_markup=InlineKeyboardMarkup(kb)); return DELAY
    def quick(update,ctx):
        q=update.callback_query; q.answer()
        parts=q.data.split('|')
        if parts[0]=='manual':
            i=parts[1]; ctx.user_data['iface']=i
            q.edit_message_text(f'Interfaz {INTERFACE_META.get(i,{}).get("label",i)}. Delay/latencia ms:')
            return DELAY
        _,i,d,j,l=parts
        if i not in CONTROL_INTERFACES: q.edit_message_text('Interfaz inválida.'); return -1
        ok,out=apply_netem(i,d,j,l)
        label=INTERFACE_META.get(i,{}).get('label',i)
        q.edit_message_text(f'Aplicado preset en {label}: delay={d}ms jitter={j}ms pérdida={l}%. {out}' if ok else f'Error en {label}: {out}')
        return -1
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
            dp.add_handler(ConversationHandler(entry_points=[CommandHandler('start',start),CommandHandler('config',start)],states={SELECT:[CallbackQueryHandler(sel,pattern='^select_')],DELAY:[CallbackQueryHandler(quick,pattern='^(quick|manual)\\|'),MessageHandler(Filters.text & ~Filters.command,setd)],JITTER:[MessageHandler(Filters.text & ~Filters.command,setj)],LOSS:[MessageHandler(Filters.text & ~Filters.command,setl)]},fallbacks=[CommandHandler('cancel',cancel)]))
            u.start_polling(); u.idle()
        except Exception as e: logger.error(f'Telegram error: {e}')
    threading.Thread(target=bot,daemon=True).start()
if TELEGRAM_ENABLED and not Updater:
    TG_STATE={}
    def tg_api(method, payload=None):
        url=f'https://api.telegram.org/bot{TELEGRAM_TOKEN}/{method}'
        try:
            r=requests.post(url,json=payload or {},timeout=15)
            if not r.ok: logger.error(f'Telegram API {method} fallo: {r.status_code} {r.text[:300]}')
            return r.ok, r.json() if r.text else {}
        except Exception as e:
            logger.error(f'Telegram API {method} error: {e}')
            return False, {}
    def tg_allowed(chat_id):
        return (not TELEGRAM_CHAT_ID) or str(chat_id)==str(TELEGRAM_CHAT_ID)
    def tg_iface_label(i):
        return INTERFACE_META.get(i,{}).get('label',i) if isinstance(INTERFACE_META,dict) else i
    def tg_iface_keyboard():
        return {'inline_keyboard':[[{'text':tg_iface_label(i)[:60],'callback_data':f'select_{i}'}] for i in CONTROL_INTERFACES]}
    def tg_preset_keyboard(i):
        return {'inline_keyboard':[
            [{'text':'100ms','callback_data':f'quick|{i}|100|0|0'},{'text':'300ms','callback_data':f'quick|{i}|300|0|0'},{'text':'500ms','callback_data':f'quick|{i}|500|0|0'}],
            [{'text':'Jitter 50','callback_data':f'quick|{i}|0|50|0'},{'text':'Jitter 100','callback_data':f'quick|{i}|0|100|0'}],
            [{'text':'Loss 1%','callback_data':f'quick|{i}|0|0|1'},{'text':'Loss 5%','callback_data':f'quick|{i}|0|0|5'},{'text':'Loss 10%','callback_data':f'quick|{i}|0|0|10'}],
            [{'text':'Manual','callback_data':f'manual|{i}'},{'text':'Reset','callback_data':f'quick|{i}|0|0|0'}]
        ]}
    def tg_send(chat_id, text, markup=None):
        payload={'chat_id':chat_id,'text':text}
        if markup: payload['reply_markup']=markup
        return tg_api('sendMessage',payload)
    def tg_edit(chat_id, message_id, text, markup=None):
        payload={'chat_id':chat_id,'message_id':message_id,'text':text}
        if markup: payload['reply_markup']=markup
        return tg_api('editMessageText',payload)
    def tg_handle_text(msg):
        chat_id=msg.get('chat',{}).get('id')
        text=(msg.get('text') or '').strip()
        if not tg_allowed(chat_id): tg_send(chat_id,'Acceso no autorizado.'); return
        if text in ('/start','/config','start','config'):
            TG_STATE.pop(str(chat_id),None)
            tg_send(chat_id,'Selecciona la interfaz:',tg_iface_keyboard()); return
        if text == '/cancel':
            TG_STATE.pop(str(chat_id),None)
            tg_send(chat_id,'Cancelado.'); return
        state=TG_STATE.get(str(chat_id))
        if not state:
            tg_send(chat_id,'Usa /start para seleccionar una interfaz.'); return
        try:
            if state.get('step')=='delay':
                state['delay']=to_number(text,'delay',0.0); state['step']='jitter'; tg_send(chat_id,'Jitter ms:'); return
            if state.get('step')=='jitter':
                state['jitter']=to_number(text,'jitter',0.0); state['step']='loss'; tg_send(chat_id,'Ruido/perdida %:'); return
            if state.get('step')=='loss':
                loss=to_number(text,'perdida',0.0,100.0)
                iface=state['iface']; delay=state.get('delay',0); jitter=state.get('jitter',0)
                ok,out=apply_netem(iface,delay,jitter,loss)
                label=tg_iface_label(iface)
                tg_send(chat_id, f'Aplicado en {label}: delay={tc_num(delay)}ms jitter={tc_num(jitter)}ms perdida={tc_num(loss)}%. {out}' if ok else f'Error en {label}: {out}')
                TG_STATE.pop(str(chat_id),None); return
        except Exception as e:
            tg_send(chat_id,f'Valor invalido: {e}')
    def tg_handle_callback(cb):
        chat_id=cb.get('message',{}).get('chat',{}).get('id')
        msg_id=cb.get('message',{}).get('message_id')
        data=cb.get('data') or ''
        tg_api('answerCallbackQuery',{'callback_query_id':cb.get('id')})
        if not tg_allowed(chat_id): tg_edit(chat_id,msg_id,'Acceso no autorizado.'); return
        if data.startswith('select_'):
            iface=data.split('_',1)[1]
            if iface not in CONTROL_INTERFACES: tg_edit(chat_id,msg_id,'Seleccion invalida.'); return
            TG_STATE[str(chat_id)]={'iface':iface,'step':'preset'}
            tg_edit(chat_id,msg_id,f'Interfaz {tg_iface_label(iface)}. Elige preset o modo manual:',tg_preset_keyboard(iface)); return
        parts=data.split('|')
        if len(parts)>=2 and parts[0]=='manual':
            iface=parts[1]
            TG_STATE[str(chat_id)]={'iface':iface,'step':'delay'}
            tg_edit(chat_id,msg_id,f'Interfaz {tg_iface_label(iface)}. Delay/latencia ms:'); return
        if len(parts)==5 and parts[0]=='quick':
            _,iface,delay,jitter,loss=parts
            if iface not in CONTROL_INTERFACES: tg_edit(chat_id,msg_id,'Interfaz invalida.'); return
            ok,out=apply_netem(iface,delay,jitter,loss)
            label=tg_iface_label(iface)
            tg_edit(chat_id,msg_id,f'Aplicado preset en {label}: delay={delay}ms jitter={jitter}ms perdida={loss}%. {out}' if ok else f'Error en {label}: {out}')
    def tg_http_bot():
        offset=0
        while True:
            try:
                ok,data=tg_api('getUpdates',{'timeout':25,'offset':offset,'allowed_updates':['message','callback_query']})
                if ok:
                    for upd in data.get('result',[]):
                        offset=max(offset,upd.get('update_id',0)+1)
                        if 'message' in upd: tg_handle_text(upd['message'])
                        if 'callback_query' in upd: tg_handle_callback(upd['callback_query'])
                time.sleep(1)
            except Exception as e:
                logger.error(f'Telegram HTTP fallback error: {e}')
                time.sleep(5)
    threading.Thread(target=tg_http_bot,daemon=True).start()
TEMPLATE=r"""
<!doctype html><html lang='es'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Ryuz WAN Simulator</title><link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'><script src='https://cdn.jsdelivr.net/npm/chart.js'></script><style>:root{--ryuz-green:#01a982;--ryuz-ink:#18212a;--ryuz-teal:#0b7f77;--ryuz-cyan:#00c8ff;--ryuz-purple:#614ad3;--ryuz-bg:#f4faf8}body{background:radial-gradient(circle at 15% 0%,rgba(1,169,130,.22),transparent 28%),linear-gradient(135deg,#f7fffc,#eef6ff 58%,#fff7fb);color:var(--ryuz-ink);min-height:100vh}.card{background:rgba(255,255,255,.94);border:1px solid rgba(1,169,130,.28);border-top:5px solid var(--ryuz-green);border-radius:8px;box-shadow:0 18px 42px rgba(24,33,42,.12)}.form-control,.form-select{background:#fff;color:var(--ryuz-ink);border:1px solid rgba(24,33,42,.18)}.btn-primary{background:var(--ryuz-green);border-color:var(--ryuz-green);color:#071512;font-weight:700}.btn-outline-light{border-color:var(--ryuz-green);color:var(--ryuz-ink);background:#fff}.btn-outline-light:hover{background:var(--ryuz-green);border-color:var(--ryuz-green);color:#071512}.output{background:#10251f;color:#dffcf3;padding:10px;border-radius:6px;white-space:pre-wrap}.chart-container{height:200px}.badge-soft{background:linear-gradient(135deg,var(--ryuz-green),var(--ryuz-cyan));color:#071512}details{background:#eefaf6;border:1px solid rgba(1,169,130,.24);border-radius:6px;padding:8px 10px;margin-top:10px}summary{cursor:pointer;color:var(--ryuz-teal);font-weight:700}</style></head><body><div class='container py-4'><h1 class='text-center'>Ryuz WAN Simulator</h1><p class='text-center'>L3/NAT y L2 Bridge por pares entrada/salida</p>{% with messages=get_flashed_messages(with_categories=true) %}{% for c,m in messages %}<div class='alert alert-{{c}}'>{{m}}</div>{% endfor %}{% endwith %}<div class='d-flex justify-content-center gap-2 mb-4 flex-wrap'><form method='post' action='{{url_for("configure")}}'><input type='hidden' name='action' value='reset_all'><button class='btn btn-primary'>Restablecer todas</button></form><a class='btn btn-outline-light' href='{{url_for("tls_settings")}}'>HTTPS</a><a class='btn btn-outline-light' href='{{url_for("prebeta")}}'>Pre-beta ReactUI</a><select id='unit' class='form-select w-auto' onchange='updateCharts()'><option value='mbps'>Mbps</option><option value='kbps'>Kbps</option><option value='mb'>MB/s</option><option value='kb'>KB/s</option></select></div><div class='row'>{% for i in interfaces %}<div class='col-md-6 col-lg-4 mb-4'><div class='card p-4 h-100'><h4>{{stats[i].label}}</h4><div>{% if stats[i].bridge %}<span class='badge badge-soft'>{{stats[i].bridge}}</span>{% endif %} {% if stats[i].role %}<span class='badge badge-soft'>{{stats[i].role}}</span>{% endif %}{% if stats[i].wan %}<span class='badge badge-soft'>WAN {{stats[i].wan}}</span>{% endif %}{% if stats[i].lan %}<span class='badge badge-soft'>LAN {{stats[i].lan}}</span>{% endif %}</div><details><summary>Detalles del enlace</summary><small>Interfaz: {{i}}{% if stats[i].subnet %}<br>Subred: {{stats[i].subnet}}{% endif %}{% if stats[i].wan_private %}<br>IP WAN privada: {{stats[i].wan_private}}{% endif %}{% if stats[i].wan_public %}<br>IP WAN pública: {{stats[i].wan_public}}{% endif %}{% if stats[i].wan_bw %}<br>BW estimado: {{stats[i].wan_bw}}{% endif %}{% if stats[i].peer %}<br>Peer: {{stats[i].peer}}{% endif %}{% if stats[i].mac %}<br>MAC WAN/Peer: {{stats[i].mac}}{% endif %}{% if stats[i].lan_mac %}<br>MAC LAN: {{stats[i].lan_mac}}{% endif %}</small></details><form method='post' action='{{url_for("configure")}}' class='mt-3'><input type='hidden' name='iface' value='{{i}}'><input type='hidden' name='action' value='apply'><label>Delay/latencia ms</label><input class='form-control' type='number' name='delay' step='.1' min='0' value='{{stats[i].delay}}'><label>Jitter ms</label><input class='form-control' type='number' name='jitter' step='.1' min='0' value='{{stats[i].jitter}}'><label>Ruido/Pérdida %</label><input class='form-control' type='number' name='loss' step='.1' min='0' max='100' value='{{stats[i].loss}}'><div class='mt-3 d-flex gap-2'><button class='btn btn-primary'>Aplicar</button><button class='btn btn-warning' onclick='this.form.elements["action"].value="reset"'>Restablecer</button></div></form><div class='mt-3 d-flex flex-wrap gap-1'>{% for label,d,j,l in quicks %}<form method='post' action='{{url_for("configure")}}'><input type='hidden' name='iface' value='{{i}}'><input type='hidden' name='action' value='apply'><input type='hidden' name='delay' value='{{d}}'><input type='hidden' name='jitter' value='{{j}}'><input type='hidden' name='loss' value='{{l}}'><button class='btn btn-outline-light btn-sm'>{{label}}</button></form>{% endfor %}</div><div class='chart-container mt-3'><canvas id='c{{loop.index}}'></canvas></div><pre class='output mt-2' id='o{{loop.index}}'></pre></div></div>{% endfor %}</div><div class='text-center'>Ryuz WAN Simulator - Versión __WANSIM_VERSION__</div></div><script>const data={{chart|safe}};let charts={};function updateCharts(){let u=document.getElementById('unit').value;data.forEach((x,n)=>{let s=x.stats,vals=[s[u+'_in'],s[u+'_out'],s.delay,s.jitter,s.loss],id='c'+(n+1),ctx=document.getElementById(id);if(!ctx)return;if(charts[id]){charts[id].data.datasets[0].data=vals;charts[id].update()}else{charts[id]=new Chart(ctx.getContext('2d'),{type:'bar',data:{labels:['Entrada','Salida','Delay','Jitter','Ruido/Pérdida'],datasets:[{label:x.label,data:vals,borderWidth:1,backgroundColor:['#01a982','#00c8ff','#614ad3','#ffb000','#ff5a7a']}]},options:{responsive:true,maintainAspectRatio:false,scales:{y:{beginAtZero:true}}}})}document.getElementById('o'+(n+1)).innerText='WAN: '+(s.wan||'')+'\nLAN: '+(s.lan||'')+'\nSubred: '+(s.subnet||'')+'\nDelay: '+Number(s.delay).toFixed(1)+' ms\nJitter: '+Number(s.jitter).toFixed(1)+' ms\nRuido/Pérdida: '+Number(s.loss).toFixed(1)+' %\nEntrada: '+Number(s[u+'_in']).toFixed(2)+' '+u+'\nSalida: '+Number(s[u+'_out']).toFixed(2)+' '+u})}window.onload=updateCharts;</script></body></html>
"""

TLS_TEMPLATE=r"""
<!doctype html><html lang='es'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>HTTPS - Ryuz WAN Simulator</title><link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'><style>body{background:linear-gradient(135deg,#f7fffc,#eef6ff);color:#18212a;min-height:100vh}.panel{background:#fff;border:1px solid rgba(1,169,130,.24);border-top:5px solid #01a982;border-radius:8px;padding:24px;box-shadow:0 18px 42px rgba(24,33,42,.12)}.form-control,.form-select{background:#fff;color:#18212a;border:1px solid rgba(24,33,42,.18)}.form-select option{color:#111}.btn-primary{background:#01a982;border-color:#01a982;color:#071512;font-weight:700}.btn-outline-light{border-color:#01a982;color:#18212a;background:#fff}.btn-outline-light:hover{background:#01a982;color:#071512}</style></head><body><div class='container py-4'><div class='d-flex justify-content-between align-items-center mb-3'><h1>HTTPS</h1><a class='btn btn-outline-light' href='{{url_for("dashboard")}}'>Dashboard</a></div>{% with messages=get_flashed_messages(with_categories=true) %}{% for c,m in messages %}<div class='alert alert-{{c}}'>{{m}}</div>{% endfor %}{% endwith %}<div class='panel'><p>Estado actual: <strong>{{"habilitado" if enabled else "deshabilitado"}}</strong></p><form method='post' action='{{url_for("tls_upload")}}' enctype='multipart/form-data'><label>Formato</label><select class='form-select mb-3' name='mode'><option value='pfx'>PFX / P12 / PKCS12</option><option value='pem'>PEM certificado + llave</option><option value='bundle'>PEM bundle</option><option value='der'>DER certificado + llave DER</option></select><label>Certificado, bundle o PFX</label><input class='form-control mb-3' type='file' name='cert' required><label>Llave privada, solo para PEM/DER separados</label><input class='form-control mb-3' type='file' name='key'><label>Password, solo para PFX/P12 si aplica</label><input class='form-control mb-3' type='password' name='password'><button class='btn btn-primary'>Activar HTTPS</button></form><form method='post' action='{{url_for("tls_disable")}}' class='mt-3'><button class='btn btn-warning'>Desactivar HTTPS</button></form></div></div></body></html>
"""

PREBETA_TEMPLATE=r"""
<!doctype html><html lang='es'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Pre-beta ReactUI - Ryuz WAN Simulator</title><link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'><script src='https://unpkg.com/react@18/umd/react.development.js'></script><script src='https://unpkg.com/react-dom@18/umd/react-dom.development.js'></script><script src='https://unpkg.com/@babel/standalone/babel.min.js'></script><style>:root{--g:#01a982;--ink:#18212a;--cyan:#00c8ff;--purple:#614ad3;--mag:#ff5a7a;--bg:#f4faf8}body{background:radial-gradient(circle at 12% 0%,rgba(1,169,130,.22),transparent 28%),linear-gradient(135deg,#f7fffc,#eef6ff 58%,#fff7fb);color:var(--ink);min-height:100vh}.panel{background:rgba(255,255,255,.96);border:1px solid rgba(1,169,130,.25);border-top:5px solid var(--g);border-radius:8px;padding:18px;box-shadow:0 18px 42px rgba(24,33,42,.12)}.pill{display:inline-flex;gap:6px;align-items:center;border-radius:999px;padding:4px 10px;background:#e9faf5;color:#0b645c;font-weight:700}.btn-primary{background:var(--g);border-color:var(--g);color:#071512;font-weight:700}.btn-outline-dark{border-color:var(--g)}.diagram{background:#10251f;color:#dffcf3;border-radius:8px;padding:14px;white-space:pre-wrap;font-family:ui-monospace,Menlo,Consolas,monospace}.service-ok{color:#078765;font-weight:700}.service-bad{color:#b42318;font-weight:700}.table{--bs-table-bg:transparent}</style></head><body><div id='root'></div><script type='text/babel'>
const {useEffect,useState}=React;
const emptyDraft={topology:'nat',l3:{segment:'10.254',links:[{wan:'',lan:'',vlans:10,startVlan:100,baseOctet:10}]},bridge:{pairs:[{in:'',out:''},{in:'',out:''},{in:'',out:''}]},telegram:{bots:[{name:'principal',token:'',chatId:''}]}};
function App(){
  const [state,setState]=useState(null); const [draft,setDraft]=useState(emptyDraft); const [msg,setMsg]=useState('');
  const load=()=>fetch('/api/prebeta/state').then(r=>r.json()).then(d=>{setState(d); setDraft(Object.assign({},emptyDraft,d.draft||{}));});
  useEffect(()=>{load();},[]);
  const save=()=>fetch('/api/prebeta/save',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(draft)}).then(r=>r.json()).then(d=>setMsg(d.message||'Guardado'));
  const restart=s=>fetch('/api/prebeta/daemon/restart',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({service:s})}).then(r=>r.json()).then(d=>{setMsg(d.message||d.error); setTimeout(load,1200);});
  const validateBot=b=>fetch('/api/prebeta/telegram/validate',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)}).then(r=>r.json()).then(d=>setMsg(d.message||d.error));
  if(!state)return <div className='container py-4'>Cargando...</div>;
  const ifaces=state.interfaces||[];
  const setL3=(idx,key,val)=>{const links=[...(draft.l3?.links||[])]; links[idx]={...links[idx],[key]:val}; setDraft({...draft,l3:{...draft.l3,links}})};
  const setBridge=(idx,key,val)=>{const pairs=[...(draft.bridge?.pairs||[])]; pairs[idx]={...pairs[idx],[key]:val}; setDraft({...draft,bridge:{...draft.bridge,pairs}})};
  const addL3=()=>setDraft({...draft,l3:{...draft.l3,links:[...(draft.l3?.links||[]),{wan:'',lan:'',vlans:10,startVlan:200,baseOctet:20}].slice(0,2)}});
  const diagram=draft.topology==='bridge' ? (draft.bridge?.pairs||[]).filter(p=>p.in||p.out).map((p,i)=>`L2L #${i+1}: ${p.in||'entrada'} <== bridge ==> ${p.out||'salida'}`).join('\\n') : (draft.l3?.links||[]).map((l,i)=>`WAN ${i+1}: ${l.wan||'wan'}\\n  | NAT/DHCP VLAN ${l.startVlan||100}-${Number(l.startVlan||100)+Number(l.vlans||1)-1}\\nLAN ${i+1}: ${l.lan||'lan'} -> ${draft.l3?.segment||'10.254'}.${l.baseOctet||10}.0/24`).join('\\n\\n');
  return <div className='container-fluid py-4 px-4'><div className='d-flex justify-content-between align-items-center mb-3 flex-wrap gap-2'><div><h1>Pre-beta ReactUI</h1><span className='pill'>Version 2 draft</span> <span className='pill'>V1 estable sincronizada</span></div><a className='btn btn-outline-dark' href='/'>Volver a V1</a></div>{msg&&<div className='alert alert-info'>{msg}</div>}<div className='row g-3'><div className='col-xl-4'><div className='panel mb-3'><h4>Topologia</h4><select className='form-select mb-3' value={draft.topology} onChange={e=>setDraft({...draft,topology:e.target.value})}><option value='nat'>L3 / NAT</option><option value='bridge'>Bridge L2L</option></select>{draft.topology==='nat'&&<div><label>Segmento recomendado</label><select className='form-select mb-3' value={draft.l3?.segment||'10.254'} onChange={e=>setDraft({...draft,l3:{...draft.l3,segment:e.target.value}})}><option>10.254</option><option>172.16</option><option>192.168</option></select>{(draft.l3?.links||[]).map((l,i)=><div className='border rounded p-2 mb-2' key={i}><strong>WAN/LAN #{i+1}</strong><select className='form-select my-1' value={l.wan||''} onChange={e=>setL3(i,'wan',e.target.value)}><option value=''>WAN</option>{ifaces.map(x=><option key={x.name}>{x.name}</option>)}</select><select className='form-select my-1' value={l.lan||''} onChange={e=>setL3(i,'lan',e.target.value)}><option value=''>LAN trunk</option>{ifaces.map(x=><option key={x.name}>{x.name}</option>)}</select><div className='row g-2'><div className='col'><input className='form-control' type='number' value={l.vlans||1} onChange={e=>setL3(i,'vlans',e.target.value)} placeholder='VLANs'/></div><div className='col'><input className='form-control' type='number' value={l.startVlan||100} onChange={e=>setL3(i,'startVlan',e.target.value)} placeholder='VLAN inicial'/></div><div className='col'><input className='form-control' type='number' value={l.baseOctet||10} onChange={e=>setL3(i,'baseOctet',e.target.value)} placeholder='Octeto'/></div></div></div>)}<button className='btn btn-sm btn-outline-dark' onClick={addL3}>Agregar WAN/LAN</button></div>}{draft.topology==='bridge'&&<div>{(draft.bridge?.pairs||[]).map((p,i)=><div className='border rounded p-2 mb-2' key={i}><strong>L2L #{i+1}</strong><select className='form-select my-1' value={p.in||''} onChange={e=>setBridge(i,'in',e.target.value)}><option value=''>Entrada</option>{ifaces.map(x=><option key={x.name}>{x.name}</option>)}</select><select className='form-select my-1' value={p.out||''} onChange={e=>setBridge(i,'out',e.target.value)}><option value=''>Salida</option>{ifaces.map(x=><option key={x.name}>{x.name}</option>)}</select></div>)}</div>}<button className='btn btn-primary mt-2' onClick={save}>Guardar draft</button></div><div className='panel'><h4>Telegram multi-bot</h4>{(draft.telegram?.bots||[]).map((b,i)=><div className='border rounded p-2 mb-2' key={i}><input className='form-control my-1' value={b.name||''} onChange={e=>{const bots=[...(draft.telegram?.bots||[])]; bots[i]={...bots[i],name:e.target.value}; setDraft({...draft,telegram:{bots}})}} placeholder='Nombre'/><input className='form-control my-1' value={b.token||''} onChange={e=>{const bots=[...(draft.telegram?.bots||[])]; bots[i]={...bots[i],token:e.target.value}; setDraft({...draft,telegram:{bots}})}} placeholder='Bot token'/><input className='form-control my-1' value={b.chatId||''} onChange={e=>{const bots=[...(draft.telegram?.bots||[])]; bots[i]={...bots[i],chatId:e.target.value}; setDraft({...draft,telegram:{bots}})}} placeholder='Chat ID'/><button className='btn btn-sm btn-outline-dark' onClick={()=>validateBot(b)}>Validar sincronizacion</button></div>)}<button className='btn btn-sm btn-outline-dark' onClick={()=>setDraft({...draft,telegram:{bots:[...(draft.telegram?.bots||[]),{name:'bot',token:'',chatId:''}]}})}>Agregar bot</button></div></div><div className='col-xl-4'><div className='panel mb-3'><h4>Resumen conceptual</h4><div className='diagram'>{diagram||'Define interfaces para generar el diagrama.'}</div></div><div className='panel'><h4>Interfaces detectadas</h4><div className='table-responsive'><table className='table table-sm'><thead><tr><th>Interfaz</th><th>IP</th><th>MAC</th><th>Estado</th></tr></thead><tbody>{ifaces.map(x=><tr key={x.name}><td>{x.name}</td><td>{x.ip||'-'}</td><td>{x.mac||'-'}</td><td>{x.state}</td></tr>)}</tbody></table></div></div></div><div className='col-xl-4'><div className='panel mb-3'><h4>Daemons</h4>{(state.daemons||[]).map(s=><div className='d-flex justify-content-between align-items-center border-bottom py-2' key={s.name}><div><strong>{s.name}</strong><br/><span className={s.active==='active'?'service-ok':'service-bad'}>{s.active||'unknown'}</span> / {s.enabled||'unknown'}</div><button className='btn btn-sm btn-outline-dark' onClick={()=>restart(s.name)}>Restart</button></div>)}</div><div className='panel'><h4>DHCP leases</h4><div className='table-responsive'><table className='table table-sm'><thead><tr><th>IP</th><th>Host</th><th>MAC</th><th>Estado</th></tr></thead><tbody>{(state.leases||[]).map((l,i)=><tr key={i}><td>{l.ip}</td><td>{l.host||'-'}</td><td>{l.mac||'-'}</td><td>{l.state||'-'}</td></tr>)}</tbody></table></div></div></div></div></div>
}
ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
</script></body></html>
"""

REACTUI_STAGE_TEMPLATE=r"""
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>ReactUI pre-beta - Ryuz WAN Simulator</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
  <script src="https://unpkg.com/react@18/umd/react.development.js"></script>
  <script src="https://unpkg.com/react-dom@18/umd/react-dom.development.js"></script>
  <script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>
  <style>
    :root{--g:#01a982;--ink:#18212a;--cyan:#00c8ff;--purple:#614ad3;--pink:#ff5a7a}
    body{background:radial-gradient(circle at 12% 0%,rgba(1,169,130,.24),transparent 28%),linear-gradient(135deg,#f7fffc,#edf7ff 60%,#fff7fb);color:var(--ink);min-height:100vh}
    .panel{background:rgba(255,255,255,.96);border:1px solid rgba(1,169,130,.24);border-top:5px solid var(--g);border-radius:8px;padding:18px;box-shadow:0 18px 42px rgba(24,33,42,.12)}
    .btn-primary{background:var(--g);border-color:var(--g);color:#071512;font-weight:700}.btn-outline-dark{border-color:var(--g)}
    .pill{display:inline-flex;border-radius:999px;padding:4px 10px;background:#e9faf5;color:#0b645c;font-weight:700}
    .diagram,.plan{background:#10251f;color:#dffcf3;border-radius:8px;padding:14px;white-space:pre-wrap;font-family:ui-monospace,Menlo,Consolas,monospace}
    .ok{color:#078765;font-weight:700}.bad{color:#b42318;font-weight:700}.warn{color:#a15c00;font-weight:700}
    .table{--bs-table-bg:transparent}
  </style>
</head>
<body><div id="root"></div>
<script type="text/babel">
const {useEffect,useState}=React;
const emptyDraft={topology:'nat',l3:{segment:'10.254',links:[{wan:'',lan:'',vlans:10,startVlan:100,baseOctet:10,wanMode:'dhcp',wanIp:'',wanMask:'24',wanGateway:''}]},bridge:{pairs:[{in:'',out:''},{in:'',out:''},{in:'',out:''}]},telegram:{bots:[{name:'principal',token:'',chatId:''}]}};
function App(){
  const [state,setState]=useState(null),[draft,setDraft]=useState(emptyDraft),[result,setResult]=useState(null);
  const load=()=>fetch('/api/prebeta/state').then(r=>r.json()).then(d=>{setState(d); setDraft({...emptyDraft,...(d.draft||{})});});
  useEffect(()=>{load();},[]);
  const api=(url,body)=>fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}).then(r=>r.json()).then(setResult);
  const setL3=(i,k,v)=>{const links=[...(draft.l3?.links||[])]; links[i]={...links[i],[k]:v}; setDraft({...draft,l3:{...draft.l3,links}})};
  const setBridge=(i,k,v)=>{const pairs=[...(draft.bridge?.pairs||[])]; pairs[i]={...pairs[i],[k]:v}; setDraft({...draft,bridge:{...draft.bridge,pairs}})};
  const addL3=()=>setDraft({...draft,l3:{...draft.l3,links:[...(draft.l3?.links||[]),{wan:'',lan:'',vlans:10,startVlan:200,baseOctet:20,wanMode:'dhcp',wanIp:'',wanMask:'24',wanGateway:''}].slice(0,2)}});
  if(!state)return <div className="container py-4">Cargando...</div>;
  const ifaces=state.interfaces||[];
  const diagram=draft.topology==='bridge'
    ? (draft.bridge?.pairs||[]).filter(p=>p.in||p.out).map((p,i)=>`L2L #${i+1}: ${p.in||'entrada'} <== bridge ==> ${p.out||'salida'}`).join('\n')
    : (draft.l3?.links||[]).map((l,i)=>`WAN ${i+1}: ${l.wan||'wan'} (${l.wanMode||'dhcp'}${l.wanMode==='manual'?`, ${l.wanIp}/${l.wanMask} gw ${l.wanGateway}`:''})\n  | NAT/DHCP VLAN ${l.startVlan||100}-${Number(l.startVlan||100)+Number(l.vlans||1)-1}\nLAN ${i+1}: ${l.lan||'lan'} -> ${draft.l3?.segment||'10.254'}.${l.baseOctet||10}.0/24`).join('\n\n');
  return <div className="container-fluid py-4 px-4">
    <div className="d-flex justify-content-between align-items-center mb-3 flex-wrap gap-2"><div><h1>ReactUI pre-beta</h1><span className="pill">V1 estable: 1.116-stable</span> <span className="pill">Etapa 2 draft</span></div><a className="btn btn-outline-dark" href="/">Volver a Stable</a></div>
    {result&&<div className={'alert '+(result.ok?'alert-success':'alert-warning')}>{result.message||result.error||'Resultado recibido'}</div>}
    <div className="row g-3">
      <div className="col-xl-4"><div className="panel mb-3"><h4>Topologia editable</h4><select className="form-select mb-3" value={draft.topology} onChange={e=>setDraft({...draft,topology:e.target.value})}><option value="nat">L3 / NAT</option><option value="bridge">Bridge L2L</option></select>
        {draft.topology==='nat'&&<div><label>Segmento VLAN recomendado</label><select className="form-select mb-3" value={draft.l3?.segment||'10.254'} onChange={e=>setDraft({...draft,l3:{...draft.l3,segment:e.target.value}})}><option>10.254</option><option>172.16</option><option>192.168</option></select>{(draft.l3?.links||[]).map((l,i)=><div className="border rounded p-2 mb-2" key={i}><strong>WAN/LAN #{i+1}</strong><select className="form-select my-1" value={l.wan||''} onChange={e=>setL3(i,'wan',e.target.value)}><option value="">WAN</option>{ifaces.map(x=><option key={x.name}>{x.name}</option>)}</select><select className="form-select my-1" value={l.lan||''} onChange={e=>setL3(i,'lan',e.target.value)}><option value="">LAN trunk</option>{ifaces.map(x=><option key={x.name}>{x.name}</option>)}</select><select className="form-select my-1" value={l.wanMode||'dhcp'} onChange={e=>setL3(i,'wanMode',e.target.value)}><option value="dhcp">WAN DHCP</option><option value="manual">WAN Manual</option></select>{l.wanMode==='manual'&&<div className="row g-2 mb-2"><div className="col"><input className="form-control" value={l.wanIp||''} onChange={e=>setL3(i,'wanIp',e.target.value)} placeholder="IP WAN"/></div><div className="col"><input className="form-control" value={l.wanMask||'24'} onChange={e=>setL3(i,'wanMask',e.target.value)} placeholder="Mascara/CIDR"/></div><div className="col"><input className="form-control" value={l.wanGateway||''} onChange={e=>setL3(i,'wanGateway',e.target.value)} placeholder="Gateway"/></div></div>}<div className="row g-2"><div className="col"><input className="form-control" type="number" value={l.vlans||1} onChange={e=>setL3(i,'vlans',e.target.value)} placeholder="VLANs"/></div><div className="col"><input className="form-control" type="number" value={l.startVlan||100} onChange={e=>setL3(i,'startVlan',e.target.value)} placeholder="VLAN inicial"/></div><div className="col"><input className="form-control" type="number" value={l.baseOctet||10} onChange={e=>setL3(i,'baseOctet',e.target.value)} placeholder="Octeto"/></div></div></div>)}<button className="btn btn-sm btn-outline-dark" onClick={addL3}>Agregar WAN/LAN</button></div>}
        {draft.topology==='bridge'&&<div>{(draft.bridge?.pairs||[]).map((p,i)=><div className="border rounded p-2 mb-2" key={i}><strong>L2L #{i+1}</strong><select className="form-select my-1" value={p.in||''} onChange={e=>setBridge(i,'in',e.target.value)}><option value="">Entrada</option>{ifaces.map(x=><option key={x.name}>{x.name}</option>)}</select><select className="form-select my-1" value={p.out||''} onChange={e=>setBridge(i,'out',e.target.value)}><option value="">Salida</option>{ifaces.map(x=><option key={x.name}>{x.name}</option>)}</select></div>)}</div>}
        <div className="d-flex flex-wrap gap-2 mt-3"><button className="btn btn-primary" onClick={()=>api('/api/prebeta/save',draft)}>Guardar draft</button><button className="btn btn-outline-dark" onClick={()=>api('/api/reactui/validate',draft)}>Validar</button><button className="btn btn-outline-dark" onClick={()=>api('/api/reactui/plan',draft)}>Plan de despliegue</button></div></div>
        <div className="panel"><h4>Telegram multi-bot</h4>{(draft.telegram?.bots||[]).map((b,i)=><div className="border rounded p-2 mb-2" key={i}><input className="form-control my-1" value={b.name||''} onChange={e=>{const bots=[...(draft.telegram?.bots||[])]; bots[i]={...bots[i],name:e.target.value}; setDraft({...draft,telegram:{bots}})}} placeholder="Nombre"/><input className="form-control my-1" value={b.token||''} onChange={e=>{const bots=[...(draft.telegram?.bots||[])]; bots[i]={...bots[i],token:e.target.value}; setDraft({...draft,telegram:{bots}})}} placeholder="Bot token"/><input className="form-control my-1" value={b.chatId||''} onChange={e=>{const bots=[...(draft.telegram?.bots||[])]; bots[i]={...bots[i],chatId:e.target.value}; setDraft({...draft,telegram:{bots}})}} placeholder="Chat ID"/><button className="btn btn-sm btn-outline-dark" onClick={()=>api('/api/prebeta/telegram/validate',b)}>Validar sincronizacion</button></div>)}</div></div>
      <div className="col-xl-4"><div className="panel mb-3"><h4>Diagrama conceptual</h4><div className="diagram">{diagram||'Define interfaces para generar el diagrama.'}</div></div><div className="panel"><h4>Resultado validacion/plan</h4><pre className="plan">{result?JSON.stringify(result,null,2):'Sin validacion todavia.'}</pre></div></div>
      <div className="col-xl-4"><div className="panel mb-3"><h4>Daemons</h4>{(state.daemons||[]).map(s=><div className="d-flex justify-content-between align-items-center border-bottom py-2" key={s.name}><div><strong>{s.name}</strong><br/><span className={s.active==='active'?'ok':'bad'}>{s.active||'unknown'}</span> / {s.enabled||'unknown'}</div><button className="btn btn-sm btn-outline-dark" onClick={()=>api('/api/prebeta/daemon/restart',{service:s.name})}>Restart</button></div>)}</div><div className="panel"><h4>DHCP leases</h4><table className="table table-sm"><thead><tr><th>IP</th><th>Host</th><th>MAC</th><th>Estado</th></tr></thead><tbody>{(state.leases||[]).map((l,i)=><tr key={i}><td>{l.ip}</td><td>{l.host||'-'}</td><td>{l.mac||'-'}</td><td>{l.state||'-'}</td></tr>)}</tbody></table></div></div>
    </div></div>
}
ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
</script></body></html>
"""

def restart_service_later():
    def _restart():
        try:
            subprocess.run('sudo systemctl restart wansim.service',shell=True,timeout=20)
        except Exception as e:
            logger.error(f'No se pudo reiniciar wansim.service: {e}')
    threading.Timer(1.0,_restart).start()

def write_tls_config(enabled):
    try:
        lines=[]
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE,'r',encoding='utf-8',errors='ignore') as f:
                lines=f.read().splitlines()
        values={'ENABLE_HTTPS':'s' if enabled else 'n','TLS_MODE':'web','TLS_CERT_FILE':TLS_CERT_FILE,'TLS_KEY_FILE':TLS_KEY_FILE,'TLS_ENABLE_FILE':TLS_ENABLE_FILE}
        seen=set(); out=[]
        for line in lines:
            key=line.split('=',1)[0] if '=' in line else ''
            if key in values:
                out.append(f'{key}={values[key]}'); seen.add(key)
            else:
                out.append(line)
        for key,val in values.items():
            if key not in seen: out.append(f'{key}={val}')
        with open(CONFIG_FILE,'w',encoding='utf-8') as f:
            f.write('\n'.join(out)+'\n')
    except Exception as e:
        logger.error(f'No se pudo actualizar config TLS: {e}')

def save_upload(field, target):
    item=request.files.get(field)
    if not item or not item.filename:
        raise ValueError(f'Archivo requerido: {field}')
    item.save(target)

def validate_tls_pair():
    import ssl
    ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(TLS_CERT_FILE,TLS_KEY_FILE)

def install_tls_from_request():
    os.makedirs(TLS_DIR,exist_ok=True)
    os.chmod(TLS_DIR,0o700)
    mode=(request.form.get('mode') or '').strip()
    cert_tmp=os.path.join(TLS_DIR,'upload_cert.tmp')
    key_tmp=os.path.join(TLS_DIR,'upload_key.tmp')
    save_upload('cert',cert_tmp)
    password=request.form.get('password') or ''
    if mode=='pfx':
        c=subprocess.run(['openssl','pkcs12','-in',cert_tmp,'-clcerts','-nokeys','-out',TLS_CERT_FILE,'-passin',f'pass:{password}'],capture_output=True,text=True,timeout=30)
        k=subprocess.run(['openssl','pkcs12','-in',cert_tmp,'-nocerts','-nodes','-out',TLS_KEY_FILE,'-passin',f'pass:{password}'],capture_output=True,text=True,timeout=30)
        if c.returncode or k.returncode: raise ValueError((c.stderr or '')+(k.stderr or ''))
    elif mode=='pem':
        save_upload('key',key_tmp)
        os.replace(cert_tmp,TLS_CERT_FILE); os.replace(key_tmp,TLS_KEY_FILE)
    elif mode=='bundle':
        os.replace(cert_tmp,TLS_CERT_FILE)
        with open(TLS_CERT_FILE,'rb') as src, open(TLS_KEY_FILE,'wb') as dst: dst.write(src.read())
    elif mode=='der':
        save_upload('key',key_tmp)
        c=subprocess.run(['openssl','x509','-inform','DER','-in',cert_tmp,'-out',TLS_CERT_FILE],capture_output=True,text=True,timeout=30)
        k=subprocess.run(['openssl','rsa','-inform','DER','-in',key_tmp,'-out',TLS_KEY_FILE],capture_output=True,text=True,timeout=30)
        if c.returncode or k.returncode: raise ValueError((c.stderr or '')+(k.stderr or ''))
    else:
        raise ValueError('Formato TLS no soportado')
    os.chmod(TLS_CERT_FILE,0o600); os.chmod(TLS_KEY_FILE,0o600)
    validate_tls_pair()
    with open(TLS_ENABLE_FILE,'w',encoding='utf-8') as f: f.write('enabled\n')
    write_tls_config(True)

@app.route('/tls')
def tls_settings():
    return render_template_string(TLS_TEMPLATE, enabled=tls_is_ready())

@app.route('/tls/upload',methods=['POST'])
def tls_upload():
    try:
        install_tls_from_request()
        flash('Certificado instalado. El servicio se reiniciara en HTTPS. Vuelve a abrir el dashboard con https://','success')
        restart_service_later()
    except Exception as e:
        logger.exception('Error configurando TLS')
        flash(f'No se pudo activar HTTPS: {e}','danger')
    return redirect(url_for('tls_settings'))

@app.route('/tls/disable',methods=['POST'])
def tls_disable():
    try:
        if TLS_ENABLE_FILE and os.path.exists(TLS_ENABLE_FILE): os.remove(TLS_ENABLE_FILE)
        write_tls_config(False)
        flash('HTTPS desactivado. El servicio se reiniciara en HTTP.','success')
        restart_service_later()
    except Exception as e:
        flash(f'No se pudo desactivar HTTPS: {e}','danger')
    return redirect(url_for('tls_settings'))

def read_config_file():
    data={}
    try:
        with open(CONFIG_FILE,'r',encoding='utf-8',errors='ignore') as f:
            for line in f:
                line=line.strip()
                if not line or line.startswith('#') or '=' not in line: continue
                k,v=line.split('=',1); data[k]=v
    except Exception:
        pass
    return data

def list_interfaces():
    items=[]
    root='/sys/class/net'
    try:
        names=sorted(n for n in os.listdir(root) if n!='lo')
    except Exception:
        names=[]
    ip_map={}
    ok,out=run("ip -o -4 addr show")
    if ok:
        for line in out.splitlines():
            parts=line.split()
            if len(parts)>=4: ip_map[parts[1]]=parts[3].split('/')[0]
    for name in names:
        try:
            mac=open(os.path.join(root,name,'address'),encoding='utf-8').read().strip()
        except Exception:
            mac=''
        try:
            state=open(os.path.join(root,name,'operstate'),encoding='utf-8').read().strip()
        except Exception:
            state='unknown'
        items.append({'name':name,'mac':mac,'state':state,'ip':ip_map.get(name,'')})
    return items

def service_state(name):
    safe={'wansim.service','wansim-l2-persist.service','isc-dhcp-server','dhcpd','iptables'}
    if name not in safe:
        return {'name':name,'active':'blocked','enabled':'blocked'}
    ok_a,out_a=run(f'systemctl is-active {name} 2>/dev/null || true')
    ok_e,out_e=run(f'systemctl is-enabled {name} 2>/dev/null || true')
    return {'name':name,'active':out_a.strip() or 'unknown','enabled':out_e.strip() or 'unknown'}

def daemon_list():
    names=['wansim.service']
    if DHCP_SERVICE: names.append(DHCP_SERVICE)
    names.extend(['wansim-l2-persist.service','iptables'])
    dedup=[]
    for n in names:
        if n and n not in dedup: dedup.append(n)
    return [service_state(n) for n in dedup]

def read_dhcp_leases():
    paths=['/var/lib/dhcp/dhcpd.leases','/var/lib/dhcpd/dhcpd.leases','/var/lib/dhcp/dhcpd.leases~']
    text=''
    for p in paths:
        try:
            with open(p,'r',encoding='utf-8',errors='ignore') as f:
                text=f.read()
                break
        except Exception:
            continue
    leases=[]
    for m in re.finditer(r'lease\s+([0-9.]+)\s+\{(.*?)\}',text,re.S):
        body=m.group(2); ip=m.group(1)
        mac=re.search(r'hardware\s+ethernet\s+([^;]+);',body)
        host=re.search(r'client-hostname\s+"([^"]+)"',body)
        state=re.search(r'binding\s+state\s+([^;]+);',body)
        leases.append({'ip':ip,'mac':mac.group(1) if mac else '', 'host':host.group(1) if host else '', 'state':state.group(1) if state else ''})
    return leases[-80:]

def default_prebeta_draft():
    cfg=read_config_file()
    draft={'topology':'bridge' if cfg.get('TOPOLOGY_MODE')=='bridge' else 'nat','l3':{'segment':cfg.get('SEGMENT_PREFIX','10.254'),'links':[]},'bridge':{'pairs':[]},'telegram':{'bots':[{'name':'principal','token':TELEGRAM_TOKEN,'chatId':TELEGRAM_CHAT_ID}]}}
    for link in (cfg.get('L3_LINKS_CSV') or '').split(';'):
        parts=link.split(':')
        if len(parts)>=6:
            _,wan,lan,start,octet,segment=parts[:6]
            mode=parts[6] if len(parts)>6 and parts[6] else 'dhcp'
            cidr=parts[7] if len(parts)>7 else ''
            gateway=parts[8] if len(parts)>8 else ''
            wan_ip,wan_mask='','24'
            if cidr and '/' in cidr:
                wan_ip,wan_mask=cidr.split('/',1)
            draft['l3']['segment']=segment
            draft['l3']['links'].append({'wan':wan,'lan':lan,'vlans':cfg.get('NUM_VLANS','10'),'startVlan':start,'baseOctet':octet,'wanMode':mode,'wanIp':wan_ip,'wanMask':wan_mask,'wanGateway':gateway})
    if not draft['l3']['links']:
        draft['l3']['links']=[{'wan':cfg.get('WAN_IF',''),'lan':cfg.get('LAN_IF',''),'vlans':cfg.get('NUM_VLANS','10'),'startVlan':cfg.get('START_VLAN','100'),'baseOctet':cfg.get('BASE_OCTET','10'),'wanMode':'dhcp','wanIp':'','wanMask':'24','wanGateway':''}]
    for pair in (cfg.get('BRIDGE_PAIRS_CSV') or '').split(';'):
        parts=pair.split(':')
        if len(parts)>=3: draft['bridge']['pairs'].append({'in':parts[1],'out':parts[2]})
    while len(draft['bridge']['pairs'])<3:
        draft['bridge']['pairs'].append({'in':'','out':''})
    return draft

def load_prebeta_draft():
    try:
        with open(PREBETA_STATE_FILE,'r',encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return default_prebeta_draft()

@app.route('/prebeta')
def prebeta():
    return render_template_string(REACTUI_STAGE_TEMPLATE)

@app.route('/api/prebeta/state')
def prebeta_state():
    return jsonify({'version':'pre-beta-reactui','topology':TOPOLOGY_MODE,'interfaces':list_interfaces(),'controlInterfaces':CONTROL_INTERFACES,'meta':INTERFACE_META,'draft':load_prebeta_draft(),'daemons':daemon_list(),'leases':read_dhcp_leases()})

@app.route('/api/prebeta/save',methods=['POST'])
def prebeta_save():
    try:
        data=request.get_json(force=True,silent=False)
        os.makedirs(os.path.dirname(PREBETA_STATE_FILE),exist_ok=True)
        with open(PREBETA_STATE_FILE,'w',encoding='utf-8') as f:
            json.dump(data,f,ensure_ascii=False,indent=2)
        return jsonify({'ok':True,'message':'Draft pre-beta guardado y disponible para la siguiente evolucion.'})
    except Exception as e:
        logger.exception('No se pudo guardar prebeta')
        return jsonify({'ok':False,'error':str(e)}),400

def validate_reactui_draft(draft):
    import ipaddress
    errors=[]; warnings=[]; actions=[]
    interfaces={x['name'] for x in list_interfaces()}
    used_ifaces=set()
    if draft.get('topology')=='nat':
        l3=draft.get('l3') or {}
        segment=l3.get('segment') or '10.254'
        vlan_ranges=[]; octet_ranges=[]
        links=l3.get('links') or []
        if not 1 <= len(links) <= 2:
            errors.append('L3/NAT permite de 1 a 2 pares WAN/LAN.')
        for idx,link in enumerate(links,1):
            wan=link.get('wan') or ''
            lan=link.get('lan') or ''
            if wan not in interfaces: errors.append(f'Par #{idx}: WAN no existe o esta vacia.')
            if lan not in interfaces: errors.append(f'Par #{idx}: LAN no existe o esta vacia.')
            if wan and lan and wan==lan: errors.append(f'Par #{idx}: WAN y LAN no pueden ser la misma interfaz.')
            for iface in (wan,lan):
                if iface and iface in used_ifaces: errors.append(f'Par #{idx}: interfaz repetida: {iface}.')
                if iface: used_ifaces.add(iface)
            try:
                vlans=int(link.get('vlans') or 0); start=int(link.get('startVlan') or 0); base=int(link.get('baseOctet') or 0)
                if vlans < 1: errors.append(f'Par #{idx}: VLANs debe ser mayor a 0.')
                if start < 1 or start+vlans-1 > 4094: errors.append(f'Par #{idx}: rango VLAN fuera de 1-4094.')
                if base < 1 or base+vlans-1 > 254: errors.append(f'Par #{idx}: rango de octetos fuera de 1-254.')
                vr=(start,start+vlans-1); orng=(base,base+vlans-1)
                if any(vr[0] <= r[1] and vr[1] >= r[0] for r in vlan_ranges): errors.append(f'Par #{idx}: rango VLAN se solapa con otro par.')
                if any(orng[0] <= r[1] and orng[1] >= r[0] for r in octet_ranges): errors.append(f'Par #{idx}: rango de octetos se solapa con otro par.')
                vlan_ranges.append(vr); octet_ranges.append(orng)
                if (link.get('wanMode') or 'dhcp') == 'manual':
                    ip=link.get('wanIp') or ''; mask=str(link.get('wanMask') or ''); gw=link.get('wanGateway') or ''
                    iface=ipaddress.ip_interface(f'{ip}/{mask.lstrip("/")}')
                    ipaddress.ip_address(gw)
                    wan_net=iface.network
                    for octet in range(base,base+vlans):
                        lan_net=ipaddress.ip_network(f'{segment}.{octet}.0/24')
                        if wan_net.overlaps(lan_net): errors.append(f'Par #{idx}: WAN {wan_net} se solapa con LAN {lan_net}.')
                    actions.append(f'Configurar {wan} manual {iface.with_prefixlen} gateway {gw}.')
                else:
                    actions.append(f'Configurar {wan} por DHCP o conservar lease vigente.')
                actions.append(f'Crear {vlans} VLAN(s) desde ID {start} en {lan}, segmento {segment}.{base}.0/24 en adelante.')
                actions.append(f'Aplicar NAT hacia {wan} para las subredes del par #{idx}.')
            except Exception as e:
                errors.append(f'Par #{idx}: parametros IP/VLAN invalidos: {e}')
    else:
        pairs=(draft.get('bridge') or {}).get('pairs') or []
        active=[p for p in pairs if p.get('in') or p.get('out')]
        if not 1 <= len(active) <= 3: errors.append('Bridge L2L requiere de 1 a 3 pares activos.')
        for idx,pair in enumerate(active,1):
            inn=pair.get('in') or ''; out=pair.get('out') or ''
            if inn not in interfaces: errors.append(f'L2L #{idx}: entrada no existe o esta vacia.')
            if out not in interfaces: errors.append(f'L2L #{idx}: salida no existe o esta vacia.')
            if inn and out and inn==out: errors.append(f'L2L #{idx}: entrada y salida no pueden ser iguales.')
            for iface in (inn,out):
                if iface and iface in used_ifaces: errors.append(f'L2L #{idx}: interfaz repetida: {iface}.')
                if iface: used_ifaces.add(iface)
            actions.append(f'Crear bridge L2L #{idx}: {inn} <-> {out}.')
    if (draft.get('telegram') or {}).get('bots'):
        actions.append('Actualizar definicion multi-bot Telegram y validar getMe/getChat antes de activar.')
    if errors:
        warnings.append('No se debe aplicar hasta resolver los errores.')
    else:
        actions.insert(0,'Tomar snapshot de configuracion estable y preparar rollback.')
        actions.append('Reiniciar servicios y validar dashboard, DHCP, NAT/bridge y Telegram.')
    return {'ok':not errors,'errors':errors,'warnings':warnings,'actions':actions}

@app.route('/api/reactui/validate',methods=['POST'])
def reactui_validate():
    draft=request.get_json(force=True,silent=True) or {}
    result=validate_reactui_draft(draft)
    result['message']='Validacion exitosa.' if result['ok'] else 'Validacion con errores.'
    return jsonify(result), (200 if result['ok'] else 400)

@app.route('/api/reactui/plan',methods=['POST'])
def reactui_plan():
    draft=request.get_json(force=True,silent=True) or {}
    result=validate_reactui_draft(draft)
    result['message']='Plan de despliegue generado.' if result['ok'] else 'Plan bloqueado por validacion.'
    result['note']='Pre-beta: este endpoint enumera y valida cambios. La aplicacion destructiva queda bloqueada hasta estabilizar ReactUI.'
    return jsonify(result), (200 if result['ok'] else 400)

@app.route('/api/prebeta/daemon/restart',methods=['POST'])
def prebeta_daemon_restart():
    data=request.get_json(force=True,silent=True) or {}
    service=data.get('service','')
    allowed={'wansim.service','wansim-l2-persist.service','isc-dhcp-server','dhcpd','iptables'}
    if service not in allowed:
        return jsonify({'ok':False,'error':'Servicio no permitido'}),400
    ok,out=run(f'sudo systemctl restart {service}')
    return jsonify({'ok':ok,'message':f'Restart enviado a {service}' if ok else out})

@app.route('/api/prebeta/telegram/validate',methods=['POST'])
def prebeta_telegram_validate():
    data=request.get_json(force=True,silent=True) or {}
    token=(data.get('token') or TELEGRAM_TOKEN or '').strip()
    chat_id=(data.get('chatId') or TELEGRAM_CHAT_ID or '').strip()
    if not token:
        return jsonify({'ok':False,'error':'Token requerido'}),400
    try:
        r=requests.get(f'https://api.telegram.org/bot{token}/getMe',timeout=12)
        if not r.ok: return jsonify({'ok':False,'error':r.text}),400
        bot=r.json().get('result',{}).get('username','bot')
        if chat_id:
            c=requests.get(f'https://api.telegram.org/bot{token}/getChat',params={'chat_id':chat_id},timeout=12)
            if not c.ok: return jsonify({'ok':False,'error':c.text}),400
        return jsonify({'ok':True,'message':f'Telegram sincronizado con @{bot}.'})
    except Exception as e:
        return jsonify({'ok':False,'error':str(e)}),400

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

if __name__=='__main__':
    ssl_context=(TLS_CERT_FILE,TLS_KEY_FILE) if HTTPS_ENABLED and TLS_CERT_FILE and TLS_KEY_FILE else None
    app.run(host='0.0.0.0',port=app.config['PORT'],ssl_context=ssl_context)
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
if ! "$PYTHON_BIN" -m py_compile "$WANSIM_DASHBOARD"; then
    log_message "ERROR" "Error de sintaxis en $WANSIM_DASHBOARD."
    echo "${COLOR_ERROR}Error de sintaxis en $WANSIM_DASHBOARD. Revisa con '$PYTHON_BIN -m py_compile $WANSIM_DASHBOARD'.${COLOR_RESET}"
    exit 1
fi
log_message "OK" "Sintaxis de $WANSIM_DASHBOARD verificada."

# Reemplazar placeholders en el archivo Python de forma segura
log_message "DEBUG" "Reemplazando placeholders en $WANSIM_DASHBOARD con reemplazo seguro..."
HTTPS_ENABLED=0
if [ "${ENABLE_HTTPS:-n}" = "s" ] && [ -n "${TLS_CERT_FILE:-}" ] && [ -n "${TLS_KEY_FILE:-}" ]; then
    HTTPS_ENABLED=1
fi
export TELEGRAM_TOKEN TELEGRAM_CHAT_ID TELEGRAM_ENABLED PYTHON_VLAN_LIST PYTHON_INTERFACE_META DASHBOARD_PORT WANSIM_VERSION NETEM_STATE_FILE HTTPS_ENABLED TLS_CERT_FILE TLS_KEY_FILE TLS_DIR TLS_ENABLE_FILE CONFIG_FILE PREBETA_STATE_FILE DHCP_SERVICE TOPOLOGY_MODE
if ! "$PYTHON_BIN" - "$WANSIM_DASHBOARD" <<'PYREPLACE'
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
    "__HTTPS_ENABLED__": os.environ.get("HTTPS_ENABLED", "0"),
    "__TLS_CERT_FILE_LITERAL__": json.dumps(os.environ.get("TLS_CERT_FILE", "")),
    "__TLS_KEY_FILE_LITERAL__": json.dumps(os.environ.get("TLS_KEY_FILE", "")),
    "__TLS_DIR_LITERAL__": json.dumps(os.environ.get("TLS_DIR", "")),
    "__TLS_ENABLE_FILE_LITERAL__": json.dumps(os.environ.get("TLS_ENABLE_FILE", "")),
    "__CONFIG_FILE_LITERAL__": json.dumps(os.environ.get("CONFIG_FILE", "")),
    "__PREBETA_STATE_FILE_LITERAL__": json.dumps(os.environ.get("PREBETA_STATE_FILE", "")),
    "__DHCP_SERVICE_LITERAL__": json.dumps(os.environ.get("DHCP_SERVICE", "")),
    "__TOPOLOGY_MODE_LITERAL__": json.dumps(os.environ.get("TOPOLOGY_MODE", "")),
    "__NETEM_STATE_FILE__": os.environ.get("NETEM_STATE_FILE", os.path.expanduser("~/wansim_netem_state.json")),
    "__WANSIM_VERSION__": os.environ.get("WANSIM_VERSION", "1.116-stable"),
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
if ! "$PYTHON_BIN" -m py_compile "$WANSIM_DASHBOARD"; then
    log_message "ERROR" "Error de sintaxis final en $WANSIM_DASHBOARD después de reemplazar variables."
    echo "${COLOR_ERROR}Error de sintaxis final en $WANSIM_DASHBOARD. Revisa con '$PYTHON_BIN -m py_compile $WANSIM_DASHBOARD' y 'nl -ba $WANSIM_DASHBOARD | sed -n \"1,40p\"'.${COLOR_RESET}"
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

# Liberar el puerto del dashboard
log_message "INFO" "Liberando puerto $DASHBOARD_PORT..."
for port in "$DASHBOARD_PORT"; do
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
ExecStart=$PYTHON_BIN $WANSIM_DASHBOARD
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
if ss -tuln | grep -q ":$DASHBOARD_PORT"; then
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
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}$HOSTNAME - pares L3/NAT configurados${COLOR_CYAN}             │${COLOR_RESET}"
    if [ -n "${L3_LINKS_CSV:-}" ]; then
        IFS=';' read -r -a SUMMARY_L3_LINKS <<< "$L3_LINKS_CSV"
    else
        SUMMARY_L3_LINKS=("1:${WAN_IF}:${LAN_IF}:${START_VLAN:-100}:${BASE_OCTET:-10}:${SEGMENT_PREFIX:-192.168}")
    fi
    for summary_link in "${SUMMARY_L3_LINKS[@]}"; do
        IFS=':' read -r summary_idx summary_wan summary_lan summary_start_vlan summary_base_octet summary_segment <<< "$summary_link"
        echo "${COLOR_CYAN}│ ${COLOR_GREEN}Par #$summary_idx:${COLOR_RESET} LAN $summary_lan -> WAN $summary_wan${COLOR_CYAN}                  │${COLOR_RESET}"
        for (( i=0; i<${NUM_VLANS:-0} && i<3; i++ )); do
            current_vlan_id=$(( summary_start_vlan + i ))
            subnet_octet=$(( summary_base_octet + i ))
            printf "${COLOR_CYAN}│   ${COLOR_CYAN}VLAN %-4s${COLOR_RESET} %-18s ${COLOR_CYAN}│${COLOR_RESET}\n" "$current_vlan_id" "${summary_segment}.${subnet_octet}.0/24"
        done
        if [ ${NUM_VLANS:-0} -gt 3 ]; then
            echo "${COLOR_CYAN}│   ${COLOR_CYAN}... total ${NUM_VLANS:-0} VLANs para este par${COLOR_CYAN}                  │${COLOR_RESET}"
        fi
    done
fi
echo "${COLOR_CYAN}│                                                        │${COLOR_RESET}"
echo "${COLOR_CYAN}│ ${COLOR_CYAN}Topología:${COLOR_RESET} $TOPOLOGY_MODE${COLOR_CYAN}                              │${COLOR_RESET}"
if [ "$TOPOLOGY_MODE" = "bridge" ]; then
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}Interfaz LAN:${COLOR_RESET} $LAN_IF${COLOR_CYAN}                            │${COLOR_RESET}"
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}Interfaz Destino:${COLOR_RESET} $DEST_IF${COLOR_CYAN}                      │${COLOR_RESET}"
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}Control de Tráfico:${COLOR_RESET} $( [ "$CONFIG_TC" = "s" ] && echo "Habilitado" || echo "Deshabilitado")${COLOR_CYAN}               │${COLOR_RESET}"
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}Gestión con Salida a Internet:${COLOR_RESET} $( [ "$IS_MGMT" = "s" ] && echo "Sí" || echo "No")${COLOR_CYAN}          │${COLOR_RESET}"
else
    echo "${COLOR_CYAN}│ ${COLOR_CYAN}Pares L3:${COLOR_RESET} ${NUM_L3_LINKS:-1} / VLANs por par: ${NUM_VLANS:-0}${COLOR_CYAN}             │${COLOR_RESET}"
    if [ "$CONFIG_DHCP" = "s" ]; then
        echo "${COLOR_CYAN}│ ${COLOR_CYAN}DHCP:${COLOR_RESET} Sí (segmento base: ${SEGMENT_PREFIX:-192.168}.X.0/24)${COLOR_CYAN} │${COLOR_RESET}"
    else
        echo "${COLOR_CYAN}│ ${COLOR_CYAN}DHCP:${COLOR_RESET} No${COLOR_CYAN}                                       │${COLOR_RESET}"
    fi
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
URL_SCHEME="http"
if [ "${ENABLE_HTTPS:-n}" = "s" ]; then
    URL_SCHEME="https"
fi
HTTP_URL="$URL_SCHEME://$HOST_IP:$DASHBOARD_PORT"
echo "${COLOR_INFO}Dashboard disponible en: $HTTP_URL${COLOR_RESET}"
if command -v qrencode >/dev/null 2>&1; then
    qrencode -t ANSIUTF8 "$HTTP_URL"
else
    log_message "ADVERTENCIA" "qrencode no está instalado. No se puede generar el código QR."
    echo "${COLOR_WARN}No se pudo generar el código QR. Instala qrencode para habilitar esta función.${COLOR_RESET}"
fi

# Mensaje final
echo "${COLOR_OK}Script completado. Revisa $LOGFILE para más detalles.${COLOR_RESET}"
