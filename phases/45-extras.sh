#!/usr/bin/env bash
# OPTIONAL: EasyEffects (Ubuntu apt) and songrec (its author's Launchpad PPA, key checked against Launchpad's fingerprint).
# New packages only, like the other apt phases. The dots autostart EasyEffects in Hyprland; Plasma doesn't start it.
# Rollback: sudo apt-get purge $(cat "$SRC/apt-installed-extras.txt") && sudo apt-get autoremove
#           sudo rm /etc/apt/sources.list.d/songrec-ppa.sources /etc/apt/keyrings/songrec-ppa.gpg && sudo apt-get update
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

mkdir -p "$SRC"
REC=$SRC/apt-installed-extras.txt

# https://launchpad.net/~marin-m/+archive/ubuntu/songrec (signing_key_fingerprint in the Launchpad API)
SONGREC_FPR=86A389B4B401FAB17A0168506888550B2FC77D09
KEY=/etc/apt/keyrings/songrec-ppa.gpg
SRCS=/etc/apt/sources.list.d/songrec-ppa.sources

step "songrec PPA key"
tmp=$(mktemp); at_exit 'rm -f "$tmp"'
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x$SONGREC_FPR" | gpg --dearmor > "$tmp"
fpr=$(gpg --show-keys --with-colons "$tmp" | awk -F: '/^fpr/{print $10; exit}')
[ "$fpr" = "$SONGREC_FPR" ] || die "songrec PPA key fingerprint mismatch: $fpr"
ok "Key fingerprint OK: $fpr"

sudo -v
sudo install -d -m 0755 /etc/apt/keyrings
sudo install -m 0644 "$tmp" "$KEY"
. /etc/os-release
sudo tee "$SRCS" >/dev/null <<EOF
Types: deb
URIs: https://ppa.launchpadcontent.net/marin-m/songrec/ubuntu
Suites: $VERSION_CODENAME
Components: main
Signed-By: $KEY
EOF
sudo apt-get update

step "apt: easyeffects songrec"
apt_install_new_only "$REC" easyeffects songrec
ok "Extras installed."
