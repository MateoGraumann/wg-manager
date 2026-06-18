#!/bin/bash

# ==============================================================================
# WireGuard CLI Manager - Servidor y Peer Simétrico
# ==============================================================================

# Colores para la salida en consola
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0;0m' # No Color

# Validar que se ejecute como Root/Sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED} Error: Este script requiere privilegios de Administrador (Root). Ejecútalo con sudo.${NC}"
    exit 1
fi

# Función para verificar e instalar WireGuard según la distribución
install_wireguard() {
    if ! command -v wg &> /dev/null; then
        echo -e "${YELLOW} WireGuard no está instalado. Detectando gestor de paquetes...${NC}"
        if [ -f /etc/debian_version ]; then
            apt-get update && apt-get install -y wireguard qrencode iptables
        elif [ -f /etc/arch-release ]; then
            pacman -Sy --noconfirm wireguard-tools qrencode iptables
        elif [ -f /etc/redhat-release ]; then
            dnf install -y epel-release && dnf install -y wireguard-tools qrencode iptables
        else
            echo -e "${RED} Distribución no soportada automáticamente. Instala 'wireguard' manualmente.${NC}"
            exit 1
        fi
    fi
}

# MODO 1: Inicializar Servidor
init_server() {
    local port=${1:-51820}
    local server_ip_range="10.0.0.1/24"
    
    echo -e "${BLUE} Iniciando configuración del Servidor WireGuard...${NC}"
    install_wireguard

    # 1. Detectar automáticamente la interfaz de red pública por defecto
    local public_iface=$(ip route | grep default | awk '{print $5}' | head -n 1)
    if [ -z "$public_iface" ]; then
        echo -e "${RED} No se pudo detectar la interfaz de red pública automáticamente.${NC}"
        exit 1
    fi
    echo -e "${GREEN} Interfaz pública detectada: $public_iface${NC}"

    # 2. Habilitar el redireccionamiento de IP (IP Forwarding) en el Kernel
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard-forward.conf
    sysctl --system &> /dev/null

    # 3. Crear directorio y generar llaves del servidor
    mkdir -p /etc/wireguard
    cd /etc/wireguard || exit
    umask 077
    wg genkey | tee server_private.key | wg pubkey > server_public.key
    
    local priv_key=$(cat server_private.key)

    # 4. Crear archivo base del servidor wg0.conf con reglas NAT integradas
    cat <<EOF > /etc/wireguard/wg0.conf
[Interface]
Address = $server_ip_range
ListenPort = $port
PrivateKey = $priv_key
SaveConfig = false

# Reglas de enrutamiento al levantar y tumbar la interfaz
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $public_iface -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $public_iface -j MASQUERADE
EOF

    # 5. Levantar y habilitar el servicio
    wg-quick up wg0
    systemctl enable wg-quick@wg0 &> /dev/null

    echo -e "${GREEN} ¡Servidor WireGuard configurado con éxito en el puerto $port!${NC}"
    echo -e "${YELLOW}Clave pública del servidor para referencia:${NC} $(cat server_public.key)"
}

# MODO 2: Crear credenciales para un nuevo Peer desde el Servidor
add_peer() {
    local client_name=$1
    local client_ip=$2
    local server_endpoint=$3 # Formato: IP_PUBLICA_SERVIDOR:PUERTO
    
    if [ ! -f /etc/wireguard/wg0.conf ]; then
        echo -e "${RED} El servidor local no está configurado. Ejecuta primero --init-server.${NC}"
        exit 1
    fi

    echo -e "${BLUE} Generando credenciales para el peer: $client_name...${NC}"
    
    local real_user=${SUDO_USER:-$USER}
    local user_desktop=$(su - $real_user -c 'xdg-user-dir DESKTOP')
    local output_file="${user_desktop}/${client_name}.conf"
    
    cd /etc/wireguard || exit
    umask 077
    
    # 1. Generar llaves únicas para el cliente
    local client_priv_key=$(wg genkey)
    local client_pub_key=$(echo "$client_priv_key" | wg pubkey)
    local server_pub_key=$(cat server_public.key)
    
    # 2. Modificar dinámicamente el archivo del servidor para registrar el peer
    cat <<EOF >> /etc/wireguard/wg0.conf

[Peer]
# Name = $client_name
PublicKey = $client_pub_key
AllowedIPs = $client_ip/32
EOF

    # Recargar la configuración del servidor en caliente sin tirar conexiones existentes
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

    echo -e "${GREEN} ¡Peer registrado en el servidor de forma segura!${NC}"
    echo -e "${YELLOW} Archivo generado para exportar:${NC} $output_file"
    echo -e "${BLUE} Si deseas escanearlo con el móvil, aquí tienes el código QR:${NC}"
    
    # Mostrar QR en terminal si la herramienta está disponible
    if command -v qrencode &> /dev/null; then
        qrencode -t ansiutf8 < "$output_file"
    fi
    
    # Cambiar el propietario del archivo generado al usuario real para quitar la cruz de permisos
    chown "$real_user:$real_user" "$output_file"
}

# MODO 3: Levantar interfaz en el Peer local usando su archivo .conf externo
init_peer() {
    local config_file=$1

    if [ ! -f "$config_file" ]; then
        echo -e "${RED} Error: El archivo de configuración '$config_file' no existe.${NC}"
        exit 1
    fi

    echo -e "${BLUE} Inicializando entorno local como Peer...${NC}"
    install_wireguard

    # Mover y aislar permisos del archivo en el cliente remoto
    mkdir -p /etc/wireguard
    cp "$config_file" /etc/wireguard/wg0.conf
    chmod 600 /etc/wireguard/wg0.conf

    # Levantar el enlace
    wg-quick up wg0
    systemctl enable wg-quick@wg0 &> /dev/null

    echo -e "${GREEN} ¡Conexión establecida con éxito! Tu interfaz WireGuard local es wg0.${NC}"
}

# MODO 4: Instalar la herramienta de forma global en el PATH
install_to_path() {
    local target_path="/usr/local/bin/wg-manager"
    
    echo -e "${BLUE} Instalando wg-manager en el PATH del sistema...${NC}"
    
    # Copiar el script actual al directorio de binarios globales
    cp "$0" "$target_path"
    chmod +x "$target_path"
    
    if [ -x "$target_path" ]; then
        echo -e "${GREEN} ¡Instalación completada! Ahora puedes usar 'wg-manager' desde cualquier directorio.${NC}"
    else
        echo -e "${RED} Error al intentar instalar la herramienta.${NC}"
        exit 1
    fi
}

# Menú Principal de Banderas (Flags)
case "$1" in
    --install)
        install_to_path
        ;;
    --init-server)
        init_server "$2"
        ;;
    --add-peer)
        if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
            echo -e "${RED} Error: Faltan argumentos obligatorios.${NC}"
            echo "Uso: $0 --add-peer [nombre_dispositivo] [ip_privada_cliente] [ip_publica_server:puerto]"
            echo "Ejemplo: $0 --add-peer laptop-trabajo 10.0.0.2 198.51.100.45:51820"
            exit 1
        fi
        add_peer "$2" "$3" "$4"
        ;;
    --init-peer)
        if [ -z "$2" ]; then
            echo -e "${RED} Error: Debes especificar la ruta del archivo de configuración.${NC}"
            echo "Uso: $0 --init-peer [ruta/archivo_cliente.conf]"
            exit 1
        fi
        init_peer "$2"
        ;;
    *)
        echo -e "${YELLOW}Manual de uso rápido de wg-manager.sh:${NC}"
        echo "  $0 --init-server [puerto_opcional]"
        echo "  $0 --add-peer [nombre_peer] [ip_vpn] [endpoint_publico_server:puerto]"
        echo "  $0 --init-peer [archivo.conf]"
        exit 1
        ;;
esac
