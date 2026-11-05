# 🛡️ CyberLab Controller (`cyberlab-ctl`)

A lightweight, zero-dependency Bash automation tool to orchestrate, monitor, and interact with a local KVM/Libvirt Cybersecurity Homelab.

Designed for security researchers, pentetesting enthusiasts, and SOC analysts operating on Linux hosts.

---

## ⚡ Overview

Managing multi-node virtual labs with GUIs (Virt-Manager, VirtualBox) introduces operational friction. `cyberlab-ctl` provides a single CLI entry point to:

* **Boot / Graceful Shutdown** VMs in sequential or reverse order.
* **Real-time Metrics Dashboard**: A live, terminal-native monitor (`top`-style) displaying VM operational status, dynamic IP assignments, and live RAM consumption.
* **Automated Workspace Tiling**: Launches dedicated, passwordless SSH terminals arranged in screen quadrants.
* **Smart Window Lifecycle**: Terminals automatically terminate upon `exit`, but stay open if SSH connectivity drops for immediate debugging.
* **Unified GUI / Web Launch**: Launches SPICE/VNC native displays (`virt-viewer`) alongside SOC web dashboards (`xdg-open`).

---

## 🏗️ Architecture

```
                      +---------------------------------------+
                      |           Host (Linux KVM)            |
                      |            CLI: `cyberlab`            |
                      +-------------------+-------------------+
                                          |
                               Network: 192.168.122.0/24
                                          |
         +--------------------------------+--------------------------------+
         |                                |                                |
         v                                v                                v
+------------------+             +------------------+             +------------------+
|     KALI_VM      |             | DEBIAN_VM_TARGET |             |      WAZUH       |
|    (Red Team)    |             |  (Vulnerable)    |             |  (SIEM / Blue)   |
|  192.168.122.2   |             |  192.168.122.4   |             |  192.168.122.3   |
+------------------+             +------------------+             +------------------+
```

---

## 🚀 Quick Start

### Prerequisites
* KVM / QEMU / Libvirt installed on the host.
* `virt-viewer`, `xdpyinfo`, and `x11-utils` (for geometry calculations).
* `qemu-guest-agent` active on guest machines.

```bash
sudo apt update && sudo apt install -y virt-viewer x11-utils
```

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/<your-username>/cyberlab-ctl.git
   cd cyberlab-ctl
   ```
2. Link the executable into your path:
   ```bash
   mkdir -p ~/.local/bin
   cp bin/cyberlab ~/.local/bin/cyberlab
   chmod +x ~/.local/bin/cyberlab
   ```
3. Make sure `~/.local/bin` is in your `$PATH`.

---

## 💻 Usage

```bash
# Start all lab nodes and enable memory telemetry
cyberlab start

# Open the live CLI monitoring dashboard (press 'q' to quit)
cyberlab status

# Deploy SSH sessions in auto-tiled quadrants
cyberlab ssh

# Open a dedicated terminal for a single VM
cyberlab ssh kali
cyberlab ssh target
cyberlab ssh wazuh

# Launch GUI display screens and Wazuh web dashboard
cyberlab gui
cyberlab gui kali
cyberlab gui wazuh

# Gracefully power off the entire lab
cyberlab stop
```

---

## 🔑 Authentication & Crypto Policies

For seamless passwordless access, key deployment must match guest cryptographic policies:

* **Standard Linux (Debian, Kali):** Ed25519 keys (`~/.ssh/id_ed25519`).
* **Enterprise / FIPS appliances (Wazuh / Amazon Linux 2023):** Requires ECDSA keys (`~/.ssh/id_ecdsa`):
  ```bash
  ssh-keygen -t ecdsa -b 256 -N "" -f ~/.ssh/id_ecdsa
  ssh-copy-id -i ~/.ssh/id_ecdsa.pub wazuh-user@<WAZUH_IP>
  ```

---

## 📜 License
MIT License. Feel free to fork and adapt to your hypervisor setup!
