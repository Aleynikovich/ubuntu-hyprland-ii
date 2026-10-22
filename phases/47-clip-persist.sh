#!/usr/bin/env bash
# Clipboard persistence: copied text survives quitting the app it came from.
# Why: on Wayland the copying app owns the clipboard, so closing it (Super+Q on VS Code) empties it. wl-clip-persist is not packaged for Ubuntu
#   (and needs a Rust toolchain), so templates/scripts/clip-persist.sh does the same for text with wl-clipboard's wl-paste --watch + wl-copy.
# Rollback: remove the clip-persist line from ~/.config/hypr/custom/execs.lua and ~/.config/hypr/custom/scripts/clip-persist.sh; pkill -f 'wl-paste --type text --watch .*clip-persist'
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

step "clip-persist script"
install -Dm755 "$(dirname "$0")/../templates/scripts/clip-persist.sh" ~/.config/hypr/custom/scripts/clip-persist.sh

step "Start it with Hyprland"
EXECS="$HOME/.config/hypr/custom/execs.lua"
if grep -q clip-persist.sh "$EXECS" 2>/dev/null; then echo "exec already present"; else
  cat >> "$EXECS" <<'EOF2'

-- Keep copied text after the source app quits (templates/scripts/clip-persist.sh)
hl.on("hyprland.start", function ()
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/clip-persist.sh")
end)
EOF2
fi
ok "Clipboard text persists from the next login. Now: ~/.config/hypr/custom/scripts/clip-persist.sh & disown"
