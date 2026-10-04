# Bluetooth audio (phase 97)

[← Back to the README](../README.md)

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
