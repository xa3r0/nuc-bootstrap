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
