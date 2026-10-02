#!/usr/bin/env bash
# Timestamped tarball of ~/.config and ~/.local/share before any dots are copied.
# Rollback: log out of the desktop, then `tar -xzf <tarball> -C ~`.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

D="$BACKUP_DIR/config-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$D"
step "Backing up ~/.config and ~/.local/share to $D"
cd ~
set +e
tar --warning=no-file-changed --warning=no-file-ignored -czf "$D/config-localshare.tar.gz" .config .local/share
rc=$?
set -e
# tar exits 1 when files changed while being read (normal for a running desktop); 2 is a real error.
[ $rc -le 1 ] || die "tar failed (rc=$rc)"
n=$(tar -tzf "$D/config-localshare.tar.gz" | wc -l)
ls -lh "$D/config-localshare.tar.gz"; echo "$n entries"
ok "Config backup: $D/config-localshare.tar.gz"
