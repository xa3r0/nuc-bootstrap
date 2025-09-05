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

# JD Minimal Zsh config repo (change if your URL differs)
JD_ZSH_REPO="https://github.com/xa3r0/jd-minimal-zsh.git"

install_jd_minimal_zsh() {
  local target_user="${SUDO_USER:-$USER}"
  local target_home; target_home=$(eval echo "~${target_user}")
  local zdir="${target_home}/.config/jd-minimal-zsh"
  local zsrc_line='[ -f "$HOME/.config/jd-minimal-zsh/minimal.zsh" ] && source "$HOME/.config/jd-minimal-zsh/minimal.zsh"'

  info "Installing jd-minimal-zsh for ${target_user}…"

  if [[ -d "$zdir/.git" ]]; then
    sudo -u "$target_user" -H git -C "$zdir" pull --ff-only
  else
    sudo -u "$target_user" -H mkdir -p "$target_home/.config"
    sudo -u "$target_user" -H git clone "$JD_ZSH_REPO" "$zdir"
  fi

  # If repo has its own installer, run it
  if [[ -f "$zdir/install.sh" ]]; then
    sudo -u "$target_user" -H bash "$zdir/install.sh" || warn "jd-minimal-zsh install.sh returned non-zero"
  fi

  # Ensure it's sourced in .zshrc
  local zrc="$target_home/.zshrc"
  if ! grep -Fq "jd-minimal-zsh/minimal.zsh" "$zrc" 2>/dev/null; then
    {
      echo ""
      echo "# jd-minimal-zsh"
      echo "$zsrc_line"
    } | sudo tee -a "$zrc" >/dev/null
    sudo chown "$target_user":"$target_user" "$zrc" || true
    info "jd-minimal-zsh sourced in $zrc"
  else
    info "jd-minimal-zsh already sourced in $zrc"
  fi
}

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
  install_jd_minimal_zsh || true
  post_steps

  log "Debian dev-packages complete."
  info "Tip: If bootstrap just added you to the 'docker' group, run: newgrp docker  # or log out/in"
}

main "$@"
