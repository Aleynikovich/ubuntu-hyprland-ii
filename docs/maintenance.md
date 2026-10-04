# Maintenance: rollback, extra software, updates

[← Back to the README](../README.md)

## Rollback

Each phase script's header has its own rollback line. Everything at once:

```bash
sudo rm /usr/share/wayland-sessions/hyprland-ii.desktop
sudo apt-get purge $(cat ~/src/hypr/apt-installed-build.txt ~/src/hypr/apt-installed-runtime.txt) && sudo apt-get autoremove
systemctl --user disable xdg-desktop-portal-hyprland.service
rm -rf ~/.local/opt/hyprland ~/.local/state/quickshell \
       ~/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service \
       ~/.local/share/xdg-desktop-portal/portals/hyprland.portal
xargs -a ~/src/hypr/dots-installed.txt rm -rf     # only the config dirs this repo created
rm -rf ~/src/hypr
```

Config backups from phase 15 are in `~/backups/config-*/`.


## Installing other software (no snaps, no Flatpak)

1. `sudo apt install <pkg>` from Ubuntu's repos.
2. The vendor's signed apt repo (key in `/etc/apt/keyrings`, repo in `/etc/apt/sources.list.d/*.sources`); see `phases/70-vscode.sh` for the pattern, including checking the key fingerprint.
3. A vendor `.deb`: `sudo apt install ./file.deb`.
4. Arch/AUR-only things: an Arch [distrobox](https://distrobox.it) container, with apps exported to the host launcher.


## Updating

Rebuilding while logged in to Hyprland is safe: meson/cmake components install via a staging dir and replace files with new inodes, so the running session keeps its old copies until you log in again.

### The Hyprland build

Bump with `maintenance/bump.sh <component> [new-tag]` (e.g. `maintenance/bump.sh hyprland v0.56.3`; a source dir name like `Hyprland` works too). It checks that `patches/` still apply to the new tag (a proposed tag or commit is checked out even for components without patches, so a typo fails before anything is deleted), shows the tag edit to `phases/30-build.sh` and the stamp/source dir in `~/src/hypr` it will delete, asks once, and rebuilds that component. Leave out the tag to just rebuild from a clean source dir. `--dry-run` runs the patch check and shows the plan without changing anything. Components that depend on a bumped library are not rebuilt automatically. `QT_VER`/`DOTS_COMMIT` in `config.env` are still edited by hand.

`./setup.sh --check-patches` checks every patch against its pinned tag; `./setup.sh --check-patches hyprland=v0.57.0 aquamarine=v0.16.0` checks a proposed bump. It works in temporary checkouts and never modifies the trees in `~/src/hypr`. The build applies patches from the same list (`lib/patches.sh`).

### The dots

- `maintenance/diff-dots.sh` lists what differs between `~/.config/{hypr,quickshell,fuzzel,matugen,wlogout,fish,xdg-desktop-portal,foot}` and the pinned dots (`DOTS_COMMIT`); `-p` shows the diffs, paths filter (`diff-dots.sh -p hypr/custom`). Before bumping `DOTS_COMMIT`, `diff-dots.sh --against origin/main` lists the files the bump changes and flags those you changed too (C), with whether they merge cleanly. Read-only; upstream trees are cached in `~/src/hypr/dots-pinned`.
- Templates (fresh installs): phase 50 fills `~/.config/hypr/custom/*.lua` from `templates/hypr-custom/` only where the file is blank or missing, and applies `templates/illogical-impulse-config.json` (foot for the terminal/update/password actions, `maintenance/update.sh` instead of pacman, foot/VS Code pinned) to the shell's `config.json`, only to keys still at the dots' kitty/pacman default.

### The system (apt)

`maintenance/update.sh` wraps `apt full-upgrade`:

```bash
maintenance/update.sh --check     # what would change; no root, no changes (exit 2 = blockers)
maintenance/update.sh             # check, confirm, snapshot, upgrade, verify
maintenance/update.sh --post      # verify only, e.g. after unattended-upgrades (before rebooting)
```

- **Before:** the plan is grouped into kernel/boot chain, NVIDIA, session plumbing, and the system libraries the `~/.local/opt/hyprland` build links against (found with `ldd` over every ELF there, cached in `~/src/hypr/update/`), with the components that use them. Removals and anything in `PROTECTED_PACKAGES` are refused (`--allow-removals`, `--allow-protected`); during the real run the protected packages are held and the plan is re-simulated right before upgrading.
- **Snapshot:** `~/src/hypr/update/<timestamp>/` keeps all installed versions, holds, the plan and a `downgrade.sh` with the exact old versions (`downgrade-availability.txt` says which ones can still be downloaded); `/etc` is committed to etckeeper before and after.
- **After:** (a) every ELF under the prefix still resolves its libraries (Qt's optional plugins that never resolved are a recorded baseline; `--rebaseline` accepts the current state); (b) the newest kernel has an NVIDIA module matching the userspace driver and an initrd; the files the default `limine.conf` entry points to are that kernel (BLAKE2b-verified when hashed) and its cmdline has `s2idle`/`resume=`/`resume_offset=` (and the EDID pin); the fallback entry's kernel still has its modules; if any of this fails it prints **DO NOT REBOOT** with the fix; (c) the protected state is unchanged; (d) the phase 90/95 settings survived; (e) which prefix components link against upgraded libraries. Library updates within 24.04 keep the ABI: log out and back in. Rebuild a component (`maintenance/bump.sh <component>`) only if (a) fails or it misbehaves.
- After an NVIDIA driver upgrade, **reboot** rather than logging out: until then the new userspace libraries don't match the loaded kernel module.

**unattended-upgrades** is on by default and installs from `noble-security`, which includes kernels and NVIDIA drivers. `maintenance/update.sh --unattended` shows what it may do and prints a proposed blacklist (`/etc/apt/apt.conf.d/51hyprland-ii-unattended`) that leaves kernel, NVIDIA, GRUB/shim and the Fleet agent to `update.sh`. Either way, run `update.sh --post` after it has installed something.
