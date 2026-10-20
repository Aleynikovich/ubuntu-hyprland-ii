#!/usr/bin/env bash
# Brightness keys with hold acceleration: 1% per press, then growing steps while the key is held (Hyprland repeats the bind).
# Usage: brightness-accel.sh up|down. A gap > GAP_MS since the last event starts a new press (step 1).
dir="${1:?up|down}"
state="${XDG_RUNTIME_DIR:-/tmp}/brightness-accel.$dir"
GAP_MS=400 HOLD_FREE=8 RAMP_EVERY=5 MAX_STEP=10
now=$((${EPOCHREALTIME/./} / 1000))
{ read -r last streak <"$state"; } 2>/dev/null || { last=0; streak=0; }
(( now - last > GAP_MS )) && streak=0
streak=$((streak + 1))
echo "$now $streak" >"$state"
step=1
(( streak > HOLD_FREE )) && step=$(( 1 + (streak - HOLD_FREE) / RAMP_EVERY ))
(( step > MAX_STEP )) && step=$MAX_STEP
[ "$dir" = down ] && step=-$step
qs -c "${qsConfig:-ii}" ipc call brightness adjust "$step" || brightnessctl s "${step#-}%$([ "$dir" = down ] && echo - || echo +)"
