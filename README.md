# ubuntu-hyprland-ii

Hyprland 0.56 with [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) ("illogical-impulse") as an **extra login session** on Kubuntu 24.04, next to an untouched Plasma X11 session. Optionally (phase 80), Hyprland becomes the **only** desktop: Plasma, GNOME and the X11 sessions are removed and SDDM logs straight into Hyprland.

The upstream installer is Arch-first, and on Ubuntu it only offers an experimental Nix route that doesn't match the current (Lua-config) dots. This repo builds everything from source into one folder in your home instead.

Tested 2026-10-02: Kubuntu 24.04.5, Plasma 5.27 X11, SDDM, Lenovo Legion 7 16IRX9 with an RTX 4070 (dGPU-only/MUX mode, driver 595, `nvidia_drm modeset=1`). Isaac Sim runs in both sessions.

## Quick start

```bash
git clone <this repo> ~/src/ubuntu-hyprland-ii && cd ~/src/ubuntu-hyprland-ii
./setup.sh --list        # what each phase does
./setup.sh 00            # read-only preflight
./setup.sh 10            # optional: remove all snaps + pin snapd (asks first, backs up ~/snap)
./setup.sh               # 00 15 20 30 40 50 60: backup, deps, build (~30-60 min), runtime, dots, login entry
./setup.sh 45            # optional: EasyEffects + ddcutil (apt) + songrec (author's PPA, key fingerprint checked)
./setup.sh 70            # optional: VS Code from Microsoft's apt repo
./setup.sh 80            # optional, destructive: remove Plasma/KDE apps/GNOME/X11 sessions, autologin into Hyprland
```

Phase 80 pins `packages/hyprland-only-keep.txt` (what the dots use from KDE/GNOME: Dolphin, the KDE file dialog, the network/Bluetooth/users KCMs, plasma-systemmonitor, Breeze, gnome-keyring, fprintd; plus sssd, printing, audio/network plumbing) as manually installed, then purges what `apt --auto-remove` computes around `packages/hyprland-only-roots.txt`. It shows the list first (and `EXPECT=<file>` aborts unless the list matches a reviewed one). It removes ~660 packages / 2.4 GB on a `kde-full` + `ubuntu-desktop` install; nothing is installed. The X server core stays (the NVIDIA driver package depends on it), and so does XWayland. Removed packages are listed in `~/src/hypr/apt-removed-hyprland-only-*.txt` for reinstalling; `/etc` changes are in etckeeper.

Log out and pick **Hyprland (illogical-impulse)** in SDDM. Phases can be re-run: the build is resumable (stamps in `~/src/hypr/.stamps`); to rebuild one component, delete its stamp and run `phases/30-build.sh <component>`.

## What goes where

| Where | What |
|---|---|
| `~/.local/opt/hyprland` (`PREFIX`) | Hyprland, Quickshell, Qt 6.10, KF6 Kirigami, newer wayland/libinput/xkbcommon/libei/PipeWire-client, tools |
| `~/src/hypr` (`SRC`) | sources, build trees, logs, lists of apt packages installed (for rollback) |
| `~/.config/{hypr,quickshell,fuzzel,matugen,wlogout,fish,xdg-desktop-portal}` | dots: **only copied if the folder doesn't exist** |
| `~/.local/share/{fonts/illogical-impulse,icons,themes}` | fonts, Bibata cursor, adw-gtk3 |
| `/usr/share/wayland-sessions/hyprland-ii.desktop`, `/opt/MicroTeX` (link into `PREFIX`) | written outside your home (besides apt packages); phase 80 adds `/etc/sddm.conf.d/hyprland-ii-autologin.conf` |

Not touched: Plasma configs (`kdeglobals`, `dolphinrc`, `konsolerc`, `kitty`, `fontconfig`, ...), user groups, `gsettings`, `/etc/pam.d`, the NVIDIA driver, anything in `config.env`'s `PROTECTED_UNITS` (fingerprinted before and checked after every run).

## How it stays isolated

- **RPATH, not `LD_LIBRARY_PATH`.** Every binary carries its own library path, so the session sets no library or QML path variables and apps launched from Hyprland (Isaac Sim, etc.) get the normal system libraries.
- **apt: new packages only.** Each apt phase dry-runs first and refuses to proceed if an existing package would be upgraded or removed.
- **Private Qt.** Qt 6.10 comes from Qt's official binaries (aqtinstall); Ubuntu's Qt 6.4 is left alone. The shell's QML modules are linked into the private Qt's `qml/` folder.
- **pkg-config filter.** CMake otherwise resolves private libs to `/usr/lib` copies (via `-L/usr/lib/...` from `libseat.pc`); `tools/bin/pkg-config-filtered` strips system `-L` flags.

## Ubuntu-specific workarounds

- **Compiler:** Hyprland 0.56 uses C++26 `#embed`; built with `clang-20` from Ubuntu updates against the system libstdc++ 14.
- **`patches/`:** libstdc++ 14 lacks a few C++23/26 library bits (`vector::append_range`, `string + string_view`, `ranges::starts_with`), and clang-20 + libstdc++ 14 trips on `range | std::ranges::to<T>()`. The patches swap these for equivalent C++20 code (17 one-line changes). hyprsunset's patch keeps its systemd unit inside `PREFIX`. aquamarine's patch backports three DRM teardown fixes from upstream main (after 0.15.1, DRM.cpp only, no ABI change) plus the same null-connector guard on the VT switch-away path; aquamarine is built with debug info so DRM/session crashes resolve to a source line.
- **Built because noble lacks or has too-old versions:** swappy 1.8, wayland 1.26, wayland-protocols 1.49, libinput 1.32, xkbcommon 1.13, libdisplay-info 0.4, libei 1.6, Lua 5.5, xcb-util-errors, readline (no ncurses-dev needed), PipeWire 1.2 client lib (xdph needs ≥ 1.1.82), sdbus-c++ 2, cpptrace with libunwind.
- **Plasma 5 vs the dots' KDE 6 expectations:** `session-bin/kcmshell6` forwards to `kcmshell5`.
- **Terminal:** foot (`~/.config/hypr/custom/variables.lua` sets `terminal = "foot"`; `config.json` update/password actions run `foot --hold`, and "update" runs apt instead of pacman). foot.ini is a Catppuccin Macchiato fallback at 88% alpha; the wallpaper theme (`applycolor.sh`, `term_alpha=88`) recolours it via OSC sequences at fish start. kitty was dropped because Ubuntu's kitty recompiles its Python on every launch (~0.4s slower than foot).
- **Update counter:** `session-bin/checkupdates` stands in for Arch's `checkupdates` (`apt list --upgradable`).
- **ImageMagick 6:** `session-bin/magick` maps IM7-style calls to IM6 tools.
- **Lock screen:** Quickshell's lock and the hyprlock fallback both use `/etc/pam.d/login` (hyprlock is configured with `auth:pam:module = login`), so no PAM file is added.
- **Shell logs:** `session-bin/qs` is a shim that keeps each shell instance's output (Quickshell logs to stdout) in `~/.local/state/hyprland-ii/qs-<config>.log` (previous run as `.1`) with start/exit lines; `ipc`/`kill`/etc. subcommands pass straight through. Quickshell's own `.qslog` files are in `$XDG_RUNTIME_DIR` and are lost at logout.
- **Icons:** `QS_ICON_THEME=breeze-dark` (the private Qt has no KDE platform theme).
- **VS Code on Hyprland:** `~/.vscode/argv.json` gets `"password-store": "gnome-libsecret"` (Hyprland isn't auto-detected).

## Sleep and hibernate (phases 90-93, Lenovo Legion 7 16IRX9 + RTX 4070, driver 595 open)

Found the hard way (about ten hard reboots); don't undo these without testing with an RTC wake alarm, not the lid:

- **s2idle, not S3 "deep".** After S3 the NVIDIA driver never re-lights the eDP panel (black even on the text console). Phase 91 puts `mem_sleep_default=s2idle` on the Limine command line.
- **NVIDIA suspends from the kernel** (`NVreg_UseKernelSuspendNotifiers=1`, runtime D3 off) and the `nvidia-suspend/resume/hibernate` systemd services are masked: their `chvt 63` dance froze the whole machine on resume (phase 90).
- **Hibernate** uses a 32 GB `/swap.img` with `resume=UUID=... resume_offset=...` on the command line (phases 90/91). Wake it with the power button; the RTC alarm cannot wake from S4 here.
- **The machine boots Limine from the ESP, not GRUB** (phase 92 removes GRUB). Phase 91 installs `limine-esp-sync` (kernel postinst and `update-initramfs` hooks) so the ESP copy of the kernel/initrd follows `/boot`; the previous kernel stays as the second menu entry, without the EDID pin.
- Phase 93 pins the panel EDID (`drm.edid_firmware`): it stops a retry loop after resume, but it was not what fixed sleep.

## Known issues

- **Switching to a text console (Ctrl+Alt+F*n*) inside Hyprland** crashed it (segfault at address 0 in aquamarine when the seat is disabled). `patches/aquamarine-drm-teardown-fixes.patch` targets this but is not confirmed yet; until it is, log out instead. If it still crashes: `journalctl -k -b | grep segfault`, then `llvm-addr2line-20 -f -C -i -e ~/.local/opt/hyprland/lib/libaquamarine.so.0.15.1 0x<offset>` with the offset from the `[...]` part.
- **ydotool** is a shim over `wtype` (`session-bin/ydotool`): real ydotool needs `/dev/uinput`, i.e. permission for any of your programs to type into every session; wtype uses Hyprland's virtual-keyboard protocol and only reaches Hyprland windows. It covers clipboard auto-paste and the on-screen keyboard (US key table); mouse commands aren't supported.
- `maintenance/repair-etckeeper.sh`: one-off repair for a corrupt `/etc/.git` (backs it up to `/root` first).
- The session wrapper's NVIDIA variables assume a dGPU-only (MUX) laptop or a desktop; review them on hybrid graphics.

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

Bump a tag in `phases/30-build.sh` (or `QT_VER`/`DOTS_COMMIT` in `config.env`), delete the component's source dir and stamp in `~/src/hypr`, and re-run that component. Check that the patches still apply; upstream may have changed the patched lines.
