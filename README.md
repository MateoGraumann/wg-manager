# WireGuard CLI Manager (wg-manager.sh)

Una herramienta integral y simétrica escrita en Bash para automatizar por completo el despliegue de redes VPN basadas en WireGuard. Este script elimina la complejidad de configurar interfaces de red, enrutamiento de Firewall y el intercambio manual de llaves criptográficas, permitiendo levantar infraestructuras Site-to-Peer en cuestión de segundos.

---

## Características Principales

* **Simetría Total (Servidor/Cliente):** El mismo script se utiliza para inicializar el nodo central o para acoplar un nodo cliente de forma automática.
* **Gestión Inteligente de Permisos:** Identifica al usuario real detrás de sudo para exportar las configuraciones directamente a su directorio personal con los permisos correctos, evitando bloqueos de Root.
* **Enrutamiento Automatizado:** Detecta de forma autónoma la interfaz de red pública nativa (eth0, enp3s0, etc.) y aplica reglas dinámicas de iptables (NAT/MASQUERADE) para permitir la navegación segura.
* **Aprovisionamiento Rápido por QR:** Genera códigos QR directamente en la consola para conectar dispositivos móviles al instante mediante escaneo.
* **Multi-Distribución:** Soporte nativo para sistemas basados en Debian/Kali, Arch Linux y RHEL/Fedora.

---

## Requisitos Previos

* Sistema operativo Linux (Debian, Kali, Arch, etc.).
* Privilegios de administrador (sudo).

---

## Modo de Uso

Primero, asigne permisos de ejecución al script:
```bash
chmod +x wg-manager.sh
