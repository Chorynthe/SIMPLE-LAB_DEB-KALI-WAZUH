Ce projet documente la mise en place d'un environnement complet de détection et de réponse aux incidents (SIEM / SOC) sous **VirtualBox**, ainsi que l'émulation d'attaques réalistes, leur détection en temps réel et la réponse active.

---

## 🌐 1. Architecture Réseau (LabNet : `192.168.100.0/24`)

L'environnement est isolé sur un réseau interne (*Internal Network*) VirtualBox :

| Rôle | Système | IP | Description |
| :--- | :--- | :--- | :--- |
| **SOC / SIEM** | Wazuh Appliance 4.x | `192.168.100.2` | Collecte des événements, moteur d'analyse, corrélation et dashboard OpenSearch |
| **Attaquant** | Kali Linux | `192.168.100.10` | Outils offensifs : Nmap, Hydra, curl, GTFOBins |
| **Cible / Défense** | Debian 12 (x86_64) | `192.168.100.20` | Agent Wazuh, service SSH, Apache/PHP vulnérable (SQLi/LFI) |

---

## 🎯 2. Scénarios Réalisés & Détections SOC

### A. Reconnaissance & Force Brute SSH
* **Vecteur :** Scan de ports avec Nmap, suivi d'une attaque par dictionnaire avec Hydra sur le compte `devuser`.
* **Détection SOC :**
  * Règles d'authentification SSH (échecs répétés, PAM login failed).
  * Alignement de conformité réglementaire : **PCI DSS 10.2.4 & 10.2.5**.
* **Réponse active (Active Response) :**
  * Déclenchement automatique de la commande `firewall-drop` bannissant temporairement l'IP attaquante au niveau d'`iptables/nftables`.

### B. Élévation de Privilèges via Mauvaise Configuration Sudo
* **Vecteur :** Exploitation d'une permission `sudo` mal restreinte sur `/usr/bin/find` (technique GTFOBins) pour obtenir un shell root :
  ```bash
  sudo /usr/bin/find . -exec /bin/sh \; -quit
Détection SOC :Alerte Rule ID 5402 (Successful sudo to ROOT executed).Cartographie MITRE ATT&CK : T1548.003 (Abuse Elevation Control Mechanism: Sudo and Sudo Caching).C. Surveillance d'Intégrité de Fichiers (FIM / Syscheck)Configuration : Activation du monitoring en temps réel (realtime="yes") via les appels noyau inotify et calcul des différentiels (report_changes="yes").Vecteur : Création d'une persistance via /etc/cron.d/malicious_job et altération de /etc/passwd.Détection SOC :Rule ID 554 : Détection de l'ajout d'un nouveau fichier suspect.Rule ID 550 : Détection de modification avec restitution du différentiel textuel injecté (syscheck.diff).Méthodologie d'investigation : Approche Threat Hunting sans connaître le nom de fichier au préalable (filtrage par groupe de règles et jokers syscheck.path: /etc/*).D. Audit Applicatif Web (En cours / À venir)Déploiement d'une page PHP vulnérable aux injections SQL et traversées de répertoires (Directory Traversal / LFI).Ingestion des journaux /var/log/apache2/access.log et /var/log/apache2/error.log par l'agent Wazuh.🛠️ 3. Dépannage Système & Réseau (Troubleshooting)Problème rencontréCauseSolution appliquéeVirtualBox rc=-1908Incompatibilité de compilation des modules sur noyau Linux expérimentalDémarrage sur noyau stable (6.8.x) via GRUB et recompilation via /sbin/vboxconfigBlocage invite grub>Menu GRUB masqué par défautUtilisation de normal puis modification permanente de /etc/default/grub (TIMEOUT_STYLE=menu)CPU i686 détecté sur DebianProfil VM créé par défaut en architecture 32 bitsBascule du type d'OS de la VM vers Debian (64-bit) dans la configuration VirtualBoxGel complet de Kali (souris/clavier)Conflit d'Additions Invité VirtualBox préinstalléesRéinitialisation de la VM, éjection de l'ISO et réparation via dpkg --configure -aPorts fermés au scan NmapDémon SSH non installé sur la machine cibleInstallation d'openssh-server et activation via systemctl enable --now sshPerte des adresses IP au rebootUtilisation temporaire de ip addr add sans persistanceConfiguration dans les fichiers statiques (interfaces, systemd-networkd, nmcli)Crash de wazuh-agent.serviceErreur de syntaxe XML dans ossec.conf (balise fermante </directories incomplète)Localisation via nano -l et validation de la structure avant redémarrage du démonAbsence d'alertes FIM à l'initialisationModifications effectuées avant la fin de l'inventaire initial (baseline)Analyse des logs ossec.log pour attendre le signal Real-time file integrity monitoring started📁 4. Structure du DépôtPlaintext.
├── README.md
├── configs/
│   ├── debian-target/       # ossec.conf (agent), configuration Apache
│   └── wazuh-server/        # ossec.conf (manager, active-response)
├── scripts/
│   ├── offensive/           # Scripts d'automatisation des attaques (Hydra, curl)
│   └── defensive/           # Scripts de déploiement et durcissement
└── docs/                    # Captures d'écran et extraits d'alertes JSON réelles
