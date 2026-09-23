#!/usr/bin/env bash

validate_network_tooling() {
  local required=(ip tc iptables iptables-save iptables-restore sysctl)
  local item
  for item in "${required[@]}"; do
    command_exists "$item" || die "Dependencia de red ausente: $item"
  done
  if [[ "$WANSIM_OS_FAMILY" == "debian" ]]; then
    command_exists dhcpd || die "isc-dhcp-server no proporcionó dhcpd."
  else
    command_exists dhcpd || die "dhcp-server no proporcionó dhcpd."
  fi
  log_ok "Herramientas L2/L3, netem, firewall y DHCP validadas."
}

configure_selected_firewall_ports() {
  [[ "$WANSIM_CONFIGURE_FIREWALL" == "1" ]] || return 0
  local ports=("$WANSIM_HTTP_PORT/tcp")
  [[ "$WANSIM_HTTPS_MODE" == "off" ]] || ports+=("$WANSIM_HTTPS_PORT/tcp")
  if command_exists firewall-cmd && systemctl is-active --quiet firewalld; then
    local port
    for port in "${ports[@]}"; do firewall-cmd --permanent --add-port="$port"; done
    firewall-cmd --reload
  elif command_exists ufw && ufw status | grep -q '^Status: active'; then
    local port
    for port in "${ports[@]}"; do ufw allow "$port"; done
  else
    log_warn "No hay un firewall administrado activo; no se modificaron reglas de entrada."
    return 0
  fi
  log_ok "Firewall actualizado únicamente para: ${ports[*]}."
}
