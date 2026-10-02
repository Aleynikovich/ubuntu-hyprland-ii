#!/usr/bin/env bash
# Run the phases in order, or pick some. Every phase can also be run directly: phases/NN-name.sh
# Either way, lib/common.sh fingerprints PROTECTED_* (config.env) first and fails (exit 3) if they changed.
#   ./setup.sh                 all default phases
#   ./setup.sh 30 40           only those phases (by number prefix)
#   ./setup.sh --list
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
export REPO
source "$REPO/lib/common.sh"

# 10-remove-snaps and 70-vscode are opt-in: pass them explicitly.
DEFAULT=(00 15 20 30 40 50 60)

if [ "${1:-}" = --list ] || [ "${1:-}" = -h ]; then
  for f in "$REPO"/phases/*.sh; do printf '%-26s %s\n' "$(basename "$f")" "$(sed -n 2p "$f" | sed 's/^# //')"; done
  echo; echo "Default: ${DEFAULT[*]}   (opt-in: 10 = remove snaps, 70 = VS Code)"; exit 0
fi
[ $# -gt 0 ] && SEL=("$@") || SEL=("${DEFAULT[@]}")

for n in "${SEL[@]}"; do
  f=$(ls "$REPO"/phases/"$n"-*.sh 2>/dev/null | head -1)
  [ -n "$f" ] || die "No phase $n (see --list)"
  step "Phase $(basename "$f")"
  bash "$f"
done

ok "Done: ${SEL[*]}"
