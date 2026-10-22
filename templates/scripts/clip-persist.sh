#!/usr/bin/env bash
# Keep copied text alive after the app that copied it quits.
# Wayland: the app that copied owns the clipboard, so quitting it (e.g. Super+Q on VS Code) empties the clipboard.
# Each time the text clipboard changes, hand ownership to wl-copy, which keeps serving it. Loop guard: a hash of the text
# we last re-copied (our own wl-copy triggers the watcher again). Text only: images stay with cliphist history, and the
# html/rich flavours of a copy are not kept (plain text is). Password-manager copies (hint type) are left alone.
set -u
state="${XDG_RUNTIME_DIR:-/tmp}/clip-persist.last"

if [ "${1:-}" = "--handle" ]; then
  wl-paste --list-types 2>/dev/null | grep -q x-kde-passwordManagerHint && exit 0
  text=$(cat; printf x); text=${text%x}   # sentinel keeps trailing newlines
  [ -n "$text" ] || exit 0
  h=$(printf %s "$text" | sha256sum | cut -d' ' -f1)
  [ "$h" = "$(cat "$state" 2>/dev/null)" ] && exit 0
  printf %s "$h" > "$state"
  printf %s "$text" | wl-copy
  exit 0
fi

exec wl-paste --type text --watch "$0" --handle
