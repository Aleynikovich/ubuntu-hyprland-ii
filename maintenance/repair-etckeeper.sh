#!/usr/bin/env bash
# One-off: repair etckeeper's /etc/.git after a corrupt (empty) object ("bad object HEAD" on every apt run).
# Changes only /etc/.git; the files in /etc are never touched. Steps:
#   1. back up /etc/.git to /root (root-only: it holds copies of /etc, including shadow)
#   2. delete empty object files
#   3. if HEAD's history is still broken: point the branch at the newest intact commit from the reflog (asks),
#      or, if there is none, start a fresh history (asks)
#   4. rebuild the index from that commit and commit the current /etc
# Rollback: sudo rm -rf /etc/.git && sudo tar -xzf /root/etc-git-<timestamp>.tar.gz -C /etc
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
g(){ sudo git -C /etc "$@"; }
intact(){ g rev-list --objects "$1" >/dev/null 2>&1; }   # every object reachable from $1 exists

grep -q '^VCS="git"' /etc/etckeeper/etckeeper.conf || die "etckeeper isn't configured for git."
sudo -v
sudo test -d /etc/.git || die "/etc/.git not found."
TS=$(date +%Y%m%d-%H%M%S); BK=/root/etc-git-$TS.tar.gz

step "Backup of /etc/.git -> $BK"
sudo sh -c "umask 077 && tar -czf '$BK' -C /etc .git"
sudo ls -l "$BK"

step "Diagnosis"
br=$(g symbolic-ref --short HEAD 2>/dev/null || echo master)   # reads .git/HEAD; works even if the commit is gone
echo "branch: $br"
g fsck --full 2>&1 | grep -vE '^(dangling|Checking|notice)' | head -20 || true
empty=$(sudo find /etc/.git/objects -type f -empty)
echo "empty object files: $(printf '%s' "$empty" | grep -c . || true)"
[ -n "$empty" ] && echo "$empty"

step "Repair"
[ -n "$empty" ] && echo "$empty" | sudo xargs rm -f
if intact HEAD; then
  ok "History is intact once the empty objects are gone."
else
  good=
  for c in $(sudo cat /etc/.git/logs/HEAD "/etc/.git/logs/refs/heads/$br" 2>/dev/null | awk '{print $2}' | tac); do
    if intact "$c"; then good=$c; break; fi
  done
  if [ -n "$good" ]; then
    echo "Newest intact commit: $(g log -1 --format='%h %ci %s' "$good")"
    confirm "Point $br at it? Commits after it are lost from the history (the files in /etc are not affected)." \
      || die "Aborted. Backup kept at $BK"
    g update-ref "refs/heads/$br" "$good"
  else
    warn "No intact commit in the reflog: the old history can't be recovered (it stays in $BK)."
    confirm "Start a fresh etckeeper history? (the files in /etc are not affected)" || die "Aborted. Backup kept at $BK"
    sudo mv /etc/.git "/root/etc-git-broken-$TS"
    sudo etckeeper init
  fi
fi
# The index may still point at deleted objects; a mixed reset rebuilds it from HEAD without touching /etc.
g rev-parse -q --verify HEAD >/dev/null && g reset -q

step "Commit the current /etc"
sudo etckeeper commit "etckeeper repair ($TS): recommit /etc after a corrupt object" || true
if g fsck --full 2>&1 | grep -iE 'missing|broken|bad|error'; then die "fsck still reports problems (backup: $BK)."; fi
g log --oneline -5
ok "etckeeper repaired. Backup: $BK"
