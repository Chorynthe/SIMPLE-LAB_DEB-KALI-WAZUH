#!/usr/bin/env bash
set -e

# Output colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== CyberLab Controller Installer ===${NC}\n"

# 1. Check host system dependencies
echo -e "${BLUE}[1/4] Checking required packages on host...${NC}"

REQUIRED_PKGS=()
[ ! -x "$(command -v virt-viewer)" ] && REQUIRED_PKGS+=("virt-viewer")
[ ! -x "$(command -v xdpyinfo)" ]    && REQUIRED_PKGS+=("x11-utils")

if [ ${#REQUIRED_PKGS[@]} -gt 0 ]; then
  echo -e "${YELLOW}[!] Missing packages detected: ${REQUIRED_PKGS[*]}${NC}"
  if command -v apt-get &>/dev/null; then
    echo "[*] Installing via apt..."
    sudo apt-get update && sudo apt-get install -y "${REQUIRED_PKGS[@]}"
  elif command -v dnf &>/dev/null; then
    echo "[*] Installing via dnf..."
    # x11-utils corresponds to xorg-x11-utils on Fedora/RHEL
    sudo dnf install -y virt-viewer xorg-x11-utils
  else
    echo -e "${RED}[X] Unknown package manager. Please install manually: ${REQUIRED_PKGS[*]}${NC}"
  fi
else
  echo -e "${GREEN}[✓] All software dependencies are already installed.${NC}"
fi

# 2. Check Libvirt group membership
echo -e "\n${BLUE}[2/4] Checking libvirt/kvm group membership...${NC}"
if groups "$USER" | grep -Eq '\b(libvirt|kvm)\b'; then
  echo -e "${GREEN}[✓] User $USER belongs to the libvirt/kvm group.${NC}"
else
  echo -e "${YELLOW}[!] Warning: Your user is not a member of the libvirt group.${NC}"
  echo "    Add your user with: sudo usermod -aG libvirt,kvm $USER"
fi

# 3. Deploy executable
echo -e "\n${BLUE}[3/4] Deploying executable to ~/.local/bin...${NC}"
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

SCRIPT_SRC="$(dirname "$0")/bin/cyberlab"

# Look for binary in bin/ or current directory
if [ -f "$SCRIPT_SRC" ]; then
  cp "$SCRIPT_SRC" "$INSTALL_DIR/cyberlab"
elif [ -f "$(dirname "$0")/cyberlab" ]; then
  cp "$(dirname "$0")/cyberlab" "$INSTALL_DIR/cyberlab"
else
  echo -e "${RED}[X] Error: Could not find 'cyberlab' binary in current directory.${NC}"
  exit 1
fi

chmod +x "$INSTALL_DIR/cyberlab"
echo -e "${GREEN}[✓] Binary successfully installed: $INSTALL_DIR/cyberlab${NC}"

# 4. Verify PATH variable
echo -e "\n${BLUE}[4/4] Checking PATH environment variable...${NC}"
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  echo -e "${YELLOW}[!] ~/.local/bin is not in your PATH.${NC}"
  
  SHELL_RC="$HOME/.bashrc"
  [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.zshrc"
  
  echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
  echo -e "${GREEN}[✓] Automatically added to $SHELL_RC.${NC}"
  echo -e "${YELLOW}    Run 'source $SHELL_RC' to refresh your current terminal.${NC}"
else
  echo -e "${GREEN}[✓] ~/.local/bin is already in your PATH.${NC}"
fi

echo -e "\n${GREEN}=== Installation completed successfully! ===${NC}"
echo "Try it now:"
echo "  cyberlab status"
