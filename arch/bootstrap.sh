#!/usr/bin/env bash
# ======================================================================
# Arch Linux Bootstrap (nuc-bootstrap)
# Safe-ish to re-run (pacman handles existing packages).
# ======================================================================
set -Eeuo pipefail
IFS=$'\n\t'

log()  { printf "\033[1;32m[✔]\033[0m %s\n" "$*"; }
info() { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }

require_root_or_sudo() {
  if [[ $EUID -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || { err "sudo missing"; exit 1; }
    sudo -v || { err "sudo auth failed"; exit 1; }
  fi
}
require_root_or_sudo

# Pacman sanity
sudo pacman -Sy --noconfirm --needed base-devel git curl wget unzip zip neovim zsh openssh xclip python-pipx
python -m pipx ensurepath || true

# Default shell → zsh
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

# Docker (pacman)
if ! command -v docker >/dev/null 2>&1; then
  sudo pacman -S --noconfirm --needed docker docker-buildx docker-compose
  sudo systemctl enable --now docker
  sudo usermod -aG docker "$USER" || true
  info "Docker: $(docker --version)"; docker compose version || true
fi

# VS Code (oss variant: code) via community repo
if ! command -v code >/dev/null 2>&1; then
  # You can choose: 'code' (vscodium) or 'visual-studio-code-bin' via AUR.
  sudo pacman -S --noconfirm --needed code || warn "Install 'code' failed (try VSCodium or AUR)"
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

log "Arch bootstrap complete."
