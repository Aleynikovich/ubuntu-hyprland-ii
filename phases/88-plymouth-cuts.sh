#!/usr/bin/env bash
# Boot/shutdown splash: the "cuts" Plymouth theme (adi1090x/plymouth-themes, GPL-3.0, vendored in templates/plymouth-cuts).
# Rebuilds the running kernel's initrd; the Limine ESP sync hook (phase 91) copies it to the ESP and keeps the previous
# *kernel's* initrd as the fallback entry, so "Ubuntu (previous)" still boots with the old splash.
# Rollback: sudo update-alternatives --remove default.plymouth /usr/share/plymouth/themes/cuts/cuts.plymouth
#   && sudo update-initramfs -u && sudo rm -r /usr/share/plymouth/themes/cuts   (falls back to bgrt, priority 110)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_hw

T=/usr/share/plymouth/themes/cuts
step "Install the cuts theme"
sudo install -d "$T"
sudo cp -f "$REPO"/templates/plymouth-cuts/* "$T"/
sudo chmod 644 "$T"/*
sudo update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$T/cuts.plymouth" 150
sudo update-alternatives --set default.plymouth "$T/cuts.plymouth"
update-alternatives --display default.plymouth | head -3

step "Initramfs for the running kernel (the ESP copy is synced by the phase 91 hook)"
sudo update-initramfs -u -k "$(uname -r)"
lsinitramfs "/boot/initrd.img-$(uname -r)" | grep -c 'plymouth/themes/cuts' || true

ok "Reboot to see it. If the screen looks wrong, choose 'Ubuntu (7.0.0-31-generic, previous)' in the Limine menu."
