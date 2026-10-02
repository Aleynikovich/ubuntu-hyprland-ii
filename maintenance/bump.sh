#!/usr/bin/env bash
# Bump (or just rebuild) one git-sourced component of phases/30-build.sh. Steps:
#   1. check patches/ against the new tag (or the pinned one); stop if any fail (--dry-run: exit 1)
#   2. rewrite the tag in phases/30-build.sh (only if a new tag is given)
#   3. delete the component's stamp and source dir in $SRC (asks first)
#   4. run phases/30-build.sh <component>
# Usage: maintenance/bump.sh [--dry-run] <component|source-dir> [new-tag]   (--dry-run: steps 1 and a plan, no changes)
# Rollback: git checkout phases/30-build.sh, then rerun this without a tag.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$REPO/lib/patches.sh"

DRY=0
[ "${1:-}" = --dry-run ] && { DRY=1; shift; }
[ $# -ge 1 ] && [ $# -le 2 ] || die "Usage: $0 [--dry-run] <component> [new-tag]"
C=$(src_comp "$1")
[ -n "$C" ] || die "Not a git-sourced component in 30-build.sh: $1 (known: $(src_table | cut -d' ' -f1 | paste -sd' '))"
read -r _ KIND URL OLD DIR < <(src_entry "$C")
NEW=${2:-$OLD}
STAMP=$SRC/.stamps/$C

step "$C: $OLD -> $NEW  ($URL)"
if [ "$NEW" != "$OLD" ] && [ "$KIND" = src ]; then
  lsrc=0; git ls-remote --exit-code -q "$URL" "refs/tags/$NEW" >/dev/null || lsrc=$?
  [ $lsrc = 2 ] && die "No tag $NEW at $URL"
  [ $lsrc = 0 ] || die "Could not reach $URL (git ls-remote exit $lsrc)"
fi
PATCHES_OK=1
if ! check_patches "$C=$NEW"; then
  PATCHES_OK=0; [ $DRY = 1 ] || die "Patches don't apply to $NEW: refresh patches/$DIR-*.patch first."
  warn "Patches don't apply to $NEW: a real run would stop here."
fi

step "Plan"
NEWPHASE=$(mktemp); at_exit "rm -f '$NEWPHASE'"
if [ "$NEW" != "$OLD" ]; then
  # Literal replacement (tags contain dots) on the line the table was read from, then re-read to be sure.
  LINE=$(grep -n "^c_$C(){" "$BUILD_PHASE" | cut -d: -f1)
  awk -v n="$LINE" -v a=" $URL $OLD $DIR" -v b=" $URL $NEW $DIR" \
    'NR == n { i = index($0, a); if (i) $0 = substr($0, 1, i - 1) b substr($0, i + length(a)) } 1' "$BUILD_PHASE" > "$NEWPHASE"
  [ "$(BUILD_PHASE=$NEWPHASE src_entry "$C" | cut -d' ' -f4)" = "$NEW" ] || die "Could not rewrite the tag on line $LINE of $BUILD_PHASE"
  diff -u --label "a/phases/30-build.sh" --label "b/phases/30-build.sh" "$BUILD_PHASE" "$NEWPHASE" || true
fi
[ -e "$STAMP" ] && echo "rm     $STAMP" || echo "(no stamp $STAMP)"
[ -d "$SRC/$DIR" ] && echo "rm -rf $SRC/$DIR  ($(du -sh "$SRC/$DIR" | cut -f1))" || echo "(no source dir $SRC/$DIR)"
echo "run    phases/30-build.sh $C"
if [ $DRY = 1 ]; then ok "Dry run: nothing changed."; [ $PATCHES_OK = 1 ]; exit; fi
confirm "Go ahead?" || die "Aborted."

if [ "$NEW" != "$OLD" ]; then cat "$NEWPHASE" > "$BUILD_PHASE"; ok "phases/30-build.sh: $C $OLD -> $NEW"; fi  # cat keeps the mode
rm -f "$STAMP"; rm -rf "${SRC:?}/${DIR:?}"
bash "$BUILD_PHASE" "$C"
