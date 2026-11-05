#!/usr/bin/env bash
set -e

# Couleurs pour l'affichage
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Installation de CyberLab Controller ===${NC}\n"

# 1. Vérification des dépendances système
echo -e "${BLUE}[1/4] Vérification des paquets requis sur l'hôte...${NC}"

REQUIRED_PKGS=()
[ ! -x "$(command -v virt-viewer)" ] && REQUIRED_PKGS+=("virt-viewer")
[ ! -x "$(command -v xdpyinfo)" ]    && REQUIRED_PKGS+=("x11-utils")

if [ ${#REQUIRED_PKGS[@]} -gt 0 ]; then
  echo -e "${YELLOW}[!] Paquets manquants détectés : ${REQUIRED_PKGS[*]}${NC}"
  if command -v apt-get &>/dev/null; then
    echo "[*] Installation via apt..."
    sudo apt-get update && sudo apt-get install -y "${REQUIRED_PKGS[@]}"
  elif command -v dnf &>/dev/null; then
    echo "[*] Installation via dnf..."
    # x11-utils équivaut à xorg-x11-utils sur Fedora/RHEL
    sudo dnf install -y virt-viewer xorg-x11-utils
  else
    echo -e "${RED}[X] Gestionnaire de paquets inconnu. Veuillez installer manuellement : ${REQUIRED_PKGS[*]}${NC}"
  fi
else
  echo -e "${GREEN}[✓] Toutes les dépendances logicielles sont déjà présentes.${NC}"
fi

# 2. Vérification de l'accès à Libvirt
echo -e "\n${BLUE}[2/4] Vérification du groupe libvirt...${NC}"
if groups "$USER" | grep -Eq '\b(libvirt|kvm)\b'; then
  echo -e "${GREEN}[✓] L'utilisateur $USER appartient bien au groupe libvirt/kvm.${NC}"
else
  echo -e "${YELLOW}[!] Attention : Votre utilisateur n'est pas dans le groupe libvirt.${NC}"
  echo "    Vous pouvez l'ajouter avec : sudo usermod -aG libvirt,kvm $USER"
fi

# 3. Déploiement de l'exécutable
echo -e "\n${BLUE}[3/4] Déploiement de l'exécutable dans ~/.local/bin...${NC}"
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

SCRIPT_SRC="$(dirname "$0")/bin/cyberlab"

# Si le fichier est directement à la racine ou dans bin/
if [ -f "$SCRIPT_SRC" ]; then
  cp "$SCRIPT_SRC" "$INSTALL_DIR/cyberlab"
elif [ -f "$(dirname "$0")/cyberlab" ]; then
  cp "$(dirname "$0")/cyberlab" "$INSTALL_DIR/cyberlab"
else
  echo -e "${RED}[X] Erreur : Impossible de trouver le binaire 'cyberlab' dans le dossier courant.${NC}"
  exit 1
fi

chmod +x "$INSTALL_DIR/cyberlab"
echo -e "${GREEN}[✓] Binaire installé avec succès : $INSTALL_DIR/cyberlab${NC}"

# 4. Vérification du PATH
echo -e "\n${BLUE}[4/4] Vérification de la variable PATH...${NC}"
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  echo -e "${YELLOW}[!] ~/.local/bin n'est pas présent dans votre variable PATH.${NC}"
  
  SHELL_RC="$HOME/.bashrc"
  [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.zshrc"
  
  echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
  echo -e "${GREEN}[✓] Ajouté automatiquement à $SHELL_RC.${NC}"
  echo -e "${YELLOW}    Exécutez 'source $SHELL_RC' pour rafraîchir votre terminal actuel.${NC}"
else
  echo -e "${GREEN}[✓] ~/.local/bin est déjà présent dans le PATH.${NC}"
fi

echo -e "\n${GREEN}=== Installation terminée avec succès ! ===${NC}"
echo "Essayez dès maintenant :"
echo "  cyberlab status"
