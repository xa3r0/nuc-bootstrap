#!/usr/bin/env bash
# ======================================================================
# Kali Linux dev-packages (nuc-bootstrap)
# Categories: Eye Candy, Utilities, Support, Dev
# Uses apt-get; prefers VSCodium over VS Code.
# ======================================================================
set -Eeuo pipefail
IFS=$'\n\t'

log()  { printf "\033[1;32m[✔]\033[0m %s\n" "$*"; }
info() { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }

require_sudo() { if [[ $EUID -ne 0 ]]; then command -v sudo >/dev/null || { err "sudo missing"; exit 1; }; sudo -v || { err "sudo auth failed"; exit 1; }; fi; }
update_indexes() { sudo apt-get update -y; }
pkg_install() { sudo apt-get install -y --no-install-recommends "$@"; }

# ----------------- Package sets -----------------
EYE_CANDY=(fonts-firacode gnome-tweaks gnome-shell-extension-manager bat eza neofetch)
UTILS=(htop btop curl wget ca-certificates gnupg unzip zip xz-utils tree ripgrep jq xclip fzf tmux)
SUPPORT=(build-essential pkg-config lsb-release software-properties-common apt-transport-https neovim flatpak gnome-software-plugin-flatpak)
DEV=(git git-lfs zsh python3 python3-venv python3-pip pipx openjdk-21-jdk golang rustup direnv shellcheck clang cmake)

install_codium_optional() {
  # Try VSCodium if available in Kali repos; if not, recommend enabling the official VSCodium repo
  if command -v codium >/dev/null 2>&1; then return 0; fi
  info "Attempting to install VSCodium (preferred on Kali)…"
  if apt-cache policy codium | grep -q Candidate; then
    pkg_install codium || warn "codium install failed"
  else
    warn "codium not in current repos. Consider enabling VSCodium repo: https://vscodium.com/#install"
  fi
}

post_steps() {
  python3 -m pipx ensurepath || true
  if ! command -v rustc >/dev/null 2>&1; then
    info "Installing Rust via rustup for ${SUDO_USER:-$USER}"
    if [[ -n "${SUDO_USER:-}" ]]; then su - "${SUDO_USER}" -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
    else curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; fi
  fi
  if ! command -v node >/dev/null 2>&1; then
    info "Installing Node via NVM for ${SUDO_USER:-$USER}"
    if [[ -n "${SUDO_USER:-}" ]]; then
      su - "${SUDO_USER}" -c '
        set -e
        if [ ! -d "$HOME/.nvm" ]; then curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash; fi
        export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"
        nvm install --lts && nvm alias default "lts/*"
      '
    else
      [[ -d "$HOME/.nvm" ]] || curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
      export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"
      nvm install --lts && nvm alias default "lts/*"
    fi
  fi
}

main() {
  require_sudo
  update_indexes

  info "Installing Eye Candy…";   pkg_install "${EYE_CANDY[@]}"
  info "Installing Utilities…";   pkg_install "${UTILS[@]}"
  info "Installing Support…";     pkg_install "${SUPPORT[@]}"
  info "Installing Dev stack…";   pkg_install "${DEV[@]}"

  install_codium_optional || true
  post_steps

  log "Kali dev-packages complete."
}
main "$@"
