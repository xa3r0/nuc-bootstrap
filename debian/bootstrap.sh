#!/usr/bin/env bash
# ======================================================================
# Debian Bootstrap (nuc-bootstrap)
# Safe to re-run; skips steps if already completed.
# Maintainer: xa3r0 (Janardhan) | Repo: xa3r0/nuc-bootstrap
# Tested on: Debian 12 (bookworm), 13 (trixie)
# ======================================================================
set -Eeuo pipefail
IFS=$'\n\t'

log()  { printf "\033[1;32m[✔]\033[0m %s\n" "$*"; }
info() { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }

require_sudo() {
  if [[ $EUID -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
      err "sudo not found; install sudo first (login as root: apt update && apt install -y sudo)"
      exit 1
    fi
    sudo -v || { err "sudo auth failed"; exit 1; }
  fi
}

require_sudo

sudo apt-get update -y
sudo apt-get install -y --no-install-recommends       ca-certificates apt-transport-https gnupg lsb-release software-properties-common

# --- Essentials
sudo apt-get install -y --no-install-recommends       zsh git curl wget unzip zip build-essential pkg-config       python3 python3-venv python3-pip pipx       openssh-client xclip neovim       fonts-firacode

# Ensure pipx path
python3 -m pipx ensurepath || true

# Set zsh default if not already
if [[ "$SHELL" != *"zsh" ]]; then
  chsh -s "$(command -v zsh)" "$USER" || warn "Could not change shell; run: chsh -s $(which zsh)"
fi

# --- NodeJS via nvm (Debian-friendly)
if ! command -v node >/dev/null 2>&1; then
  info "Installing Node via nvm…"
  if [[ ! -d "$HOME/.nvm" ]]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm alias default 'lts/*'
  info "Node: $(node -v) | npm: $(npm -v)"
else
  info "Node present: $(node -v)"
fi

# --- Docker (official repo for Debian)
if ! command -v docker >/dev/null 2>&1; then
  info "Installing Docker Engine…"
  . /etc/os-release
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo         "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian         ${VERSION_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER" || true
  info "Docker: $(docker --version)"
  info "Docker Compose: $(docker compose version)"
else
  info "Docker present: $(docker --version)"
fi

# --- VS Code on Debian (Microsoft repo)
if ! command -v code >/dev/null 2>&1; then
  info "Adding VS Code repository…"
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg >/dev/null
  echo "deb [arch=$(dpkg --print-architecture)] https://packages.microsoft.com/repos/code stable main" |         sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y code || warn "VS Code install failed"
fi

# --- Pull in common pieces if present
if [[ -d "$(dirname "$0")/../common" ]]; then
  COMMON_DIR="$(cd "$(dirname "$0")/../common" && pwd)"
  if [[ -f "$COMMON_DIR/aliases.zsh" ]] && ! grep -q "nuc-bootstrap aliases" "$HOME/.zshrc" 2>/dev/null; then
    {
      echo ""
      echo "# nuc-bootstrap aliases"
      echo "source '$COMMON_DIR/aliases.zsh'"
    } >> "$HOME/.zshrc"
    info "Added nuc-bootstrap aliases to ~/.zshrc"
  fi
  if [[ -f "$COMMON_DIR/dotfiles-setup.sh" ]]; then
    bash "$COMMON_DIR/dotfiles-setup.sh" || warn "dotfiles-setup.sh returned non-zero"
  fi
fi

log "Debian bootstrap finished."
