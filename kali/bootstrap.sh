#!/usr/bin/env bash
# ======================================================================
# Kali Linux Bootstrap (nuc-bootstrap)
# Safe to re-run. Kali-rolling is Debian-based but with its own repos.
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

# zsh default
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

# Docker: try official Debian repo; if it fails, fall back to distro docker.io
if ! command -v docker >/dev/null 2>&1; then
  info "Installing Docker Engine…"
  set +e
  . /etc/os-release
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${VERSION_CODENAME:-bookworm} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    warn "Docker official repo failed; installing docker.io from Kali/Debian"
    sudo apt-get install -y docker.io docker-compose-plugin || err "Docker install failed"
  fi
  sudo usermod -aG docker "$USER" || true
  info "Docker: $(docker --version)"; docker compose version || true
fi

# VS Code (optional; many prefer VSCodium on Kali)
if ! command -v code >/dev/null 2>&1; then
  warn "Skipping VS Code repo on Kali. Consider 'codium' (VSCodium):"
  warn "  sudo apt-get install -y codium   # if repo enabled"
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

log "Kali bootstrap complete."
