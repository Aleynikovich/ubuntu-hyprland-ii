# Shared helpers. Sourced by setup.sh and every phase; not meant to be run directly.
# shellcheck shell=bash

REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../config.env
source "$REPO/config.env"

c_info=$'\033[1;36m'; c_warn=$'\033[1;33m'; c_err=$'\033[1;31m'; c_ok=$'\033[1;32m'; c_off=$'\033[0m'
step(){ printf '\n%s== %s%s\n' "$c_info" "$*" "$c_off"; }
warn(){ printf '%sWARN: %s%s\n' "$c_warn" "$*" "$c_off" >&2; }
die(){ printf '%sERROR: %s%s\n' "$c_err" "$*" "$c_off" >&2; exit 1; }
ok(){ printf '%s%s%s\n' "$c_ok" "$*" "$c_off"; }

confirm(){ # confirm "question" -> returns 0 on y/Y; ASSUME_YES=1 skips the prompt
  [ "${ASSUME_YES:-0}" = 1 ] && return 0
  local a; read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[yY]$ ]]
}

[ "$(id -u)" -ne 0 ] || die "Run as your normal user; phases call sudo themselves where needed."

# apt install that refuses to upgrade or remove anything already installed (dry run first).
# Usage: apt_install_new_only <record-file> pkg...
apt_install_new_only(){
  local record=$1; shift
  local sim; sim=$(apt-get -s install --no-install-recommends "$@" 2>&1) || { echo "$sim" | tail -5; die "apt dry run failed"; }
  local touched removed
  touched=$(echo "$sim" | grep -E '^Inst \S+ \[' || true)
  removed=$(echo "$sim" | grep -E '^Remv' || true)
  if [ -n "$touched$removed" ]; then
    echo "$touched"; echo "$removed"
    confirm "The packages above would be UPGRADED or REMOVED. Continue anyway?" || die "Aborted: refusing to change existing packages."
  fi
  echo "$sim" | awk '/^Inst/{print $2}' >> "$record"
  echo "Installing $(echo "$sim" | grep -c '^Inst') new package(s) (recorded in $record for rollback)."
  sudo apt-get install -y --no-install-recommends "$@"
}

# Record/compare the state of PROTECTED_UNITS (and their package) so phases can prove they didn't change them.
protected_fingerprint(){
  local u
  for u in $PROTECTED_UNITS; do
    printf '%s active=%s enabled=%s\n' "$u" "$(systemctl is-active "$u" 2>/dev/null)" "$(systemctl is-enabled "$u" 2>/dev/null)"
    local exe; exe=$(systemctl show -p ExecStart --value "$u" 2>/dev/null | grep -oE 'path=[^ ;]+' | head -1 | cut -d= -f2)
    [ -n "$exe" ] && dpkg -S "$exe" 2>/dev/null | cut -d: -f1 | xargs -r dpkg-query -W -f='  pkg ${Package} ${Version}\n'
  done
}
protected_check(){ # protected_check <before-file>
  [ -z "$PROTECTED_UNITS" ] && return 0
  local after; after=$(protected_fingerprint)
  if diff <(cat "$1") <(echo "$after") >/dev/null; then ok "Protected units unchanged: $PROTECTED_UNITS"
  else warn "Protected units CHANGED:"; diff <(cat "$1") <(echo "$after") || true; fi
}
