#!/usr/bin/env bash
# win11 VM with the RTX 4070 passed through, shown by Looking Glass B7 on the laptop panel (no external monitor, no dummy plug).
# Installs: Looking Glass client (built into ~/.local), its config, shared memory file + AppArmor rule, the vBIOS file, ~/.local/bin/vm-gpu,
# the root helper /usr/local/sbin/vm-gpu-nvidia and the udev rule 99-vm-gpu.rules (NVIDIA module unload/load around the VM, Hyprland kept off the card),
# the VM definition (templates/libvirt-win11.xml, QXL fallback: libvirt-win11-qxl.xml) and, with a prompt, Hyprland's "VM mode".
# Windows side (once, in the guest): docs/windows-vm.md.
# Rollback: virsh define $BACKUP (the old VM definition is saved there); rm ~/.local/bin/vm-gpu ~/.local/bin/looking-glass-client ~/.config/looking-glass
#   ~/.config/hyprland-ii/gpu-passthrough; sudo rm /etc/tmpfiles.d/10-looking-glass.conf /usr/share/vgabios/rtx4070.rom;
#   sudo rm /usr/local/sbin/vm-gpu-nvidia /etc/udev/rules.d/99-vm-gpu.rules /etc/udev/rules.d/71-nvidia.rules /etc/vm-gpu/vm-mode /etc/sudoers.d/vm-gpu; sudo udevadm control --reload;
#   remove the /dev/shm/looking-glass line from /etc/apparmor.d/local/abstractions/libvirt-qemu; log out and in.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_hw

LG_TAG=B7
LG_SRC="$SRC/LookingGlass"
BACKUP="$BACKUP_DIR/win11-before-gpu-passthrough.xml"
shopt -s nullglob; grp=(/sys/kernel/iommu_groups/*/devices/0000:01:00.0); shopt -u nullglob
[ "${#grp[@]}" -eq 1 ] || die "No IOMMU group for 0000:01:00.0: enable VT-d in the BIOS and check lspci."
members=$(ls "$(dirname "${grp[0]}")")
[ "$(echo "$members" | wc -l)" -le 2 ] || die "The 4070 shares its IOMMU group with other devices: $(echo $members)"

step "Looking Glass $LG_TAG client (build dependencies, source, build into ~/.local)"
sudo apt-get install -y binutils-dev cmake fonts-dejavu-core libfontconfig-dev g++ pkg-config \
  libegl-dev libgl-dev libgles-dev libspice-protocol-dev nettle-dev \
  libx11-dev libxcursor-dev libxi-dev libxinerama-dev libxpresent-dev libxss-dev libxkbcommon-dev libxcb-shm0-dev \
  libwayland-dev wayland-protocols libdecor-0-dev libpipewire-0.3-dev libpulse-dev libsamplerate0-dev
lg_ver() { "$HOME/.local/bin/looking-glass-client" --version 2>&1 || true; }   # exits non-zero; pipefail would abort the phase
if ! lg_ver | grep -q "($LG_TAG)"; then
  mkdir -p "$SRC"
  [ -d "$LG_SRC" ] || git clone --depth 1 --branch "$LG_TAG" --recurse-submodules --shallow-submodules https://github.com/gnif/LookingGlass.git "$LG_SRC"
  mkdir -p "$LG_SRC/client/build"
  (cd "$LG_SRC/client/build" && cmake -DCMAKE_INSTALL_PREFIX="$HOME/.local" .. && make -j"$(nproc)" && make install)
fi
lg_ver | grep -m1 Looking || true

step "Looking Glass client config (German Legion keyboard: no Scroll Lock or Right Ctrl, so Insert is the escape key)"
mkdir -p "$HOME/.config/looking-glass"
[ -f "$HOME/.config/looking-glass/client.ini" ] || cat > "$HOME/.config/looking-glass/client.ini" <<'INI'
; Looking Glass client for the win11 VM (laptop panel, Hyprland/Wayland)
[app]
shmFile=/dev/shm/looking-glass

[spice]
host=127.0.0.1
port=5900

[input]
; keyboard (incl. the Windows key) goes to the VM while its window is focused; Insert gives it back
grabKeyboardOnFocus=yes
escapeKey=KEY_INSERT
autoCapture=yes
rawMouse=yes

[egl]
; artifacts / black frames on Wayland + Intel
doubleBuffer=yes
noBufferAge=yes
noSwapDamage=yes
INI

step "Shared memory file for the frames (128 MiB) and AppArmor access for QEMU"
echo "f /dev/shm/looking-glass 0660 $USER kvm -" | sudo tee /etc/tmpfiles.d/10-looking-glass.conf >/dev/null
sudo systemd-tmpfiles --create /etc/tmpfiles.d/10-looking-glass.conf
sudo mkdir -p /etc/apparmor.d/local/abstractions
grep -qxF '/dev/shm/looking-glass rw,' /etc/apparmor.d/local/abstractions/libvirt-qemu 2>/dev/null \
  || echo '/dev/shm/looking-glass rw,' | sudo tee -a /etc/apparmor.d/local/abstractions/libvirt-qemu >/dev/null

step "vm-gpu and nv-run"
install -D -m755 "$REPO/bin/vm-gpu" "$HOME/.local/bin/vm-gpu"
install -D -m755 "$REPO/bin/nv-run" "$HOME/.local/bin/nv-run"
install -D -m755 "$REPO/bin/hii-session" "$HOME/.local/bin/hii-session"   # session switch for the sidebar buttons: saves and restores the windows   # run one command on the 4070 from the iGPU-pinned VM-mode session

step "Root helper (NVIDIA module unload/load) and udev rule (keeps Hyprland off the 4070's DRM node in VM mode)"
sudo install -o root -g root -m 755 "$REPO/templates/vm-gpu/vm-gpu-nvidia" /usr/local/sbin/vm-gpu-nvidia
sudo install -o root -g root -m 644 "$REPO/templates/vm-gpu/99-vm-gpu.rules" /etc/udev/rules.d/99-vm-gpu.rules
# NVIDIA's packaged 71-nvidia.rules runs `modprobe -r nvidia-drm/-modeset/-uvm` when the nvidia driver unregisters. Racing with our
# unload/load that became a self-sustaining unload/load loop every ~3 s (2026-10-05). Override it with a copy that keeps only the add rules.
sudo sh -c 'grep -v "ACTION==\"remove\"" /usr/lib/udev/rules.d/71-nvidia.rules > /etc/udev/rules.d/71-nvidia.rules'
sudo udevadm control --reload
if ! sudo -n -l /usr/local/sbin/vm-gpu-nvidia unload >/dev/null 2>&1; then
  warn "Optional, for a password-free 'vm-gpu start/stop' (otherwise sudo asks each time): sudo visudo -f /etc/sudoers.d/vm-gpu, one line:"
  echo "$USER ALL=(root) NOPASSWD: /usr/local/sbin/vm-gpu-nvidia unload, /usr/local/sbin/vm-gpu-nvidia load, /usr/local/sbin/vm-gpu-nvidia mode vm, /usr/local/sbin/vm-gpu-nvidia mode normal"
fi

step "vBIOS of the 4070 (the VM needs it: laptop GPUs do not initialise reliably in a guest without it)"
if [ -f /usr/share/vgabios/rtx4070.rom ]; then ls -l /usr/share/vgabios/rtx4070.rom
else "$HOME/.local/bin/vm-gpu" rom; fi

step "VM definition"
virsh -c qemu:///system list --all --name | grep -qx win11 || die "No win11 VM defined: define it from templates/libvirt-win11-qxl.xml first."
virsh -c qemu:///system domstate win11 | grep -q 'shut off' || die "Shut win11 down first: virsh shutdown win11"
mkdir -p "$BACKUP_DIR"
[ -f "$BACKUP" ] || virsh -c qemu:///system dumpxml --inactive win11 > "$BACKUP"
echo "Old definition saved to $BACKUP"
if confirm "Replace the win11 definition with templates/libvirt-win11.xml (GPU passthrough, no QXL)?"; then
  virsh -c qemu:///system define "$REPO/templates/libvirt-win11.xml"
fi

step "Hyprland VM mode (Hyprland must not hold the 4070 open; external monitors on the HDMI port then stop working on the host)"
"$HOME/.local/bin/vm-gpu" mode show
if confirm "Turn VM mode on (log out and in afterwards)?"; then "$HOME/.local/bin/vm-gpu" mode vm; fi
command -v etckeeper >/dev/null && sudo etckeeper commit "Phase 94: win11 GPU passthrough" || true
ok "Windows side once (docs/windows-vm.md), then: vm-gpu start"
