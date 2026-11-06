# 1. TECHNICAL WRITE-UP

## Objective & Scope

Design and industrialization of an offensive/defensive (*Red vs. Blue*) cybersecurity training lab hosted on a single Linux laptop (ThinkPad L14 Gen 4). The goal was to eliminate operational friction (boot times, repetitive GUI clicks in VirtualBox/VMware, manual IP lookups, and window management) through 100% CLI orchestration built on **KVM / QEMU / Libvirt**.

## Lab Topology

* **Hypervisor:** Linux KVM / Libvirt (`qemu:///system`)
* **Network:** Isolated Libvirt NAT Bridge `192.168.122.0/24` (Libvirt DHCP)
* **Virtual Machines:**
  * **`KALI_VM`** (`192.168.122.2`): Attack / Red Team node (User: `kali`).
  * **`DEBIAN_VM_TARGET`** (`192.168.122.4`): Vulnerable target node (User: `jweak`).
  * **`WAZUH`** (`192.168.122.3`): Blue Team SIEM/XDR appliance (User: `wazuh-user` + HTTPS Web UI).

```text
                      +---------------------------------------+
                      |       Physical Host (ThinkPad)        |
                      |            CLI: `cyberlab`            |
                      +-------------------+-------------------+
                                          | (virsh / SSH)
                       Libvirt NAT Bridge | 192.168.122.0/24
         +--------------------------------+--------------------------------+
         |                                |                                |
         v                                v                                v
+------------------+             +------------------+             +------------------+
|     KALI_VM      |             | DEBIAN_VM_TARGET |             |      WAZUH       |
|  (Red Team Box)  |             |  (Target/Vuln)   |             |   (SIEM / SOC)   |
|  192.168.122.2   |             |  192.168.122.4   |             |  192.168.122.3   |
+------------------+             +------------------+             +------------------+
```

## Key Achievements & Engineering Challenges Solved

1. **Programmatic Control & Real-Time Telemetry:**
   * Custom Bash automation utility `cyberlab` integrated into `$PATH` (`~/.local/bin/cyberlab`).
   * Interactive CLI dashboard leveraging `tput smcup`/`civis` for flicker-free in-place refreshes, combined with Libvirt introspection commands (`dommemstat --period 2 --live` and `domifaddr`).

2. **SSH Protocol Tuning & Asymmetric Cryptography:**
   * Passwordless SSH key deployment across all nodes.
   * **Resolved Incident:** The Wazuh appliance (Amazon Linux 2023 / FIPS-compliant) rejected standard `ed25519` keys during the `KEXINIT` handshake phase. Resolved by generating and deploying an `ECDSA-SHA2-NISTP256` elliptic-curve key pair compliant with the appliance's cryptographic policies.

3. **Workspace Orchestration & Hybrid Window Tiling:**
   * Multi-window GNOME Terminal automation with dynamic screen geometry calculation (`xdpyinfo`) to tile SSH sessions into screen quadrants.
   * Smart shell lifecycle management: chaining `ssh ... && exit || exec bash` ensures the terminal window closes immediately upon a voluntary `exit`, while keeping the terminal open for diagnostics if a network or SSH error occurs.
   * Unified `gui` command combining native remote display viewers (`virt-viewer --wait`) with automated host browser launch (`xdg-open`) targeting the Wazuh HTTPS dashboard.
