#!/usr/bin/env bash
# Compare the live ~/.config dirs that phase 50 installs with the pinned end-4/dots-hyprland (DOTS_COMMIT in config.env).
# Read-only: never changes ~/.config or the $SRC/dots-hyprland checkout (trees are exported with `git archive` into
# $SRC/dots-pinned/<sha>; the checkout is only fetched into when a commit is missing).
#   maintenance/diff-dots.sh [-p] [--against <commit|branch>] [path...]
#     (default)  summary: M modified, A only in ~/.config, D missing from ~/.config, T same as the repo's template
#     -p         full unified diffs instead of the summary
#     --against  preview a dots bump: compares DOTS_COMMIT -> <commit> for the files in ~/.config, and flags files
#                changed on both sides (C), with whether `git merge-file` would merge them cleanly. Use origin/main for upstream HEAD.
#     path...    only these paths, relative to ~/.config (e.g. hypr/custom quickshell/ii/modules/bar)
# Files that phase 50 installs from templates/ are compared with the template, not with upstream.
# ~/.config/illogical-impulse/config.json isn't in the dots (the shell writes it); its keys are checked against
# templates/illogical-impulse-config.json instead.
set -euo pipefail
PROTECTED_UNITS='' PROTECTED_PACKAGES='' PROTECTED_PATHS=''   # read-only: skip the protected-state check
source "$(dirname "$0")/../lib/common.sh"

DOTS=$SRC/dots-hyprland
CACHE=$SRC/dots-pinned
# Same dirs as phase 50's COPY, plus foot (phase 50 installs templates/foot.ini there).
eval "$(grep -m1 '^COPY=(' "$REPO/phases/50-dots.sh")"
[ "${#COPY[@]}" -gt 0 ] || die "couldn't read COPY=(...) from phases/50-dots.sh"
DIRS=("${COPY[@]}" foot)
# Written at runtime by the shell/fish/switchwall.sh, not by anyone's hand. Matched against the path relative to ~/.config.
IGNORE='^(fish/fish_variables|hypr/custom/scripts/__restore_video_wallpaper\.sh|foot/foot\.ini\.orig)$|(^|/)\.git$|(^|/)__pycache__/|\.pyc$|\.bak[^/]*$'
# Expected to show as M: edited in place by this repo's phases, or rewritten by matugen on every wallpaper change.
label(){ # label <rel> -> why the file differs, if known
  case $1 in
    hypr/hyprlock.conf|quickshell/ii/scripts/colors/applycolor.sh) echo '  (phase 50 edits this)' ;;
    hypr/hypridle.conf) echo '  (phase 90 edits this)' ;;
    hypr/hyprland/colors.lua|hypr/hyprlock/colors.conf|fuzzel/fuzzel_theme.ini) echo '  (matugen: wallpaper colours)' ;;
  esac
}

PATCH=0 AGAINST='' FILTER=()
while [ $# -gt 0 ]; do
  case $1 in
    -p) PATCH=1 ;;
    --against) [ $# -ge 2 ] || die "--against needs a commit"; AGAINST=$2; shift ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*) die "unknown option: $1 (see --help)" ;;
    *) FILTER+=("${1%/}") ;;
  esac
  shift
done

resolve(){ # resolve <commit|ref> -> full sha, fetching from origin if the checkout doesn't have it
  local r=$1 c
  if c=$(git -C "$DOTS" rev-parse -q --verify "$r^{commit}"); then
    [[ $r == origin/* ]] || { echo "$c"; return; }   # remote-tracking refs: refresh first
  fi
  git -C "$DOTS" fetch -q origin 2>/dev/null || true
  git -C "$DOTS" fetch -q origin "${r#origin/}" 2>/dev/null || true
  c=$(git -C "$DOTS" rev-parse -q --verify "$r^{commit}") || c=$(git -C "$DOTS" rev-parse -q --verify "FETCH_HEAD^{commit}") \
    || die "dots commit not found: $r"
  echo "$c"
}

export_tree(){ # export_tree <sha> -> dir holding that commit's dots/.config (cached; submodules included)
  local c=$1 out=$CACHE/$1 mode type sha path
  if [ ! -f "$out/.complete" ]; then
    rm -rf "$out"; mkdir -p "$out"
    git -C "$DOTS" archive "$c" dots/.config | tar -x -C "$out" --strip-components=2
    # git archive leaves submodules (quickshell's shapes widget) as empty dirs: export them from their own repos.
    while read -r mode type sha path; do
      [ "$type" = commit ] || continue
      if ! git -C "$DOTS/$path" cat-file -e "$sha^{commit}" 2>/dev/null && ! git -C "$DOTS/$path" fetch -q origin "$sha" 2>/dev/null; then
        warn "submodule $path @ ${sha:0:7} not available locally; its files are skipped"; continue
      fi
      mkdir -p "$out/${path#dots/.config/}"
      git -C "$DOTS/$path" archive "$sha" | tar -x -C "$out/${path#dots/.config/}"
    done < <(git -C "$DOTS" ls-tree -r "$c" dots/.config)
    touch "$out/.complete"
  fi
  echo "$out"
}

template_for(){ # template_for <rel> -> repo template phase 50 installs at ~/.config/<rel>, if any
  case $1 in
    foot/foot.ini) echo "$REPO/templates/foot.ini" ;;
    hypr/custom/*) [ ! -f "$REPO/templates/hypr-custom/${1#hypr/custom/}" ] || echo "$REPO/templates/hypr-custom/${1#hypr/custom/}" ;;
  esac
}

wanted(){ # wanted <rel> -> 0 if it passes the path filter
  local f
  [ "${#FILTER[@]}" -gt 0 ] || return 0
  for f in "${FILTER[@]}"; do [[ $1 == "$f" || $1 == "$f"/* ]] && return 0; done
  return 1
}

same(){ # same <a> <b> -> 0 if both exist with identical content, or both are missing
  if [ -e "$1" ] && [ -e "$2" ]; then cmp -s "$1" "$2"; else [ ! -e "$1" ] && [ ! -e "$2" ]; fi
}

udiff(){ # udiff <old> <new> <old-label> <new-label>
  local a=$1 b=$2
  [ -e "$a" ] || a=/dev/null; [ -e "$b" ] || b=/dev/null
  diff -u --color=auto --label "$3" --label "$4" "$a" "$b" || true
}

[ -d "$DOTS" ] || git clone -q "$DOTS_REPO" "$DOTS"
BASE=$(resolve "$DOTS_COMMIT"); B=$(export_tree "$BASE")
if [ -n "$AGAINST" ]; then NEW=$(resolve "$AGAINST"); N=$(export_tree "$NEW"); fi

# Every file under the compared dirs, upstream (base and, with --against, new) or local.
mapfile -t FILES < <(
  for d in "${DIRS[@]}"; do
    for root in "$B" ${N:+"$N"} "$HOME/.config"; do
      [ -d "$root/$d" ] && (cd "$root" && find "$d" \( -type f -o -type l \) -print)
    done
  done | sort -u | grep -Ev "$IGNORE" || true
)

declare -A COUNT=()
note(){ COUNT[$1]=$(( ${COUNT[$1]:-0} + 1 )); }

if [ -z "$AGAINST" ]; then
  [ $PATCH = 1 ] || step "~/.config vs dots @ ${BASE:0:7} (M modified, A local only, D missing locally, T = repo template)"
  for rel in "${FILES[@]}"; do
    wanted "$rel" || continue
    local_f=$HOME/.config/$rel ref=$B/$rel tag='' lbl="dots@${BASE:0:7}/$rel"
    t=$(template_for "$rel")
    if [ -n "$t" ]; then ref=$t tag='  (vs templates/)' lbl="templates/${t#"$REPO"/templates/}"; fi
    [ -n "$t" ] || tag=$(label "$rel")
    same "$ref" "$local_f" && { [ -z "$t" ] || { note T; [ $PATCH = 1 ] || echo "T  $rel"; }; continue; }
    if [ ! -e "$ref" ]; then s=A; elif [ ! -e "$local_f" ]; then s=D; else s=M; fi
    note "$s"
    if [ $PATCH = 1 ]; then udiff "$ref" "$local_f" "$lbl" "local/$rel"; else echo "$s  $rel$tag"; fi
  done
else
  [ $PATCH = 1 ] || step "Dots bump ${BASE:0:7} -> ${NEW:0:7}: what it changes in files you have (U only upstream changed it, C both changed it, N new upstream, R removed upstream)"
  for rel in "${FILES[@]}"; do
    wanted "$rel" || continue
    local_f=$HOME/.config/$rel base=$B/$rel new=$N/$rel
    [ -z "$(template_for "$rel")" ] || continue   # repo templates: bumping the dots doesn't touch them
    up=1; same "$base" "$new" && up=0
    loc=1; same "$base" "$local_f" && loc=0
    [ $up = 1 ] || continue   # upstream didn't change it: nothing to merge
    if [ ! -e "$base" ]; then s=N; extra=''; [ -e "$local_f" ] && { same "$new" "$local_f" && continue; s=C extra='  (exists locally, differs)'; }
    elif [ ! -e "$new" ]; then s=R; extra=''; [ $loc = 1 ] && extra='  (you changed it)'
    elif [ $loc = 0 ]; then s=U; extra=''
    elif same "$new" "$local_f"; then continue   # you already have upstream's new version
    elif [ ! -e "$local_f" ]; then s=U; extra='  (missing locally)'
    else
      s=C; m=$(mktemp); cp "$local_f" "$m"
      if git merge-file -q "$m" "$base" "$new"; then extra='  (merges cleanly)'; else extra="  ($? conflict(s))"; fi
      rm -f "$m"
    fi
    extra+=$(label "$rel")
    note "$s"
    if [ $PATCH = 0 ]; then echo "$s  $rel$extra"; continue; fi
    echo "### $s $rel$extra"
    udiff "$base" "$new" "dots@${BASE:0:7}/$rel" "dots@${NEW:0:7}/$rel"
    if [ "$s" = C ] && [ -e "$base" ]; then
      echo "### your changes:"; udiff "$base" "$local_f" "dots@${BASE:0:7}/$rel" "local/$rel"
    fi
  done
fi

# The shell's config.json: generated at first start, so compare only the keys the repo sets (templates/illogical-impulse-config.json).
CJ=$HOME/.config/illogical-impulse/config.json OV=$REPO/templates/illogical-impulse-config.json
if [ -z "$AGAINST" ] && [ -f "$OV" ] && wanted illogical-impulse/config.json; then
  [ $PATCH = 1 ] || step "illogical-impulse/config.json vs templates/illogical-impulse-config.json (only the keys the template sets)"
  if [ ! -f "$CJ" ]; then echo "D  illogical-impulse/config.json (the shell hasn't started yet)"
  elif ! command -v jq >/dev/null; then warn "jq not installed: skipped"
  else
    # One "path = value" line per template leaf (arrays compared whole); print those where config.json differs.
    leaves='paths(type != "object") as $p | select(($p | map(type) | index("number")) == null) | $p'
    while IFS= read -r p; do
      want=$(jq -c --argjson p "$p" 'getpath($p)' "$OV"); have=$(jq -c --argjson p "$p" 'getpath($p)' "$CJ")
      [ "$want" = "$have" ] && { note T; continue; }
      note M; echo "M  config.json $(jq -rn --argjson p "$p" '$p | join(".")'): $have  (template: $want)"
    done < <(jq -c "$leaves" "$OV")
  fi
fi

[ $PATCH = 1 ] && exit 0
summary=''
for s in M A D T U C N R; do [ -z "${COUNT[$s]:-}" ] || summary+="$s=${COUNT[$s]} "; done
ok "${summary:-no differences}"
