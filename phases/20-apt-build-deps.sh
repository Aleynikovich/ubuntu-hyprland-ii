#!/usr/bin/env bash
# Build dependencies from Ubuntu's own repos. New packages only: aborts (asks) if anything would be upgraded/removed.
# Rollback: sudo apt-get purge $(cat "$SRC/apt-installed-build.txt") && sudo apt-get autoremove
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

mkdir -p "$SRC"
mapfile -t pkgs < <(grep -v -E '^\s*(#|$)' "$REPO/packages/apt-build-deps.txt")
step "apt: ${#pkgs[@]} build dependencies (clang-20, meson, -dev libraries)"
sudo -v
apt_install_new_only "$SRC/apt-installed-build.txt" "${pkgs[@]}"
clang++-20 --version | head -1
ok "Build dependencies installed."
