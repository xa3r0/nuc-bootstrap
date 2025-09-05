#!/usr/bin/env bash
# =============================================================================
# nuc-bootstrap installer
# Detects OS, shows disclaimer, and runs the correct per-OS bootstrap.
# Optional flags: --dev, --hardening, --all, --yes
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

# --- UI helpers ---------------------------------------------------------------
log()  { printf "\033[1;32m[✔]\033[0m %s\n" "$*"; }
info() { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }

ask_yes_no() {
  # ask_yes_no "Question?"  (default = No)
  local prompt="${1:-Proceed?}"
  read -r -p "$(printf "\033[1;33m[?]\033[0m %s [y/N] " "$prompt")" ans || true
  case "${ans:-}" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Flags --------------------------------------------------------------------
RUN_BOOTSTRAP=1
RUN_DEV=0
RUN_HARD=0
ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    --dev) RUN_DEV=1 ;;
    --hardening) RUN_HARD=1 ;;
    --all) RUN_DEV=1; RUN_HARD=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --help|-h)
      cat <<'EOF'
Usage: ./install.sh [--dev] [--hardening] [--all] [--yes]
  --dev         Also run <os>/dev-packages.sh after bootstrap
  --hardening   Also run <os>/sec-hardening.sh after bootstrap (if present)
  --all         Shortcut for --dev --hardening
  --yes, -y     Non-interactive; accept disclaimer & proceed
EOF
      exit 0
      ;;
    *) warn "Unknown flag: $arg" ;;
  esac
done

# --- Detect OS and map to folder ---------------------------------------------
detect_os_folder() {
  local id like
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"; like="${ID_LIKE:-}"
  fi

  case "${id,,}" in
    ubuntu) echo "ubuntu" ;;
    debian) echo "debian" ;;
    linuxmint) echo "mint" ;;
    arch|archlinux) echo "arch" ;;
    kali) echo "kali" ;;
    *)
      # Fall back using ID_LIKE if helpful
      case "${like,,}" in
        *debian*|*ubuntu*) echo "debian" ;;
        *) echo "" ;;
      esac
      ;;
  esac
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_FOLDER="$(detect_os_folder || true)"

if [[ -z "${OS_FOLDER}" ]]; then
  err "Unsupported or undetected OS. Aborting."
  info "Detected via /etc/os-release; supported: ubuntu, debian, linuxmint, arch, kali."
  exit 1
fi

BOOTSTRAP="${SCRIPT_DIR}/${OS_FOLDER}/bootstrap.sh"
DEVPKG="${SCRIPT_DIR}/${OS_FOLDER}/dev-packages.sh"
HARDEN="${SCRIPT_DIR}/${OS_FOLDER}/sec-hardening.sh"

[[ -x "$BOOTSTRAP" ]] || { err "Missing or non-executable: $BOOTSTRAP"; exit 1; }
[[ $RUN_DEV -eq 0 || -f "$DEVPKG" ]] || warn "No dev-packages script at ${DEVPKG} (skipping)"
[[ $RUN_HARD -eq 0 || -f "$HARDEN"  ]] || warn "No sec-hardening script at ${HARDEN} (skipping)"

# --- Environment sanity checks ------------------------------------------------
has_net() {
  # quick dumb check: DNS + TCP
  command -v getent >/dev/null 2>&1 && getent hosts github.com >/dev/null 2>&1 && return 0
  ping -c1 -W1 1.1.1.1 >/dev/null 2>&1 && return 0
  return 1
}

if ! has_net; then
  warn "Network connectivity check failed. You may hit errors fetching packages."
fi

# WSL note (just a warning)
if grep -qi microsoft /proc/version 2>/dev/null; then
  warn "Windows Subsystem for Linux detected. Some steps (e.g., systemd services) may differ."
fi

# --- Disclaimer ---------------------------------------------------------------
cat <<'DISCLAIMER'
===============================================================================
DISCLAIMER
This script will make system-level changes (package installs, repos, configs).
By proceeding, you accept that the author(s) are NOT responsible for any issues,
data loss, or system instability that may result. Review the scripts before use.

You can exit now (Ctrl+C) or decline at the prompt to abort.
===============================================================================
DISCLAIMER

info "Detected OS folder: ${OS_FOLDER}"
info "Plan:"
echo "  - Run: ${BOOTSTRAP}"
[[ $RUN_DEV  -eq 1 && -f "$DEVPKG" ]]  && echo "  - Then: ${DEVPKG}"
[[ $RUN_HARD -eq 1 && -f "$HARDEN"  ]] && echo "  - Then: ${HARDEN}"

if [[ $ASSUME_YES -ne 1 ]]; then
  ask_yes_no "Proceed with the above actions?" || { warn "User cancelled."; exit 1; }
fi

# --- Run ----------------------------------------------------------------------
set -o pipefail

info "Starting bootstrap…"
bash "$BOOTSTRAP"

if [[ $RUN_DEV -eq 1 && -f "$DEVPKG" ]]; then
  info "Running dev-packages…"
  bash "$DEVPKG"
fi

if [[ $RUN_HARD -eq 1 && -f "$HARDEN" ]]; then
  info "Running sec-hardening…"
  bash "$HARDEN"
fi

log "All requested steps completed."
info "Tip: if you were added to the 'docker' group, run: newgrp docker  # or log out/in"
