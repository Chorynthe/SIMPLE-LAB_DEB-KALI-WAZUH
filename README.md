# 🛡️ VirtualBox Cyber Range : Lab SOC Wazuh & Simulation d'Attaques

Ce projet documente la conception, le déploiement et l'exploitation d'un environnement de détection et de réponse aux incidents (SIEM / SOC) entièrement virtualisé sous **Oracle VirtualBox**. 

L'objectif est d'émuler des attaques réelles (reconnaissance, force brute, élévation de privilèges, persistance, altération d'intégrité et attaques web), d'observer leur détection en temps réel au sein d'un SIEM et de configurer des mécanismes de remédiation automatique (*Active Response*).

---

## 🌐 1. Architecture Réseau & Rôles des Machines

L'ensemble de l'environnement évolue sur un réseau interne isolé VirtualBox nommé **`LabNet`** sur le plan d'adressage **`192.168.100.0/24`**.

```text
       +-------------------------------------------------------+
       |               Réseau Isolé : LabNet                   |
       |                 192.168.100.0/24                      |
       +-------------------------------------------------------+
              |                            |                 |
              |                            |                 |
     +-----------------+          +-----------------+        |
     |   Kali Linux    |          |  Debian Target  |        |
     | 192.168.100.10  |          | 192.168.100.20  |        |
     |  [Attaquant]    |          |    [Cible]      |        |
     +-----------------+          +-----------------+        |
              |                            |                 |
              |--- (Attaques SSH, Web) --->|                 |
                                           |                 |
                                    [Agent Wazuh]            |
                                           |                 |
                                   (Logs & Alertes)          |
                                           v                 v
                                  +----------------------------+
                                  |    Wazuh Server / SIEM     |
                                  |      192.168.100.2         |
                                  |      [SOC Analyste]        |
                                  +----------------------------+
```

### Inventaire des Nœuds

| Rôle | Système d'exploitation | Adresse IP | Description & Services |
| :--- | :--- | :--- | :--- |
| **SOC / SIEM** | Wazuh Appliance (v4.x) | `192.168.100.2` | Serveur Wazuh, moteur d'analyse et de corrélation, dashboard OpenSearch, indexeur d'alertes |
| **Attaquant** | Kali Linux (x86_64) | `192.168.100.10` | Nmap, Hydra, curl, scripts d'exploitation GTFOBins |
| **Cible (Défense)** | Debian 12 (x86_64) | `192.168.100.20` | Agent Wazuh 4.x, OpenSSH Server, serveur web Apache/PHP avec endpoint vulnérable |

---

## 🎯 2. Scénarios d'Attaque & Détections SOC

### A. Reconnaissance Réseau & Force Brute SSH
* **Vecteur d'attaque :**
  1. Cartographie des ports et services via `nmap -sV -p- 192.168.100.20`.
  2. Attaque par dictionnaire sur le service SSH ciblant le compte `devuser` via Hydra.
* **Télémétrie & Détection Wazuh :**
  * Ingestion des logs `/var/log/auth.log`.
  * Déclenchement des alertes :
    * **Règle ID 5710 :** `sshd: Attempt to login using a non-existent user`.
    * **Règle ID 5716 :** `sshd: authentication failed`.
    * **Règle ID 5720 :** `Multiple failed logins from a single host` (Niveau de sévérité 10).
  * **Conformité réglementaire :** Mappé sur les exigences **PCI DSS 10.2.4 & 10.2.5** (surveillance des échecs d'authentification).
* **Réponse Active (*Active Response*) :**
  * Déclenchement automatique du script `firewall-drop` paramétré sur les règles 5712 et 5720.
  * Blocage temporaire de l'IP source de Kali (`192.168.100.10`) via `iptables/nftables` avec un timeout de 180 secondes.

---

### B. Élévation de Privilèges via Mauvaise Configuration Sudo (GTFOBins)
* **Vecteur d'attaque :**
  * Compromission préalable du compte `devuser`.
  * Découverte d'une directive permissive dans le fichier sudoers : `devuser ALL=(ALL) NOPASSWD: /usr/bin/find`.
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
  * Modification de `/var/ossec/etc/ossec.conf` sur l'agent pour activer l'analyse en temps réel (*inotify*) et le reporting de diff :
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
  * Collecte continue de `/var/log/apache2/access.log` et `/var/log/apache2/error.log` via les balises `<localfile>` de type `apache`.
* **Attaques & Détections :**
  * Détection d'injections SQL (Règles 31103 / 31106).
  * Détection de tentatives de traversée de répertoires (Règle 31101).

---

## 🛠️ 3. Résolution des Pannes Systèmes & Réseau (Troubleshooting)

Ce lab a nécessité la résolution de plusieurs contraintes matérielles, de virtualisation, de noyau et de syntaxe :

| Problème / Symptôme | Cause Racine | Solution Appliquée |
| :--- | :--- | :--- |
| **Erreur VirtualBox rc=-1908 (`vboxdrv` non chargé)** | Conflit de symboles lors de la compilation des modules sur le noyau Linux expérimental hôte (`7.0.0-31-generic`). | Démarrage sur le noyau Linux stable (`6.8.0-139-generic`) via GRUB et recompilation réussie via `/sbin/vboxconfig`. |
| **Blocage dans l'invite `grub>`** | Menu de démarrage masqué par défaut ou temps d'affichage nul. | Boot manuel avec la commande `normal`, puis configuration permanente dans `/etc/default/grub` (`TIMEOUT_STYLE=menu`, `TIMEOUT=10`) suivi de `update-grub`. |
| **Erreur « requires x86-64 CPU, detected i686 » (Debian)** | La VM avait été provisionnée avec le profil 32 bits par défaut de VirtualBox. | Modification des paramètres généraux de la machine virtuelle : sélection du profil `Debian (64-bit)`. |
| **Écran noir / gel graphique au boot de Kali (OVA)** | Conflits de mémoire vidéo et mauvaise détection du pilote graphique invité. | Passage du contrôleur d'affichage sur `VMSVGA`, désactivation de l'accélération 3D et allocation de 128 Mo de VRAM. |
| **Gel complet de l'interface de Kali (souris/clavier)** | Conflit entre les paquets préinstallés et l'installateur générique du CD VirtualBox Guest Additions. | Réinitialisation matérielle (Reset), éjection de l'image ISO et réparation des paquets via `dpkg --configure -a`. |
| **Ports fermés au scan Nmap (`1000 closed ports`)** | Le démon SSH n'était pas présent sur l'installation minimale Debian. | Installation et activation du paquet : `apt install openssh-server && systemctl enable --now ssh`. |
| **Destination Host Unreachable / Conflits réseau** | Faute de frappe sur l'IP cible et conflit de routage entre eth0 (Host-Only) et le réseau interne. | Migration intégrale du lab sur un plan d'adressage unifié et dédié : `192.168.100.0/24`. |
| **Perte des adresses IP après redémarrage des VM** | Assignations temporaires via `ip addr add` volatiles en mémoire. | Configuration statique dans les fichiers de configuration système respectifs : `/etc/network/interfaces` (Debian), `systemd-networkd` (Wazuh) et `NetworkManager / nmcli` (Kali). |
| **Échec au démarrage de `wazuh-agent.service`** | Erreur de syntaxe XML dans `ossec.conf` (balise fermante `</directories` sans chevron `>` et ligne tronquée en doublon). | Diagnostic via `wazuh-agentd -t` et `nano -l`, nettoyage de la structure XML et validation du redémarrage du service. |
| **Absence d'alertes FIM (`syscheck`) après modification** | Les modifications ont eu lieu avant la complétion de la première analyse d'inventaire de référence (*baseline*). | Analyse du journal `/var/ossec/logs/ossec.log`, attente de l'événement `Real-time file integrity monitoring started`, puis déclenchement des tests. |
| **Rejet Git `GH007: Your push would publish a private email`** | Protection de confidentialité activée sur le compte GitHub rejetant l'adresse locale. | Configuration de l'e-mail `users.noreply.github.com`, réécriture de l'auteur via `git commit --amend --reset-author` et persistance du token via `credential.helper store`. |

---

## 📁 4. Structure du Dépôt

```text
.
├── .gitignore
├── README.md
├── configs/
│   ├── debian-target/
│   │   ├── ossec.conf               # Configuration de l'agent (FIM temps réel + logs Apache)
│   │   ├── sudoers-devuser          # Règle sudo vulnérable (/usr/bin/find)
│   │   └── vuln.php                 # Page PHP vulnérable aux injections SQL / LFI
│   └── wazuh-server/
│       └── ossec.conf               # Configuration du manager (Active Response firewall-drop)
├── scripts/
│   ├── offensive/
│   │   ├── ssh_bruteforce.sh        # Attaque par dictionnaire automatisée avec Hydra
│   │   ├── privesc_gtfobins.sh      # Commande d'évasion root via find
│   │   └── web_attacks.sh           # Payloads curl (SQLi, Directory Traversal)
│   └── defensive/
│       └── test_fim.sh              # Script de test de génération d'alertes d'intégrité
└── docs/
    └── alerts-json/                 # Extraits JSON bruts d'alertes Wazuh (Règles 5402, 550, 554, 5720)
```

---

## 🧠 Compétences Démontrées

* **Blue Team / Analyse SOC :** Déploiement et administration d'un SIEM (Wazuh), configuration de la réponse active, corrélation d'événements multi-sources, surveillance d'intégrité (FIM), utilisation des frameworks **MITRE ATT&CK** et **PCI DSS**.
* **Red Team / Pentest :** Reconnaissance réseau (Nmap), attaques par force brute (Hydra), élévation de privilèges Linux (GTFOBins), techniques de persistance système, exploitation applicative (SQLi, LFI).
* **Administration Systèmes & Réseaux :** Dépannage avancé de l'hyperviseur Linux (Kernel, GRUB, modules DKMS), segmentation réseau, administration de services système (Systemd, Syslog, Apache), gestion de version et traçabilité avec Git.