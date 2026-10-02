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
for d in "${COPY[@]}"; do
  if [ -e "$HOME/.config/$d" ]; then echo "skip (exists): ~/.config/$d"; continue; fi
  rsync -a "$DOTS/dots/.config/$d/" "$HOME/.config/$d/"
  echo "$HOME/.config/$d" >> "$LOG"; echo "copied: ~/.config/$d"
done
mkdir -p ~/.local/share/icons
[ -e ~/.local/share/icons/illogical-impulse.svg ] || cp "$DOTS/dots/.local/share/icons/illogical-impulse.svg" ~/.local/share/icons/
# templates/hypr-custom/*.lua -> ~/.config/hypr/custom/ (the dots' override files; they survive dots updates). Upstream ships
# them blank (one newline), so only blank or missing ones are filled. variables.lua: terminal kitty, text editor VS Code (the dots try kate first).
# After the copy loop: creating ~/.config/hypr first would make it skip the hypr dots.
mkdir -p ~/.config/hypr/custom
for t in "$REPO"/templates/hypr-custom/*; do
  f=~/.config/hypr/custom/$(basename "$t")
  if [ -f "$f" ] && grep -q '[^[:space:]]' "$f"; then echo "skip (not empty): $f"; else install -m644 "$t" "$f"; echo "installed: $f"; fi
done

# hyprlock fallback: Ubuntu has no /etc/pam.d/hyprlock (PAM would fall back to "deny all"). Use the login policy,
# the same one Quickshell's lock screen uses, instead of adding a file to /etc.
if ! grep -q 'module = login' ~/.config/hypr/hyprlock.conf; then
  printf '\n# Ubuntu: no /etc/pam.d/hyprlock; use the login policy (same one Quickshell lock uses)\nauth {\n    pam {\n        module = login\n    }\n}\n' >> ~/.config/hypr/hyprlock.conf
fi

step "Terminal: kitty (phase 48) + foot fallback config; wallpaper theming keeps terminals translucent"
# foot stays installed as a fallback: templates/foot.ini keeps the dots' keybindings and adds fonts/padding/Catppuccin Macchiato/72% alpha.
mkdir -p ~/.config/foot
if [ -f ~/.config/foot/foot.ini ] && ! cmp -s "$REPO/templates/foot.ini" ~/.config/foot/foot.ini && [ ! -e ~/.config/foot/foot.ini.orig ]; then
  cp ~/.config/foot/foot.ini ~/.config/foot/foot.ini.orig
fi
install -m644 "$REPO/templates/foot.ini" ~/.config/foot/foot.ini
# applycolor.sh: term_alpha (kitty ignores it: see kitty.conf background_opacity; foot takes it over OSC 11). The dots' OSC template hard-codes
# "[100]" (opaque) for foot, which overrides foot.ini's alpha at every shell start: make it follow term_alpha.
sed -i -E 's/^term_alpha=[0-9]+/term_alpha=72/' ~/.config/quickshell/ii/scripts/colors/applycolor.sh
sed -i 's/\[100\]/[$alpha]/g' ~/.config/quickshell/ii/scripts/colors/terminal/sequences.txt
# Terminal rice: kitty runs fish (kitty.conf `shell fish`); conf.d/rice.fish = zoxide/fzf/bat/eza + fastfetch greeting, kept apart from the dots'
# config.fish. starship.toml = the two-line prompt with the path/git pills (a previous one is kept as .orig; not a dots dir, so Plasma never reads it).
mkdir -p ~/.config/fish/conf.d
install -m644 "$REPO/templates/fish-rice.fish" ~/.config/fish/conf.d/rice.fish
if [ -f ~/.config/starship.toml ] && ! cmp -s "$REPO/templates/starship.toml" ~/.config/starship.toml && [ ! -e ~/.config/starship.toml.orig ]; then
  cp ~/.config/starship.toml ~/.config/starship.toml.orig
fi
install -m644 "$REPO/templates/starship.toml" ~/.config/starship.toml
# bat's Catppuccin theme (Ubuntu's bat doesn't ship it; rice.fish sets BAT_THEME): drop it in and rebuild bat's cache.
if command -v batcat >/dev/null; then
  mkdir -p ~/.config/bat/themes
  install -m644 "$REPO/templates/bat-catppuccin-macchiato.tmTheme" "$HOME/.config/bat/themes/Catppuccin Macchiato.tmTheme"
  batcat cache --build >/dev/null
fi
# The shell's config.json: templates/illogical-impulse-config.json holds the keys we set (terminal/update/password actions via
# kitty, "update" runs maintenance/update.sh instead of pacman; kitty + VS Code pinned instead of cmake-gui). A key is only set while
# config.json still has the dots' kitty/pacman default (or lacks it), so anything changed later in the shell's settings is kept.
CJ=~/.config/illogical-impulse/config.json   # exists after the shell's first run; skipped (with a note) otherwise
if [ ! -f "$CJ" ]; then
  warn "no $CJ yet: start the shell once, then re-run phase 50 to point its terminal actions at kitty"
elif ! command -v jq >/dev/null; then
  warn "jq not installed: $CJ left as is (apply templates/illogical-impulse-config.json by hand)"
else
  # @REPO@ in the template = this checkout; an earlier template's plain "apt upgrade" update action is replaced too
  jq --indent 4 --arg repo "$REPO" --arg home "$HOME" --slurpfile ov "$REPO/templates/illogical-impulse-config.json" '
    ($ov[0] | walk(if type == "string" then gsub("@REPO@"; $repo) | gsub("@HOME@"; $home) else . end)) as $o |
    reduce ($o | paths(type != "object") | select(map(type) | index("number") | not)) as $p (.;
      if (getpath($p) | . == null or (tojson | test("kitty|foot|pacman|apt upgrade"))) then setpath($p; $o | getpath($p)) else . end)
  ' "$CJ" > "$CJ.tmp" || { rm -f "$CJ.tmp"; die "Cannot parse $CJ (shell mid-write?); re-run phase 50."; }
  # Only replace the file when a value changed (jq reformats empty arrays; a rewrite makes the running shell reload).
  if jq -e --slurpfile new "$CJ.tmp" '. == $new[0]' "$CJ" >/dev/null; then rm "$CJ.tmp"; else mv "$CJ.tmp" "$CJ"; echo "updated: $CJ"; fi
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
