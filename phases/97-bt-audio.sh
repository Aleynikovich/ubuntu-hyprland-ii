#!/usr/bin/env bash
# Bluetooth audio without stutter/pops on the RTL8852CE (Wi-Fi + BT combo): no geoclue Wi-Fi scans, PipeWire keeps RT, Wi-Fi PS off, newer Wi-Fi fw
# Why (measured 2026-10-03, rtw89 btc_info + iw event + busctl monitor):
#   - geoclue asked wpa_supplicant for a full 2.4/5/6 GHz scan every 15 s (the shell's weather "enableGPS" kept it running; its
#     Mozilla Location Service backend is gone, so every lookup failed anyway). Each scan parks the shared radio on 2.4 GHz for ~5 s,
#     right on top of the A2DP link: ~700 scans and ~350 band switches in 2.5 h.
#   - rtkit's canary "starved" across every suspend and demoted PipeWire's RT threads for good; under CPU/network load the BT encoder
#     thread then missed its deadlines (stutter + pops; wired audio has a bigger buffer). Group pipewire = RT via rlimits, no rtkit.
#   - Wi-Fi power save: the coex engine re-ran on every LPS enter/leave (~4400 radio_state events in 2.5 h).
#   - Wi-Fi fw 0.27.125.0 (noble's linux-firmware) is older than kernel 7.0's coex expects ("WL FW report invalid", BT_FW_coex mismatch);
#     upstream's newer one goes to /lib/firmware/updates, which the loader prefers. BT fw (rtl8852cu_fw_v2) already = upstream.
# Rollback: sudo rm /etc/geoclue/conf.d/90-no-wifi-scan.conf /etc/NetworkManager/conf.d/wifi-powersave-off.conf
#   /lib/firmware/updates/rtw89/rtw8852c_fw-2.bin; sudo gpasswd -d "$USER" pipewire; set bar.weather.enableGPS back to true; reboot.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_hw

# linux-firmware commit "rtw89: 8852c: update REGD R73-R60, txpwr R82 and element of diag MAC" (2026-01-27): fw v0.27.129.4
FW_COMMIT=f9c84ebaefbf22f30a5a327aef97884be5ed5e22
FW_SHA256=916e87d1470bce5400712f53d419ae68a0f44d858670c57e118d4f0b1d89c5b4
FW_DST=/lib/firmware/updates/rtw89/rtw8852c_fw-2.bin

step "geoclue: no Wi-Fi source (it scanned every 15 s; its lookup service no longer exists)"
sudo install -d /etc/geoclue/conf.d
sudo tee /etc/geoclue/conf.d/90-no-wifi-scan.conf >/dev/null <<'EOF2'
[wifi]
enable=false
EOF2
sudo systemctl try-restart geoclue.service

step "Shell weather: use the configured city instead of GPS"
CJ=~/.config/illogical-impulse/config.json
if [ -f "$CJ" ] && command -v jq >/dev/null; then
  if [ "$(jq '.bar.weather.enableGPS' "$CJ")" = true ]; then
    jq --indent 4 '.bar.weather.enableGPS = false' "$CJ" > "$CJ.tmp" && mv "$CJ.tmp" "$CJ"
    echo "enableGPS -> false (city: $(jq -r '.bar.weather.city' "$CJ"))"
  else echo "already off"; fi
else warn "no $CJ (or no jq): turn off GPS in the shell's weather settings by hand"; fi

step "$USER -> group pipewire (RT priority from /etc/security/limits.d/25-pw-rlimits.conf, not rtkit)"
if id -nG "$USER" | tr ' ' '\n' | grep -qx pipewire; then echo "already in pipewire"; else sudo usermod -aG pipewire "$USER"; fi

step "NetworkManager: Wi-Fi power save off"
sudo tee /etc/NetworkManager/conf.d/wifi-powersave-off.conf >/dev/null <<'EOF2'
# Overrides default-wifi-powersave-on.conf (later file wins): rtw89 BT coex re-ran on every power-save toggle. Phase 97.
[connection]
wifi.powersave = 2
EOF2
sudo nmcli general reload conf

step "Wi-Fi firmware: rtw8852c_fw-2.bin from linux-firmware $FW_COMMIT -> $FW_DST"
if [ -f "$FW_DST" ] && echo "$FW_SHA256  $FW_DST" | sha256sum -c --quiet 2>/dev/null; then echo "already installed"
else
  tmp=$(mktemp); at_exit "rm -f '$tmp'"
  curl -fsSL -o "$tmp" "https://gitlab.com/kernel-firmware/linux-firmware/-/raw/$FW_COMMIT/rtw89/rtw8852c_fw-2.bin"
  echo "$FW_SHA256  $tmp" | sha256sum -c --quiet || die "checksum mismatch for the downloaded firmware"
  sudo install -D -m644 "$tmp" "$FW_DST"
fi

command -v etckeeper >/dev/null && sudo etckeeper commit "Phase 97: Bluetooth audio coexistence" || true
ok "Reboot (new firmware + group). Check: 'sudo grep -E \"WL_FW|scan_start|radio_state\" /sys/kernel/debug/ieee80211/phy0/rtw89/btc_info'
  shows WL_FW 0.27.129.x and scan_start barely moving; 'ps -L -o cls,rtprio,comm -p \$(pgrep -x pipewire)' shows FF 88 on data-loop, also after a suspend."
