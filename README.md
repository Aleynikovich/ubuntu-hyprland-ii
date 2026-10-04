# ubuntu-hyprland-ii

Setup scripts for a Lenovo Legion 7 16IRX9 running Ubuntu 24.04. This README has two parts:

1. **[Laptop fixes (for IT)](#laptop-fixes-for-it)**: fixes for Bluetooth audio, sleep/hibernate and responsiveness on this Legion model. They don't depend on the desktop (they work on stock Plasma) and are what other Legion laptops on the same hardware are likely to need.
2. **[Personal desktop setup (optional)](#personal-desktop-setup-optional)**: Hyprland with end-4's dots. This is the laptop owner's own customization; nothing in part 1 needs it.

## Laptop fixes (for IT)

Tested on: Lenovo Legion 7 16IRX9 (DMI product `83FD`), Intel i9 + RTX 4070 in dGPU-only (MUX) mode, NVIDIA driver 595 (open), Realtek RTL8852CE Wi-Fi/Bluetooth, Ubuntu 24.04.5 with kernel `7.0.0-38-generic`, upgrading from `7.0.0-31-generic`. Isaac Sim runs well on this setup, both on X11 (Plasma) and on Wayland (the Hyprland session in part 2).

### Summary

| Problem | Cause (measured) | Fix | Phase | Result |
|---|---|---|---|---|
| Bluetooth headphones stutter and pop, worse under CPU load or during downloads; wired audio fine | Wi-Fi scanned every 15 s by the location service; PipeWire lost realtime priority after every suspend; Wi-Fi power save; outdated Wi-Fi firmware | See [Bluetooth audio](#bluetooth-audio-phase-97-realtek-rtl8852ce) | 97 | Much better. Occasional pops remain during heavy Wi-Fi downloads (radio limit of the combo chip) |
| Black panel or frozen machine after suspend | S3 "deep" sleep; NVIDIA's systemd sleep services | s2idle; NVIDIA kernel suspend notifiers; those services masked | 90, 91 | Fixed |
| Hibernate didn't work | No resume configuration; swap too small | 32 GB `/swap.img` + `resume=`/`resume_offset=` | 90, 91 | Works (wake with the power button) |
| Panel stuck at 640x480 / black after resume | Panel EDID re-read on resume | EDID pinned with `drm.edid_firmware` | 93 | Fixed (secondary; s2idle was the main fix) |
| Laptop slows down badly when the Windows VM runs RobotStudio / TIA Portal next to other work | Only 8 GB swap on 31 GiB RAM; small unpinned VM (12 GiB, 4 vCPUs) | 32 GB swap; VM with 20 GiB, 16 vCPUs pinned to the P-cores, Hyper-V enlightenments, virtio with iothreads | 90 + VM definition | Fixed; see [Windows 11 VM](#windows-11-vm-for-tia-portal--robotstudio-libvirt-templateslibvirt-win11xml) |
| First window or animation after idle stutters | GPU idles at 210 MHz; CPU in `power-saver` on AC | GPU clock floors and `performance` profile on AC only | 95 | Fixed |

### Applying them

```bash
git clone <this repo> ~/src/ubuntu-hyprland-ii && cd ~/src/ubuntu-hyprland-ii
./setup.sh 00      # read-only: reports whether this machine matches the tested hardware
./setup.sh 97      # Bluetooth audio, then reboot
./setup.sh 90 91   # sleep + hibernate (91 needs Limine; see "GRUB machines" below), then reboot
./setup.sh 93      # optional: pin the panel EDID
./setup.sh 95      # optional: GPU/CPU clocks up on AC
./setup.sh 98      # optional: lid close blanks the panel on AC / Keep awake, else hibernates
```

The Windows VM isn't a phase: `virsh define templates/libvirt-win11.xml` recreates it (see [Windows 11 VM](#windows-11-vm-for-tia-portal--robotstudio-libvirt-templateslibvirt-win11xml)).

- Run as the normal user; the scripts call `sudo` themselves. Each phase can be re-run safely.
- **Rollback:** every phase script has a rollback line in its header. If etckeeper is installed, `/etc` changes are committed with a "Phase NN" message.
- **Hardware check:** phases 90-95, 97 and 98 compare DMI (`vendor|product|version`) against `HW_TESTED` in `config.env` (`LENOVO|83FD|Legion 7 16IRX9`) and refuse to run on anything else. On another Legion model, review the phase, then run it with `HII_FORCE_HW=1`. For phase 97, first check that the machine has the same chip: `lspci -nn | grep -i network` should show `RTL8852CE ... [10ec:c852]`.
- **Fleet agent:** every run fingerprints the Fleet/osquery agent (`orbit`, `fleet-osquery`, `sunrise-firstboot`; listed in `config.env`) before it starts and checks it afterwards. The run fails with exit code 3 if anything about the agent changed. None of these phases touch it.
- **GRUB machines:** phase 91 writes the kernel command line into Limine (this laptop boots Limine; phase 92 removed GRUB). On a stock GRUB install, run only phase 90. Then add `mem_sleep_default=s2idle resume=UUID=<UUID of the / filesystem> resume_offset=<first physical block of /swap.img>` to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub` and run `sudo update-grub`. Phase 91 shows how both values are derived (`findmnt -no UUID /`, `filefrag -v /swap.img`). The GRUB path has not been tested.

### Bluetooth audio (phase 97, Realtek RTL8852CE)

**Symptom:** A2DP headphones (Bose QC35, QC45 and others) stutter and pop, worst under CPU load or while downloading. Wired audio is fine.

**Hardware:** Wi-Fi and Bluetooth on this Legion are one Realtek RTL8852CE chip. Wi-Fi is on PCIe (driver `rtw89_8852ce`), Bluetooth on internal USB (`0bda:5852`, driver `btusb`/`btrtl`), and they share the antennas. Any Wi-Fi activity takes airtime from Bluetooth. The driver's Wi-Fi/Bluetooth sharing ("coexistence") state can be read as root from `/sys/kernel/debug/ieee80211/phy0/rtw89/btc_info`.

**Causes found** (measured with `btc_info`, `iw event` and `busctl monitor`):

1. **The location service scanned Wi-Fi every 15 seconds.** geoclue requested a full scan of 2.4, 5 and 6 GHz every 15 s, each lasting about 5 s. During a scan the radio sits on 2.4 GHz channels, on top of the Bluetooth link: about 700 scans in 2.5 hours. geoclue was kept running by a weather widget's GPS option. The Wi-Fi positioning service it queries (Mozilla Location Service) shut down in 2024, so every lookup failed and was retried.
2. **PipeWire lost realtime priority after every suspend.** rtkit's watchdog sees the sleep gap as a hung system and demotes every thread it had made realtime. PipeWire never asks again until the next login. The Bluetooth encoder thread then competes with downloads and builds at normal priority and misses deadlines.
3. **Wi-Fi power save** made the driver re-run its coexistence logic on every power-save enter/leave: about 4,400 times in 2.5 hours.
4. **Outdated Wi-Fi firmware.** Ubuntu 24.04's `linux-firmware` ships 0.27.125.0. Kernel 7.0's coexistence code couldn't read its status reports ("WL FW report invalid"). The Bluetooth firmware (`rtl8852cu_fw_v2.bin`) is already identical to upstream's.

**What phase 97 changes:**

| Change | File / command |
|---|---|
| geoclue's Wi-Fi source off. Apps lose Wi-Fi positioning, which already didn't work. | `/etc/geoclue/conf.d/90-no-wifi-scan.conf` |
| Weather widget uses its configured city instead of GPS. Only if the Hyprland shell is installed; skipped otherwise. | `~/.config/illogical-impulse/config.json` |
| User added to group `pipewire`, so PipeWire gets realtime priority from Ubuntu's `/etc/security/limits.d/25-pw-rlimits.conf` directly, without rtkit. Takes effect after the next login. | `usermod -aG pipewire` |
| Wi-Fi power save off | `/etc/NetworkManager/conf.d/wifi-powersave-off.conf` |
| Wi-Fi firmware 0.27.129.4 from upstream linux-firmware (pinned commit, SHA-256 checked) | `/lib/firmware/updates/rtw89/rtw8852c_fw-2.bin` |

The kernel loads firmware from `/lib/firmware/updates/` before `/lib/firmware/`, so the `linux-firmware` package itself is not changed. **Delete that file once Ubuntu's `linux-firmware` ships 0.27.129.4 or newer.** Otherwise it keeps overriding later Ubuntu firmware updates.

**Check after the reboot:**

```bash
journalctl -k -b | grep 'rtw89.*Firmware version'          # 0.27.129.4
iw dev wlp114s0 get power_save                             # off
ps -L -o cls,rtprio,comm -p $(pgrep -x pipewire)           # pw-data-loop: FF 88 (also after a suspend/resume)
timeout 60 iw event -t | grep -c 'scan started'            # 0 or 1, not 4
sudo grep -E 'WL_FW|scan_start|radio_state|stat_cnt' /sys/kernel/debug/ieee80211/phy0/rtw89/btc_info
pw-top                                                     # ERR column for bluez_output stays 0
```

**Result** (2026-10-03, Bose QC35 on SBC, Steam download and YouTube running at the same time):

| | Before | After |
|---|---|---|
| Wi-Fi scans | 1 every 15 s | 2 in 9 minutes (normal background scans) |
| Power-save toggles seen by the driver | ~4,400 in 2.5 h | 1 |
| Wi-Fi firmware status reports | invalid | valid |
| PipeWire priority | normal after any suspend | realtime (FIFO 88) |
| PipeWire errors on the Bluetooth output | n/a | 0 |
| Headset signal at the laptop | -78 dBm | -64 dBm |

**Remaining issue:** occasional pops while Wi-Fi is fully busy (e.g. a large Steam download). The audio software reports no errors; the pops are Bluetooth packets lost over the air, about 2.7 retransmissions per second during the download. Wi-Fi was on 5 GHz with 160 MHz width, which doesn't overlap Bluetooth's band, but both radios still share the chip's antennas. The driver has no setting that gives Bluetooth priority while Wi-Fi is on 5 GHz. Options, cheapest first:

1. Limit large downloads (e.g. Steam → Settings → Downloads → bandwidth limit).
2. Use an 80 MHz instead of 160 MHz channel on the access point.
3. A USB Bluetooth adapter with its own antenna (Intel AX210-based, or Realtek RTL8761B), with the internal Bluetooth disabled. This is the complete fix and the recommendation if other Legions with this chip report the same problem.

**Rollback:** `sudo rm /etc/geoclue/conf.d/90-no-wifi-scan.conf /etc/NetworkManager/conf.d/wifi-powersave-off.conf /lib/firmware/updates/rtw89/rtw8852c_fw-2.bin; sudo gpasswd -d "$USER" pipewire`, then reboot.

### Sleep and hibernate (phases 90-93)

Found the hard way (about ten hard reboots); don't undo these without testing with an RTC wake alarm, not the lid:

- **s2idle, not S3 "deep".** After S3 the NVIDIA driver never re-lights the eDP panel (black even on the text console). Phase 91 puts `mem_sleep_default=s2idle` on the Limine command line.
- **NVIDIA suspends from the kernel** (`NVreg_UseKernelSuspendNotifiers=1`, runtime D3 off) and the `nvidia-suspend/resume/hibernate` systemd services are masked: their `chvt 63` dance froze the whole machine on resume (phase 90).
- **Hibernate** uses a 32 GB `/swap.img` with `resume=UUID=... resume_offset=...` on the command line (phases 90/91). Wake it with the power button; the RTC alarm cannot wake from S4 here.
- **The machine boots Limine from the ESP, not GRUB** (phase 92 removes GRUB, after checking that Limine can boot on its own: EFI entry, ESP kernel/initrd = newest `/boot` kernel, `limine.conf` has the resume/s2idle/EDID args; it asks before purging). Phase 91 installs `limine-esp-sync` (kernel postinst and `update-initramfs` hooks) so the ESP copy of the kernel/initrd follows `/boot`; the previous kernel stays as the second menu entry, without the EDID pin.
- Phase 93 pins the panel EDID (`drm.edid_firmware`): it stops a retry loop after resume, but it was not what fixed sleep.

### Responsiveness on AC (phase 95)

Symptom: after some time in one app, the first new window (e.g. a terminal after a while in VS Code) or workspace switch stutters once, then everything is snappy. Measured cause: the RTX 4070 idles at P8 (210 MHz) and the first frame waits for it to clock up; the CPU was also sitting in `power-saver`/EPP `power` on AC. Phase 95 installs `/usr/local/sbin/gpu-warm`, `gpu-warm.service` (boot, resume from suspend/hibernate) and a udev rule (AC plug/unplug):

- **On AC:** GPU graphics clock floor 1200 MHz and memory clock floor 6001 MHz (maxes unchanged; the graphics floor alone was not enough: memory idled at 810 MHz of 8001 and the first blur/workspace frame after idle still stuttered until memory was locked too; idle draw ~10 W vs ~4 W, P4), power profile `performance`, CPU governor `performance` (Isaac Sim warns about a `powersave` governor even though `intel_pstate` + EPP `performance` is equivalent), and `nvidia-persistenced` is pulled in.
- **On battery:** floor released, `balanced`, governor `powersave`.

`maintenance/power-report.sh` prints a snapshot (AC, profile, governor/EPP, GPU P-state/clocks/draw, battery rate averaged over `SECS`, default 10 s). Run it idle once on AC and once on battery to compare. On AC with phase 95: `performance` profile/governor/EPP, GPU at P4 with gr 1200 MHz and mem 6001 MHz, ~10 W idle GPU draw. (`nvidia-smi` shows persistence mode "Disabled": Ubuntu's `nvidia-persistenced` runs with `--no-persistence-mode`, which still keeps the driver initialized; that is what matters here.)

Isaac Sim's "IOMMU is enabled" warning is Ubuntu's default and was left alone (turning it off needs a kernel command line change).

### Lid close (phase 98)

Symptom: after suspend the screen is dark but the fans keep spinning and the keyboard stays lit. Measured on battery: about 6.3 W while "asleep" (0.54 Wh in 307 s), although the CPU package sat in S0ix for 95% of that time. The BIOS has no sleep-mode option, and S3 leaves the panel dark (see Sleep above), so s2idle stays; the laptop's embedded controller just never powers the fans and backlight down.

**Fix:** logind ignores the lid (`/etc/systemd/logind.conf.d/10-lid.conf`), and `/etc/polkit-1/rules.d/10-hibernate.rules` overrides Ubuntu's polkit rule that denies hibernate to users. Hyprland's lid-switch binds run `~/.config/hypr/custom/scripts/lid-action.sh`: on AC, or with the shell's "Keep awake" toggle on (`idle.inhibit` in `~/.local/state/quickshell/states.json`), closing the lid only turns the panel (`eDP-1`) off; on battery with Keep awake off it runs `systemctl hibernate`, at any charge level. If AC is unplugged while the lid is already closed (and Keep awake is off), a udev rule starts `lid-unplug-hibernate.service`, which hibernates. Opening the lid turns the panel back on. After any resume, hypridle's `after_sleep_cmd` runs `resume-display.sh`, which toggles the panel off and on once (1.5 s after resume) and then focuses the lock screen (without it the NVIDIA panel stayed dark until a key press). Idle timeout and Super+Shift+L still use plain suspend.

### Windows 11 VM for TIA Portal / RobotStudio (libvirt, `templates/libvirt-win11.xml`)

**Symptom:** running heavy Windows engineering tools (RobotStudio, TIA Portal, CAD) in the VM, or several at once next to host apps, slowed the whole laptop down a lot.

**Cause:** the laptop has 31 GiB of RAM but only had 8 GB of swap. The VM was small and slow (12 GiB, 4 unpinned vCPUs), and the host had little room when memory ran short.

**Fix:** a bigger, pinned VM, plus 32 GB of swap from phase 90 (`SWAP_GB` there; the same swap file is used for hibernate):

- **RAM budget:** the VM holds a fixed 20 GiB while it runs, leaving about 11 GiB for the host. Keep at least 8 GiB for the host; with Isaac Sim or other heavy host apps running at the same time, either shut the VM down or lower its memory (`virsh edit win11`, `<memory>` and `<currentMemory>`). The 32 GB of swap absorbs peaks instead of the machine stalling; `systemd-oomd` is active as the last resort.
- **Other machines:** the CPU pinning below assumes the Legion's i9 layout (24 threads; P-core threads 0-15, E-cores 16-23). Check `lscpu --extended` and adjust the `cputune` block before reusing the definition on different hardware.

Not a phase: the VM already exists on this laptop and `templates/libvirt-win11.xml` is a copy of its current definition, kept here so it can be recreated (`virsh define templates/libvirt-win11.xml`, or `virsh edit win11` to change it live). Tuned for engineering tools (TIA Portal, RobotStudio, CAD) on the Legion's 24-thread i9:

- **CPU:** 16 vCPUs (8 cores x 2 threads) pinned 1:1 to host CPUs 0-15, the P-cores. The QEMU emulator thread runs on E-cores 16-19 and the disk iothread on 20-21, so the host stays responsive under load. `migratable="off"` exposes `invtsc` to the guest; `cache mode="passthrough"`.
- **Hyper-V enlightenments:** relaxed, vapic, spinlocks, vpindex, runtime, synic, stimer, reset, frequencies, tlbflush, ipi; `hypervclock` on, `kvmclock` off.
- **Memory:** 20 GiB of 31 GiB fixed, memfd-backed and shared (virtiofs needs that); balloon removed. Keep at least 8 GiB for the host.
- **Disk/network:** virtio qcow2 with `cache=none io=native discard=unmap` on a dedicated iothread with 8 queues; virtio NIC with `vhost` and 4 queues. The network is libvirt's NAT `default`: to reach real PLCs or robot controllers on the LAN, switch to a bridge or macvtap.
- **Video:** QXL with 128 MiB ram/vram for 4K and multi-monitor work; four SPICE USB redirectors.
- **Unchanged:** UEFI + Secure Boot (OVMF secboot), emulated TPM 2.0, `localtime` clock, virtiofs share of `~/Downloads` as `share`, the MSDM ACPI table (`/var/lib/libvirt/acpi/win11-msdm.bin`, referenced but not stored in this repo).

Before this the VM had 12 GiB, 4 plain vCPUs, a 64 MiB QXL, and only `relaxed/vapic/spinlocks/vpindex/synic/stimer/frequencies`.

## Personal desktop setup (optional)

The rest of this README is the laptop owner's own desktop: Hyprland with end-4's dots as an extra session. IT doesn't need any of it for the fixes above.

Hyprland 0.56 with [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) ("illogical-impulse") as an **extra login session** on Ubuntu 24.04, next to an untouched Plasma X11 session. Optionally (phase 80), Hyprland becomes the **only** desktop: Plasma, GNOME and the X11 sessions are removed and SDDM logs straight into Hyprland.

The upstream installer is Arch-first, and on Ubuntu it only offers an experimental Nix route that doesn't match the current (Lua-config) dots. This repo builds everything from source into one folder in your home instead.

Tested 2026-10-02: Ubuntu 24.04.5, Plasma 5.27 X11, SDDM, Lenovo Legion 7 16IRX9 with an RTX 4070 (dGPU-only/MUX mode, driver 595, `nvidia_drm modeset=1`). Isaac Sim runs well in both, including on Wayland (Hyprland); apps started from Hyprland use the normal system libraries (see "How it stays isolated").

![The desktop: kitty with the time-of-day ASCII sunrise greeting, btop, eza, bat and a GPU monitor](docs/screenshots/desktop.jpg)

The terminal greeting is `templates/kitty-fetch`: an ASCII sun over a horizon (fastfetch beside it) that rises in about half a second and sits higher or lower, and warmer or paler, depending on the time of day.

### Quick start

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

The laptop phases (90-95, 97) are in [Laptop fixes (for IT)](#laptop-fixes-for-it).

Phase 80 pins `packages/hyprland-only-keep.txt` (what the dots use from KDE/GNOME: Dolphin, the KDE file dialog, the network/Bluetooth/users KCMs, plasma-systemmonitor, Breeze, gnome-keyring, fprintd; plus sssd, printing, audio/network plumbing) as manually installed, then purges what `apt --auto-remove` computes around `packages/hyprland-only-roots.txt`. It shows the list first (and `EXPECT=<file>` aborts unless the list matches a reviewed one). It removes ~660 packages / 2.4 GB on a `kde-full` + `ubuntu-desktop` install; nothing is installed. The X server core stays (the NVIDIA driver package depends on it), and so does XWayland. Removed packages are listed in `~/src/hypr/apt-removed-hyprland-only-*.txt` for reinstalling; `/etc` changes are in etckeeper.

Log out and pick **Hyprland (illogical-impulse)** in SDDM. Phases can be re-run: the build is resumable (stamps in `~/src/hypr/.stamps`); to rebuild one component, delete its stamp and run `phases/30-build.sh <component>`.

### What goes where

| Where | What |
|---|---|
| `~/.local/opt/hyprland` (`PREFIX`) | Hyprland, Quickshell, Qt 6.10, KF6 Kirigami, newer wayland/libinput/xkbcommon/libei/PipeWire-client, tools |
| `~/src/hypr` (`SRC`) | sources, build trees, logs, lists of apt packages installed (for rollback) |
| `~/.config/{hypr,quickshell,fuzzel,matugen,wlogout,fish,xdg-desktop-portal}` | dots: **only copied if the folder doesn't exist** |
| `~/.local/share/{fonts/illogical-impulse,icons,themes}` | fonts, Bibata cursor, adw-gtk3 |
| `/usr/share/wayland-sessions/hyprland-ii.desktop`, `/opt/MicroTeX` (link into `PREFIX`) | written outside your home (besides apt packages); phase 80 adds `/etc/sddm.conf.d/hyprland-ii-autologin.conf`; phase 95 adds `/usr/local/sbin/gpu-warm`, `/etc/systemd/system/gpu-warm.service`, `/etc/udev/rules.d/99-gpu-warm.rules` |

Not touched: Plasma configs (`kdeglobals`, `dolphinrc`, `konsolerc`, `fontconfig`, ...), user groups (except phase 96: `video`, phase 97: `pipewire`), `gsettings`, `/etc/pam.d`, the NVIDIA driver, anything in `config.env`'s `PROTECTED_UNITS`/`PROTECTED_PACKAGES`/`PROTECTED_PATHS` (the Fleet/osquery agent `orbit`, `fleet-osquery`, `sunrise-firstboot`; fingerprinted before and checked after every run). No phase here touches them, including the laptop phases (90-97).

### How it stays isolated

- **RPATH, not `LD_LIBRARY_PATH`.** Every binary carries its own library path, so the session sets no library or QML path variables and apps launched from Hyprland (Isaac Sim, etc.) get the normal system libraries.
- **apt: new packages only.** Each apt phase dry-runs first and refuses to proceed if an existing package would be upgraded or removed.
- **Private Qt.** Qt 6.10 comes from Qt's official binaries (aqtinstall); Ubuntu's Qt 6.4 is left alone. The shell's QML modules are linked into the private Qt's `qml/` folder.
- **pkg-config filter.** CMake otherwise resolves private libs to `/usr/lib` copies (via `-L/usr/lib/...` from `libseat.pc`); `tools/bin/pkg-config-filtered` strips system `-L` flags.

### Ubuntu-specific workarounds

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

### Monitors

`templates/hypr-custom/general.lua` (copied to `~/.config/hypr/custom/general.lua`) has three monitor rules:

- **Laptop panel** (`eDP-1`): 3200x2000@165, scale 1.25, pinned to `0x0`, so it is 2560x1600 logical.
- **Home monitor, Samsung Odyssey G93SC** (49" OLED, HDMI): 5120x1440@240, scale 1, directly above the laptop panel and centred on it (`-1280x-1440`). It is matched by description, not port, and VRR is left off (OLED flicker). It needs this rule: without it, it came up at 3840x2160@60 under the dots' old fallback, and at 3840x1080@120 (the mode it reports as preferred) under the new one. Changing the laptop scale means changing the x offset: `-(5120 - laptop_width / scale) / 2`.
- **Any other monitor** (office, projector; HDMI or USB-C): its own preferred mode, scale `auto`, placed above the laptop (`auto-up`). This replaces the dots' fallback in `hyprland/general.lua`, which forced the laptop panel's 3200x2000@165 at scale 1.25 onto every monitor. For a monitor you use often, add a rule like the Odyssey's (`hyprctl monitors` shows its description).

### Linked workspaces across monitors

Hyprland gives every workspace to one monitor. `session/shims/hypr-sync-workspaces` (started from `custom/execs.lua`) makes all monitors switch together instead: when the focused monitor changes to workspace N, every other monitor switches to its own N.

- **Groups:** it uses the dots' workspace groups of 10. The laptop panel always has 1-10. The other monitors follow sorted by description (make, model, serial), so a monitor gets the same group whichever HDMI/USB-C port or dock it is on: with one external it has 11-20, with two the second one has 21-30. With the Odyssey connected, SUPER+3 shows workspace 3 on the laptop and 13 on the Odyssey, and SUPER+Alt+3 sends a window to workspace 3 of the monitor it is on. Windows don't span monitors.
- **Plugging and unplugging:** on every switch, plug, unplug and at login, every workspace is moved to its group's monitor (with its windows), then each monitor shows workspace N of its group. Unplugged, an external's workspaces and windows move to the laptop (bar group 2; SUPER+1..0 from a workspace in 1-10 doesn't reach them, use the overview or SUPER+scroll). Plugged back in, they return to it. `general.lua` also pins 1-10 to the laptop panel (`hl.workspace_rule`), so a boot with an external already plugged in no longer gives it workspace 1.
- **Robustness:** with one monitor it does nothing. It runs once per session (lock in `$XDG_RUNTIME_DIR/hypr/<instance>/`), reconnects if Hyprland's event socket drops, and exits with Hyprland.
- **Tested** 2026-10-03 by disabling and re-enabling the Odyssey at runtime, by pushing workspace 1 onto the Odyssey by hand, and with the Odyssey's rule taken out (so it came up as an unknown monitor).
- **Limits:** two changes in the same instant (a workspace switch and a focus move to another monitor) link to whichever came last; the monitors still end up as a matching pair. A dock that gives two identical monitors no serial number may swap their groups between plugs.

To stop it, remove the `hypr-sync-workspaces` line from `~/.config/hypr/custom/execs.lua`.

### Known issues

- **ydotool** is a shim over `wtype` (`session-bin/ydotool`): real ydotool needs `/dev/uinput`, i.e. permission for any of your programs to type into every session; wtype uses Hyprland's virtual-keyboard protocol and only reaches Hyprland windows. It covers `key` and `type`, which is all the dots use (clipboard auto-paste, the on-screen keyboard; US key table). Mouse commands aren't implemented; nothing in the dots (or upstream at the pinned commit) uses them.
- `maintenance/repair-etckeeper.sh`: one-off repair for a corrupt `/etc/.git` (apt prints `fatal: bad object HEAD`, `object file ... is empty` or `index file corrupt`, usually after a crash or power loss during an apt run). It refuses to run if `git fsck` finds nothing wrong, and backs `/etc/.git` up to `/root` first.
- The session wrapper picks the GPU at login from `/sys/class/drm`: NVIDIA variables (`GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`, `LIBVA_DRIVER_NAME`, `NVD_BACKEND`) only when the NVIDIA card drives the built-in panel (or the connected outputs); with several GPUs, `AQ_DRM_DEVICES` lists the display GPU first. What it picked is in `~/.local/share/sddm/wayland-session.log`. Tested on dGPU-only (MUX) only; the Optimus logic is untested on hardware.
- Switching to a text console (Ctrl+Alt+F*n*) inside Hyprland used to crash it (segfault in aquamarine when the seat is disabled); fixed by `patches/aquamarine-drm-teardown-fixes.patch` (confirmed 2026-10-02: tty1 <-> tty3 and back). If it ever returns: `journalctl -k -b | grep segfault`, then `llvm-addr2line-20 -f -C -i -e ~/.local/opt/hyprland/lib/libaquamarine.so.0.15.1 0x<offset>` with the offset from the `[...]` part.

### Rollback

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

### Installing other software (no snaps, no Flatpak)

1. `sudo apt install <pkg>` from Ubuntu's repos.
2. The vendor's signed apt repo (key in `/etc/apt/keyrings`, repo in `/etc/apt/sources.list.d/*.sources`); see `phases/70-vscode.sh` for the pattern, including checking the key fingerprint.
3. A vendor `.deb`: `sudo apt install ./file.deb`.
4. Arch/AUR-only things: an Arch [distrobox](https://distrobox.it) container, with apps exported to the host launcher.

### Updating

Rebuilding while logged in to Hyprland is safe: meson/cmake components install via a staging dir and replace files with new inodes, so the running session keeps its old copies until you log in again.

#### The Hyprland build

Bump with `maintenance/bump.sh <component> [new-tag]` (e.g. `maintenance/bump.sh hyprland v0.56.3`; a source dir name like `Hyprland` works too). It checks that `patches/` still apply to the new tag (a proposed tag or commit is checked out even for components without patches, so a typo fails before anything is deleted), shows the tag edit to `phases/30-build.sh` and the stamp/source dir in `~/src/hypr` it will delete, asks once, and rebuilds that component. Leave out the tag to just rebuild from a clean source dir. `--dry-run` runs the patch check and shows the plan without changing anything. Components that depend on a bumped library are not rebuilt automatically. `QT_VER`/`DOTS_COMMIT` in `config.env` are still edited by hand.

`./setup.sh --check-patches` checks every patch against its pinned tag; `./setup.sh --check-patches hyprland=v0.57.0 aquamarine=v0.16.0` checks a proposed bump. It works in temporary checkouts and never modifies the trees in `~/src/hypr`. The build applies patches from the same list (`lib/patches.sh`).

#### The dots

- `maintenance/diff-dots.sh` lists what differs between `~/.config/{hypr,quickshell,fuzzel,matugen,wlogout,fish,xdg-desktop-portal,foot}` and the pinned dots (`DOTS_COMMIT`); `-p` shows the diffs, paths filter (`diff-dots.sh -p hypr/custom`). Before bumping `DOTS_COMMIT`, `diff-dots.sh --against origin/main` lists the files the bump changes and flags those you changed too (C), with whether they merge cleanly. Read-only; upstream trees are cached in `~/src/hypr/dots-pinned`.
- Templates (fresh installs): phase 50 fills `~/.config/hypr/custom/*.lua` from `templates/hypr-custom/` only where the file is blank or missing, and applies `templates/illogical-impulse-config.json` (foot for the terminal/update/password actions, `maintenance/update.sh` instead of pacman, foot/VS Code pinned) to the shell's `config.json`, only to keys still at the dots' kitty/pacman default.

#### The system (apt)

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
