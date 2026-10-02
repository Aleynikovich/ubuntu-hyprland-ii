#!/usr/bin/env bash
# kitty from the upstream release binary (Ubuntu's 0.32 has no cursor_trail and recompiles its Python modules on every launch)
# -> ~/.local/kitty.app, plus launcher entries and the xdg default terminal. No sudo, no apt.
# Rollback: rm -rf ~/.local/kitty.app ~/.local/bin/{kitty,kitten} ~/.local/share/applications/kitty{,-open}.desktop ~/.config/xdg-terminals.list
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

K=$HOME/.local/kitty.app
if [ -x "$K/bin/kitty" ] && [ "$("$K/bin/kitty" --version | awk '{print $2}')" = "$KITTY_VER" ]; then
  ok "kitty $KITTY_VER already installed"
else
  step "kitty $KITTY_VER -> $K"
  tmp=$(mktemp -d); at_exit 'rm -rf "$tmp"'
  curl -fsSL -o "$tmp/kitty.txz" "https://github.com/kovidgoyal/kitty/releases/download/v$KITTY_VER/kitty-$KITTY_VER-x86_64.txz"
  mkdir -p "$tmp/x" && tar -xJf "$tmp/kitty.txz" -C "$tmp/x"
  rm -rf "$K"; mv "$tmp/x" "$K"
fi

mkdir -p ~/.local/bin ~/.local/share/applications ~/.config
ln -sfn "$K/bin/kitty" ~/.local/bin/kitty; ln -sfn "$K/bin/kitten" ~/.local/bin/kitten
for f in kitty kitty-open; do   # absolute Exec/Icon: the session's PATH has no ~/.local/bin
  sed -e "s|^Exec=kitty|Exec=$K/bin/kitty|" -e "s|^Icon=kitty|Icon=$K/share/icons/hicolor/256x256/apps/kitty.png|" \
    "$K/share/applications/$f.desktop" > ~/.local/share/applications/$f.desktop
done
update-desktop-database ~/.local/share/applications 2>/dev/null || true
printf 'kitty.desktop\n' > ~/.config/xdg-terminals.list

# Config: the template has the Catppuccin palette, 72% opacity, cursor trail, and no remembered window size (a remembered
# "maximized" state made kitty open fullscreen instead of tiling).
mkdir -p ~/.config/kitty
if [ -f ~/.config/kitty/kitty.conf ] && ! cmp -s "$REPO/templates/kitty.conf" ~/.config/kitty/kitty.conf && [ ! -e ~/.config/kitty/kitty.conf.orig ]; then
  cp ~/.config/kitty/kitty.conf ~/.config/kitty/kitty.conf.orig
fi
install -m644 "$REPO/templates/kitty.conf" ~/.config/kitty/kitty.conf
rm -f ~/.cache/kitty/main.json
ok "kitty ready"
