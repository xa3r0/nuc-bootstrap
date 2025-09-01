#!/usr/bin/env bash
set -Eeuo pipefail
info() { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
# Example dotfiles bootstrap (non-destructive): extend as needed
DOTSRC="$(cd "$(dirname "$0")" && pwd)/dotfiles"
if [[ -d "$DOTSRC" ]]; then
  info "Staging dotfiles from $DOTSRC (backing up existing files)"
  for f in "$DOTSRC"/.*; do
    base="$(basename "$f")"
    [[ "$base" == "." || "$base" == ".." ]] && continue
    target="$HOME/$base"
    if [[ -e "$target" && ! -L "$target" ]]; then
      mv "$target" "${target}.bak.$(date +%s)" || true
    fi
    ln -snf "$f" "$target"
  done
fi
