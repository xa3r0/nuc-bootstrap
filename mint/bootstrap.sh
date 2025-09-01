#!/usr/bin/env bash
# ======================================================================
# Linux Mint Bootstrap (nuc-bootstrap)
# Safe to re-run.
# Tested on: Mint 21/22 (based on Ubuntu)
# ======================================================================
set -Eeuo pipefail
IFS=$'\n\t'

log()  { printf "\033[1;32m[✔]\033[0m %s\n" "$*"; }
info() { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }

require_sudo() {
  if [[ $EUID -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || { err "sudo missing"; exit 1; }
    sudo -v || { err "sudo auth failed"; exit 1; }
  fi
}
require_sudo

sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  ca-certificates apt-transport-https gnupg lsb-release software-properties-common

sudo apt-get install -y --no-install-recommends \
  zsh git curl wget unzip zip build-essential pkg-config \
  python3 python3-venv python3-pip pipx \
  openssh-client xclip neovim fonts-firacode

python3 -m pipx ensurepath || true

if [[ "${SHELL:-}" != *"zsh" ]]; then
  chsh -s "$(command -v zsh)" "$USER" || warn "Could not chsh; run manually"
fi

# Node via nvm
if ! command -v node >/dev/null 2>&1; then
  info "Installing Node via nvm…"
  [[ -d "$HOME/.nvm" ]] || curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install --lts && nvm alias default 'lts/*'
  info "Node: $(node -v) | npm: $(npm -v)"
fi

# Docker (Ubuntu instructions work for Mint)
if ! command -v docker >/dev/null 2>&1; then
  info "Installing Docker Engine…"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(
  . /etc/os-release
  echo "$UBUNTU_CODENAME"
) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER" || true
  info "Docker: $(docker --version)"; docker compose version || true
fi

# VS Code (optional)
if ! command -v code >/dev/null 2>&1; then
  info "Adding VS Code repo…"
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg >/dev/null
  sudo add-apt-repository -y "deb [arch=$(dpkg --print-architecture)] https://packages.microsoft.com/repos/code stable main"
  sudo apt-get update -y && sudo apt-get install -y code || warn "VS Code install failed"
fi

# Hook common/
if [[ -d "$(dirname "$0")/../common" ]]; then
  COMMON_DIR="$(cd "$(dirname "$0")/../common" && pwd)"
  if [[ -f "$COMMON_DIR/aliases.zsh" ]] && ! grep -q "nuc-bootstrap aliases" "$HOME/.zshrc" 2>/dev/null; then
    {
      echo ""
      echo "# nuc-bootstrap aliases"
      echo "source '$COMMON_DIR/aliases.zsh'"
    } >> "$HOME/.zshrc"
    info "Added aliases to ~/.zshrc"
  fi
  [[ -f "$COMMON_DIR/dotfiles-setup.sh" ]] && bash "$COMMON_DIR/dotfiles-setup.sh" || true
fi

log "Linux Mint bootstrap complete."
