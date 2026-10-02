#!/usr/bin/env bash
# OPTIONAL, DESTRUCTIVE: make Hyprland the only desktop. Removes Plasma/KWin/KDE apps, GNOME/gdm3, the X11 sessions
# and some background extras (packages/hyprland-only-roots.txt), keeping what the end-4 dots, corporate login (sssd),
# printing, audio and networking need (packages/hyprland-only-keep.txt). Also sets up SDDM autologin into Hyprland.
#   EXPECT=<file>  abort unless the simulated removal list matches this file exactly (one package per line)
# Rollback: sudo apt-get install $(cat "$SRC"/apt-removed-hyprland-only-*.txt)   (configs: etckeeper history of /etc)
#           sudo apt-mark auto $(cat "$SRC"/apt-marked-manual-hyprland-only-*.txt)
#           sudo rm /etc/sddm.conf.d/hyprland-ii-autologin.conf; sudo dpkg-divert --rename --remove /usr/share/xsessions/plasma.desktop
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

list(){ grep -v -E '^\s*(#|$)' "$REPO/packages/$1"; }
installed(){ dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii'; }
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p "$SRC"

step "Simulating"
keep=(); roots=(); args=()
for p in $(list hyprland-only-keep.txt); do installed "$p" && keep+=("$p") && args+=("$p+"); done
for p in $(list hyprland-only-roots.txt); do installed "$p" && roots+=("$p") && args+=("$p-"); done
if [ ${#roots[@]} -eq 0 ]; then ok "Nothing left to remove."; else
sim=$(apt-get -s --auto-remove install "${args[@]}" 2>&1) || { echo "$sim" | tail -5; die "apt simulation failed"; }
inst=$(echo "$sim" | grep -c '^Inst' || true)
[ "$inst" = 0 ] || { echo "$sim" | grep '^Inst'; die "The simulation would INSTALL packages; refusing."; }
mapfile -t remove < <(echo "$sim" | awk '/^Remv/{print $2}' | sort -u)
mb=$(printf '%s\n' "${remove[@]}" | xargs dpkg-query -W -f='${Installed-Size}\n' | awk '{s+=$1} END{printf "%.0f", s/1024}')
echo "${#keep[@]} packages pinned as manual, ${#remove[@]} to purge (${mb} MB)."
plan=$SRC/hyprland-only-plan-$TS.txt; printf '%s\n' "${remove[@]}" > "$plan"; echo "Full list: $plan"
if [ -n "${EXPECT:-}" ]; then
  diff <(grep -v '^\s*$' "$EXPECT" | sort -u) "$plan" || die "Removal list differs from $EXPECT; review before running."
  ok "Removal list matches $EXPECT."
fi
confirm "Pin the keep list and PURGE these ${#remove[@]} packages?" || die "Aborted."

step "Pinning ${#keep[@]} packages as manually installed"
sudo -v
printf '%s\n' "${keep[@]}" | xargs apt-mark showauto > "$SRC/apt-marked-manual-hyprland-only-$TS.txt" || true
sudo apt-mark manual "${keep[@]}" >/dev/null

step "Purging ${#remove[@]} packages"
cp "$plan" "$SRC/apt-removed-hyprland-only-$TS.txt"
sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y "${remove[@]}"
left=$(apt-get -s autoremove 2>/dev/null | grep -c '^Remv' || true)
[ "$left" = 0 ] && ok "Nothing else is autoremovable." || { warn "apt now lists $left autoremovable packages (not removed):"; apt-get -s autoremove | grep '^Remv'; }
fi

step "SDDM autologin into Hyprland"
sudo install -d -m 0755 /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/hyprland-ii-autologin.conf >/dev/null <<EOF
# Boot straight into Hyprland (LUKS passphrase at boot still protects the disk). Remove this file to get the greeter.
[Autologin]
User=$(id -un)
Session=hyprland-ii
Relogin=false
EOF
cat /etc/sddm.conf.d/hyprland-ii-autologin.conf
# Plasma's SDDM settings module leaves an empty [Autologin] section (User=, Session=) in /etc/sddm.conf and
# kde_settings.conf; /etc/sddm.conf is read last and would override the file above. Drop those sections.
for f in /etc/sddm.conf /etc/sddm.conf.d/kde_settings.conf; do
  [ -f "$f" ] && grep -q '^\[Autologin\]' "$f" || continue
  sudo python3 - "$f" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(re.sub(r"(?ms)^\[Autologin\]\n.*?(?=^\[|\Z)", "", s))
PY
  echo "removed [Autologin] from $f"
done

step "Hide the Plasma (X11) session (its file belongs to plasma-workspace, which the dots' users KCM needs)"
X=/usr/share/xsessions/plasma.desktop
if [ -e "$X" ] && ! dpkg-divert --list "$X" | grep -q .; then
  sudo dpkg-divert --local --rename --divert "$X.hyprland-ii-hidden" --add "$X"
fi
ls /usr/share/xsessions/ /usr/share/wayland-sessions/
ok "Hyprland-only. Removed list: $SRC/apt-removed-hyprland-only-$TS.txt"
