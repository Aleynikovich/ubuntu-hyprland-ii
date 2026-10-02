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
./setup.sh               # 00 15 20 30 40 48 50 60: backup, deps, build (~30-60 min), runtime, kitty, dots, login entry
./setup.sh 45            # optional: EasyEffects + ddcutil (apt) + songrec (author's PPA, key fingerprint checked)
./setup.sh 70            # optional: VS Code from Microsoft's apt repo
./setup.sh 80            # optional, destructive: remove Plasma/KDE apps/GNOME/X11 sessions, autologin into Hyprland
./setup.sh 90 91 92 93   # optional: sleep/hibernate fixes, Limine ESP boot, GRUB removal, panel EDID pin (see "Sleep and hibernate"; laptop-specific)
./setup.sh 95            # optional: keep GPU/CPU clocks up on AC so first launches aren't laggy (see "Responsiveness")
```

Phases 90-95 are specific to a Lenovo Legion 7 16IRX9 (RTX 4070, MUX in dGPU mode): they check DMI against `HW_TESTED` in `config.env` and refuse to run elsewhere unless `HII_FORCE_HW=1`. Phase 00 only reports whether the machine matches.

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

Not touched: Plasma configs (`kdeglobals`, `dolphinrc`, `konsolerc`, `fontconfig`, ...), user groups, `gsettings`, `/etc/pam.d`, the NVIDIA driver, anything in `config.env`'s `PROTECTED_UNITS`/`PROTECTED_PACKAGES`/`PROTECTED_PATHS` (the Fleet/osquery agent `orbit`, `fleet-osquery`, `sunrise-firstboot`; fingerprinted before and checked after every run). No phase here touches them, including the later ones (90-95).

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

## Sleep and hibernate (phases 90-93, Lenovo Legion 7 16IRX9 + RTX 4070, driver 595 open)

Found the hard way (about ten hard reboots); don't undo these without testing with an RTC wake alarm, not the lid:

- **s2idle, not S3 "deep".** After S3 the NVIDIA driver never re-lights the eDP panel (black even on the text console). Phase 91 puts `mem_sleep_default=s2idle` on the Limine command line.
- **NVIDIA suspends from the kernel** (`NVreg_UseKernelSuspendNotifiers=1`, runtime D3 off) and the `nvidia-suspend/resume/hibernate` systemd services are masked: their `chvt 63` dance froze the whole machine on resume (phase 90).
- **Hibernate** uses a 32 GB `/swap.img` with `resume=UUID=... resume_offset=...` on the command line (phases 90/91). Wake it with the power button; the RTC alarm cannot wake from S4 here.
- **The machine boots Limine from the ESP, not GRUB** (phase 92 removes GRUB, after checking that Limine can boot on its own: EFI entry, ESP kernel/initrd = newest `/boot` kernel, `limine.conf` has the resume/s2idle/EDID args; it asks before purging). Phase 91 installs `limine-esp-sync` (kernel postinst and `update-initramfs` hooks) so the ESP copy of the kernel/initrd follows `/boot`; the previous kernel stays as the second menu entry, without the EDID pin.
- Phase 93 pins the panel EDID (`drm.edid_firmware`): it stops a retry loop after resume, but it was not what fixed sleep.

## Responsiveness (phase 95)

Symptom: after some time in one app, the first new window (e.g. a terminal after a while in VS Code) or workspace switch stutters once, then everything is snappy. Measured cause: the RTX 4070 idles at P8 (210 MHz) and the first frame waits for it to clock up; the CPU was also sitting in `power-saver`/EPP `power` on AC. Phase 95 installs `/usr/local/sbin/gpu-warm`, `gpu-warm.service` (boot, resume from suspend/hibernate) and a udev rule (AC plug/unplug):

- **On AC:** GPU graphics clock floor 1200 MHz and memory clock floor 6001 MHz (maxes unchanged; the graphics floor alone was not enough: memory idled at 810 MHz of 8001 and the first blur/workspace frame after idle still stuttered until memory was locked too; idle draw ~10 W vs ~4 W, P4), power profile `performance`, CPU governor `performance` (Isaac Sim warns about a `powersave` governor even though `intel_pstate` + EPP `performance` is equivalent), and `nvidia-persistenced` is pulled in.
- **On battery:** floor released, `balanced`, governor `powersave`.

`maintenance/power-report.sh` prints a snapshot (AC, profile, governor/EPP, GPU P-state/clocks/draw, battery rate averaged over `SECS`, default 10 s). Run it idle once on AC and once on battery to compare. On AC with phase 95: `performance` profile/governor/EPP, GPU at P4 with gr 1200 MHz and mem 6001 MHz, ~10 W idle GPU draw. (`nvidia-smi` shows persistence mode "Disabled": Ubuntu's `nvidia-persistenced` runs with `--no-persistence-mode`, which still keeps the driver initialized; that is what matters here.)

Isaac Sim's "IOMMU is enabled" warning is Ubuntu's default and was left alone (turning it off needs a kernel command line change).

## Known issues

- **ydotool** is a shim over `wtype` (`session-bin/ydotool`): real ydotool needs `/dev/uinput`, i.e. permission for any of your programs to type into every session; wtype uses Hyprland's virtual-keyboard protocol and only reaches Hyprland windows. It covers `key` and `type`, which is all the dots use (clipboard auto-paste, the on-screen keyboard; US key table). Mouse commands aren't implemented; nothing in the dots (or upstream at the pinned commit) uses them.
- `maintenance/repair-etckeeper.sh`: one-off repair for a corrupt `/etc/.git` (apt prints `fatal: bad object HEAD`, `object file ... is empty` or `index file corrupt`, usually after a crash or power loss during an apt run). It refuses to run if `git fsck` finds nothing wrong, and backs `/etc/.git` up to `/root` first.
- The session wrapper picks the GPU at login from `/sys/class/drm`: NVIDIA variables (`GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`, `LIBVA_DRIVER_NAME`, `NVD_BACKEND`) only when the NVIDIA card drives the built-in panel (or the connected outputs); with several GPUs, `AQ_DRM_DEVICES` lists the display GPU first. What it picked is in `~/.local/share/sddm/wayland-session.log`. Tested on dGPU-only (MUX) only; the Optimus logic is untested on hardware.
- Switching to a text console (Ctrl+Alt+F*n*) inside Hyprland used to crash it (segfault in aquamarine when the seat is disabled); fixed by `patches/aquamarine-drm-teardown-fixes.patch` (confirmed 2026-10-02: tty1 <-> tty3 and back). If it ever returns: `journalctl -k -b | grep segfault`, then `llvm-addr2line-20 -f -C -i -e ~/.local/opt/hyprland/lib/libaquamarine.so.0.15.1 0x<offset>` with the offset from the `[...]` part.

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
