#!/bin/bash

# ==============================================================================
# WireGuard CLI Manager - Server and Symmetric Peer
# ==============================================================================

# Console output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

msg_success() { echo -e "${GREEN}$*${NC}"; }
msg_error()   { echo -e "${RED}$*${NC}" >&2; }
msg_warning() { echo -e "${YELLOW}$*${NC}"; }
msg_info()    { echo -e "${BLUE}$*${NC}"; }

die() {
    msg_error "$@"
    exit 1
}

# Require root
[ "$EUID" -ne 0 ] && die "Root privileges required. Run with sudo."

# Install WireGuard if missing (distro-aware)
install_wireguard() {
    if ! command -v wg &> /dev/null; then
        msg_warning "WireGuard not found. Installing..."
        if [ -f /etc/debian_version ]; then
            apt-get update && apt-get install -y wireguard qrencode iptables
        elif [ -f /etc/arch-release ]; then
            pacman -Sy --noconfirm wireguard-tools qrencode iptables
        elif [ -f /etc/redhat-release ]; then
            dnf install -y epel-release && dnf install -y wireguard-tools qrencode iptables
        else
            die "Unsupported distribution. Install wireguard manually."
        fi
    fi
}

# MODE 1: Initialize server
init_server() {
    local port=${1:-51820}
    local server_ip_range="10.0.0.1/24"

    install_wireguard

    local public_iface=$(ip route | grep default | awk '{print $5}' | head -n 1)
    [ -z "$public_iface" ] && die "Could not detect public network interface."

    # Enable IP forwarding
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard-forward.conf
    sysctl --system &> /dev/null

    # Generate server keys
    mkdir -p /etc/wireguard
    cd /etc/wireguard || exit
    umask 077
    wg genkey | tee server_private.key | wg pubkey > server_public.key

    local priv_key=$(cat server_private.key)

    # Write wg0.conf with NAT rules
    cat <<EOF > /etc/wireguard/wg0.conf
[Interface]
Address = $server_ip_range
ListenPort = $port
PrivateKey = $priv_key
SaveConfig = false

# Routing rules on interface up/down
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $public_iface -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $public_iface -j MASQUERADE
EOF

    # Start and enable service
    wg-quick up wg0
    systemctl enable wg-quick@wg0 &> /dev/null

    msg_success "Server ready on port $port ($public_iface)."
    msg_info "Public key: $(cat server_public.key)"
}

# MODE 2: Add peer credentials on server
add_peer() {
    local client_name=$1
    local client_ip=$2
    local server_endpoint=$3 # Format: PUBLIC_IP:PORT

    [ ! -f /etc/wireguard/wg0.conf ] && die "Server not configured. Run --init-server first."

    # check if peer already exists
    grep -q "# Name = $client_name$" /etc/wireguard/wg0.conf && die "Peer '$client_name' already exists."
    # check if IP is already assigned
    grep -q "AllowedIPs = $client_ip/32" /etc/wireguard/wg0.conf && die "IP $client_ip is already assigned."

    local real_user=${SUDO_USER:-$USER}
    local user_desktop=$(su - $real_user -c 'xdg-user-dir DESKTOP')
    local output_file="${user_desktop}/${client_name}.conf"

    cd /etc/wireguard || exit
    umask 077

    local client_priv_key=$(wg genkey)
    local client_pub_key=$(echo "$client_priv_key" | wg pubkey)
    local server_pub_key=$(cat server_public.key)

    cat <<EOF >> /etc/wireguard/wg0.conf

[Peer]
# Name = $client_name
PublicKey = $client_pub_key
AllowedIPs = $client_ip/32
EOF

    wg syncconf wg0 <(wg-quick strip wg0)

    cat <<EOF > "$output_file"
[Interface]
PrivateKey = $client_priv_key
Address = $client_ip/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $server_pub_key
Endpoint = $server_endpoint
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    chown "$real_user:$real_user" "$output_file"

    msg_success "Peer '$client_name' added ($client_ip). Config: $output_file"
    command -v qrencode &> /dev/null && qrencode -t ansiutf8 < "$output_file"
}

# MODE 3: Bring up local peer from external .conf
init_peer() {
    local config_file=$1

    [ ! -f "$config_file" ] && die "Config file not found: $config_file"

    install_wireguard

    mkdir -p /etc/wireguard
    cp "$config_file" /etc/wireguard/wg0.conf
    chmod 600 /etc/wireguard/wg0.conf

    wg-quick up wg0
    systemctl enable wg-quick@wg0 &> /dev/null

    msg_success "Connected (wg0)."
}

# MODE 4: Remove peer from server
remove_peer() {
    local client_name=$1
    local conf_file="/etc/wireguard/wg0.conf"

    [ ! -f "$conf_file" ] && die "Server not configured."
    grep -q "# Name = $client_name" "$conf_file" || die "Peer '$client_name' not found."

    local pub_key=$(grep -A 1 "# Name = $client_name" "$conf_file" | grep "PublicKey" | awk '{print $3}')
    [ -n "$pub_key" ] && wg set wg0 peer "$pub_key" remove 2>/dev/null

    local temp_conf=$(mktemp)
    sed '/^\[Peer\]/,$d' "$conf_file" > "$temp_conf"

    local current_peer_block=""
    local skip_current=false

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^\[Peer\] ]]; then
            if [ -n "$current_peer_block" ] && [ "$skip_current" = false ]; then
                echo -e "\n[Peer]\n$current_peer_block" >> "$temp_conf"
            fi
            current_peer_block=""
            skip_current=false
            continue
        fi

        [[ "$line" =~ "# Name = $client_name" ]] && skip_current=true

        if [ -n "$line" ] && [[ ! "$line" =~ ^[[:space:]]*$ ]]; then
            if [ -z "$current_peer_block" ]; then
                current_peer_block="$line"
            else
                current_peer_block="$current_peer_block"$'\n'"$line"
            fi
        fi
    done < <(sed -n '/^\[Peer\]/,$p' "$conf_file")

    [ -n "$current_peer_block" ] && [ "$skip_current" = false ] && echo -e "\n[Peer]\n$current_peer_block" >> "$temp_conf"

    mv "$temp_conf" "$conf_file"
    chmod 600 "$conf_file"

    wg syncconf wg0 <(wg-quick strip wg0)

    local real_user=${SUDO_USER:-$USER}
    local user_desktop=$(su - $real_user -c 'xdg-user-dir DESKTOP')
    local client_file="${user_desktop}/${client_name}.conf"
    [ -f "$client_file" ] && rm -f "$client_file"

    msg_success "Peer '$client_name' removed."
}

# MODE 5: Server status and registered peers
show_status() {
    [ ! -f /etc/wireguard/wg0.conf ] && die "Server not configured or wg0 is down."

    local port=$(grep "ListenPort" /etc/wireguard/wg0.conf | awk '{print $3}')
    local addr=$(grep "Address" /etc/wireguard/wg0.conf | awk '{print $3}')

    msg_info "wg0 — VPN $addr, port $port"
    echo ""
    printf "%-15s %-15s %-20s %-15s\n" "Name" "IP" "Handshake" "Rx/Tx"
    printf '%.0s-' {1..65}; echo

    while read -r pub_key endpoint allowed_ips latest_handshake transfer_rx transfer_tx; do
        [ -z "$pub_key" ] && continue

        local client_name=$(grep -B 2 "$pub_key" /etc/wireguard/wg0.conf | grep "# Name" | awk -F'= ' '{print $2}')
        [ -z "$client_name" ] && client_name="Unknown"

        local clean_ip=$(echo "$allowed_ips" | sed 's/\/32//')

        local handshake_readable="$latest_handshake"
        if [ "$latest_handshake" = "0" ] || [ -z "$latest_handshake" ]; then
            handshake_readable="Never"
        else
            handshake_readable=$(date -d "@$latest_handshake" +"%H:%M:%S (%d/%m)")
        fi

        local traffic="0 B"
        if [ "$transfer_rx" -gt 0 ] || [ "$transfer_tx" -gt 0 ]; then
            local rx_mb=$(echo "scale=2; $transfer_rx / 1048576" | bc 2>/dev/null || echo "0")
            local tx_mb=$(echo "scale=2; $transfer_tx / 1048576" | bc 2>/dev/null || echo "0")
            traffic="${rx_mb}MB/${tx_mb}MB"
        fi

        printf "%-15s %-15s %-20s %-15s\n" "$client_name" "$clean_ip" "$handshake_readable" "$traffic"

    done < <(wg show wg0 dump | tail -n +2 | awk '{print $1, $3, $4, $5, $6, $7}')
}

# MODE 6: Install to system PATH
install_to_path() {
    local target_path="/usr/local/bin/wg-manager"

    cp "$0" "$target_path"
    chmod +x "$target_path"

    [ -x "$target_path" ] && msg_success "Installed to $target_path" || die "Installation failed."
}

show_usage() {
    msg_warning "Usage:"
    echo "  $0 --init-server [port]"
    echo "  $0 --add-peer <name> <vpn_ip> <server_ip:port>"
    echo "  $0 --init-peer <config.conf>"
    echo "  $0 --remove-peer <name>"
    echo "  $0 --show"
    echo "  $0 --install"
}

# CLI entry point
case "$1" in
    --install)
        install_to_path
        ;;
    --init-server)
        init_server "$2"
        ;;
    --add-peer)
        if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
            msg_error "Missing arguments for --add-peer."
            show_usage
            exit 1
        fi
        add_peer "$2" "$3" "$4"
        ;;
    --init-peer)
        if [ -z "$2" ]; then
            msg_error "Config file path required."
            show_usage
            exit 1
        fi
        init_peer "$2"
        ;;
    --remove-peer)
        if [ -z "$2" ]; then
            msg_error "Peer name required."
            show_usage
            exit 1
        fi
        remove_peer "$2"
        ;;
    --show)
        show_status
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
