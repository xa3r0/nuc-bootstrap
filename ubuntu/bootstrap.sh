#!/usr/bin/env bash
# ======================================================================
# Ubuntu Bootstrap (nuc-bootstrap)
# Safe to re-run; idempotent where possible.
# Maintainer: xa3r0 (Janardhan) | Repo: xa3r0/nuc-bootstrap
# Tested on: Ubuntu 22.04 / 24.04
# ======================================================================
set -euo pipefail
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

require_ubuntu(){
  if ! command -v lsb_release >/dev/null 2>&1; then err "lsb_release missing"; exit 1; fi
  local dist ver; dist=$(lsb_release -is); ver=$(lsb_release -rs)
  [[ "$dist" == "Ubuntu" ]] || { err "Detected $dist (not Ubuntu)"; exit 1; }
  info "Detected $dist $ver"
}

noninteractive(){ export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a; }

ensure_nala(){
  if ! command -v nala >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y nala
  else
    info "nala already present"
  fi
}

sys_update(){
  info "System update with nala"
  nala update || sudo apt-get update
  nala upgrade -y || sudo apt-get dist-upgrade -y
}

remove_bad_nodesource(){
  # Remove broken NodeSource 22.x noble entry if present
  if [[ -f /etc/apt/sources.list.d/nodesource.list ]] && \
     grep -q 'deb\.nodesource\.com.*node_22\.x.*noble' /etc/apt/sources.list.d/nodesource.list; then
    warn "Removing broken NodeSource node_22.x repo for noble"
    sudo rm -f /etc/apt/sources.list.d/nodesource.list
    sudo rm -f /etc/apt/keyrings/nodesource.gpg || true
    nala update || sudo apt-get update
  fi
}

base_tools(){
  info "Installing base desktop + CLI tools"
  nala install -y \
    gdebi-core htop btop neofetch \
    gnome-tweaks gnome-shell-extension-manager \
    curl wget ca-certificates gnupg \
    unzip zip xz-utils tree jq ripgrep \
    software-properties-common apt-transport-https ufw
}

dev_stack(){
  info "Installing dev stack (build-essential, git, zsh, Python, pipx, Java 21)"
  nala install -y \
    build-essential git zsh \
    python3 python3-pip python3-venv pipx \
    openjdk-21-jdk neovim fonts-firacode xclip
  # pipx path for invoking user
  if [[ -n "${SUDO_USER:-}" ]]; then
    su - "${SUDO_USER}" -c 'python3 -m pipx ensurepath' || true
  fi
  # default shell → zsh (non-fatal if it fails)
  if [[ -n "${SUDO_USER:-}" ]]; then
    chsh -s "$(command -v zsh)" "${SUDO_USER}" || true
  fi
}

node_via_nvm(){
  # Install NVM + Node (22 or LTS) for invoking user
  [[ -n "${SUDO_USER:-}" ]] || { warn "No SUDO_USER; skipping NVM"; return 0; }
  info "Installing Node via NVM for ${SUDO_USER}"
  su - "${SUDO_USER}" -c '
    set -e
    if [ ! -d "$HOME/.nvm" ]; then
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    fi
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh"
    # Choose: 22 (your original choice) or LTS
    nvm install 22
    nvm alias default 22
    echo "Node: $(node -v) | npm: $(npm -v)"
  '
}

docker_setup(){
  info "Installing Docker Engine + Compose"
  # remove distro docker if present
  nala remove -y docker docker-engine docker.io containerd runc || true

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  nala update
  nala install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable --now docker

  # add invoking user to docker group
  if [[ -n "${SUDO_USER:-}" ]]; then
    sudo usermod -aG docker "${SUDO_USER}" || true
    info "If 'docker' group was just added, run: newgrp docker  # or log out/in"
  fi
}

flatpak_setup(){
  info "Enabling Flatpak + Flathub"
  nala install -y flatpak
  nala install -y gnome-software-plugin-flatpak || true
  if ! flatpak remotes --columns=name | grep -q '^flathub$'; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
}

hardening(){
  info "UFW + unattended-upgrades"
  nala install -y ufw unattended-upgrades
  sudo ufw --force enable
  sudo ufw allow OpenSSH || true
  sudo dpkg-reconfigure -f noninteractive unattended-upgrades || true
}

qol_shell(){
  info "QoL zsh aliases + neofetch"
  if [[ -n "${SUDO_USER:-}" ]]; then
    UHOME=$(eval echo "~${SUDO_USER}")
    if ! grep -q "forge-qol-aliases" "$UHOME/.zshrc" 2>/dev/null; then
      cat >> "$UHOME/.zshrc" <<'EOF'
# forge-qol-aliases
alias ll="ls -alh"
alias grep="grep --color=auto"
# show neofetch on interactive login
if [[ $- == *i* ]] && command -v neofetch >/dev/null 2>&1; then neofetch; fi
EOF
      sudo chown "${SUDO_USER}:${SUDO_USER}" "$UHOME/.zshrc"
    fi
  fi
}

vscode_repo_optional(){
  # Optional: enable VS Code repo (skip if you prefer VSCodium)
  if ! command -v code >/dev/null 2>&1; then
    info "Adding VS Code repo…"
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg >/dev/null
    sudo add-apt-repository -y "deb [arch=$(dpkg --print-architecture)] https://packages.microsoft.com/repos/code stable main"
    nala update && nala install -y code || warn "VS Code install failed"
  fi
}

hook_common(){
  # Pull in nuc-bootstrap/common if present
  if [[ -d "$(dirname "$0")/../common" ]]; then
    local COMMON_DIR; COMMON_DIR="$(cd "$(dirname "$0")/../common" && pwd)"
    if [[ -f "$COMMON_DIR/aliases.zsh" ]] && ! grep -q "nuc-bootstrap aliases" "$HOME/.zshrc" 2>/dev/null; then
      {
        echo ""
        echo "# nuc-bootstrap aliases"
        echo "source '$COMMON_DIR/aliases.zsh'"
      } >> "$HOME/.zshrc"
      info "Added common aliases to ~/.zshrc"
    fi
    [[ -f "$COMMON_DIR/dotfiles-setup.sh" ]] && bash "$COMMON_DIR/dotfiles-setup.sh" || true
  fi
}

summary(){
  echo
  echo "============================================"
  echo "NUC Bootstrap (Ubuntu) - done"
  echo "What you got:"
  echo "- System updated (nala), base tools & GNOME tweaks"
  echo "- Dev toolchain: Git, Zsh, Python, pipx, Java 21"
  echo "- Node 22 via NVM for ${SUDO_USER:-your user}"
  echo "- Docker Engine + Compose (user in 'docker' group)"
  echo "- Flatpak + Flathub"
  echo "- UFW enabled + unattended-upgrades"
  echo "- Common/ aliases + dotfiles (if present)"
  echo
  echo "Next:"
  echo "- Open a new terminal to load NVM defaults"
  echo "- Run: newgrp docker  # or log out/in for docker group"
  echo "============================================"
}

main(){
  require_sudo
  require_ubuntu
  noninteractive
  ensure_nala
  sys_update
  remove_bad_nodesource
  base_tools
  dev_stack
  node_via_nvm
  docker_setup
  flatpak_setup
  hardening
  qol_shell
  vscode_repo_optional
  hook_common
  summary
}

main "$@"
