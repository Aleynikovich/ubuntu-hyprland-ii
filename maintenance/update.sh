#!/usr/bin/env bash
# Careful `apt full-upgrade`: show what the upgrade touches (kernel/boot, NVIDIA, system libs the $PREFIX build links against,
# PROTECTED_PACKAGES, removals), snapshot versions + /etc, upgrade, then check that the next boot and the session still work.
# Usage:
#   update.sh                  pre-check, confirm, snapshot, `apt-get full-upgrade`, post-checks
#   update.sh --check          pre-check only (no changes, no prompts; refreshes the lists only if sudo needs no password)
#   update.sh --post [--since 'YYYY-MM-DD HH:MM:SS']
#                              post-checks only, e.g. after unattended-upgrades (default window: since the last post-check)
#   update.sh --unattended     report what unattended-upgrades may install on its own, and print a proposed config
# Options: --yes (no prompts; keeps old conffiles)  --allow-removals  --allow-protected  --rescan (rebuild the lib cache)
#          --rebaseline (accept the current set of unresolved libs under $PREFIX as the new normal)
# Exit: 0 ok, 1 failed check / aborted, 2 blockers in the plan (--check), 3 PROTECTED_* changed, 4 boot checks failed (DO NOT REBOOT)
# State: $SRC/update/ (lib cache, ldd baseline, one snapshot dir per run with the exact old versions)
# Rollback of an upgrade: $SRC/update/<timestamp>/downgrade.sh lists `apt-get install --allow-downgrades pkg=oldver ...`
#   (works for versions still in the archive or /var/cache/apt/archives); /etc: `sudo git -C /etc log` (etckeeper).
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

MODE=full; SINCE=""; ALLOW_REMOVALS=0; ALLOW_PROTECTED=0; RESCAN=0; REBASELINE=0
while [ $# -gt 0 ]; do
  case $1 in
    --check) MODE=check ;;
    --post) MODE=post ;;
    --unattended) MODE=unattended ;;
    --since) SINCE=${2:?--since needs a time}; shift ;;
    --yes|-y) ASSUME_YES=1 ;;
    --allow-removals) ALLOW_REMOVALS=1 ;;
    --allow-protected) ALLOW_PROTECTED=1 ;;
    --rescan) RESCAN=1 ;;
    --rebaseline) REBASELINE=1 ;;
    -h|--help) sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0"; exit 0 ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
  shift
done

UPD=$SRC/update
CACHE=$UPD/prefix-syslibs.tsv        # <ELF relative to PREFIX> <TAB> <system lib path> <TAB> <package>
BASELINE=$UPD/ldd-missing-baseline.txt  # <ELF> <TAB> <soname> already unresolved before (e.g. Qt's optional SQL drivers)
ESP=/boot/efi
mkdir -p "$UPD"
TMP=$(mktemp -d)
# shellcheck disable=SC2016  # expanded when the hook runs
at_exit 'rm -rf "$TMP"'
FAIL=0; BOOT_FAIL=0
bad(){ warn "$*"; FAIL=1; }
bootbad(){ warn "$*"; BOOT_FAIL=1; }
can_sudo(){ sudo -n true 2>/dev/null; }

# ---------------------------------------------------------------- $PREFIX -> system libs -> packages
# ELF files of the build (the tools/ venv is build-only and excluded).
prefix_elfs(){
  local f m
  find "$PREFIX" \( -path "$PREFIX/tools" -o -path "$PREFIX/include" \) -prune -o \
    -type f \( -name '*.so' -o -name '*.so.*' -o -perm -u+x \) -print | sort |
  while IFS= read -r f; do
    m=; LC_ALL=C IFS= read -r -n 4 m < "$f" 2>/dev/null || true
    [ "$m" = $'\177ELF' ] && printf '%s\n' "$f"
  done
}

# Writes $TMP/edges (<rel> <TAB> <lib path outside PREFIX>) and $TMP/missing (<rel> <TAB> <soname>).
ldd_scan(){
  local f rel
  : > "$TMP/edges"; : > "$TMP/missing"
  while IFS= read -r f; do
    rel=${f#"$PREFIX"/}
    { ldd "$f" 2>/dev/null || true; } | awk -v rel="$rel" -v pre="$PREFIX/" -v E="$TMP/edges" -v M="$TMP/missing" '
      $2 == "=>" && $3 == "not" { print rel "\t" $1 >> M; next }
      $2 == "=>" && $3 ~ /^\// { if (index($3, pre) != 1) print rel "\t" $3 >> E; next }
      $1 ~ /^\// && $2 ~ /^\(0x/ { if (index($1, pre) != 1) print rel "\t" $1 >> E }'
  done < <(prefix_elfs)
  sort -u -o "$TMP/missing" "$TMP/missing"
}

# Resolve lib paths to packages (merged /usr: dpkg may know a file under /lib or /usr/lib, or only its symlink target).
build_cache(){
  echo "Scanning ELF files under $PREFIX for system libraries (ldd)..."
  ldd_scan
  cut -f2 "$TMP/edges" | sort -u > "$TMP/libs"
  local l r c
  while IFS= read -r l; do
    r=$(readlink -f "$l" || echo "$l")
    for c in "$l" "$r"; do printf '%s\n' "$c"; case $c in /usr/*) printf '%s\n' "${c#/usr}" ;; *) printf '/usr%s\n' "$c" ;; esac; done
  done < "$TMP/libs" | sort -u > "$TMP/cands"
  # "pkg1:amd64, pkg2:amd64: /path" (diversion lines skipped); keep the first owner, without the arch.
  xargs -a "$TMP/cands" -d '\n' dpkg -S 2>/dev/null | grep -v '^diversion' |
    awk -F': ' '{ split($1, o, ", "); sub(/:.*/, "", o[1]); print $2 "\t" o[1] }' | sort -u > "$TMP/owners" || true
  while IFS= read -r l; do
    r=$(readlink -f "$l" || echo "$l")
    for c in "$l" "$r" "/usr$l" "${l#/usr}" "/usr$r" "${r#/usr}"; do printf '%s\t%s\n' "$l" "$c"; done
  done < "$TMP/libs" > "$TMP/libcands"
  awk -F'\t' 'NR == FNR { o[$1] = $2; next }
    !($1 in seen) { seen[$1] = 1; order[++n] = $1; pkg[$1] = "?" }
    pkg[$1] == "?" && ($2 in o) { pkg[$1] = o[$2] }
    END { for (i = 1; i <= n; i++) print order[i] "\t" pkg[order[i]] }' "$TMP/owners" "$TMP/libcands" > "$TMP/libpkg"
  awk -F'\t' 'NR == FNR { pkg[$1] = $2; next } { print $1 "\t" $2 "\t" pkg[$2] }' "$TMP/libpkg" "$TMP/edges" | sort -u > "$CACHE.new"
  mv -f "$CACHE.new" "$CACHE"
  cp -f "$TMP/missing" "$UPD/ldd-missing-last.txt"
  SCANNED=1
}
cache_fresh(){
  [ -s "$CACHE" ] && [ ! /var/lib/dpkg/status -nt "$CACHE" ] &&
    [ -z "$(find "$PREFIX" \( -path "$PREFIX/tools" -o -path "$PREFIX/include" \) -prune -o -type f -newer "$CACHE" -print -quit)" ]
}
SCANNED=0
ensure_cache(){ # a fresh cache also means the set of unresolved libs is unchanged
  if [ "$RESCAN" = 0 ] && cache_fresh && [ -f "$UPD/ldd-missing-last.txt" ]; then
    cp "$UPD/ldd-missing-last.txt" "$TMP/missing"; SCANNED=1; echo "Using the cached $PREFIX library scan ($CACHE)."
  else build_cache; fi
}

# $PREFIX component (phases/30-build.sh name, for maintenance/bump.sh) that installed a file.
component_of(){
  case $1 in
    qt/*) echo qt ;;
    bin/Hyprland|bin/hyprland|bin/hyprctl|bin/hyprpm|bin/start-hyprland) echo hyprland ;;
    bin/hyprland-share-picker|libexec/xdg-desktop-portal-hyprland) echo xdph ;;
    bin/hyprland-dialog|bin/hyprland-donate-screen|bin/hyprland-run|bin/hyprland-update-screen|bin/hyprland-welcome) echo hyprland_guiutils ;;
    lib/libaquamarine*) echo aquamarine ;;
    lib/libhyprutils*) echo hyprutils ;;
    lib/libhyprlang*) echo hyprlang ;;
    lib/libhyprcursor*|bin/hyprcursor-util) echo hyprcursor ;;
    lib/libhyprgraphics*) echo hyprgraphics ;;
    lib/libhyprwire*|bin/hyprwire-scanner) echo hyprwire ;;
    lib/libhyprtoolkit*) echo hyprtoolkit ;;
    bin/hyprwayland-scanner) echo hyprwayland_scanner ;;
    lib/libhyprland-quick-style*|qml/org/hyprland/*) echo hyprland_qt_support ;;
    lib/libwayland-*|bin/wayland-scanner) echo wayland ;;
    lib/libxkbcommon*|lib/libxkbregistry*) echo xkbcommon ;;
    lib/libinput*|bin/libinput|libexec/libinput/*|lib/udev/libinput-*) echo libinput ;;
    bin/lua|bin/luac|lib/liblua*) echo lua ;;
    lib/libxcb-errors*) echo xcb_errors ;;
    lib/libdisplay-info*|bin/di-edid-decode) echo libdisplay_info ;;
    lib/libei*|lib/liboeffis*|bin/ei-*) echo libei ;;
    lib/libreadline*|lib/libhistory*) echo readline ;;
    lib/libiniparser*) echo iniparser ;;
    lib/libabsl_*) echo abseil ;;
    lib/libKirigami*|qml/org/kde/kirigami/*) echo kirigami ;;
    lib/libKF6SyntaxHighlighting*|bin/ksyntaxhighlighter6|qml/org/kde/syntaxhighlighting/*) echo syntax_highlighting ;;
    lib/libcpptrace*) echo cpptrace ;;
    bin/quickshell|bin/qs|lib/quickshell/*) echo quickshell ;;
    lib/libsdbus-c++*) echo sdbus ;;
    bin/pipewire*|bin/pw-*|bin/spa-*|lib/libpipewire*|lib/libspa*|lib/pipewire-0.3/*|lib/spa-0.2/*) echo pipewire ;;
    bin/hypridle) echo hypridle ;;
    bin/hyprlock) echo hyprlock ;;
    bin/hyprpicker) echo hyprpicker ;;
    bin/hyprsunset) echo hyprsunset ;;
    bin/swappy) echo swappy ;;
    opt/MicroTeX/*|lib/libLaTeX*|lib/libmicrotex*) echo microtex ;;
    bin/matugen|bin/uv|bin/uvx|bin/starship) echo "runtime(phase 40 prebuilt: ${1#bin/})" ;;
    *) echo "other:$1" ;;
  esac
}
components_for_pkgs(){ # pkg... -> "component  (via pkg, pkg)" lines
  [ $# -gt 0 ] || return 0
  local rel _lib pkg
  printf '%s\n' "$@" > "$TMP/want"
  while IFS=$'\t' read -r rel _lib pkg; do
    printf '%s\t%s\n' "$(component_of "$rel")" "$pkg"
  done < <(awk -F'\t' 'NR == FNR { w[$1] = 1; next } ($3 in w)' "$TMP/want" "$CACHE" ${PRE_CACHE:+"$PRE_CACHE"}) |
    sort -u | awk -F'\t' '{ v[$1] = ($1 in v) ? v[$1] ", " $2 : $2 } END { for (c in v) printf "  %-22s (via %s)\n", c, v[c] }' | sort
}

# Unresolved libs vs the baseline: new entries are a breakage. The baseline only grows with --rebaseline.
check_missing(){
  [ "$SCANNED" = 1 ] || build_cache
  if [ ! -f "$BASELINE" ] || [ "$REBASELINE" = 1 ]; then
    cp -f "$TMP/missing" "$BASELINE"
    echo "ldd baseline recorded: $(grep -c . "$BASELINE" || true) pre-existing unresolved lib(s) (e.g. Qt's optional plugins); see $BASELINE"
  fi
  comm -23 "$TMP/missing" <(sort -u "$BASELINE") > "$TMP/newmissing"
  if [ -s "$TMP/newmissing" ]; then
    bad "Libraries that no longer resolve under $PREFIX (not in the baseline):"
    sed 's/^/  /' "$TMP/newmissing" >&2
    echo "Rebuild these components (maintenance/bump.sh <component>):"
    cut -f1 "$TMP/newmissing" | while IFS= read -r r; do component_of "$r"; done | sort -u | sed 's/^/  /'
  else
    ok "(a) Every ELF under $PREFIX resolves its libraries ($(grep -c . "$BASELINE" || true) known-optional ones ignored)."
    comm -12 "$TMP/missing" <(sort -u "$BASELINE") > "$BASELINE.tmp"; mv -f "$BASELINE.tmp" "$BASELINE"   # shrink if fixed
  fi
}

# ---------------------------------------------------------------- plan
# $TMP/plan: action <TAB> pkg (no arch) <TAB> pkg (as apt prints it) <TAB> old <TAB> new <TAB> origin
simulate(){
  if [ -n "${UPDATE_SIM_FILE:-}" ]; then cp "$UPDATE_SIM_FILE" "$TMP/sim"   # testing aid: a saved `apt-get -s full-upgrade` output
  else apt-get -s -o Debug::NoLocking=1 full-upgrade > "$TMP/sim" 2>&1 || { tail -20 "$TMP/sim" >&2; die "apt-get -s full-upgrade failed."; }
  fi
  awk '
    /^Inst / { name = $2; full = $2; sub(/:.*/, "", name); old = ""; rest = $0
               if ($3 ~ /^\[/) { old = $3; gsub(/[][]/, "", old) }
               new = ""; origin = ""
               if (match(rest, /\(([^ ]+) ([^)]*)\)/)) { s = substr(rest, RSTART + 1, RLENGTH - 2); split(s, a, " "); new = a[1]; origin = a[2] }
               print (old == "" ? "new" : "upgrade") "\t" name "\t" full "\t" old "\t" new "\t" origin; next }
    /^Remv / { name = $2; full = $2; sub(/:.*/, "", name); old = $3; gsub(/[][]/, "", old)
               print "remove\t" name "\t" full "\t" old "\t\t"; next }' "$TMP/sim" > "$TMP/plan"
}

refresh_lists(){
  if [ "$MODE" = check ]; then
    if can_sudo; then sudo -n apt-get update -qq || warn "apt-get update failed; using the cached package lists."
    else
      local age; age=$(stat -c %y /var/lib/apt/periodic/update-success-stamp 2>/dev/null | cut -d. -f1 || echo unknown)
      warn "Package lists not refreshed (sudo needs a password). Using lists from: ${age:-unknown} (apt-daily refreshes them)."
    fi
  else
    sudo apt-get update
  fi
}

KERNEL_RE='^(linux-(image|modules|headers|generic|signed|hwe|firmware|tools|objects|buildinfo)|grub|shim|initramfs-tools|limine)'
NVIDIA_RE='nvidia|^dkms$'
PLUMBING_RE='^(libc6|libc-bin|libstdc[+][+]6|libgcc-s1|systemd|udev|libudev1|libsystemd0|dbus|kmod|sddm|xwayland|libgbm1|libegl-mesa0|libgl1-mesa-dri|mesa-|libdrm2|polkitd|libpam|etckeeper|pipewire|wireplumber)'

summarize(){
  local n_up n_new n_rm
  n_up=$(awk -F'\t' '$1 == "upgrade"' "$TMP/plan" | wc -l); n_new=$(awk -F'\t' '$1 == "new"' "$TMP/plan" | wc -l)
  n_rm=$(awk -F'\t' '$1 == "remove"' "$TMP/plan" | wc -l)
  step "Plan: $n_up upgrade(s), $n_new new, $n_rm removal(s)"
  awk '/deferred due to phasing/ { f = 1; print; next } f && /^ / { print; next } { f = 0 }' "$TMP/sim"
  BLOCK=0
  show(){ # title regex-on-name
    local t=$1 re=$2 rows
    rows=$(awk -F'\t' -v re="$re" '$2 ~ re { printf "  %-8s %-45s %s -> %s\n", $1, $3, ($4 == "" ? "-" : $4), ($5 == "" ? "-" : $5) }' "$TMP/plan")
    [ -n "$rows" ] || return 0
    printf '\n%s%s%s\n%s\n' "$c_warn" "$t" "$c_off" "$rows"
  }
  show "Kernel / boot chain (initrd, Limine ESP copy and NVIDIA module are checked afterwards):" "$KERNEL_RE"
  NEWK=$(awk -F'\t' '$1 == "new" && $2 ~ /^linux-image-[0-9].*-generic$/ { sub(/^linux-image-/, "", $2); print $2 }' "$TMP/plan" | sort -V | tail -1)
  if [ -n "$NEWK" ]; then
    echo "  -> new kernel $NEWK: limine-esp-sync makes it the default Limine entry; the current ESP kernel becomes the fallback."
    awk -F'\t' -v k="$NEWK" '$2 ~ "^linux-modules-nvidia-.*-" k "$"' "$TMP/plan" | grep -q . ||
      echo "  -> no prebuilt linux-modules-nvidia-*-$NEWK in the plan: the NVIDIA module must come from DKMS (checked afterwards)."
  fi
  awk -F'\t' '$2 ~ /^(grub|shim)/' "$TMP/plan" | grep -q . &&
    warn "GRUB/shim in the plan: this machine boots Limine (phase 92 removed GRUB). A GRUB install may change the EFI boot order."
  show "NVIDIA / DKMS (reboot right after; until then new GL/CUDA apps and a fresh Hyprland login may fail):" "$NVIDIA_RE"
  show "Session/boot plumbing (log out or reboot afterwards):" "$PLUMBING_RE"

  # system libs the $PREFIX build links against
  cut -f3 "$CACHE" | grep -vx '?' | sort -u > "$TMP/prefixpkgs"
  awk -F'\t' 'NR == FNR { p[$1] = 1; next } ($2 in p) { print $2 }' "$TMP/prefixpkgs" "$TMP/plan" | sort -u > "$TMP/hit"
  if [ -s "$TMP/hit" ]; then
    printf '\n%sSystem libraries the %s build links against (%s of %s such packages):%s\n' "$c_warn" "$PREFIX" \
      "$(grep -c . "$TMP/hit")" "$(grep -c . "$TMP/prefixpkgs")" "$c_off"
    awk -F'\t' 'NR == FNR { h[$1] = 1; next } ($2 in h) { printf "  %-45s %s -> %s\n", $3, ($4 == "" ? "-" : $4), $5 }' "$TMP/hit" "$TMP/plan"
    echo "  Components using them (same-release updates keep the ABI; a session restart picks them up):"
    # shellcheck disable=SC2046
    components_for_pkgs $(cat "$TMP/hit")
  fi

  # protected packages
  local p hit_prot=
  for p in $PROTECTED_PACKAGES; do awk -F'\t' -v p="$p" '$2 == p' "$TMP/plan" | grep -q . && hit_prot+=" $p"; done
  if [ -n "$hit_prot" ]; then
    if [ "$ALLOW_PROTECTED" = 1 ]; then warn "PROTECTED package(s) in the plan:$hit_prot (allowed by --allow-protected)."
    else printf '%sBLOCKER: PROTECTED package(s) in the plan:%s (config.env PROTECTED_PACKAGES; pass --allow-protected only if the owner agreed)%s\n' "$c_err" "$hit_prot" "$c_off"; BLOCK=1; fi
  fi
  if [ "$n_rm" -gt 0 ]; then
    printf '\n%s%s package(s) would be REMOVED:%s\n' "$c_err" "$n_rm" "$c_off"
    awk -F'\t' '$1 == "remove" { print "  " $3 " " $4 }' "$TMP/plan"
    if [ "$ALLOW_REMOVALS" = 1 ]; then warn "Removals allowed by --allow-removals."
    else printf '%sBLOCKER: removals are refused by default (review, then --allow-removals).%s\n' "$c_err" "$c_off"; BLOCK=1; fi
  fi
  local holds; holds=$(apt-mark showhold 2>/dev/null || true)
  [ -z "$holds" ] || echo "Held (not upgraded): $(echo "$holds" | tr '\n' ' ')"
  local other; other=$(awk -F'\t' -v k="$KERNEL_RE" -v n="$NVIDIA_RE" -v s="$PLUMBING_RE" '$1 != "remove" && $2 !~ k && $2 !~ n && $2 !~ s' "$TMP/plan" |
    awk -F'\t' -v prot=" $PROTECTED_PACKAGES " 'NR == FNR { h[$1] = 1; next } !($2 in h) && !index(prot, " " $2 " ") { print $3 }' "$TMP/hit" - | sort | tr '\n' ' ')
  [ -z "$other" ] || printf '\nOther: %s\n' "$other"
}

# ---------------------------------------------------------------- unattended-upgrades
uu_report(){
  local enabled bl origins
  enabled=$(apt-config shell X APT::Periodic::Unattended-Upgrade | sed -E "s/^X='?([^']*)'?$/\1/")
  if ! dpkg-query -W -f='${db:Status-Abbrev}' unattended-upgrades 2>/dev/null | grep -q '^ii' || [ "${enabled:-0}" = 0 ]; then
    echo "unattended-upgrades: off."; return 0
  fi
  bl=$(apt-config dump | awk -F'"' '/^Unattended-Upgrade::Package-Blacklist:: /{print $2}' | tr '\n' ' ')
  origins=$(apt-config dump | awk -F'"' '/^Unattended-Upgrade::Allowed-Origins:: /{print $2}' | tr '\n' ' ')
  echo "unattended-upgrades: ON (APT::Periodic::Unattended-Upgrade=$enabled; apt-daily-upgrade.timer $(systemctl is-enabled apt-daily-upgrade.timer 2>/dev/null))."
  echo "  origins: $origins"
  echo "  blacklist: ${bl:-<none>}"
  # u-u matches each blacklist entry as a regex against the start of the package name
  local risky=() name e covered
  for name in linux-image-generic-hwe-24.04 linux-modules-nvidia-595-open-generic-hwe-24.04 nvidia-driver-595-open libnvidia-gl-595; do
    covered=0
    for e in $bl; do [[ $name =~ ^$e ]] && covered=1; done
    [ "$covered" = 1 ] || risky+=("$name")
  done
  if [ ${#risky[@]} -gt 0 ]; then
    warn "unattended-upgrades may install kernel/NVIDIA updates from -security on its own (not blacklisted: ${risky[*]})."
    echo "  After it did: maintenance/update.sh --post (before rebooting). Proposed config: maintenance/update.sh --unattended"
  else
    ok "  kernel/NVIDIA packages are blacklisted for unattended-upgrades."
  fi
}
uu_proposal(){
  cat <<'EOF'

Proposed (NOT applied) /etc/apt/apt.conf.d/51hyprland-ii-unattended:
----
// Kernel, NVIDIA, boot chain and the protected agent only through maintenance/update.sh,
// which checks the DKMS/prebuilt module, initrd and Limine ESP copy before you reboot.
// Entries are Python regexes matched from the start of the package name.
Unattended-Upgrade::Package-Blacklist {
    "linux-";
    "nvidia-";
    "libnvidia-";
    "xserver-xorg-video-nvidia";
    "dkms$";
    "grub";
    "shim";
    "fleet-osquery$";
};
Unattended-Upgrade::Automatic-Reboot "false";
----
Apply: sudo tee /etc/apt/apt.conf.d/51hyprland-ii-unattended < that-file && sudo etckeeper commit "u-u: no kernel/nvidia"
Check: apt-config dump | grep Package-Blacklist ; sudo unattended-upgrade --dry-run --debug 2>&1 | grep -i blacklist
Trade-off: kernel/NVIDIA security fixes then wait for you (the shell's update counter shows them).
EOF
}

# ---------------------------------------------------------------- post-checks
nvidia_user_ver(){ dpkg-query -W -f='${Version}\n' 'nvidia-utils-*' 2>/dev/null | grep -m1 . | cut -d- -f1; }
esp_kver(){ strings "$1" 2>/dev/null | grep -m1 -oE '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-generic' || true; }
same_file(){ # a b: 0 same, 1 different, 2 unknown (unreadable without root)
  if [ -r "$1" ] && [ -r "$2" ]; then cmp -s "$1" "$2" && return 0 || return 1; fi
  if can_sudo; then sudo -n cmp -s "$1" "$2" && return 0 || return 1; fi
  [ "$(stat -c %s "$1" 2>/dev/null)" = "$(stat -c %s "$2" 2>/dev/null)" ] && return 2 || return 1
}
check_kernel_modules(){ # kver label
  local k=$1 uv mv
  [ -f "/lib/modules/$k/modules.dep" ] || { bootbad "$2 kernel $k: /lib/modules/$k missing (removed by autoremove?)."; return; }
  uv=$(nvidia_user_ver)
  [ -n "$uv" ] || return 0
  mv=$(modinfo -k "$k" -F version nvidia 2>/dev/null || true)
  if [ -z "$mv" ]; then
    bootbad "$2 kernel $k: no nvidia module. Fix: sudo dkms autoinstall -k $k  (or install linux-modules-nvidia-*-$k)"
  elif [ "$mv" != "$uv" ]; then
    bootbad "$2 kernel $k: nvidia module $mv != userspace $uv ($(modinfo -k "$k" -n nvidia)). Fix: sudo dkms autoinstall -k $k"
  else
    ok "  $2 kernel $k: nvidia $mv ($(modinfo -k "$k" -n nvidia | sed "s|/lib/modules/$k/||"))"
  fi
}
check_boot(){
  local newest running esp_new esp_old r
  newest=$(find /boot -maxdepth 1 -name 'vmlinuz-*' -printf '%f\n' | sed 's/^vmlinuz-//' | sort -V | tail -1)
  running=$(uname -r)
  echo "Kernels: running $running, newest installed $newest"
  check_kernel_modules "$newest" newest
  [ -s "/boot/initrd.img-$newest" ] || bootbad "No /boot/initrd.img-$newest. Fix: sudo update-initramfs -c -k $newest"
  if [ ! -f "$ESP/limine.conf" ]; then warn "No $ESP/limine.conf (not booting via Limine?): ESP checks skipped."; return; fi
  mountpoint -q "$ESP" || { bootbad "$ESP is not mounted: limine-esp-sync silently skipped. Fix: sudo mount $ESP && sudo limine-esp-sync $newest"; return; }
  for f in /usr/local/sbin/limine-esp-sync /etc/kernel/postinst.d/zz-limine-esp /etc/initramfs/post-update.d/limine-esp; do
    [ -x "$f" ] || bootbad "Missing sync hook $f (re-run phase 91)."
  done
  esp_new=$(esp_kver "$ESP/vmlinuz")
  [ "$esp_new" = "$newest" ] || bootbad "ESP vmlinuz is $esp_new, not the newest kernel $newest. Fix: sudo limine-esp-sync $newest"
  r=0; same_file "/boot/vmlinuz-$newest" "$ESP/vmlinuz" || r=$?
  case $r in 0) ;; 1) bootbad "ESP vmlinuz differs from /boot/vmlinuz-$newest. Fix: sudo limine-esp-sync $newest" ;;
              2) echo "  (ESP vmlinuz: version and size match; content not compared: /boot/vmlinuz-* is root-only and sudo needs a password)" ;; esac
  r=0; same_file "/boot/initrd.img-$newest" "$ESP/initrd.img" || r=$?
  case $r in 0) ;; 1) bootbad "ESP initrd.img differs from /boot/initrd.img-$newest. Fix: sudo limine-esp-sync $newest" ;;
              2) echo "  (ESP initrd: size matches; content not compared without root)" ;; esac
  esp_old=$(esp_kver "$ESP/vmlinuz.old")
  if [ -z "$esp_old" ]; then warn "No fallback kernel on the ESP ($ESP/vmlinuz.old)."
  else check_kernel_modules "$esp_old" "fallback (ESP vmlinuz.old)"; fi
  grep -q 'mem_sleep_default=s2idle' "$ESP/limine.conf" || bootbad "limine.conf lost mem_sleep_default=s2idle (re-run phase 91)."
  grep -q 'resume=UUID=' "$ESP/limine.conf" || bootbad "limine.conf lost resume=UUID= (re-run phase 91)."
  [ "$BOOT_FAIL" = 1 ] || ok "(b) Next boot: ESP has $newest (kernel+initrd = /boot), fallback ${esp_old:-none}, NVIDIA module present."
  [ "$running" = "$newest" ] || echo "  Reboot to run $newest (Limine default entry)."
  # loaded module vs (possibly upgraded) userspace
  local uv lv; uv=$(nvidia_user_ver); lv=$(cat /sys/module/nvidia/version 2>/dev/null || true)
  if [ -n "$uv" ] && [ -n "$lv" ] && [ "$uv" != "$lv" ]; then
    warn "REBOOT NEEDED: NVIDIA userspace is $uv, loaded module $lv. New GL/CUDA apps and a fresh Hyprland login fail until you reboot (don't just log out)."
  fi
}
check_sleep_setup(){
  local u s conf=/etc/modprobe.d/nvidia-sleep-fix.conf ksn dpm f0=$FAIL
  FAIL=0
  [ -f "$conf" ] || { echo "(d) Phase 90 not applied ($conf missing): sleep checks skipped."; return 0; }
  for u in nvidia-suspend nvidia-resume nvidia-hibernate nvidia-suspend-then-hibernate; do
    s=$(systemctl is-enabled "$u.service" 2>/dev/null || true)
    [ "$s" = masked ] || bad "$u.service is '$s', not masked (phase 90). Fix: sudo systemctl mask $u.service"
  done
  ksn=$(modprobe -c 2>/dev/null | awk '/^options nvidia /' | grep -oE 'NVreg_UseKernelSuspendNotifiers=[^ ]+' | tail -1 | cut -d= -f2)
  dpm=$(modprobe -c 2>/dev/null | awk '/^options nvidia /' | grep -oE 'NVreg_DynamicPowerManagement=[^ ]+' | tail -1 | cut -d= -f2)
  [ "$ksn" = 1 ] || bad "Effective NVreg_UseKernelSuspendNotifiers is '${ksn:-unset}', not 1 (a driver package overrides $conf?)."
  [ "$dpm" = 0x00 ] || bad "Effective NVreg_DynamicPowerManagement is '${dpm:-unset}', not 0x00."
  if [ -f /etc/systemd/system/gpu-warm.service ]; then
    s=$(systemctl is-enabled gpu-warm.service 2>/dev/null || true); [ "$s" = enabled ] || bad "gpu-warm.service is '$s' (phase 95)."
  fi
  [ "$FAIL" = 1 ] || ok "(d) nvidia-suspend/resume/hibernate masked; NVreg_UseKernelSuspendNotifiers=1, DynamicPowerManagement=0x00 in effect."
  [ "$f0" = 0 ] || FAIL=1
}
check_protected(){
  local last=$UPD/protected-last.txt
  [ -n "$PROTECTED_UNITS$PROTECTED_PACKAGES$PROTECTED_PATHS" ] || return 0
  if [ -f "$last" ]; then
    if [ "$(protected_fingerprint)" = "$(cat "$last")" ]; then ok "(c) Protected state = last snapshot ($(stat -c %y "$last" | cut -d. -f1))."
    else bad "(c) Protected state differs from the last snapshot ($last); expected only if Fleet updated itself:"
      diff "$last" <(protected_fingerprint) >&2 || true
      echo "    If that change is expected (agent self-update), accept it: protected_fingerprint is re-recorded after rm $last"; fi
  else
    protected_fingerprint > "$last"; echo "(c) Protected fingerprint recorded in $last (the in-run check happens on exit)."
  fi
}

upgraded_since(){ # -> package names (no arch) installed/upgraded in dpkg.log after $1
  { zcat -f /var/log/dpkg.log.*.gz 2>/dev/null || true; cat /var/log/dpkg.log.1 /var/log/dpkg.log 2>/dev/null || true; } |
    awk -v s="$1" '($3 == "upgrade" || $3 == "install") && ($1 " " $2) > s { n = $4; sub(/:.*/, "", n); print n }' | sort -u
}

post_checks(){ # [package...] that were upgraded
  step "Post-checks"
  build_cache   # always fresh: package names/paths may have changed
  check_missing
  check_boot
  check_protected
  check_sleep_setup
  if [ $# -gt 0 ]; then
    printf '%s\n' "$@" | sort -u > "$TMP/upgraded"
    cut -f3 "$CACHE" ${PRE_CACHE:+"$PRE_CACHE"} | grep -vx '?' | sort -u > "$TMP/prefixpkgs"
    comm -12 "$TMP/upgraded" "$TMP/prefixpkgs" > "$TMP/hit"
    if [ -s "$TMP/hit" ]; then
      echo "(e) Upgraded system libs used by $PREFIX: $(tr '\n' ' ' < "$TMP/hit")"
      echo "    Components linking them (log out/in to load the new libs; rebuild with maintenance/bump.sh <component> only if one misbehaves or (a) failed):"
      # shellcheck disable=SC2046
      components_for_pkgs $(cat "$TMP/hit")
    else
      ok "(e) None of the $# upgraded packages are libs the $PREFIX build links against."
    fi
  else
    echo "(e) No upgraded packages in the window."
  fi
  date '+%F %T' > "$UPD/last-post"
  echo
  if [ "$BOOT_FAIL" = 1 ]; then
    printf '%s%s\n  DO NOT REBOOT: the next boot is not verified (see the warnings above).\n%s%s\n' "$c_err" "$(printf '%.0s#' {1..78})" "$(printf '%.0s#' {1..78})" "$c_off" >&2
    exit 4
  fi
  [ "$FAIL" = 0 ] || die "Post-checks failed (see above)."
  ok "All post-checks passed."
}

# ---------------------------------------------------------------- main
case $MODE in
  unattended)
    uu_report
    echo "History (unattended-upgrades log): $(grep -hc 'Packages that will be upgraded' /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null || true) run(s) with upgrades;" \
      "kernel/NVIDIA among them: $(grep -h 'Packages that will be upgraded' /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null | grep -cE ' (linux-image|linux-modules|nvidia-|libnvidia-)' || true)"
    uu_proposal; exit 0 ;;
  post)
    if [ -z "$SINCE" ]; then SINCE=$(cat "$UPD/last-post" 2>/dev/null || date -d '-7 days' '+%F %T'); fi
    echo "Packages changed since $SINCE (dpkg.log):"
    mapfile -t CHANGED < <(upgraded_since "$SINCE")
    echo "  ${#CHANGED[@]} package(s)${CHANGED[*]:+: $(printf '%s ' "${CHANGED[@]}" | cut -c1-600)}"
    post_checks "${CHANGED[@]}"
    exit 0 ;;
esac

step "Refreshing package lists"
refresh_lists
step "Simulating apt-get full-upgrade"
ensure_cache
simulate
summarize
echo
uu_report
check_missing   # catches breakage that happened before this run (e.g. unattended-upgrades)

if [ "$MODE" = check ]; then
  [ "$BLOCK" = 0 ] || exit 2
  exit "$FAIL"
fi

[ "$BLOCK" = 0 ] || die "Blockers above; nothing changed."
FAIL=0   # a pre-existing problem found above is re-checked after the upgrade
if ! [ -s "$TMP/plan" ]; then
  ok "Nothing to upgrade."
  post_checks
  exit 0
fi
confirm "Snapshot, then run sudo apt-get full-upgrade with this plan?" || die "Aborted; nothing changed."

step "Snapshot"
sudo -v
TS=$(date +%Y%m%d-%H%M%S); SNAP=$UPD/$TS; mkdir -p "$SNAP"
cp "$TMP/sim" "$SNAP/simulation.txt"; cp "$TMP/plan" "$SNAP/plan.tsv"; cp "$CACHE" "$SNAP/prefix-syslibs.tsv"
PRE_CACHE=$SNAP/prefix-syslibs.tsv
dpkg -l > "$SNAP/dpkg-l.txt"
dpkg-query -W -f='${db:Status-Abbrev}\t${Package}:${Architecture}\t${Version}\n' > "$SNAP/versions-all.tsv"
apt-mark showhold > "$SNAP/holds.txt"; apt-mark showmanual > "$SNAP/manual.txt"
awk -F'\t' '$1 == "upgrade" { print $3 "=" $4 }' "$TMP/plan" > "$SNAP/old-versions.txt"
awk -F'\t' '$1 == "new" { print $3 }' "$TMP/plan" > "$SNAP/newly-installed.txt"
# Which old versions could actually be reinstalled (still in an archive, or a .deb in apt's cache)?
: > "$SNAP/downgrade-availability.txt"
while IFS='=' read -r p v; do
  if apt-cache show "$p=$v" 2>/dev/null | grep -q '^Filename:'; then src=archive
  elif ls /var/cache/apt/archives/"${p%%:*}"_"${v//:/%3a}"_*.deb >/dev/null 2>&1; then src=cache
  else src=NONE; fi
  printf '%s=%s\t%s\n' "$p" "$v" "$src" >> "$SNAP/downgrade-availability.txt"
done < "$SNAP/old-versions.txt"
n_none=$(grep -c $'\tNONE$' "$SNAP/downgrade-availability.txt" || true)
{ echo '#!/bin/sh'; echo "# Reinstall the versions from before update.sh $TS (newly installed packages: see newly-installed.txt)"
  echo "sudo apt-get install --allow-downgrades $(tr '\n' ' ' < "$SNAP/old-versions.txt")"; } > "$SNAP/downgrade.sh"
chmod +x "$SNAP/downgrade.sh"
protected_fingerprint > "$SNAP/protected.txt"; cp -f "$SNAP/protected.txt" "$UPD/protected-last.txt"
{ ls -l /boot "$ESP"; cat "$ESP/limine.conf"; } > "$SNAP/boot.txt" 2>&1 || true
echo "Snapshot: $SNAP ($(grep -c . "$SNAP/old-versions.txt" || true) old versions; $n_none of them not re-downloadable, see downgrade-availability.txt)"
if command -v etckeeper >/dev/null && sudo etckeeper unclean; then
  sudo etckeeper commit "update.sh: before full-upgrade ($TS)"
fi

step "apt-get full-upgrade (log: /var/log/apt/term.log)"
APT_OPTS=()
[ "$ALLOW_REMOVALS" = 1 ] || APT_OPTS+=(--no-remove)
[ "${ASSUME_YES:-0}" = 1 ] && APT_OPTS+=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
set +e; sudo apt-get full-upgrade "${APT_OPTS[@]}"; rc=$?; set -e
[ "$rc" = 0 ] || warn "apt-get full-upgrade exited with $rc; running the post-checks anyway."
command -v etckeeper >/dev/null && { sudo etckeeper unclean && sudo etckeeper commit "update.sh: after full-upgrade ($TS)" || true; }
# shellcheck disable=SC2046
post_checks $(awk -F'\t' '$1 != "remove" { print $2 }' "$TMP/plan")
[ "$rc" = 0 ] || exit 1
