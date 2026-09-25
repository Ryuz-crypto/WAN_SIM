#!/usr/bin/env bash

detect_platform() {
  [[ -r /etc/os-release ]] || die "No existe /etc/os-release; plataforma no soportada."
  # shellcheck disable=SC1091
  source /etc/os-release
  WANSIM_DISTRO_ID="${ID,,}"
  WANSIM_DISTRO_VERSION="${VERSION_ID:-unknown}"
  WANSIM_ARCH="$(uname -m)"
  WANSIM_KERNEL="$(uname -r)"
  case "$WANSIM_DISTRO_ID" in
    ubuntu|debian) WANSIM_OS_FAMILY=debian; WANSIM_PACKAGE_MANAGER=apt-get ;;
    fedora|rocky) WANSIM_OS_FAMILY=rhel; WANSIM_PACKAGE_MANAGER=dnf ;;
    *) die "Distribución no soportada: $WANSIM_DISTRO_ID $WANSIM_DISTRO_VERSION" ;;
  esac
  export WANSIM_DISTRO_ID WANSIM_DISTRO_VERSION WANSIM_ARCH WANSIM_KERNEL WANSIM_OS_FAMILY WANSIM_PACKAGE_MANAGER
  log_ok "Plataforma: $WANSIM_DISTRO_ID $WANSIM_DISTRO_VERSION, $WANSIM_ARCH, kernel $WANSIM_KERNEL."
}

validate_platform() {
  [[ "$WANSIM_ARCH" == "x86_64" || "$WANSIM_ARCH" == "aarch64" ]] || die "Arquitectura no soportada: $WANSIM_ARCH"
  [[ -d /run/systemd/system ]] || die "WAN_SIM 2 requiere systemd como PID 1."
  command_exists systemctl || die "systemctl no está disponible."
  local available_kb
  available_kb="$(df -Pk /opt 2>/dev/null | awk 'NR==2 {print $4}')"
  [[ "$available_kb" =~ ^[0-9]+$ ]] || die "No se pudo calcular el espacio disponible."
  (( available_kb >= 3145728 )) || die "Se requieren al menos 3 GiB libres en el sistema de archivos de /opt."
  WANSIM_VIRTUALIZATION="$(systemd-detect-virt 2>/dev/null || true)"
  [[ -n "$WANSIM_VIRTUALIZATION" ]] || WANSIM_VIRTUALIZATION=physical
  export WANSIM_VIRTUALIZATION
  log_ok "Validación local correcta; entorno: $WANSIM_VIRTUALIZATION."
}

validate_python_runtime() {
  command_exists python3 || die "Python 3 no quedó disponible después de instalar las dependencias base."
  local version
  version="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  python3 -c 'import sys; raise SystemExit(0 if (3, 9) <= sys.version_info[:2] <= (3, 14) else 1)' || \
    die "Python $version no está soportado por WAN_SIM 2; se requiere Python 3.9 a 3.14."
  export WANSIM_PYTHON_VERSION="$version"
  log_ok "Runtime Python $version compatible."
}

validate_connectivity() {
  [[ "$WANSIM_SKIP_CONNECTIVITY" == "1" ]] && { log_warn "Pruebas de conectividad omitidas."; return; }
  command_exists curl || return 0
  local endpoint
  for endpoint in https://github.com https://registry-1.docker.io/v2/; do
    curl --silent --show-error --location --head --connect-timeout 8 --max-time 20 "$endpoint" >/dev/null || \
      die "No hay conectividad hacia $endpoint. Usa --skip-connectivity-check sólo en repositorios internos preparados."
  done
  log_ok "Conectividad con GitHub y Docker Hub validada."
}
