#!/usr/bin/env bash
# Network primitives used by the compatible V1 entrypoint.

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
print(ipaddress.ip_interface(f"{ip_addr}/{mask}").with_prefixlen)
PYCIDR
}

valid_ipv4() {
    python3 - "$1" <<'PYIP' >/dev/null 2>&1
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
    if wan.overlaps(ipaddress.ip_network(f"{prefix}.{octet}.0/24")):
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
        wansim_log "INFO" "Configurando WAN $iface en modo manual: $cidr gateway=$gateway metric=$metric"
        sudo ip addr flush dev "$iface" >/tmp/wansim_wan_ip.log 2>&1 || true
        sudo ip addr add "$cidr" dev "$iface" >/tmp/wansim_wan_ip.log 2>&1 || {
            wansim_log "ERROR" "No se pudo asignar $cidr a $iface: $(cat /tmp/wansim_wan_ip.log)"
            return 1
        }
        sudo ip route replace default via "$gateway" dev "$iface" metric "$metric" >/tmp/wansim_wan_route.log 2>&1 || {
            wansim_log "ERROR" "No se pudo agregar gateway $gateway para $iface: $(cat /tmp/wansim_wan_route.log)"
            return 1
        }
    elif command -v dhclient >/dev/null 2>&1; then
        sudo dhclient -r "$iface" >/dev/null 2>&1 || true
        sudo dhclient "$iface" >/tmp/wansim_wan_dhcp.log 2>&1 || wansim_log "ADVERTENCIA" "No se pudo renovar DHCP en $iface; se conserva el lease actual."
    elif [ -z "$(iface_private_ip "$iface")" ]; then
        wansim_log "ADVERTENCIA" "dhclient no esta disponible y $iface no tiene IPv4. Usa modo manual o instala un cliente DHCP."
    fi
}
