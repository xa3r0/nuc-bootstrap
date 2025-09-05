#!/usr/bin/env bash
# ======================================================================
# Debian dev-packages (nuc-bootstrap)
# Installs packages by category: Eye Candy, Utilities, Support, Dev.
# Idempotent; uses apt-get, avoids recommends.
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
    command -v sudo >/dev/null 2>&1 || { err "sudo missing"; exit 1; }
    sudo -v || { err "sudo auth failed"; exit 1; }
  fi
}

update_indexes() { sudo apt-get update -y; }

pkg_install() {
  # usage: pkg_install pkg1 pkg2 ...
  sudo apt-get install -y --no-install-recommends "$@"
}

# ----------------- Package sets -----------------
EYE_CANDY=(fonts-firacode gnome-tweaks gnome-shell-extension-manager bat eza neofetch)
UTILS=(htop btop curl wget ca-certificates gnupg unzip zip xz-utils tree ripgrep jq xclip fzf tmux)
SUPPORT=(build-essential pkg-config lsb-release software-properties-common apt-transport-https neovim flatpak gnome-software-plugin-flatpak)
DEV=(git git-lfs zsh python3 python3-venv python3-pip pipx openjdk-21-jdk golang rustup direnv shellcheck clang cmake)

install_vscode_optional() {
  if command -v code >/dev/null 2>&1; then
    return 0
  fi
  info "Adding VS Code repository (optional)…"
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg >/dev/null
  echo "deb [arch=$(dpkg --print-architecture)] https://packages.microsoft.com/repos/code stable main" \
    | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
  update_indexes
  pkg_install code || warn "VS Code install failed; consider VSCodium"
}

post_steps() {
  # pipx path
  python3 -m pipx ensurepath || true

  # rustup (user-space)
  if ! command -v rustc >/dev/null 2>&1; then
    info "Installing Rust via rustup for ${SUDO_USER:-$USER}"
    if [[ -n "${SUDO_USER:-}" ]]; then
      su - "${SUDO_USER}" -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
    else
      curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    fi
  fi

  # Node via NVM (if not done in bootstrap)
  if ! command -v node >/dev/null 2>&1; then
    info "Installing Node via NVM for ${SUDO_USER:-$USER}"
    if [[ -n "${SUDO_USER:-}" ]]; then
      su - "${SUDO_USER}" -c '
        set -e
        if [ ! -d "$HOME/.nvm" ]; then
          curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        fi
        export NVM_DIR="$HOME/.nvm"
        . "$NVM_DIR/nvm.sh"
        nvm install --lts
        nvm alias default "lts/*"
      '
    else
      if [[ ! -d "$HOME/.nvm" ]]; then
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
      fi
      export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"
      nvm install --lts && nvm alias default "lts/*"
    fi
  fi
}

main() {
  require_sudo
  update_indexes

  info "Installing Eye Candy…"
  pkg_install "${EYE_CANDY[@]}"

  info "Installing Utilities…"
  pkg_install "${UTILS[@]}"

  info "Installing Support…"
  pkg_install "${SUPPORT[@]}"

  info "Installing Dev stack…"
  pkg_install "${DEV[@]}"

  install_vscode_optional || true
  post_steps

  log "Debian dev-packages complete."
  info "Tip: If bootstrap just added you to the 'docker' group, run: newgrp docker  # or log out/in"
}

main "$@"
