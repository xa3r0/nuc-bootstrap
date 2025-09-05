#!/usr/bin/env bash
# ======================================================================
# Arch Linux dev-packages (nuc-bootstrap)
# Categories: Eye Candy, Utilities, Support, Dev
# Uses pacman; optional AUR via yay if present.
# ======================================================================
set -Eeuo pipefail
IFS=$'\n\t'

log()  { printf "\033[1;32m[✔]\033[0m %s\n" "$*"; }
info() { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }

require_sudo() { if [[ $EUID -ne 0 ]]; then command -v sudo >/dev/null || { err "sudo missing"; exit 1; }; sudo -v || { err "sudo auth failed"; exit 1; }; fi; }
update_indexes() { sudo pacman -Sy --noconfirm; }
pkg_install() { sudo pacman -S --noconfirm --needed "$@"; }

# ----------------- Package sets -----------------
EYE_CANDY=(ttf-fira-code gnome-tweaks bat eza neofetch)
# Note: Extension manager is in AUR as 'extension-manager'
UTILS=(htop btop curl wget ca-certificates gnupg unzip zip xz tree ripgrep jq xclip fzf tmux)
SUPPORT=(base-devel pkgconf lsb-release neovim flatpak)
DEV=(git git-lfs zsh python python-pipx jdk-openjdk go rustup direnv shellcheck clang cmake)

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


install_extension_manager_if_yay() {
  if command -v extension-manager >/dev/null 2>&1; then return 0; fi
  if command -v yay >/dev/null 2>&1; then
    info "Installing GNOME Extension Manager from AUR via yay…"
    yay -S --noconfirm extension-manager || warn "AUR install failed"
  else
    warn "extension-manager (AUR) not installed (no yay found)"
  fi
}

install_vscode_optional() {
  # Choose OSS 'code' from community or VSCodium (AUR: vscodium-bin)
  if command -v code >/dev/null 2>&1; then return 0; fi
  info "Installing 'code' (community) — optional editor"
  sudo pacman -S --noconfirm --needed code || warn "Install 'code' failed; consider 'vscodium-bin' via AUR"
}

post_steps() {
  # pipx path (python-pipx already installed)
  python -m pipx ensurepath || true

  # rustup bootstrap (user-space)
  if ! command -v rustc >/dev/null 2>&1; then
    info "Installing Rust via rustup for ${SUDO_USER:-$USER}"
    if [[ -n "${SUDO_USER:-}" ]]; then su - "${SUDO_USER}" -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
    else curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; fi
  fi

  # NVM + Node (if not already)
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
  install_extension_manager_if_yay || true
  install_jd_minimal_zsh || true

  info "Installing Utilities…";   pkg_install "${UTILS[@]}"
  info "Installing Support…";     pkg_install "${SUPPORT[@]}"
  info "Installing Dev stack…";   pkg_install "${DEV[@]}"

  install_vscode_optional || true
  post_steps

  log "Arch dev-packages complete."
}
main "$@"
