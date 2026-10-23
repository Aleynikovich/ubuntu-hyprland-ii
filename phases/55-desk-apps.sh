#!/usr/bin/env bash
# Desk apps: Slack, WhatsApp, Linear, Notion as Vivaldi app windows with a home workspace and a jump key each.
# Why: as Vivaldi tabs they can't be told apart, so they can't have a fixed place. templates/scripts/desk-app.sh opens each one as an app
#   window (its own class) on its home workspace and jumps to it from anywhere, on either monitor. Apps and home workspaces are listed in
#   the script, keys in the keybinds block below.
# Rollback: remove the desk-app blocks from ~/.config/hypr/custom/keybinds.lua and rules.lua, and ~/.config/hypr/custom/scripts/desk-app.sh
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

step "desk-app script"
install -Dm755 "$(dirname "$0")/../templates/scripts/desk-app.sh" ~/.config/hypr/custom/scripts/desk-app.sh

step "Jump keys"
BINDS="$HOME/.config/hypr/custom/keybinds.lua"
if grep -q desk-app.sh "$BINDS" 2>/dev/null; then echo "binds already present"; else
  cat >> "$BINDS" <<'EOF2'

-- Desk apps (custom/scripts/desk-app.sh): SUPER+ALT+key jumps to the app (opens it on its home workspace if it isn't running; again on it
-- cycles its windows, or goes back if there is only one). SUPER+SHIFT+ALT+key opens another window of it on this workspace.
-- Ordered (pairs() isn't) so the cheatsheet (SUPER+/) lists them in this order, under "Desk".
for _, d in ipairs({ { "C", "slack", "Slack" }, { "W", "whatsapp", "WhatsApp" }, { "L", "linear", "Linear" }, { "N", "notion", "Notion" } }) do
    local key, app, name = d[1], d[2], d[3]
    hl.bind("SUPER + ALT + " .. key, hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/desk-app.sh " .. app), { description = "Desk: " .. name })
    hl.bind("SUPER + SHIFT + ALT + " .. key, hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/desk-app.sh " .. app .. " new"),
        { description = "Desk: New " .. name .. " window here" })
end
EOF2
fi

step "Opaque app windows"
# Their class is vivaldi-<host>__<path>-<profile>, which the vivaldi-stable rule (no blur, opaque) doesn't match.
RULES="$HOME/.config/hypr/custom/rules.lua"
if grep -q 'desk-app' "$RULES" 2>/dev/null; then echo "rule already present"; else
  cat >> "$RULES" <<'EOF2'
-- Vivaldi app windows (custom/scripts/desk-app.sh): opaque, no blur, like the browser itself
hl.window_rule({match = { class = "^vivaldi-.*__.*$" }, no_blur = true, opacity = 1})
EOF2
fi
ok "SUPER+ALT+C/W/L/N: Slack, WhatsApp, Linear, Notion (Hyprland reloads the binds on save)"
