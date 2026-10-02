#!/usr/bin/env bash
# Copy the illogical-impulse dots, but only into config dirs that don't exist yet and that Plasma doesn't read.
# Also installs the session wrapper + shims and registers the Hyprland portal for D-Bus. No sudo.
# Rollback: rm -rf the dirs listed in $SRC/dots-installed.txt, rm -rf "$PREFIX/session-bin",
#           systemctl --user disable xdg-desktop-portal-hyprland.service,
#           rm ~/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service ~/.local/share/xdg-desktop-portal/portals/hyprland.portal
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

P=$PREFIX
DOTS=$SRC/dots-hyprland
LOG=$SRC/dots-installed.txt

# Copied: used only by the Hyprland session. xdg-desktop-portal holds hyprland-portals.conf (only read when desktop=Hyprland).
COPY=(hypr quickshell fuzzel matugen wlogout fish xdg-desktop-portal)
# Deliberately NOT copied (Plasma/other apps read them): kdeglobals dolphinrc konsolerc starship.toml fontconfig
#   Kvantum darklyrc kde-material-you-colors zshrc.d mpv *-flags.conf. The upstream installer's gsettings/kwriteconfig
#   theme changes and user-group changes (input, i2c) are skipped too.

step "Dots @ ${DOTS_COMMIT:0:7}"
[ -d "$DOTS" ] || git clone -q "$DOTS_REPO" "$DOTS"
git -C "$DOTS" fetch -q origin "$DOTS_COMMIT" 2>/dev/null || true
git -C "$DOTS" checkout -q "$DOTS_COMMIT"
git -C "$DOTS" submodule update -q --init --recursive

touch "$LOG"
# Terminal: foot (see ~/.config/foot/foot.ini); text editor: VS Code (the dots try kate first). custom/variables.lua is the dots' override file and survives updates.
if [ ! -s ~/.config/hypr/custom/variables.lua ]; then
  mkdir -p ~/.config/hypr/custom
  printf -- '-- Personal overrides (loaded after hyprland/variables.lua; survives dots updates)\nterminal = "foot"\ntextEditor = "code"\n' > ~/.config/hypr/custom/variables.lua
fi
for d in "${COPY[@]}"; do
  if [ -e "$HOME/.config/$d" ]; then echo "skip (exists): ~/.config/$d"; continue; fi
  rsync -a "$DOTS/dots/.config/$d/" "$HOME/.config/$d/"
  echo "$HOME/.config/$d" >> "$LOG"; echo "copied: ~/.config/$d"
done
mkdir -p ~/.local/share/icons
[ -e ~/.local/share/icons/illogical-impulse.svg ] || cp "$DOTS/dots/.local/share/icons/illogical-impulse.svg" ~/.local/share/icons/

# hyprlock fallback: Ubuntu has no /etc/pam.d/hyprlock (PAM would fall back to "deny all"). Use the login policy,
# the same one Quickshell's lock screen uses, instead of adding a file to /etc.
if ! grep -q 'module = login' ~/.config/hypr/hyprlock.conf; then
  printf '\n# Ubuntu: no /etc/pam.d/hyprlock; use the login policy (same one Quickshell lock uses)\nauth {\n    pam {\n        module = login\n    }\n}\n' >> ~/.config/hypr/hyprlock.conf
fi

step "foot terminal: config + point the shell's terminal actions at it"
# The dots ship their own foot.ini; ours (templates/foot.ini) keeps their keybindings and adds fonts/padding/Catppuccin Macchiato/88% alpha.
mkdir -p ~/.config/foot
if [ -f ~/.config/foot/foot.ini ] && ! cmp -s "$REPO/templates/foot.ini" ~/.config/foot/foot.ini && [ ! -e ~/.config/foot/foot.ini.orig ]; then
  cp ~/.config/foot/foot.ini ~/.config/foot/foot.ini.orig
fi
install -m644 "$REPO/templates/foot.ini" ~/.config/foot/foot.ini
sed -i 's/^term_alpha=100/term_alpha=88/' ~/.config/quickshell/ii/scripts/colors/applycolor.sh   # wallpaper theming keeps the terminal translucent
CJ=~/.config/illogical-impulse/config.json   # exists after the shell's first run; skipped (with a note) otherwise
if [ -f "$CJ" ]; then
  sed -i 's/kitty -1 --hold=\?[a-z]* \?/foot --hold /; s/"terminal": "kitty -1"/"terminal": "foot"/; s/"kitty"/"foot"/' "$CJ"
else
  warn "no $CJ yet: start the shell once, then re-run phase 50 to point its terminal actions at foot"
fi

step "Session wrapper + shims -> $P/session-bin"
S=$P/session-bin; mkdir -p "$S"
for b in Hyprland hyprland hyprctl hyprpm hyprlock hypridle hyprpicker hyprsunset start-hyprland hyprland-share-picker \
         hyprland-dialog hyprland-donate-screen hyprland-run hyprland-update-screen hyprland-welcome \
         hyprshot matugen starship uv uvx quickshell swappy; do
  if [ -e "$P/bin/$b" ]; then ln -sfn "$P/bin/$b" "$S/$b"; fi
done
install -m755 "$REPO/session/hyprland-ii-session" "$S/hyprland-ii-session"
sed -i "s|^P=\"\$HOME/.local/opt/hyprland\"|P=\"$P\"|" "$S/hyprland-ii-session"   # honour a custom PREFIX
rm -f "$S/qs"   # was a plain symlink to $P/bin/qs before the logging shim
install -m755 "$REPO"/session/shims/* "$S/"

step "Register xdg-desktop-portal-hyprland (UseIn=Hyprland/wlroots only; ignored under KDE)"
mkdir -p ~/.local/share/dbus-1/services ~/.local/share/xdg-desktop-portal/portals
ln -sfn "$P/share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service" ~/.local/share/dbus-1/services/
ln -sfn "$P/share/xdg-desktop-portal/portals/hyprland.portal" ~/.local/share/xdg-desktop-portal/portals/
# Linked, not enabled: has ConditionEnvironment=WAYLAND_DISPLAY, so it never starts under X11 Plasma.
systemctl --user link "$P/lib/systemd/user/xdg-desktop-portal-hyprland.service" 2>/dev/null || true

step "Config check"
rt=$(mktemp -d); at_exit 'rm -rf "$rt"'
XDG_RUNTIME_DIR=$rt "$P/bin/Hyprland" --verify-config -c ~/.config/hypr/hyprland.lua 2>&1 | tail -1
ok "Dots installed. Copied dirs are listed in $LOG"
