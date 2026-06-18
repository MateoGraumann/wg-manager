# WireGuard CLI Manager (wg-manager)

Una herramienta integral y simétrica escrita en Bash para automatizar por completo el despliegue de redes VPN basadas en WireGuard. Este script elimina la complejidad de configurar interfaces de red, enrutamiento de Firewall y el intercambio manual de llaves criptográficas, permitiendo levantar infraestructuras Site-to-Peer o redes IoT en cuestión de segundos.

---

## Características Principales

* **Instalación Global:** Permite añadir la herramienta directamente al PATH del sistema para ser ejecutada desde cualquier directorio.
* **Simetría Total (Servidor/Cliente):** El mismo script se utiliza para inicializar el nodo central o para acoplar un nodo cliente de forma automática.
* **Gestión Inteligente de Permisos:** Identifica al usuario real detrás de sudo para exportar las configuraciones directamente a su pantalla principal con los permisos correctos, evitando bloqueos de Root.
* **Enrutamiento Automatizado:** Detecta de forma autónoma la interfaz de red pública nativa (eth0, enp3s0, etc.) y aplica reglas dinámicas de iptables (NAT/MASQUERADE) para permitir la navegación segura.
* **Aprovisionamiento Rápido por QR:** Genera códigos QR directamente en la consola para conectar dispositivos móviles al instante mediante escaneo.
* **Multi-Distribución:** Soporte nativo para sistemas basados en Debian/Kali, Arch Linux y RHEL/Fedora.

---

## Requisitos Previos

* Sistema operativo Linux (Debian, Kali, Arch, etc.).
* Privilegios de administrador (sudo).

---

## Instalación y Modo de Uso

### 0. Instalación en el Sistema (Recomendado)
Para poder usar la herramienta de forma global desde cualquier ruta de la terminal sin el `./`, otorgue permisos de ejecución al script original e instálelo:
```bash
chmod +x wg-manager.sh
sudo ./wg-manager.sh --install
```

A partir de este momento, puede invocar la herramienta en cualquier directorio simplemente usando wg-manager.

### 1. Inicializar el Servidor VPN
Ejecute este comando en la máquina que actuará como el servidor central. Levantará la interfaz wg0 y activará el IP Forwarding en el kernel.

```bash
sudo wg-manager --init-server [puerto_opcional]
# Por defecto utiliza el puerto 51820
```

### 2. Registrar un Nuevo Cliente (Peer)
Ejecute este comando en el servidor para autorizar un nuevo dispositivo. Reemplace la IP por la dirección pública real de su servidor.

```bash
sudo wg-manager --add-peer [nombre_cliente] [ip_privada_vpn] [ip_publica_servidor:puerto]
```

Ejemplo:

```bash
sudo wg-manager --add-peer mi-laptop 10.0.0.2 192.168.1.27:51820
```
Esto registrará al cliente sin detener el servicio del servidor. Detectará el idioma del sistema y exportará un archivo portable listo para usar en su Escritorio (ej: mi-laptop.conf). Adicionalmente desplegará un código QR en la terminal para un aprovisionamiento rápido desde dispositivos móviles.

### 3. Configurar el Cliente (Peer Remoto)
Transfiera el archivo .conf generado y una copia de este script a la máquina cliente (asegúrese de haber corrido primero el comando --install en el cliente si desea usar el comando global) y ejecute:

```bash
sudo wg-manager --init-peer /ruta/al/archivo_cliente.conf
```
El script instalará las dependencias necesarias de forma local, importará el perfil y encenderá el túnel de inmediato.
