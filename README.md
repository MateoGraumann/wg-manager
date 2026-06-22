# WireGuard CLI Manager (wg-manager)

A comprehensive and symmetric tool written in Bash to fully automate the deployment of WireGuard-based VPN networks. This script eliminates the complexity of configuring network interfaces, firewall routing, and the manual exchange of cryptographic keys, allowing you to deploy Site-to-Peer infrastructures or IoT networks in a matter of seconds.

---

## Key Features

* **Global Installation:** Allows adding the tool directly to the system's PATH to be executed from any directory.
* **Total Symmetry (Server/Client):** The exact same script is used to initialize the central node or to automatically hook up a client node.
* **Smart Permission Management:** Identifies the real user behind sudo to export configurations directly to their main desktop screen with the correct permissions, preventing root-access lockouts.
* **Automated Routing:** Autodetects the native public network interface (eth0, enp3s0, etc.) and applies dynamic iptables rules (NAT/MASQUERADE) to enable secure web browsing.
* **Fast Provisioning via QR:** Generates QR codes directly in the terminal to instantly connect mobile devices by scanning.
* **Multi-Distribution:** Native support for systems based on Debian/Kali, Arch Linux, and RHEL/Fedora.

---

## Prerequisites

* Linux Operating System (Debian, Kali, Arch, etc.).
* Administrative privileges (sudo).

---

## Installation and Usage

### 0. System Installation (Recommended)
To use the tool globally from any terminal path without using ./, grant execution permissions to the original script and install it:
```bash
chmod +x wg-manager.sh
sudo ./wg-manager.sh --install
```

From this point forward, you can invoke the tool in any directory simply by running wg-manager.

### 1. Initialize the VPN Server
Run this command on the machine that will act as the central server. This will bring up the wg0 interface and enable IP Forwarding in the kernel.
```bash
sudo wg-manager --init-server [optional_port]
# Uses port 51820 by default
```

### 2. Register a New Client (Peer)
Run this command on the server to authorize a new device. Replace the IP with your server's real public IP address.

```bash
sudo wg-manager --add-peer [client_name] [private_vpn_ip] [public_server_ip:port]
```

Example:

```bash
sudo wg-manager --add-peer my-laptop 10.0.0.2 192.168.1.27:51820
```
>[!NOTE]
>This will register the client without stopping the server service. It will autodetect the system language and export a portable file ready to use on your Desktop (e.g., my-laptop.conf). Additionally, it will display a QR code in the terminal for fast provisioning from mobile devices.

### 3. Configure the Client (Remote Peer)
Transfer the generated .conf file and a copy of this script to the client machine (make sure you have run the --install command on the client first if you want to use the global command) and execute:

```bash
sudo wg-manager --init-peer /path/to/client_file.conf
```
The script will locally install the required dependencies, import the profile, and bring up the tunnel immediately.
