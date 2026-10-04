# Sleep and hibernate (phases 90-93)

[← Back to the README](../README.md)

Found the hard way (about ten hard reboots); don't undo these without testing with an RTC wake alarm, not the lid:

- **s2idle, not S3 "deep".** After S3 the NVIDIA driver never re-lights the eDP panel (black even on the text console). Phase 91 puts `mem_sleep_default=s2idle` on the Limine command line.
- **NVIDIA suspends from the kernel** (`NVreg_UseKernelSuspendNotifiers=1`; runtime D3 off in dGPU-only mode, on in Hybrid: see [Hybrid graphics](hybrid-graphics.md)) and the `nvidia-suspend/resume/hibernate` systemd services are masked: their `chvt 63` dance froze the whole machine on resume (phase 90).
- **Hibernate** uses a 32 GB `/swap.img` with `resume=UUID=... resume_offset=...` on the command line (phases 90/91). Wake it with the power button; the RTC alarm cannot wake from S4 here.
- **The machine boots Limine from the ESP, not GRUB** (phase 92 removes GRUB, after checking that Limine can boot on its own: EFI entry, ESP kernel/initrd = newest `/boot` kernel, `limine.conf` has the resume/s2idle/EDID args; it asks before purging). Phase 91 installs `limine-esp-sync` (kernel postinst and `update-initramfs` hooks) so the ESP copy of the kernel/initrd follows `/boot`; the previous kernel stays as the second menu entry, without the EDID pin.
- Phase 93 pins the panel EDID (`drm.edid_firmware`): it stops a retry loop after resume, but it was not what fixed sleep.
