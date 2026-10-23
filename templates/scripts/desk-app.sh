#!/usr/bin/env bash
# Desk apps: web tools (Slack, Linear, ...) as Vivaldi app windows, each with a home workspace and a jump key.
# Why: as tabs they are all "vivaldi-stable" to Hyprland. `vivaldi --app=URL` windows get their own class (vivaldi-<host>__<path>-<profile>).
#   No window rule pins them, so a second Slack opened next to the code stays there. All app windows share Vivaldi's PID, so exec rules
#   can't place them: a new window is moved once it maps.
# Usage: desk-app.sh <app>       jump: its window on a visible workspace (any monitor), else the one on its home desk, else the most recent.
#                                On it already: the next one, or back to the previous window if there is only one. None: open it at home.
#        desk-app.sh <app> new   open another window of it on the focused workspace.
# Home desk n counts in every monitor's group (hypr-sync-workspaces): with the external, a Slack dragged from 1 to 11 is still at home.
app="${1:?app}" mode="${2:-jump}"
case "$app" in
  slack)    url=https://app.slack.com/client home=1 ;;
  whatsapp) url=https://web.whatsapp.com     home=1 ;;
  linear)   url=https://linear.app           home=2 ;;
  notion)   url=https://www.notion.so        home=2 ;;
  *) echo "unknown app: $app" >&2; exit 2 ;;
esac
host=${url#https://}; host=${host%%/*}
prefix="vivaldi-$host"__   # the class without path and profile: Slack's URL path changes once it loads, the class doesn't

# One run per app at a time: two quick presses while Vivaldi starts would open two windows.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/desk-app.$app.lock"
flock -n 9 || exit 0

wins() { hyprctl clients -j | jq -r --arg p "$prefix" '[.[] | select(.class | startswith($p)) | .address] | sort | join(" ")'; }
focus() { hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" >/dev/null; }

# Opens a window and moves it to workspace $1 once it maps (up to 20 s for a cold Vivaldi start).
open_on() {
  local before new i
  before=$(wins)
  hyprctl dispatch "hl.dsp.exec_cmd(\"vivaldi --app=$url\")" >/dev/null
  for ((i = 0; i < 100; i++)); do
    sleep 0.2
    new=$(comm -13 <(tr ' ' '\n' <<<"$before") <(wins | tr ' ' '\n') | head -1)
    [ -n "$new" ] && break
  done
  [ -n "$new" ] || exit 1
  hyprctl dispatch "hl.dsp.window.move({ workspace = $1, follow = false, window = \"address:$new\" })" >/dev/null
  focus "$new"
}

if [ "$mode" = new ]; then
  open_on "$(hyprctl monitors -j | jq '.[] | select(.focused) | .activeWorkspace.id')"
  exit
fi

target=$(jq -nr --argjson c "$(hyprctl clients -j)" --argjson m "$(hyprctl monitors -j)" --arg p "$prefix" --argjson home "$home" '
  ($c | map(select(.class | startswith($p))) | sort_by(.focusHistoryID)) as $w   # most recently focused first
  | ($m | map(.activeWorkspace.id)) as $vis
  | [$c[] | select(.focusHistoryID == 0)][0] as $f
  | if ($w | length) == 0 then "open"
    elif $f != null and ($f.class | startswith($p)) then
      if ($w | length) > 1 then $w[-1].address                                     # least recent: cycles through all of them
      else ([$c[] | select(.focusHistoryID == 1)][0].address // empty) end         # only one: back to where you were
    else ([$w[] | select(.workspace.id as $i | any($vis[]; . == $i))][0]
          // [$w[] | select(.workspace.id > 0 and (.workspace.id - 1) % 10 + 1 == $home)][0]
          // $w[0]).address
    end')
case "$target" in
  "") ;;
  open) open_on "$home" ;;
  *) focus "$target" ;;
esac
