#!/usr/bin/env bash
# Read-only power snapshot for comparing AC vs battery (phase 95, "Responsiveness" in the README). No sudo.
# Prints: AC state, power profile / platform profile, CPU governor + EPP, GPU P-state/clocks/power (nvidia-smi),
# display refresh + backlight, and the battery charge/discharge rate averaged over SECS seconds (default 10).
# Usage: maintenance/power-report.sh             run once on AC and once on battery (leave it idle while it samples)
#        SECS=30 maintenance/power-report.sh     longer average (power_now only updates every few seconds)
set -uo pipefail
SECS="${SECS:-10}"
rd(){ cat "$1" 2>/dev/null; }
uniqc(){ sort | uniq -c | awk '{printf "%s%s x%s", (NR>1?", ":""), $2, $1} END{print ""}'; }   # "performance x24"

echo "== $(date '+%F %T')  $(uname -r)"

ac=battery
for s in /sys/class/power_supply/*/; do
  [ "$(rd "$s/type")" = Mains ] && [ "$(rd "$s/online")" = 1 ] && ac="AC ($(basename "$s"))"
done
echo "power source:     $ac"
echo "power profile:    $(powerprofilesctl get 2>/dev/null || echo n/a)   platform_profile: $(rd /sys/firmware/acpi/platform_profile || echo n/a)"
echo "cpu driver:       $(rd /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver)   intel_pstate: $(rd /sys/devices/system/cpu/intel_pstate/status || echo n/a)   no_turbo: $(rd /sys/devices/system/cpu/intel_pstate/no_turbo || echo n/a)"
echo "cpu governor:     $(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | uniqc)"
echo "cpu EPP:          $(cat /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 2>/dev/null | uniqc)"
echo "cpu MHz (now):    $(awk '{s+=$1; if($1>m)m=$1} END{if(NR) printf "avg %d, max %d", s/NR/1000, m/1000}' /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq)"

if command -v nvidia-smi >/dev/null; then
  nvidia-smi --query-gpu=name,pstate,clocks.gr,clocks.mem,clocks.max.graphics,power.draw,temperature.gpu,utilization.gpu,persistence_mode \
    --format=csv,noheader | while IFS=, read -r n p g m x w t u pm; do
    echo "gpu:              $n |$p | gr$g (max$x) | mem$m | draw$w |$t C | util$u | persistence$pm"
  done
  for d in /sys/bus/pci/drivers/nvidia/0000:*; do
    [ -e "$d/power/runtime_status" ] && echo "gpu runtime PM:   $(basename "$d") $(rd "$d/power/runtime_status")"
  done
else
  echo "gpu:              nvidia-smi not found"
fi

if command -v hyprctl >/dev/null; then
  hyprctl monitors -j 2>/dev/null | python3 -c 'import json,sys
for m in json.load(sys.stdin):
  print("display:          %s %dx%d@%.0fHz vrr=%s" % (m["name"], m["width"], m["height"], m["refreshRate"], m.get("vrr")))' 2>/dev/null
fi
for b in /sys/class/backlight/*; do
  mx=$(rd "$b/max_brightness"); [ -e "$b/brightness" ] && [ "${mx:-0}" -gt 0 ] && echo "backlight:        $(basename "$b") $(( $(rd "$b/brightness") * 100 / mx ))%"
done

for B in /sys/class/power_supply/BAT*; do
  [ -e "$B/status" ] || continue
  sum=0; n=0
  for ((i = 0; i < SECS; i++)); do
    if [ -r "$B/power_now" ]; then w=$(rd "$B/power_now")                                   # uW
    else a=$(rd "$B/current_now"); v=$(rd "$B/voltage_now"); w=$(( ${a:-0} * ${v:-0} / 1000000 )); fi  # uA * uV -> uW
    w=${w:-0}; sum=$((sum + ${w#-})); n=$((n + 1)); sleep 1
  done
  st=$(rd "$B/status"); now=$(rd "$B/energy_now"); full=$(rd "$B/energy_full")
  [ -n "$now" ] || { now=$(( $(rd "$B/charge_now") * $(rd "$B/voltage_now") / 1000000 )); full=$(( $(rd "$B/charge_full") * $(rd "$B/voltage_now") / 1000000 )); }
  avg=$((sum / (n ? n : 1)))
  awk -v b="$(basename "$B")" -v st="$st" -v c="$(rd "$B/capacity")" -v now="$now" -v full="$full" -v avg="$avg" -v s="$SECS" 'BEGIN{
    printf "battery:          %s %s %s%% (%.1f / %.1f Wh), rate %.2f W (avg of %ss)", b, st, c, now/1e6, full/1e6, avg/1e6, s
    if (st == "Discharging" && avg > 0) printf ", ~%.1f h left", now/avg
    print "" }'
done
