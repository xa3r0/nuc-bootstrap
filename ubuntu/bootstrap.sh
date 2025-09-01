#!/usr/bin/env bash
# ======================================================================
# Ubuntu Bootstrap (nuc-bootstrap)
# Safe to re-run; skips steps if already completed.
# Maintainer: xa3r0 (Janardhan) | Repo: xa3r0/nuc-bootstrap
# Tested on: Ubuntu 22.04, 24.04
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

# Optimize apt before we start
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends       ca-certificates apt-transport-https gnupg lsb-release software-properties-common

# --- Begin user-provided content ---
#!/usr/bin/env bash
set -euo pipefail

# NUC Bootstrap for Ubuntu 24.04 - desktop + dev + docker
# Run as root: sudo ./nuc-bootstrap.sh

log(){ printf "\n[+] %s\n" "$*"; }

require_ubuntu(){
  if ! command -v lsb_release >/dev/null 2>&1; then
    log "Ubuntu required"; exit 1
  fi
  local dist ver
  dist=$(lsb_release -is); ver=$(lsb_release -rs)
  if [ "$dist" != "Ubuntu" ]; then log "Detected $dist - abort"; exit 1; fi
  log "Detected $dist $ver"
}

noninteractive(){ export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a; }

ensure_nala(){
  if ! command -v nala >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y nala
  else
    log "nala already present"
  fi
}

sys_update(){
  log "System update with nala"
  nala update || apt-get update
  nala upgrade -y || apt-get dist-upgrade -y
}

remove_bad_nodesource(){
  # If the broken node_22.x noble entry exists, remove it
  if [ -f /etc/apt/sources.list.d/nodesource.list ]; then
    if grep -q 'deb\.nodesource\.com.*node_22\.x.*noble' /etc/apt/sources.list.d/nodesource.list; then
      log "Removing broken NodeSource node_22.x repo for noble"
      rm -f /etc/apt/sources.list.d/nodesource.list
      rm -f /etc/apt/keyrings/nodesource.gpg || true
      nala update || apt-get update
    fi
  fi
}

base_tools(){
  log "Installing base desktop and CLI tools"
  nala install -y \
    gdebi-core htop btop neofetch \
    gnome-tweaks gnome-shell-extension-manager \
    curl wget ca-certificates gnupg \
    unzip zip xz-utils tree jq ripgrep \
    software-properties-common ufw apt-transport-https
}

dev_stack(){
  log "Installing dev stack - build-essential git zsh python pipx java-21"
  nala install -y \
    build-essential git zsh \
    python3 python3-pip python3-venv pipx \
    openjdk-21-jdk
  # enable pipx paths for the invoking user
  if [ -n "${SUDO_USER:-}" ]; then
    su - "${SUDO_USER}" -c 'python3 -m pipx ensurepath' || true
  fi
}

node_via_nvm(){
  # install NVM for the invoking user and Node 22
  if [ -z "${SUDO_USER:-}" ]; then
    log "No SUDO_USER found - skipping NVM install"
    return 0
  fi
  log "Installing Node via NVM for user ${SUDO_USER}"
  su - "${SUDO_USER}" -c '
    set -e
    if [ ! -d "$HOME/.nvm" ]; then
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    fi
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh"
    nvm install 22
    nvm alias default 22
  '
}

docker_setup(){
  log "Installing Docker Engine + Compose"
  # remove distro docker if present
  nala remove -y docker docker-engine docker.io containerd runc || true

  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
    > /etc/apt/sources.list.d/docker.list

  nala update
  nala install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker

  # add invoking user to docker group
  if [ -n "${SUDO_USER:-}" ]; then
    usermod -aG docker "${SUDO_USER}"
  fi
}

flatpak_setup(){
  log "Enabling Flatpak + Flathub"
  nala install -y flatpak
  nala install -y gnome-software-plugin-flatpak || true
  if ! flatpak remotes --columns=name | grep -q '^flathub$'; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
}

hardening(){
  log "Turning on UFW and unattended-upgrades"
  nala install -y ufw unattended-upgrades
  ufw --force enable
  ufw allow OpenSSH || true
  dpkg-reconfigure -f noninteractive unattended-upgrades || true
}

qol_shell(){
  log "Zsh defaults and QoL aliases"
  if [ -n "${SUDO_USER:-}" ]; then
    UHOME=$(eval echo "~${SUDO_USER}")
    if ! grep -q "forge-qol-aliases" "$UHOME/.zshrc" 2>/dev/null; then
      cat >> "$UHOME/.zshrc" <<'EOF'
# forge-qol-aliases
alias ll="ls -alh"
alias grep="grep --color=auto"
# show neofetch on interactive login
if [[ $- == *i* ]] && command -v neofetch >/dev/null 2>&1; then neofetch; fi
EOF
      chown "${SUDO_USER}:${SUDO_USER}" "$UHOME/.zshrc"
    fi
    chsh -s /usr/bin/zsh "${SUDO_USER}" || true
  fi
}

summary(){
  echo
  echo "============================================"
  echo "NUC Bootstrap - done"
  echo "What you got =>"
  echo "- Base tools and GNOME tweaks"
  echo "- Dev toolchain: git, zsh, Python, Java 21"
  echo "- Node 22 via NVM for ${SUDO_USER:-your user}"
  echo "- Docker Engine + Compose (user added to docker group)"
  echo "- Flatpak + Flathub"
  echo "- UFW enabled and unattended upgrades configured"
  echo
  echo "Next steps =>"
  echo "- Open a new terminal to load NVM defaults for Node 22"
  echo "- Either reboot or log out/in for docker group to apply"
  echo "============================================"
}

main(){
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
  summary
}

main "$@"

# --- End user-provided content ---

# --- Essentials
sudo apt-get install -y --no-install-recommends       zsh git curl wget unzip zip build-essential pkg-config       python3 python3-venv python3-pip pipx       openssh-client xclip neovim       fonts-firacode

# Ensure pipx path
python3 -m pipx ensurepath || true

# --- Set zsh as default (only if not already)
if [[ "$SHELL" != *"zsh" ]]; then
  chsh -s "$(command -v zsh)" "$USER" || warn "Could not change shell; run: chsh -s $(which zsh)"
fi

# --- NodeJS via nvm (avoids Nodesource 404 issues)
if ! command -v node >/dev/null 2>&1; then
  info "Installing Node via nvm…"
  if [[ ! -d "$HOME/.nvm" ]]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  # shellcheck disable=SC1090
  export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm alias default 'lts/*'
  info "Node: $(node -v) | npm: $(npm -v)"
else
  info "Node present: $(node -v)"
fi

# --- Docker (official repo, idempotent)
if ! command -v docker >/dev/null 2>&1; then
  info "Installing Docker Engine…"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo         "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu         $(. /etc/os-release && echo $VERSION_CODENAME) stable" |         sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER" || true
  info "Docker: $(docker --version)"
  info "Docker Compose: $(docker compose version)"
else
  info "Docker present: $(docker --version)"
fi

# --- VS Code repo (optional)
if ! command -v code >/dev/null 2>&1; then
  info "Adding VS Code repository…"
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg >/dev/null
  sudo add-apt-repository -y "deb [arch=$(dpkg --print-architecture)] https://packages.microsoft.com/repos/code stable main"
  sudo apt-get update -y && sudo apt-get install -y code || warn "VS Code install failed"
fi

# --- Common scripts & aliases (if repo is cloned with common/)
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

log "Ubuntu bootstrap finished."
