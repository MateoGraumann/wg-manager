# WireGuard CLI Manager (wg-manager)

A Bash CLI to deploy and manage WireGuard VPNs. One script works as both server and client: it handles keys, NAT/routing, peer provisioning, and systemd integration.

---

## Key Features

* **Global installation** — install to `/usr/local/bin` and run `wg-manager` from anywhere.
* **Server/client symmetry** — same script for the central node or a remote peer.
* **Hot-reload** — add or remove peers without restarting the WireGuard service.
* **Smart permissions** — exports client configs to the real user's Desktop (not root-owned).
* **Automated routing** — detects the public interface and applies iptables NAT/MASQUERADE rules.
* **QR provisioning** — prints a terminal QR code when `qrencode` is available.
* **Multi-distribution** — Debian/Kali, Arch, and RHEL/Fedora (auto-installs dependencies).

**Defaults:** VPN subnet `10.0.0.1/24` (configurable at init), listen port `51820`. Client profiles use full-tunnel (`0.0.0.0/0`), DNS `1.1.1.1` / `8.8.8.8`, and `PersistentKeepalive = 25`.

---

## Prerequisites

* Linux (Debian, Kali, Arch, Fedora, etc.)
* Root privileges (`sudo`)

---

## Command Reference

| Command | Description |
|---------|-------------|
| `--install` | Copy the script to `/usr/local/bin/wg-manager` |
| `--init-server <public_ipv4> [vpn_ip/cidr] [port]` | Set up the VPN server (`wg0`, IP forwarding, NAT) |
| `--add-peer <name> <vpn_ip>` | Register a peer and export a client `.conf` |
| `--init-peer <config.conf>` | Import a client profile and bring up `wg0` |
| `--remove-peer <name>` | Revoke a peer, disconnect it, and remove its Desktop `.conf` |
| `--show` | Show server info and peer status (handshake, traffic) |

---

## Quick Start

### 0. Install (recommended)

```bash
chmod +x wg-manager.sh
sudo ./wg-manager.sh --install
```

### 1. Initialize the server

```bash
sudo wg-manager --init-server 203.0.113.10
# Custom port:       sudo wg-manager --init-server 203.0.113.10 51821
# Custom VPN subnet: sudo wg-manager --init-server 203.0.113.10 192.168.50.1/24
# Both:              sudo wg-manager --init-server 203.0.113.10 192.168.50.1/24 51821
```

Brings up `wg0`, stores the public endpoint and VPN `Address` in `wg0.conf`, enables IP forwarding, and enables `wg-quick@wg0` on boot. Only `/24` subnets are supported.

### 2. Add a client

Run on the **server**. Use an unused address in the server's VPN `/24` (excluding `.0`, `.255`, and the server IP).

```bash
sudo wg-manager --add-peer my-laptop 10.0.0.2
# With custom subnet 192.168.50.1/24: sudo wg-manager --add-peer phone 192.168.50.2
```

Validates peer name, IP format, and subnet. The client endpoint is built automatically from the server's stored public IP and listen port.

### 3. Connect the client

Transfer the `.conf` to the client machine and run:

```bash
sudo wg-manager --init-peer /path/to/my-laptop.conf
```

Installs WireGuard if needed, imports the profile, and enables `wg-quick@wg0` on boot.

---

## Server Management

### Check status

```bash
sudo wg-manager --show
```

Shows the server VPN address, listen port, and a table of registered peers with last handshake and Rx/Tx traffic.

### Remove a peer

```bash
sudo wg-manager --remove-peer my-laptop
```

Revokes the peer from the running interface and updates `wg0.conf` without restarting the service. Deletes `my-laptop.conf` from the Desktop if present.
