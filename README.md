# 🛡️ KVM/Libvirt Cyber Range : Lab SOC Wazuh & Simulation d'Attaques

Ce projet documente la conception, l'orchestration et l'exploitation d'un environnement de détection et de réponse aux incidents (SIEM / SOC) entièrement virtualisé sous **Linux KVM / QEMU / Libvirt** et piloté en ligne de commande via l'orchestrateur **`cyberlab`**.

L'objectif est d'émuler des attaques réelles (reconnaissance, force brute, élévation de privilèges, persistance, altération d'intégrité et attaques web), d'observer leur détection en temps réel au sein d'un SIEM Wazuh et de configurer des mécanismes de remédiation automatique (*Active Response*).

> 📌 **Pourquoi ce Lab ? Guide d'Entraînement & Feuille de Route :** Consultez [**`docs/ANALYSE_ET_FEUILLE_DE_ROUTE.md`**](docs/ANALYSE_ET_FEUILLE_DE_ROUTE.md) pour découvrir la philosophie *Purple Team* du projet, la méthodologie d'entraînement optimal (Threat Hunting, Detection Engineering, Hardening CIS), les choix d'architecture et la feuille de route d'évolution (`auditd`, Suricata NDR, Ansible IaC, SOAR).

---

## 🌐 1. Architecture Réseau & Rôles des Machines

L'ensemble de l'environnement évolue sur un réseau isolé Bridge NAT Libvirt sur le plan d'adressage **`192.168.122.0/24`**, orchestré depuis l'hôte physique Linux via `virsh` et SSH.

```text
                      +---------------------------------------+
                      |          Hôte Physique Linux          |
                      |            CLI: `cyberlab`            |
                      +-------------------+-------------------+
                                          | (virsh / SSH)
                       Bridge NAT Libvirt | 192.168.122.0/24
         +--------------------------------+--------------------------------+
         |                                |                                |
         v                                v                                v
+------------------+             +------------------+             +------------------+
|     KALI_VM      |             | DEBIAN_VM_TARGET |             |      WAZUH       |
|   [Attaquant]    | --(Attaque)->|     [Cible]      | --(Logs)--> |   [SOC / SIEM]   |
|  192.168.122.2   |  (SSH, Web) |  192.168.122.4   | (Port 1514) |  192.168.122.3   |
+------------------+             +------------------+             +------------------+
```

### Inventaire des Nœuds

| Domaine KVM (`virsh`) | Rôle | Système d'exploitation | Adresse IP | Utilisateur SSH | Description & Services |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`WAZUH`** | **SOC / SIEM** | Wazuh Appliance v4.14 (Amazon Linux 2023) | `192.168.122.3` | `wazuh-user` | Serveur Wazuh, moteur d'analyse et de corrélation, dashboard OpenSearch (`https://192.168.122.3`), indexeur d'alertes |
| **`KALI_VM`** | **Attaquant (Red Team)** | Kali Linux (x86_64) | `192.168.122.2` | `kali` | Nmap, Hydra, curl, exploitation GTFOBins |
| **`DEBIAN_VM_TARGET`** | **Cible (Blue/Vuln)** | Debian 13 (x86_64) | `192.168.122.4` | `jweak` / `devuser` | Agent Wazuh (`Debian-Cible`), OpenSSH Server, serveur web Apache/PHP avec endpoint vulnérable |

---

## ⚡ 2. Orchestration CLI (`cyberlab`)

Pour éliminer la friction opérationnelle des interfaces graphiques d'hyperviseurs, le lab est piloté par l'utilitaire `cyberlab` (voir la documentation détaillée dans [`docs/README.md`](docs/README.md) et le script d'installation [`docs/INSTALL.sh`](docs/INSTALL.sh)) :

* `cyberlab start` / `cyberlab stop` : Démarrage séquentiel (avec activation des métriques mémoire `dommemstat`) et arrêt gracieux (`virsh shutdown`) des 3 machines virtuelles.
* `cyberlab status` : Tableau de bord temps réel dans le terminal (`tput`), affichant l'état, l'IP dynamique (`domifaddr`) et la consommation RAM de chaque VM.
* `cyberlab ssh [kali|target|wazuh]` : Déploiement simultané des 3 terminaux SSH répartis en quadrants d'écran (`xdpyinfo`) ou ouverture d'une console dédiée.
* `cyberlab gui [kali|target|wazuh]` : Ouverture combinée des écrans SPICE/VNC (`virt-viewer`) et du portail web Wazuh (`xdg-open https://192.168.122.3`).

---

## 🎯 3. Scénarios d'Attaque & Détections SOC

### A. Reconnaissance Réseau & Force Brute SSH
* **Vecteur d'attaque :**
  1. Cartographie des ports et services depuis `KALI_VM` (`192.168.122.2`) via `nmap -sV -p- 192.168.122.4`.
  2. Attaque par dictionnaire sur le service SSH ciblant le compte `devuser` via Hydra.
* **Télémétrie & Détection Wazuh :**
  * Ingestion des logs `/var/log/auth.log` et `journald` sur `DEBIAN_VM_TARGET`.
  * Déclenchement des alertes :
    * **Règle ID 5710 :** `sshd: Attempt to login using a non-existent user`.
    * **Règle ID 5760 / 5716 :** `sshd: authentication failed`.
    * **Règle ID 5720 :** `Multiple failed logins from a single host` (Niveau de sévérité 10).
  * **Conformité réglementaire :** Mappé sur les exigences **PCI DSS 10.2.4 & 10.2.5** (surveillance des échecs d'authentification).
* **Réponse Active (*Active Response*) :**
  * Déclenchement du script `firewall-drop` paramétré sur les règles 5712 et 5720.
  * Blocage temporaire de l'IP source de Kali (`192.168.122.2`) via `iptables/nftables` avec un timeout de 180 secondes.

---

### B. Élévation de Privilèges via Mauvaise Configuration Sudo (GTFOBins)
* **Vecteur d'attaque :**
  * Compromission préalable du compte `devuser`.
  * Découverte d'une directive permissive dans [`configs/debian/devuser-find`](configs/debian/devuser-find) (`/etc/sudoers.d/devuser-find`) :
    ```text
    devuser ALL=(ALL) NOPASSWD: /usr/bin/find
    ```
  * Exploitation de l'évasion de binaire (GTFOBins) pour obtenir un shell root complet :
    ```bash
    sudo /usr/bin/find . -exec /bin/sh \; -quit
    ```
* **Télémétrie & Détection Wazuh :**
  * Déclenchement de l'alerte **Règle ID 5402** (*Successful sudo to ROOT executed*).
  * **Cartographie MITRE ATT&CK :** Technique **T1548.003 (Abuse Elevation Control Mechanism: Sudo and Sudo Caching)**.

---

### C. Surveillance d'Intégrité de Fichiers (FIM / Syscheck) & Détection de Persistance
* **Configuration défensive :**
  * Configuration de `/var/ossec/etc/ossec.conf` sur l'agent ([`configs/debian-target/agent-ossec.conf`](configs/debian-target/agent-ossec.conf)) pour activer l'analyse en temps réel (*inotify*) et le reporting de diff :
    ```xml
    <directories realtime="yes" report_changes="yes" check_all="yes">/etc,/usr/bin,/usr/sbin</directories>
    <directories realtime="yes" check_all="yes">/root</directories>
    ```
* **Vecteurs d'attaque simulés :**
  1. **Persistance Cron :** Création d'une tâche planifiée root malveillante dans `/etc/cron.d/malicious_job`.
  2. **Altération Système :** Injection d'une ligne non autorisée dans `/etc/passwd`.
* **Télémétrie & Détection Wazuh :**
  * **Règle ID 554 :** `File added to the system: '/etc/cron.d/malicious_job'`.
  * **Règle ID 550 :** `Integrity checksum changed for: '/etc/passwd'`.
  * **Diff textuel :** Exploitation du champ JSON `syscheck.diff` permettant de visualiser la ligne exacte ajoutée au système (`+ # Modification non autorisee`).
* **Méthodologie d'investigation SOC (*Threat Hunting*) :**
  * Recherche sans connaissance préalable du nom de fichier via `rule.groups: "syscheck"` et filtres génériques `syscheck.path: /etc/*`.

---

### D. Audit Applicatif Web & Injections (Apache / PHP)
* **Composant déployé :** Serveur Apache avec module PHP hébergeant une application de test vulnérable (`/var/www/html/vuln.php`) exposant :
  * Une vulnérabilité de traversée de répertoires (*Directory Traversal / Local File Inclusion* via le paramètre `page`).
  * Une injection SQL non filtrée (via le paramètre `id`).
* **Supervision Wazuh :**
  * Collecte continue de `/var/log/apache2/access.log` et `/var/log/apache2/error.log` via les balises `<localfile>` de type `apache` ([`configs/debian-target/agent-ossec.conf`](configs/debian-target/agent-ossec.conf)).
* **Attaques & Détections :**
  * Détection d'injections SQL et d'attaques web réussies (Règles 31103 / 31104 / 31106 / 31153).
  * Détection de tentatives de traversée de répertoires et erreurs 400 (Règle 31101).

---

## 🛠️ 4. Retour d'Expérience (RETEX) & Troubleshooting

La mise en place de l'architecture KVM/Libvirt et la configuration de Wazuh ont donné lieu aux résolutions techniques suivantes (détaillées dans [`docs/WRITE-UP`](docs/WRITE-UP) et [`docs/RETEX`](docs/RETEX)) :

| Phase / Symptôme | Cause Racine | Solution Appliquée |
| :--- | :--- | :--- |
| **Activation SSH initiale (`Connection refused` sur Kali)** | Le démon `sshd` est désactivé par défaut sur Kali Linux pour réduire l'empreinte réseau. | Activation en CLI sans interface graphique via `virsh qemu-agent-command` / console série et `systemctl enable --now ssh`. |
| **Cryptographie SSH Wazuh (refus de `id_ed25519`)** | L'appliance Wazuh (Amazon Linux 2023 / FIPS compliant) applique une crypto-policy restrictive interdisant `ssh-ed25519` lors du `KEXINIT`. | Diagnostic via `ssh -vvv` (`server-sig-algs`) et déploiement d'une clé dédiée ECDSA (`ssh-keygen -t ecdsa -b 256 -f ~/.ssh/id_ecdsa`). |
| **Erreurs de profil Shell (`shopt: not found` sur Kali)** | Kali utilise `zsh` par défaut ; sourcer une configuration Bash (`PS1`) dans `zsh` provoque des erreurs en cascade. | Découplage des syntaxes (`PROMPT` dans `~/.zshrc`) ou bascule explicite via `chsh -s /bin/bash`. |
| **Cycle de vie des fenêtres GUI (`gnome-terminal`)** | Fenêtres fantômes persistant après déconnexion ou fermeture brutale sur erreur réseau. | Pattern `ssh ... && exit || exec bash` permettant de fermer le terminal sur un `exit` volontaire tout en gardant un shell ouvert en cas d'erreur de connexion. |
| **Échec au démarrage de `wazuh-agent.service`** | Erreur de syntaxe XML dans `ossec.conf` (balise fermante `</directories` incomplète ou BOM UTF-8). | Diagnostic via `/var/ossec/bin/wazuh-agentd -t` et `xmllint --noout`, correction de la structure XML et validation du service. |
| **Absence d'alertes FIM (`syscheck`) après modification** | Modifications effectuées avant la fin du premier scan d'inventaire de référence (*baseline*). | Vérification dans `/var/ossec/logs/ossec.log` de l'événement `Real-time file integrity monitoring started` avant de lancer les tests. |
| **Rejet Git `GH007: Your push would publish a private email`** | Protection de confidentialité GitHub rejetant l'adresse locale. | Configuration de l'adresse `@users.noreply.github.com` et réécriture de l'auteur via `git commit --amend --reset-author`. |

---

## 📁 5. Structure du Dépôt

```text
.
├── .gitignore
├── README.md                              # Documentation générale de l'architecture KVM & scénarios SOC
├── configs/
│   ├── debian/
│   │   └── devuser-find                   # Directive sudoers vulnérable (/usr/bin/find)
│   ├── debian-target/
│   │   └── agent-ossec.conf               # Configuration de l'agent Wazuh (192.168.122.3, FIM + logs Apache)
│   └── wazuh-server/                      # Répertoire destiné à la configuration du manager Wazuh
├── docs/
│   ├── ANALYSE_ET_FEUILLE_DE_ROUTE.md     # Rapport d'état du lab, méthodologie Purple Team, limites & roadmap
│   ├── README.md                          # Documentation de l'orchestrateur CLI `cyberlab-ctl`
│   ├── INSTALL.sh                         # Script d'installation et vérification des prérequis KVM/X11
│   ├── WRITE-UP                           # Write-up technique de l'industrialisation KVM/Libvirt
│   ├── RETEX                              # Synthèse du retour d'expérience (SSH, Zsh, FIPS, Bash)
│   ├── alerts-json/                       # Répertoire destiné aux extraits JSON d'alertes Wazuh
│   └── screenshots/                       # Répertoire destiné aux captures d'écran du lab
└── scripts/
    ├── defensive/                         # Répertoire destiné aux scripts de test FIM / Blue Team
    └── offensive/                         # Répertoire destiné aux scripts d'attaque Red Team
```
