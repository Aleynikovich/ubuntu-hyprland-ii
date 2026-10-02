#!/usr/bin/env bash
# Apps the dots call at runtime: apt (new packages only) + release binaries + fonts/cursor/GTK theme + Python venv.
# Rollback: sudo apt-get purge $(cat "$SRC/apt-installed-runtime.txt") && sudo apt-get autoremove
#           rm -rf ~/.local/share/fonts/illogical-impulse ~/.local/share/icons/Bibata-Modern-Classic \
#                  ~/.local/share/themes/adw-gtk3* ~/.local/state/quickshell/.venv && fc-cache -f
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

P=$PREFIX
DL=$SRC/dl
mkdir -p "$DL" "$P/bin"
[ -x "$P/bin/Hyprland" ] || warn "Hyprland not built yet (run 30-build first); continuing anyway."

step "apt: runtime apps"
mapfile -t pkgs < <(grep -v -E '^\s*(#|$)' "$REPO/packages/apt-runtime.txt")
sudo -v
apt_install_new_only "$SRC/apt-installed-runtime.txt" "${pkgs[@]}"

gh_asset(){ # repo regex -> download URL of the latest release asset
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" | python3 -c '
import sys,json,re
d=json.load(sys.stdin); r=re.compile(sys.argv[1])
print(next(a["browser_download_url"] for a in d["assets"] if r.search(a["name"])))' "$2"
}
verify_sha256(){ echo "$(curl -fsSL "$2" | awk '{print $1}')  $1" | sha256sum -c -; }
gh_dir_ttf(){ # repo dir regex -> URL-encoded download URLs (font filenames contain [axes])
  curl -fsSL "https://api.github.com/repos/$1/contents/$2" | python3 -c '
import sys,json,re; r=re.compile(sys.argv[1])
[print(a["download_url"]) for a in json.load(sys.stdin) if a["name"].endswith(".ttf") and r.search(a["name"])]' "$3"
}

cd "$DL"
step "Release binaries -> $P/bin (not packaged for 24.04)"
U=$(gh_asset astral-sh/uv '^uv-x86_64-unknown-linux-gnu\.tar\.gz$'); wget -q -O uv.tgz "$U"; verify_sha256 uv.tgz "$U.sha256"
tar -xzf uv.tgz --strip-components=1 -C "$P/bin" --wildcards '*/uv' '*/uvx'
U=$(gh_asset starship/starship '^starship-x86_64-unknown-linux-musl\.tar\.gz$'); wget -q -O starship.tgz "$U"; verify_sha256 starship.tgz "$U.sha256"
tar -xzf starship.tgz -C "$P/bin" starship
U=$(gh_asset InioX/matugen 'x86_64.*\.tar\.gz$'); wget -q -O matugen.tgz "$U"
rm -rf matugen-x && mkdir matugen-x && tar -xzf matugen.tgz -C matugen-x
install -m755 "$(find matugen-x -type f -name matugen | head -1)" "$P/bin/matugen"
wget -q -O "$P/bin/hyprshot" https://raw.githubusercontent.com/Gustash/Hyprshot/main/hyprshot; chmod 755 "$P/bin/hyprshot"

step "Fonts -> ~/.local/share/fonts/illogical-impulse"
F=$HOME/.local/share/fonts/illogical-impulse; mkdir -p "$F"
for spec in 'google/fonts ofl/rubik .' 'google/fonts ofl/readexpro .' 'google/fonts ofl/spacegrotesk .' 'google/fonts ofl/googlesansflex .' \
            'google/material-design-icons variablefont ^MaterialSymbols(Rounded|Outlined)'; do
  set -- $spec
  for u in $(gh_dir_ttf "$1" "$2" "$3"); do
    curl -fsSL -o "$F/$(python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.argv[1].rsplit("/",1)[1]))' "$u")" "$u"
  done
done
U=$(gh_asset ryanoasis/nerd-fonts '^JetBrainsMono\.tar\.xz$'); wget -q -O jbm-nf.txz "$U"
mkdir -p "$F/JetBrainsMonoNF"; tar -xJf jbm-nf.txz -C "$F/JetBrainsMonoNF" --wildcards 'JetBrainsMonoNerdFont-*.ttf'  # dots use only this family (not Mono/Propo/NL)
fc-cache -f "$F" >/dev/null

step "Bibata cursor + adw-gtk3 theme"
U=$(gh_asset ful1e5/Bibata_Cursor '^Bibata-Modern-Classic\.tar\.xz$'); wget -q -O bibata.txz "$U"
mkdir -p ~/.local/share/icons ~/.local/share/themes
tar -xJf bibata.txz -C ~/.local/share/icons
U=$(gh_asset lassekongo83/adw-gtk3 '\.tar\.xz$'); wget -q -O adw.txz "$U"; tar -xJf adw.txz -C ~/.local/share/themes

step "Python venv for the shell's scripts (~/.local/state/quickshell/.venv)"
DOTS=$SRC/dots-hyprland
[ -d "$DOTS" ] || git clone -q "$DOTS_REPO" "$DOTS"
git -C "$DOTS" fetch -q origin "$DOTS_COMMIT" 2>/dev/null || true
git -C "$DOTS" checkout -q "$DOTS_COMMIT"
V=$HOME/.local/state/quickshell/.venv
mkdir -p "$(dirname "$V")"
[ -x "$V/bin/python" ] || UV_NO_MODIFY_PATH=1 "$P/bin/uv" venv --prompt .venv "$V" -p 3.12
VIRTUAL_ENV=$V "$P/bin/uv" pip install -q -r "$DOTS/sdata/uv/requirements.txt"
"$V/bin/python" -c 'import PIL, gi, cv2, materialyoucolor, pywayland; print("venv ok")'

ok "Runtime ready."
