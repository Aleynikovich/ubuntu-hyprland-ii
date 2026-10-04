# Hybrid graphics: battery and thermals (phases 91 and 99)

[← Back to the README](../README.md)

**Goal:** better battery life and lower temperatures without losing the snappy desktop.

**Idea:** in the BIOS **Hybrid** mode the Intel iGPU draws the desktop and the RTX 4070 sleeps until an app is sent to it. In **dGPU-only** mode the RTX draws everything and never sleeps (about 10 W at idle on AC, about 3 W on battery, clocks locked on AC).

## Status (2026-10-04)

| Check | Result |
|---|---|
| Boots in BIOS Hybrid mode | ✅ default Limine entry boots to Hyprland |
| Hyprland on the iGPU at 3200x2000, 165 Hz | ✅ |
| NVIDIA runtime-suspends when idle (`runtime_status: suspended`) | ✅ |
| Offload to NVIDIA works and it sleeps again afterwards | ✅ about 25 s after the app exits |
| OpenGL offload to NVIDIA (`glxinfo`) | ✅ Isaac Sim and games through offload are not re-tested yet |
| Suspend and hibernate with runtime power management on | ⏳ not re-tested yet |
| External monitor (HDMI/DP, wired to the NVIDIA GPU) | ⏳ not tested yet |
| Battery life vs dGPU-only | ⏳ no like-for-like baseline: idle draw on battery was ~30 W with the iGPU, NVIDIA suspended and the panel at 100% |

Brightness barely moved the number (100% to 40% saved about 1 W). Quickshell and Hyprland used about 25% CPU each at idle, so constant redrawing at 165 Hz is the next thing to look at.

## What it changes

| Change | Where | Why |
|---|---|---|
| `NVreg_DynamicPowerManagement=0x02` | `/etc/modprobe.d/zz-nvidia-hybrid-pm.conf` (phase 99) | Lets the GPU enter runtime D3. Phase 90 had set `0x00` for the sleep fix; the `zz-` file is read last and wins |
| X server no longer forced onto NVIDIA | `/etc/X11/xorg.conf.d/20-nvidia.conf` moved to `.disabled`, `10-hybrid.conf` sets `AutoAddGPU false` (phase 99) | SDDM's X server held the NVIDIA GPU open for the whole session, so it could never sleep |
| gpu-warm knows the mode | `/usr/local/sbin/gpu-warm` (phase 95) | No `nvidia-smi` calls and no `nvidia-persistenced` while NVIDIA sleeps (either would wake or pin it); iGPU clock floor on AC |
| Session wrapper picks the display GPU | `session/hyprland-ii-session` | Panel on the iGPU: no NVIDIA environment variables, `AQ_DRM_DEVICES` lists the iGPU first |
| Extra Limine boot entries "hybrid test A/B/C" | phase 91 | Verbose boots that split a failure into kernel+iGPU (A), session (B) and NVIDIA (C). The default entry was enough, so they are only for debugging |

## Running an app on the NVIDIA GPU

```bash
__NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia <command>
```

Check which GPU is in use: add `glxinfo -B | grep renderer` as the command. Anything that does not need the RTX stays on the iGPU and the RTX stays asleep.

## Trade-offs to know

- **Panel on the iGPU.** The Intel UHD 770 is much weaker than the 4070. Whether blur, animations and window opening stay snappy over a normal working day has not been judged yet; that is the main thing to check.
- **External monitor.** The HDMI and DisplayPort outputs belong to the NVIDIA GPU. With a monitor attached the GPU has to stay awake and every frame is copied across, so the battery gain is for unplugged use without a monitor.
- **Sleep.** Runtime D3 is the setting phase 90 turned off for the suspend fix. If suspend or hibernate misbehaves, delete `/etc/modprobe.d/zz-nvidia-hybrid-pm.conf` and reboot.
- **Mode switch needs a reboot.** The BIOS MUX cannot change at runtime. Scripts detect the mode at run time, so nothing needs re-running after a switch.

## Rollback

```bash
sudo rm /etc/modprobe.d/zz-nvidia-hybrid-pm.conf /etc/X11/xorg.conf.d/10-hybrid.conf
sudo mv /etc/X11/xorg.conf.d/20-nvidia.conf.disabled /etc/X11/xorg.conf.d/20-nvidia.conf
sudo reboot       # then set the BIOS graphics mode back to Discrete if you want dGPU-only
```
