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
- **Video:** QXL with 128 MiB ram/vram for 4K and multi-monitor work; four SPICE USB redirectors.
- **Unchanged:** UEFI + Secure Boot (OVMF secboot), emulated TPM 2.0, `localtime` clock, virtiofs share of `~/Downloads` as `share`, the MSDM ACPI table (`/var/lib/libvirt/acpi/win11-msdm.bin`, referenced but not stored in this repo).

Before this the VM had 12 GiB, 4 plain vCPUs, a 64 MiB QXL, and only `relaxed/vapic/spinlocks/vpindex/synic/stimer/frequencies`.
