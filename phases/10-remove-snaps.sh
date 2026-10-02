#!/usr/bin/env bash
# OPTIONAL, DESTRUCTIVE: back up ~/snap, remove every snap, purge snapd and pin it so apt never reinstalls it.
# Rollback: sudo rm /etc/apt/preferences.d/no-snap.pref && sudo apt install snapd,
#           then `snap install` what's listed in $BACKUP_DIR/snap-removal-*/snaps-before-removal.txt
#           and `tar -xzf .../snap-home.tar.gz -C ~`.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

command -v snap >/dev/null || { ok "snapd is not installed; nothing to do."; exit 0; }
B="$BACKUP_DIR/snap-removal-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$B"
snap list | tee "$B/snap-list.txt"
snap list | awk 'NR>1{print $1}' > "$B/snaps-before-removal.txt"

if pgrep -f '^/snap/' >/dev/null; then
  pgrep -af '^/snap/' | cut -c1-100
  die "Close the snap apps above first."
fi
echo
echo "This removes ALL snaps above and their data in ~/snap (backed up first), then purges and pins snapd."
echo "apt dry run of 'purge snapd':"
apt-get -s purge snapd 2>/dev/null | grep -E '^(Purg|Remv)' || true
confirm "Proceed?" || die "Aborted."

step "Backing up ~/snap (Steam game libraries excluded) and ~/.mozilla to $B"
( cd ~ && tar --exclude='snap/steam/common/.local/share/Steam/steamapps' -czf "$B/snap-home.tar.gz" snap $( [ -d .mozilla ] && echo .mozilla ) )
ls -lh "$B/snap-home.tar.gz"

sudo -v
step "Removing snaps (apps, then runtimes, then bases)"
for pass in 1 2 3 4; do
  left=$(snap list 2>/dev/null | awk 'NR>1 && $1!="snapd"{print $1}')
  [ -z "$left" ] && break
  for s in $(echo "$left" | grep -v -E '^(core[0-9]*|bare|gnome-|gtk-common-themes|mesa-|gaming-graphics|icon-theme-|kf5-|kf6-|chromium-ffmpeg)'; \
             echo "$left" | grep -E '^(gnome-|gtk-common-themes|mesa-|gaming-graphics|icon-theme-|kf5-|kf6-|chromium-ffmpeg)'; \
             echo "$left" | grep -E '^(core[0-9]*|bare)$'); do
    sudo snap remove --purge "$s" || true
  done
done
sudo snap remove --purge snapd || true

step "Purging and pinning snapd"
sudo systemctl stop snapd.socket snapd.service 2>/dev/null || true
sudo apt-get purge -y snapd
printf 'Package: snapd\nPin: release a=*\nPin-Priority: -10\n' | sudo tee /etc/apt/preferences.d/no-snap.pref >/dev/null
if ! findmnt -rn -o TARGET | grep -q '^/snap'; then
  sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd
fi
rm -rf ~/snap

apt-cache policy snapd | head -3
ok "Snaps removed. Backup: $B"
