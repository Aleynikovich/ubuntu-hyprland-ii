# Patch checks against pinned (or proposed) tags. Sourced by setup.sh and maintenance/bump.sh after lib/common.sh.
# The tags are read from the `c_name(){ git_src|git_commit url ref dir` lines in phases/30-build.sh, so nothing is built.
# shellcheck shell=bash

BUILD_PHASE="$REPO/phases/30-build.sh"

src_table(){ # -> "component kind url ref dir" per git-sourced component
  sed -nE 's/^c_([a-z0-9_]+)\(\)\{ *git_(src|commit) +([^ ]+) +([^ ]+) +([^ ;]+).*/\1 \2 \3 \4 \5/p' "$BUILD_PHASE"
}
src_entry(){ src_table | awk -v c="$1" '$1 == c'; }  # component -> its table line (empty if not git-sourced)
src_comp(){ src_table | awk -v c="$1" '$1 == c || $5 == c {print $1; exit}'; }  # component or source dir -> component

patch_dir(){ # patch file -> source dir it belongs to (longest "<dir>-" prefix, so wayland-* never takes wayland-protocols-*)
  local b d best=; b=$(basename "$1")
  while read -r _ _ _ _ d; do [[ "$b" == "$d"-* && ${#d} -gt ${#best} ]] && best=$d; done < <(src_table)
  echo "$best"
}
patches_for(){ # dir -> its patches, in the order 30-build.sh applies them
  local p
  for p in "$REPO"/patches/"$1"-*.patch; do [ -e "$p" ] && [ "$(patch_dir "$p")" = "$1" ] && echo "$p"; done
  return 0
}

checkout_ref(){ # kind url ref dir dest: pristine tree at ref; reuses $SRC/<dir> read-only when it is already at ref
  # progress goes to fd 3, git's own output to stdout/stderr
  local kind=$1 url=$2 ref=$3 dir=$4 dest=$5 have want=
  if [ -d "$SRC/$dir/.git" ]; then
    have=$(git -C "$SRC/$dir" rev-parse HEAD)
    if [ "$kind" = src ]; then want=$(git -C "$SRC/$dir" rev-parse -q --verify "refs/tags/$ref^{commit}" || true)
    elif [[ "$have" == "$ref"* ]]; then want=$have; fi
    if [ "$want" = "$have" ]; then
      echo "  $dir: reusing $SRC/$dir ($ref)" >&3
      git -c advice.detachedHead=false clone -q --shared --no-checkout "$SRC/$dir" "$dest" && git -C "$dest" checkout -q --detach "$have"; return
    fi
  fi
  echo "  $dir: fetching $ref" >&3
  if [ "$kind" = src ]; then git -c advice.detachedHead=false clone -q --depth 1 --branch "$ref" "$url" "$dest"
  else git -c advice.detachedHead=false clone -q --filter=blob:none --no-checkout "$url" "$dest" && git -C "$dest" checkout -q "$ref"; fi
}

# check_patches [component[=ref] ...]: apply each component's patches (as 30-build.sh does) to a clean checkout of
# the pinned ref, or of the given ref for a proposed bump. No args = every component that has patches.
# A proposed ref is checked out even without patches, so a typo'd tag/commit fails here and not mid-bump.
# Prints a pass/fail table; returns 1 if any patch fails, any ref can't be checked out, or a patch matches no component.
check_patches(){
  local tmp a c ref p d kind url pin dir rc=0 rows=() errs=() comps=() orphans=() ps=() e
  declare -A want=()
  for a in "$@"; do
    c=$(src_comp "${a%%=*}")
    [ -n "$c" ] || die "Not a git-sourced component in 30-build.sh: ${a%%=*} (known: $(src_table | cut -d' ' -f1 | paste -sd' '))"
    [[ "$a" == *=* ]] && want[$c]=${a#*=} || want[$c]=${want[$c]:-}
    [[ " ${comps[*]} " == *" $c "* ]] || comps+=("$c")
  done
  if [ $# -eq 0 ]; then
    for p in "$REPO"/patches/*.patch; do
      [ -e "$p" ] || continue
      d=$(patch_dir "$p")
      if [ -z "$d" ]; then orphans+=("$p"); continue; fi
      c=$(src_table | awk -v d="$d" '$5 == d {print $1; exit}')
      [[ " ${comps[*]} " == *" $c "* ]] || comps+=("$c")
    done
  fi
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/hii-patchcheck.XXXXXX"); at_exit "rm -rf '$tmp'"
  step "Checking patches"
  for c in "${comps[@]}"; do
    read -r _ kind url pin dir < <(src_entry "$c")
    ref=${want[$c]:-$pin}
    mapfile -t ps < <(patches_for "$dir")
    if [ ${#ps[@]} -eq 0 ] && [ "$ref" = "$pin" ]; then rows+=("$c|$ref|(no patches)|ok"); continue; fi
    if ! checkout_ref "$kind" "$url" "$ref" "$dir" "$tmp/$c" 3>&1 > "$tmp/$c.log" 2>&1; then
      e=$(grep -v '^\s*$' "$tmp/$c.log" | tail -1); errs+=("$c: could not check out $ref: ${e:-git failed, no message}")
      [ ${#ps[@]} -eq 0 ] && rows+=("$c|$ref|(no patches)|FAIL")
      for p in "${ps[@]}"; do rows+=("$c|$ref|$(basename "$p")|FAIL"); done; rc=1; continue
    fi
    [ ${#ps[@]} -eq 0 ] && rows+=("$c|$ref|(no patches)|ok (ref exists)")
    for p in "${ps[@]}"; do  # applied for real, in order: a later patch may build on an earlier one
      if e=$(git -C "$tmp/$c" apply "$p" 2>&1); then rows+=("$c|$ref|$(basename "$p")|ok")
      else rows+=("$c|$ref|$(basename "$p")|FAIL"); errs+=("$(basename "$p") @ $ref:"$'\n'"$e"); rc=1; fi
    done
  done
  for p in "${orphans[@]}"; do rows+=("?|-|$(basename "$p")|FAIL"); errs+=("$(basename "$p"): no component's source dir matches its name prefix"); rc=1; done
  echo
  { echo "COMPONENT|REF|PATCH|RESULT"; printf '%s\n' "${rows[@]}"; } | column -t -s'|'
  for e in "${errs[@]}"; do echo; warn "$e"; done
  echo
  if [ $rc -eq 0 ]; then ok "All patches apply."; else warn "Some patches do not apply (see above)."; fi
  return $rc
}
