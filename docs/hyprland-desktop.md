# Hyprland desktop (optional)

[← Back to the README](../README.md)

This is the laptop owner's own desktop: Hyprland with end-4's dots. The [laptop fixes](../README.md#the-fixes-at-a-glance) don't need any of it.

Hyprland 0.56 with [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) ("illogical-impulse") as an **extra login session** on Ubuntu 24.04, next to an untouched Plasma X11 session. Optionally (phase 80), Hyprland becomes the **only** desktop: Plasma, GNOME and the X11 sessions are removed and SDDM logs straight into Hyprland.

The upstream installer is Arch-first, and on Ubuntu it only offers an experimental Nix route that doesn't match the current (Lua-config) dots. This repo builds everything from source into one folder in your home instead.

Tested 2026-10-02 (dGPU-only) and 2026-10-04 (Hybrid): Ubuntu 24.04.5, SDDM, Lenovo Legion 7 16IRX9 with an RTX 4070 (driver 595, `nvidia_drm modeset=1`). Isaac Sim runs well in both, including on Wayland (Hyprland); apps started from Hyprland use the normal system libraries (see "How it stays isolated").

![The desktop: kitty with the time-of-day ASCII sunrise greeting, btop, eza, bat and a GPU monitor](screenshots/desktop.jpg)

The terminal greeting is `templates/kitty-fetch`: an ASCII sun over a horizon (fastfetch beside it) that rises in about half a second and sits higher or lower, and warmer or paler, depending on the time of day.

## Quick start

```bash
git clone <this repo> ~/src/ubuntu-hyprland-ii && cd ~/src/ubuntu-hyprland-ii
./setup.sh --list        # what each phase does
./setup.sh 00            # read-only preflight
./setup.sh 10            # optional: remove all snaps + pin snapd (asks first, backs up ~/snap)
./setup.sh               # 00 15 20 30 40 48 50 60: backup, deps, build (~30-60 min), runtime, kitty, dots, login entry
./setup.sh 45            # optional: EasyEffects + ddcutil (apt) + songrec (author's PPA, key fingerprint checked)
./setup.sh 70            # optional: VS Code from Microsoft's apt repo
./setup.sh 80            # optional, destructive: remove Plasma/KDE apps/GNOME/X11 sessions, autologin into Hyprland
./setup.sh 96            # optional: brightness keys/slider (udev rule + video group; log out and in afterwards)
```

The laptop phases (90-99) are listed in the [README](../README.md#the-fixes-at-a-glance).

Phase 80 pins `packages/hyprland-only-keep.txt` (what the dots use from KDE/GNOME: Dolphin, the KDE file dialog, the network/Bluetooth/users KCMs, plasma-systemmonitor, Breeze, gnome-keyring, fprintd; plus sssd, printing, audio/network plumbing) as manually installed, then purges what `apt --auto-remove` computes around `packages/hyprland-only-roots.txt`. It shows the list first (and `EXPECT=<file>` aborts unless the list matches a reviewed one). It removes ~660 packages / 2.4 GB on a `kde-full` + `ubuntu-desktop` install; nothing is installed. The X server core stays (the NVIDIA driver package depends on it), and so does XWayland. Removed packages are listed in `~/src/hypr/apt-removed-hyprland-only-*.txt` for reinstalling; `/etc` changes are in etckeeper.

Log out and pick **Hyprland (illogical-impulse)** in SDDM. Phases can be re-run: the build is resumable (stamps in `~/src/hypr/.stamps`); to rebuild one component, delete its stamp and run `phases/30-build.sh <component>`.

## What goes where

| Where | What |
|---|---|
| `~/.local/opt/hyprland` (`PREFIX`) | Hyprland, Quickshell, Qt 6.10, KF6 Kirigami, newer wayland/libinput/xkbcommon/libei/PipeWire-client, tools |
| `~/src/hypr` (`SRC`) | sources, build trees, logs, lists of apt packages installed (for rollback) |
| `~/.config/{hypr,quickshell,fuzzel,matugen,wlogout,fish,xdg-desktop-portal}` | dots: **only copied if the folder doesn't exist** |
| `~/.local/share/{fonts/illogical-impulse,icons,themes}` | fonts, Bibata cursor, adw-gtk3 |
| `/usr/share/wayland-sessions/hyprland-ii.desktop`, `/opt/MicroTeX` (link into `PREFIX`) | written outside your home (besides apt packages); phase 80 adds `/etc/sddm.conf.d/hyprland-ii-autologin.conf`; phase 95 adds `/usr/local/sbin/gpu-warm`, `/etc/systemd/system/gpu-warm.service`, `/etc/udev/rules.d/99-gpu-warm.rules` |

Not touched: Plasma configs (`kdeglobals`, `dolphinrc`, `konsolerc`, `fontconfig`, ...), user groups (except phase 96: `video`, phase 97: `pipewire`), `gsettings`, `/etc/pam.d`, the NVIDIA driver, anything in `config.env`'s `PROTECTED_UNITS`/`PROTECTED_PACKAGES`/`PROTECTED_PATHS` (the Fleet/osquery agent `orbit`, `fleet-osquery`, `sunrise-firstboot`; fingerprinted before and checked after every run). No phase here touches them, including the laptop phases (90-97).

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
- **Terminal:** kitty, from the upstream release binary (phase 48, version pinned as `KITTY_VER` in `config.env`, installed in `~/.local/kitty.app`). Ubuntu's kitty 0.32 has no `cursor_trail` and ran Python with `-OO` without shipping those `.pyc` files, recompiling ~100 modules on every launch (~0.5 s); upstream's bundle starts in ~80 ms (foot ~50 ms), and `kitty -1` (single instance) makes later windows faster still. `templates/kitty.conf` has the Catppuccin palette, 72% `background_opacity`, the cursor trail, and `remember_window_size no` (a remembered "maximized" state in `~/.cache/kitty/main.json` made kitty open fullscreen instead of tiling). `templates/hypr-custom/variables.lua` sets `terminal` to the **full path**: Hyprland's PATH has no `~/.local/bin`, so a bare `kitty` does nothing on Super+Enter. `templates/hypr-custom/rules.lua` turns blur back on for foot/kitty (the dots disable it for every window) and lets the bar blur at low alpha. The shell's `config.json` update/password actions run kitty ("update" runs `maintenance/update.sh`). kitty runs fish (`shell fish` in kitty.conf; the login shell stays zsh); `templates/fish-rice.fish` (zoxide, fzf, bat, eza aliases, fastfetch greeting) and `templates/starship.toml` (two-line prompt with path/git pills) are installed by phase 50, and `symbol_map` sends icon glyphs to the Mono Nerd Font so the pill caps aren't clipped. foot stays installed as a fallback with `templates/foot.ini`. The dots' OSC theming template hard-coded `[100]` (opaque) for foot at every shell start; phase 50 changes it to `[$alpha]` and sets `term_alpha=72` in `applycolor.sh`. Kitty ignores that OSC alpha and uses `background_opacity`.
- **Update counter:** `session-bin/checkupdates` stands in for Arch's `checkupdates` (`apt list --upgradable`).
- **ImageMagick 6:** `session-bin/magick` maps IM7-style calls to IM6 tools.
- **Lock screen:** Quickshell's lock and the hyprlock fallback both use `/etc/pam.d/login` (hyprlock is configured with `auth:pam:module = login`), so no PAM file is added.
- **Shell logs:** `session-bin/qs` is a shim that keeps each shell instance's output (Quickshell logs to stdout) in `~/.local/state/hyprland-ii/qs-<config>.log` (previous run as `.1`) with start/exit lines; `ipc`/`kill`/etc. subcommands pass straight through. Quickshell's own `.qslog` files are in `$XDG_RUNTIME_DIR` and are lost at logout.
- **Icons:** `QS_ICON_THEME=breeze-dark` (the private Qt has no KDE platform theme).
- **VS Code on Hyprland:** `~/.vscode/argv.json` gets `"password-store": "gnome-libsecret"` (Hyprland isn't auto-detected).

## Monitors

`templates/hypr-custom/general.lua` (copied to `~/.config/hypr/custom/general.lua`) has three monitor rules:

- **Laptop panel** (`eDP-1`): 3200x2000@165, scale 1.25, pinned to `0x0`, so it is 2560x1600 logical.
- **Home monitor, Samsung Odyssey G93SC** (49" OLED, HDMI): 5120x1440@240, scale 1, directly above the laptop panel and centred on it (`-1280x-1440`). It is matched by description, not port, and VRR is left off (OLED flicker). It needs this rule: without it, it came up at 3840x2160@60 under the dots' old fallback, and at 3840x1080@120 (the mode it reports as preferred) under the new one. Changing the laptop scale means changing the x offset: `-(5120 - laptop_width / scale) / 2`.
- **Any other monitor** (office, projector; HDMI or USB-C): its own preferred mode, scale `auto`, placed above the laptop (`auto-up`). This replaces the dots' fallback in `hyprland/general.lua`, which forced the laptop panel's 3200x2000@165 at scale 1.25 onto every monitor. For a monitor you use often, add a rule like the Odyssey's (`hyprctl monitors` shows its description).

## Linked workspaces across monitors

Hyprland gives every workspace to one monitor. `session/shims/hypr-sync-workspaces` (started from `custom/execs.lua`) makes all monitors switch together instead: when the focused monitor changes to workspace N, every other monitor switches to its own N.

- **Groups:** it uses the dots' workspace groups of 10. The laptop panel always has 1-10. The other monitors follow sorted by description (make, model, serial), so a monitor gets the same group whichever HDMI/USB-C port or dock it is on: with one external it has 11-20, with two the second one has 21-30. With the Odyssey connected, SUPER+3 shows workspace 3 on the laptop and 13 on the Odyssey, and SUPER+Alt+3 sends a window to workspace 3 of the monitor it is on. Windows don't span monitors.
- **Plugging and unplugging:** on every switch, plug, unplug and at login, every workspace is moved to its group's monitor (with its windows), then each monitor shows workspace N of its group. Unplugged, an external's workspaces and windows move to the laptop (bar group 2; SUPER+1..0 from a workspace in 1-10 doesn't reach them, use the overview or SUPER+scroll). Plugged back in, they return to it. `general.lua` also pins 1-10 to the laptop panel (`hl.workspace_rule`), so a boot with an external already plugged in no longer gives it workspace 1.
- **Robustness:** with one monitor it does nothing. It runs once per session (lock in `$XDG_RUNTIME_DIR/hypr/<instance>/`), reconnects if Hyprland's event socket drops, and exits with Hyprland.
- **Tested** 2026-10-03 by disabling and re-enabling the Odyssey at runtime, by pushing workspace 1 onto the Odyssey by hand, and with the Odyssey's rule taken out (so it came up as an unknown monitor).
- **Limits:** two changes in the same instant (a workspace switch and a focus move to another monitor) link to whichever came last; the monitors still end up as a matching pair. A dock that gives two identical monitors no serial number may swap their groups between plugs.

To stop it, remove the `hypr-sync-workspaces` line from `~/.config/hypr/custom/execs.lua`.

## Known issues

- **ydotool** is a shim over `wtype` (`session-bin/ydotool`): real ydotool needs `/dev/uinput`, i.e. permission for any of your programs to type into every session; wtype uses Hyprland's virtual-keyboard protocol and only reaches Hyprland windows. It covers `key` and `type`, which is all the dots use (clipboard auto-paste, the on-screen keyboard; US key table). Mouse commands aren't implemented; nothing in the dots (or upstream at the pinned commit) uses them.
- `maintenance/repair-etckeeper.sh`: one-off repair for a corrupt `/etc/.git` (apt prints `fatal: bad object HEAD`, `object file ... is empty` or `index file corrupt`, usually after a crash or power loss during an apt run). It refuses to run if `git fsck` finds nothing wrong, and backs `/etc/.git` up to `/root` first.
- The session wrapper picks the display GPU at login from `/sys/class/drm` (the card with the built-in panel connected) and exports NVIDIA variables (`GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`, `LIBVA_DRIVER_NAME`, `NVD_BACKEND`) only when that card is the NVIDIA one; with several GPUs, `AQ_DRM_DEVICES` lists the display GPU first. Card numbers change between boots (the iGPU was `card2` once and `card1` another time); the wrapper handles that. What it picked is in `~/.local/share/sddm/wayland-session.log`. Tested on dGPU-only (MUX) and on Hybrid (iGPU draws the panel, [details](hybrid-graphics.md)); an external monitor on the NVIDIA ports in Hybrid is not tested yet.
- Switching to a text console (Ctrl+Alt+F*n*) inside Hyprland used to crash it (segfault in aquamarine when the seat is disabled); fixed by `patches/aquamarine-drm-teardown-fixes.patch` (confirmed 2026-10-02: tty1 <-> tty3 and back). If it ever returns: `journalctl -k -b | grep segfault`, then `llvm-addr2line-20 -f -C -i -e ~/.local/opt/hyprland/lib/libaquamarine.so.0.15.1 0x<offset>` with the offset from the `[...]` part.
