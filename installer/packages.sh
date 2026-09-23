#!/usr/bin/env bash

install_base_packages() {
  log_info "Instalando dependencias del sistema sin interacción..."
  if [[ "$WANSIM_OS_FAMILY" == "debian" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends \
      ca-certificates curl git jq openssl python3 python3-pip python3-venv \
      iproute2 iptables nftables isc-dhcp-client isc-dhcp-server util-linux
  else
    dnf -y install \
      ca-certificates curl git jq openssl python3 python3-pip \
      iproute iproute-tc iptables nftables dhcp-client dhcp-server util-linux dnf-plugins-core
  fi
  log_ok "Dependencias base y de red instaladas."
}
