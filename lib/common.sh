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

# Hardware guard for machine-specific phases (90+). Compares DMI "vendor|product|version" against HW_TESTED (config.env).
# Dies on mismatch unless HII_FORCE_HW=1: a separate opt-in, because ASSUME_YES must not silently write another laptop's
# bootloader/kernel cmdline/EDID. `require_hw report` only prints the result (phase 00).
hw_id(){ local f; for f in sys_vendor product_name product_version; do cat "/sys/class/dmi/id/$f" 2>/dev/null || echo '?'; done | paste -sd'|'; }
require_hw(){
  local id t tested; id=$(hw_id); IFS=';' read -ra tested <<<"$HW_TESTED"
  for t in "${tested[@]}"; do [ "$id" = "$t" ] && { [ "${1:-}" != report ] || ok "Hardware matches HW_TESTED: $id"; return 0; }; done
  [ "${1:-}" = report ] && { warn "Hardware not tested: found '$id', tested '$HW_TESTED'. Phases 90-95 will refuse unless HII_FORCE_HW=1."; return 0; }
  [ "${HII_FORCE_HW:-0}" = 1 ] && { warn "Hardware '$id' != tested '$HW_TESTED'; continuing (HII_FORCE_HW=1)."; return 0; }
  die "This phase is specific to '$HW_TESTED' (DMI vendor|product|version); this machine is '$id'. Review it, then rerun with HII_FORCE_HW=1."
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

# Record/compare the state of PROTECTED_UNITS/PACKAGES/PATHS (config.env) so every run can prove it didn't change them.
protected_fingerprint(){
  local u p f
  for u in $PROTECTED_UNITS; do
    printf 'unit %s active=%s enabled=%s def=%s\n' "$u" "$(systemctl is-active "$u" 2>/dev/null)" \
      "$(systemctl is-enabled "$u" 2>/dev/null)" "$(systemctl cat "$u" 2>/dev/null | sha256sum | cut -c1-16)"
  done
  for p in $PROTECTED_PACKAGES; do
    printf 'pkg %s %s\n' "$p" "$(dpkg-query -W -f='${Version} ${db:Status-Abbrev}' "$p" 2>/dev/null || echo absent)"
  done
  for f in $PROTECTED_PATHS; do
    printf 'path %s %s\n' "$f" "$(stat -c '%U:%G %a %F' "$f" 2>/dev/null || echo absent)"
  done
}
protected_check(){ # protected_check <before-file>; returns 1 if anything changed
  local after; after=$(protected_fingerprint)
  if [ "$after" = "$(cat "$1")" ]; then ok "Protected state unchanged (PROTECTED_* in config.env)."; return 0; fi
  warn "PROTECTED STATE CHANGED (PROTECTED_* in config.env):"; diff "$1" <(echo "$after") >&2 || true; return 1
}

# Cleanup hooks: use `at_exit 'cmd'` instead of `trap ... EXIT`, which would replace the guard below.
_AT_EXIT=()
at_exit(){ _AT_EXIT+=("$1"); }
_on_exit(){
  local rc=$? c
  for c in "${_AT_EXIT[@]}"; do eval "$c" || true; done
  if [ -n "${_PROTECTED_OWNER:-}" ]; then
    protected_check "$HII_PROTECTED_BEFORE" || { [ "$rc" -ne 0 ] || rc=3; }
    rm -f "$HII_PROTECTED_BEFORE"
  fi
  exit "$rc"
}
trap _on_exit EXIT

# Guard: the outermost script (setup.sh, or a phase run on its own) fingerprints first and checks on exit;
# nested phases inherit HII_PROTECTED_BEFORE and leave the check to it. Exit code 3 = protected state changed.
if [ -z "${HII_PROTECTED_BEFORE:-}" ] && [ -n "$PROTECTED_UNITS$PROTECTED_PACKAGES$PROTECTED_PATHS" ]; then
  HII_PROTECTED_BEFORE=$(mktemp); export HII_PROTECTED_BEFORE; _PROTECTED_OWNER=1
  protected_fingerprint > "$HII_PROTECTED_BEFORE"
fi
