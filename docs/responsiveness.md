# Responsiveness: GPU and CPU clocks (phase 95)

[← Back to the README](../README.md)

**Symptom:** after some time in one app, the first new window (a terminal after a while in VS Code) or workspace switch stutters once, then everything is snappy.

**Cause** (measured): the GPU that draws the desktop idles at its lowest clock and the first frame waits for it to ramp up. On the RTX 4070 that is P8 (210 MHz graphics, 810 MHz memory). The CPU was also in `power-saver` (EPP `power`) on AC.

**Fix:** `/usr/local/sbin/gpu-warm` runs at boot, after resume, and on every AC plug/unplug (`gpu-warm.service` and a udev rule). It checks the BIOS graphics mode at run time, so it keeps working if you switch modes.

| | On AC | On battery |
|---|---|---|
| **Hybrid** (iGPU draws the desktop) | iGPU floor 900 MHz (max ~1650). NVIDIA is not touched, so it can sleep | floor released; NVIDIA still not touched |
| **dGPU-only** (NVIDIA draws the desktop) | graphics floor 1200 MHz and memory floor 6001 MHz (maxes unchanged), `nvidia-persistenced` running | floors released |
| **Both modes** | power profile `performance`, CPU governor `performance` | `balanced`, governor `powersave` |

- The memory floor matters: with only the graphics floor, memory idled at 810 of 8001 MHz and the first blur/workspace frame still stuttered. The price in dGPU-only mode is about 10 W idle draw (P4) instead of about 4 W.
- The governor is set to `performance` because Isaac Sim warns about `powersave`, even though `intel_pstate` with EPP `performance` is equivalent.
- The profile switch retries for a few seconds: power-profiles-daemon sometimes answers "busy" when two AC events arrive together, which used to leave the laptop on `performance` after unplugging.

**Measure it:** `maintenance/power-report.sh` prints AC state, profile, governor/EPP, GPU state, display mode and battery rate averaged over `SECS` seconds (default 10). Run it idle once on AC and once on battery. In Hybrid it does not query `nvidia-smi` while the NVIDIA GPU sleeps (the query would wake it). `nvidia-smi` showing persistence mode "Disabled" in dGPU-only mode is expected: Ubuntu runs `nvidia-persistenced` with `--no-persistence-mode`, which still keeps the driver initialized.

Isaac Sim's "IOMMU is enabled" warning is Ubuntu's default and was left alone (turning it off needs a kernel command line change).

**Rollback:** `sudo systemctl disable --now gpu-warm.service; sudo rm /etc/systemd/system/gpu-warm.service /etc/udev/rules.d/99-gpu-warm.rules /usr/local/sbin/gpu-warm; sudo nvidia-smi -rgc; sudo nvidia-smi -rmc`
