# Windows 11 VM for TIA Portal / RobotStudio

[← Back to the README](../README.md)

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
- **Video:** no emulated GPU any more: the passed-through RTX 4070 plus a virtual display shown by Looking Glass (next section). The old QXL definition (128 MiB ram/vram, 4K and multi-monitor) is `templates/libvirt-win11-qxl.xml`, the fallback; four SPICE USB redirectors.
- **Unchanged:** UEFI + Secure Boot (OVMF secboot), emulated TPM 2.0, `localtime` clock, virtiofs share of `~/Downloads` as `share`, the MSDM ACPI table (`/var/lib/libvirt/acpi/win11-msdm.bin`, referenced but not stored in this repo).

Before this the VM had 12 GiB, 4 plain vCPUs, a 64 MiB QXL, and only `relaxed/vapic/spinlocks/vpindex/synic/stimer/frequencies`.

## GPU passthrough (RTX 4070) with Looking Glass

**Goal:** near-native Windows performance for RobotStudio, TIA Portal and CAD, on the laptop panel, with the laptop mostly plugged in. Phase 94 (`phases/94-win11-gpu.sh`) installs the host side; the Windows side is done once, below.

**How it works:** in BIOS Hybrid mode the Intel iGPU drives the panel and the 4070 has nothing to do, so it can be given to the VM. It is alone in IOMMU group 13 with its audio function. `vm-gpu start` unloads the NVIDIA kernel modules (`/usr/local/sbin/vm-gpu-nvidia unload`), libvirt binds the driverless card and its audio function to `vfio-pci` and starts the VM (`managed="yes"`); `vm-gpu stop` shuts the VM down and loads the modules again, so the 4070 is back on the host for CUDA, Isaac Sim and PRIME offload and sleeps when idle. Windows renders on the 4070 to a virtual display; the Looking Glass host app copies the frames into shared memory (`/dev/shm/looking-glass`, 128 MiB) and the client on Hyprland draws them, takes keyboard and mouse over SPICE and plays the sound through PipeWire.

**Why modules are unloaded and not just unbound:** unbinding the 4070 from the nvidia driver (595, `nvidia-drm` modeset) works once per boot; the second unbind of a re-probed device oopsed (`nv_drm_master_drop` -> NULL dereference in `nvidia_modeset`) and froze the machine (2026-10-05). A full module unload and reload is clean (tested in cycles, no kernel errors).

**Why the udev rule:** when `nvidia_drm` is loaded again the 4070 gets a new DRM card node, and Hyprland opens every new GPU on the udev hotplug event (Aquamarine checks neither the seat nor `AQ_DRM_DEVICES` for hotplugged cards). Its open handle blocks the next unload. `/etc/udev/rules.d/99-vm-gpu.rules` puts the 4070's card nodes on a seat nobody uses while `/etc/vm-gpu/vm-mode` exists (created by `vm-gpu mode vm`), so logind refuses Hyprland the device. The render node is untouched: CUDA and offload keep working.

**Why `71-nvidia.rules` is overridden:** the package rule runs `modprobe -r nvidia-drm` / `-modeset` / `-uvm` when the nvidia driver unregisters, and `modprobe -r` also drops the now-unused `nvidia` module, which fires the next remove event. Racing with the helper's unload and load, that became a self-sustaining unload/load loop every ~3 s (seen after the first VM stop). `/etc/udev/rules.d/71-nvidia.rules` is a copy of the packaged file without the `ACTION=="remove"` lines (generated by phase 94; re-generate it after an NVIDIA driver package update that changes the rules).

**Passwordless start/stop (optional):** the helper is root-owned and called through `sudo`; `vm-gpu start/stop` ask for the password unless you add `sudo visudo -f /etc/sudoers.d/vm-gpu` with one line allowing exactly `vm-gpu-nvidia unload`, `load`, `mode vm` and `mode normal`.

**Using it:** `vm-gpu start` (checks, starts the VM, blocks sleep while it runs, opens the client), `vm-gpu stop`, `vm-gpu status`, `vm-gpu client`. While the VM runs the host has no CUDA, no Isaac Sim, no PRIME offload and no external monitor on the HDMI port (that port belongs to the 4070). The client gives the keyboard (and the Windows key) to Windows while its window is focused; **Insert** gives it back. The 4070 draws 20-40 W while the VM runs: `vm-gpu start` refuses on battery unless `--battery-ok`.

**Hyprland must not hold the 4070.** By default Hyprland opens it for external monitors, and the NVIDIA driver cannot unbind with an open handle. `vm-gpu mode vm` creates `~/.config/hyprland-ii/gpu-passthrough` (and `/etc/vm-gpu/vm-mode` for the udev rule); `session/hyprland-ii-session` then starts Hyprland with the iGPU only (`AQ_DRM_DEVICES`), Mesa-only EGL (`__EGL_VENDOR_LIBRARY_FILENAMES`; glvnd would otherwise load `libEGL_nvidia`, which opens `/dev/nvidia*`) and the Intel Vulkan driver. Switching needs a re-login. `vm-gpu mode normal` removes the file again (external monitors work, the VM cannot get the GPU).

**What was needed to make the 4070 work in the guest** (all in `templates/libvirt-win11.xml`): hide KVM (`<kvm><hidden/>`) and the Hyper-V vendor id, and give the card its own vBIOS (`vm-gpu rom` dumps it to `/usr/share/vgabios/rtx4070.rom`; that directory is already readable by libvirt's AppArmor profile, `/var/lib/libvirt` is not). Code 43 never appeared with those; the fake-battery ACPI table that laptops sometimes need was not necessary.

**Windows side (once):**
1. NVIDIA driver, **Express** install. A Custom "clean installation" wipes the working driver, resets the GPU in the middle and the guest crashes; if it ever happens, `pnputil /add-driver C:\Windows\INF\oem1.inf /install` restores the driver the Windows store already has.
2. Looking Glass host from looking-glass.io, exactly the client's version (B7): extract, run `looking-glass-host-setup.exe` as administrator. It also installs the IVSHMEM driver and the service.
3. A virtual display, because the 4070 has no output in this mode: Virtual Display Driver (VirtualDrivers/Virtual-Display-Driver, signed by SignPath Foundation). Copy its `vdd_settings.xml` to `C:\VirtualDisplayDriver\`, set the modes (3200x2000 is the panel's native mode; the refresh rates 60/90/120/144/165 come from its global list), install `MttVDD.inf` and create the root device `Root\MttVDD` (devcon-style, `SetupDiCreateDeviceInfo` + `UpdateDriverForPlugAndPlayDevices`; `pnputil /add-device` has a different syntax). Choose "Show only on the virtual display" in Windows once.
4. `C:\ProgramData\Looking Glass (host)\looking-glass-host.ini` with `[d12]` / `trackDamage=no`: with damage tracking on, window fade-in animations stay stuck half-transparent.
5. The shared drive (`~/Downloads` as `share`): WinFsp plus the VirtIO FS driver; start the `VirtioFsSvc` service (set it to Automatic). It appears as `Z:`.

**Gotchas seen:**
- A passed-through GPU next to the emulated QXL display makes the pointer disappear; that is why QXL is removed. If you need the QXL fallback, `virsh define templates/libvirt-win11-qxl.xml` (no GPU).
- Client artifacts or black frames on Wayland + Intel: `egl:doubleBuffer`, `noBufferAge`, `noSwapDamage` (in `~/.config/looking-glass/client.ini`).
- The German Legion keyboard has no Scroll Lock or Right Ctrl, so the escape key is Insert.
- Windows system file corruption (`mmcbase.dll`, Device Manager would not open) came from the guest being cut off during driver installs; DISM `/RestoreHealth` then `sfc /scannow` fixed it.
- Sleep and hibernate: a vfio device breaks both. `vm-gpu start` holds a block inhibitor for the VM's lifetime; stop the VM before closing the lid on battery (the lid script hibernates).

**Rollback:** `virsh define ~/backups/win11-before-gpu-passthrough.xml` (saved by phase 94) or `templates/libvirt-win11-qxl.xml`; `vm-gpu mode normal` and log in again; the other files are listed in the header of `phases/94-win11-gpu.sh`.

