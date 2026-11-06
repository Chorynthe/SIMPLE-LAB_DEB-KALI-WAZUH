# 🛡️ KVM/Libvirt Cyber Range: Wazuh SOC Lab & Attack Simulation

This project documents the design, CLI orchestration, and operation of a fully virtualized Incident Detection & Response (**SIEM / SOC**) environment built on **Linux KVM / QEMU / Libvirt** and managed via the **`cyberlab`** CLI orchestrator.

The goal is to emulate real-world offensive techniques (reconnaissance, brute force, privilege escalation, persistence, file integrity tampering, and web exploitation), observe their real-time detection within a Wazuh SIEM, and configure automated remediation mechanisms (*Active Response*).

> 📌 **Why This Lab? Training Guide & Roadmap:** Read [**`docs/LAB_OVERVIEW_AND_ROADMAP.md`**](docs/LAB_OVERVIEW_AND_ROADMAP.md) to explore the *Purple Team* philosophy behind the project, the recommended training workflow (Threat Hunting, Detection Engineering, CIS Hardening), architectural trade-offs, and the engineering roadmap (`auditd`, Suricata NDR, Ansible IaC, SOAR).

---

## 🌐 1. Network Architecture & Node Roles

The entire environment runs on an isolated Libvirt NAT Bridge network using the **`192.168.122.0/24`** subnet, orchestrated from the Linux host via `virsh` and SSH.

```text
                      +---------------------------------------+
                      |           Linux Physical Host         |
                      |            CLI: `cyberlab`            |
                      +-------------------+-------------------+
                                          | (virsh / SSH)
                       Libvirt NAT Bridge | 192.168.122.0/24
         +--------------------------------+--------------------------------+
         |                                |                                |
         v                                v                                v
+------------------+             +------------------+             +------------------+
|     KALI_VM      |             | DEBIAN_VM_TARGET |             |      WAZUH       |
|   [Attacker]     | --(Attacks)->|     [Target]     | --(Logs)--> |   [SOC / SIEM]   |
|  192.168.122.2   |  (SSH, Web) |  192.168.122.4   | (Port 1514) |  192.168.122.3   |
+------------------+             +------------------+             +------------------+
```

### Node Inventory

| KVM Domain (`virsh`) | Role | Operating System | IP Address | SSH User | Description & Services |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`WAZUH`** | **SOC / SIEM** | Wazuh Appliance v4.14 (Amazon Linux 2023) | `192.168.122.3` | `wazuh-user` | Wazuh Manager, analysis & correlation engine, OpenSearch Dashboard (`https://192.168.122.3`), alert indexer |
| **`KALI_VM`** | **Attacker (Red Team)** | Kali Linux (x86_64) | `192.168.122.2` | `kali` | Nmap, Hydra, Nikto, curl, GTFOBins exploitation |
| **`DEBIAN_VM_TARGET`** | **Target (Blue/Vuln)** | Debian 13 (x86_64) | `192.168.122.4` | `jweak` / `devuser` | Wazuh Agent (`Debian-Target`), OpenSSH Server, Apache/PHP web server with vulnerable endpoint |

---

## ⚡ 2. CLI Orchestration (`cyberlab`)

To eliminate the operational friction of hypervisor GUIs, the lab is managed via the `cyberlab` CLI utility (see detailed documentation in [`docs/README.md`](docs/README.md) and the installer script [`docs/INSTALL.sh`](docs/INSTALL.sh)):

* `cyberlab start` / `cyberlab stop`: Sequential boot (enabling live memory telemetry via `dommemstat`) and graceful shutdown (`virsh shutdown`) of all 3 virtual machines.
* `cyberlab status`: Flicker-free, real-time terminal dashboard (`tput`) displaying operational state, dynamic IP assignment (`domifaddr`), and live RAM usage for each VM.
* `cyberlab ssh [kali|target|wazuh]`: Simultaneous deployment of 3 SSH terminals tiled into screen quadrants (`xdpyinfo`), or launch of a single dedicated console.
* `cyberlab gui [kali|target|wazuh]`: Unified launch of SPICE/VNC native displays (`virt-viewer`) alongside the Wazuh web portal (`xdg-open https://192.168.122.3`).

---

## 🎯 3. Attack Scenarios & SOC Detections

### A. Network Reconnaissance & SSH Brute Force
* **Attack Vector:**
  1. Port and service discovery from `KALI_VM` (`192.168.122.2`) via `nmap -sV -p- 192.168.122.4`.
  2. Dictionary attack against the SSH service targeting the `devuser` account using Hydra.
* **Wazuh Telemetry & Detection:**
  * Ingestion of `/var/log/auth.log` and `journald` on `DEBIAN_VM_TARGET`.
  * Triggered alerts:
    * **Rule ID 5710:** `sshd: Attempt to login using a non-existent user`.
    * **Rule ID 5760 / 5716:** `sshd: authentication failed`.
    * **Rule ID 5720:** `Multiple failed logins from a single host` (Severity level 10).
  * **Compliance Mapping:** Mapped to **PCI DSS 10.2.4 & 10.2.5** (monitoring of invalid logical access attempts).
* **Active Response:**
  * Automated execution of the `firewall-drop` script bound to rules 5712 and 5720.
  * Temporary block of the Kali source IP (`192.168.122.2`) via `iptables/nftables` with a 180-second timeout.

---

### B. Privilege Escalation via Sudo Misconfiguration (GTFOBins)
* **Attack Vector:**
  * Initial access achieved on the `devuser` account.
  * Discovery of a permissive directive in [`configs/debian/devuser-find`](configs/debian/devuser-find) (`/etc/sudoers.d/devuser-find`):
    ```text
    devuser ALL=(ALL) NOPASSWD: /usr/bin/find
    ```
  * Exploitation of the binary escape (GTFOBins) to spawn an interactive `root` shell:
    ```bash
    sudo /usr/bin/find . -exec /bin/sh \; -quit
    ```
* **Wazuh Telemetry & Detection:**
  * Triggers **Rule ID 5402** (*Successful sudo to ROOT executed*).
  * **MITRE ATT&CK Mapping:** Technique **T1548.003 (Abuse Elevation Control Mechanism: Sudo and Sudo Caching)**.

---

### C. File Integrity Monitoring (FIM / Syscheck) & Persistence Detection
* **Defensive Configuration:**
  * Agent configuration in `/var/ossec/etc/ossec.conf` ([`configs/debian-target/agent-ossec.conf`](configs/debian-target/agent-ossec.conf)) enabling real-time monitoring (*inotify*) and text diff reporting:
    ```xml
    <directories realtime="yes" report_changes="yes" check_all="yes">/etc,/usr/bin,/usr/sbin</directories>
    <directories realtime="yes" check_all="yes">/root</directories>
    ```
* **Simulated Attack Vectors:**
  1. **Cron Persistence:** Creation of a malicious root scheduled task in `/etc/cron.d/malicious_job`.
  2. **System Tampering:** Injection of an unauthorized entry into `/etc/passwd`.
* **Wazuh Telemetry & Detection:**
  * **Rule ID 554:** `File added to the system: '/etc/cron.d/malicious_job'`.
  * **Rule ID 550:** `Integrity checksum changed for: '/etc/passwd'`.
  * **Text Diff Inspection:** Extraction of the `syscheck.diff` JSON field showing the exact line added to the file (`+ # Unauthorized modification`).
* **SOC Investigation Methodology (*Threat Hunting*):**
  * Blind hunting without prior knowledge of the modified filename using `rule.groups: "syscheck"` and wildcard path filters (`syscheck.path: /etc/*`).

---

### D. Web Application Auditing & Injection Attacks (Apache / PHP)
* **Deployed Component:** Apache web server with PHP hosting a vulnerable test endpoint (`/var/www/html/vuln.php`) exposing:
  * A Directory Traversal / Local File Inclusion (*LFI*) vulnerability via the `page` parameter.
  * An unsanitized SQL Injection (*SQLi*) vulnerability via the `id` parameter.
* **Wazuh Monitoring:**
  * Continuous ingestion of `/var/log/apache2/access.log` and `/var/log/apache2/error.log` using `<localfile>` blocks of type `apache` ([`configs/debian-target/agent-ossec.conf`](configs/debian-target/agent-ossec.conf)).
* **Attacks & Detections:**
  * Detection of SQL injections and successful web attacks (Rules 31103 / 31104 / 31106 / 31153).
  * Detection of directory traversal attempts and anomalous HTTP 400 responses (Rule 31101).

---

## 🛠️ 4. Lessons Learned & Troubleshooting

Building the KVM/Libvirt architecture and tuning Wazuh involved resolving several system, cryptographic, and configuration challenges (detailed in [`docs/WRITE-UP.md`](docs/WRITE-UP.md) and [`docs/LESSONS_LEARNED.md`](docs/LESSONS_LEARNED.md)):

| Phase / Symptom | Root Cause | Solution Applied |
| :--- | :--- | :--- |
| **Initial SSH Access (`Connection refused` on Kali)** | The `sshd` daemon is disabled by default on Kali Linux to minimize its network footprint. | Headless CLI activation via `virsh qemu-agent-command` / serial console and `systemctl enable --now ssh`. |
| **Wazuh SSH Cryptography (`id_ed25519` rejected)** | The Wazuh Appliance (Amazon Linux 2023 / FIPS compliant) enforces a strict crypto-policy disallowing `ssh-ed25519` during `KEXINIT`. | Diagnosed via `ssh -vvv` (`server-sig-algs`) and deployed a dedicated ECDSA key (`ssh-keygen -t ecdsa -b 256 -f ~/.ssh/id_ecdsa`). |
| **Shell Profile Errors (`shopt: not found` on Kali)** | Kali defaults to `zsh`; sourcing a Bash configuration (`PS1`) inside `zsh` triggers cascading syntax errors. | Decoupled shell syntax (`PROMPT` in `~/.zshrc`) or explicitly switched login shell via `chsh -s /bin/bash`. |
| **GUI Terminal Lifecycle (`gnome-terminal`)** | Orphaned terminal windows remaining open after logout, or closing immediately upon network errors. | Implemented the `ssh ... && exit || exec bash` pattern to close cleanly on voluntary `exit` while keeping a diagnostic shell open if SSH fails. |
| **`wazuh-agent.service` Startup Failure** | XML syntax error in `ossec.conf` (unclosed `</directories` tag or stray UTF-8 BOM). | Diagnosed with `/var/ossec/bin/wazuh-agentd -t` and `xmllint --noout`, stripped BOM / fixed XML tags, and restarted the service. |
| **Missing FIM (`syscheck`) Alerts After File Edits** | File modifications were performed before the initial baseline inventory scan had completed. | Monitored `/var/ossec/logs/ossec.log` for `Real-time file integrity monitoring started` before triggering test modifications. |
| **Git Push Rejected (`GH007: Private email exposure`)** | GitHub email privacy protection blocked commits authored with a local address. | Configured the `@users.noreply.github.com` address and rewrote commit authorship via `git commit --amend --reset-author`. |

---

## 📁 5. Repository Structure

```text
.
├── .gitignore
├── README.md                              # Main documentation (KVM architecture & SOC scenarios)
├── configs/
│   ├── debian/
│   │   └── devuser-find                   # Vulnerable sudoers directive (/usr/bin/find)
│   ├── debian-target/
│   │   └── agent-ossec.conf               # Wazuh Agent configuration (192.168.122.3, real-time FIM + Apache logs)
│   └── wazuh-server/                      # Directory for Wazuh Manager configuration files
├── docs/
│   ├── LAB_OVERVIEW_AND_ROADMAP.md        # Lab overview, Purple Team training guide, limitations & roadmap
│   ├── README.md                          # Documentation for the `cyberlab-ctl` CLI orchestrator
│   ├── INSTALL.sh                         # Host installer & KVM/X11 dependency checker
│   ├── WRITE-UP.md                        # Technical write-up on KVM/Libvirt industrialization
│   ├── LESSONS_LEARNED.md                 # Lessons learned summary (SSH, Zsh, FIPS, Bash)
│   ├── alerts-json/                       # Directory for raw Wazuh JSON alert samples
│   └── screenshots/                       # Directory for lab screenshots
└── scripts/
    ├── defensive/                         # Directory for FIM / Blue Team validation scripts
    └── offensive/                         # Directory for Red Team attack scripts
```
