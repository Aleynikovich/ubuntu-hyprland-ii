#!/usr/bin/env bash
# Brightness keys: 1% per tap; on a long press, a burst of BURST 1% steps per event.
# Why: the panel's ACPI Video Bus never reports a held key, it sends a fresh press+release every ~250 ms (measured 220-285),
#   so Hyprland's repeat can't help. A hold is recognised by that steady rhythm: an event HOLD_MIN..HOLD_MAX ms after the
#   previous one continues it, anything else (single or double taps) starts over. Bursts begin at event HOLD_EVENTS.
# Usage: brightness-accel.sh up|down.
dir="${1:?up|down}"
state="${XDG_RUNTIME_DIR:-/tmp}/brightness-accel.$dir"
HOLD_MIN=190 HOLD_MAX=320 HOLD_EVENTS=3 BURST=6 TICK=0.012
now=$((${EPOCHREALTIME/./} / 1000))
{ read -r last streak <"$state"; } 2>/dev/null || { last=0; streak=0; }
gap=$((now - last))
(( gap < HOLD_MIN || gap > HOLD_MAX )) && streak=0
streak=$((streak + 1))
echo "$now $streak" >"$state"
step=1; [ "$dir" = down ] && step=-1
adjust() { qs -c "${qsConfig:-ii}" ipc call brightness adjust "$step" || brightnessctl s "1%$([ "$dir" = down ] && echo - || echo +)"; }
(( streak < HOLD_EVENTS )) && { adjust; exit; }
for ((i = 0; i < BURST; i++)); do adjust; sleep "$TICK"; done
