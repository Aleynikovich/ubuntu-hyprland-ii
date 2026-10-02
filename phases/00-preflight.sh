#!/usr/bin/env bash
# Read-only checks. Changes nothing.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

step "System"
. /etc/os-release
echo "$PRETTY_NAME, kernel $(uname -r), $(uname -m)"
[ "${VERSION_ID:-}" = "24.04" ] || warn "Only tested on Ubuntu/Kubuntu 24.04 (this is ${VERSION_ID:-unknown})."
[ "$(uname -m)" = x86_64 ] || die "x86_64 only."

step "Disk"
free_gb=$(df --output=avail -BG / | tail -1 | tr -dc 0-9)
echo "Free on /: ${free_gb} GB (need ~${MIN_FREE_GB} GB for the build)"
[ "$free_gb" -ge "$MIN_FREE_GB" ] || warn "Not enough free space for the build yet (removing snaps may free some)."

step "GPU"
lspci -nn | grep -E 'VGA|3D|Display' || true
if command -v nvidia-smi >/dev/null; then
  nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
  grep -rqs 'nvidia_drm.*modeset=1' /etc/modprobe.d/ && echo "nvidia_drm modeset=1: set" || warn "nvidia_drm modeset=1 not found in /etc/modprobe.d (needed for Wayland)."
  [ "$(lspci | grep -c -E 'VGA|3D')" -gt 1 ] && warn "Hybrid graphics detected: the session wrapper's NVIDIA env vars assume dGPU-only (MUX) mode. Review session/hyprland-ii-session."
fi

step "Sessions / display manager"
ls /usr/share/xsessions /usr/share/wayland-sessions 2>/dev/null
systemctl is-active sddm >/dev/null 2>&1 && echo "SDDM active" || warn "SDDM not active; the session entry is written for SDDM but works with most DMs."

step "Snaps"
command -v snap >/dev/null && snap list 2>/dev/null | awk 'NR>1{print "  "$1}' || echo "snapd not installed"

step "Protected state (PROTECTED_* in config.env)"
protected_fingerprint | grep . || echo "(none configured)"

ok "Preflight done."
