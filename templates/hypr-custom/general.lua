-- Rice: window borders. Overrides the wallpaper-generated colors (hyprland/colors.lua, rewritten whenever the wallpaper changes).
hl.config({
    general = {
        border_size = 2,
        col = {
            -- focused: mauve -> blue -> teal gradient at 45deg; unfocused: faint, so only the focused window pops
            active_border   = { colors = { "rgba(c6a0f6ff)", "rgba(8aadf4ff)", "rgba(8bd5caff)" }, angle = 45 },
            inactive_border = "rgba(494d6455)",
        },
    },
})

-- Rice: lighter blur. The iGPU draws everything at 3200x2000@165 in Hybrid mode; 3 passes at size 6 made the compositor miss every second
-- frame (Vivaldi measured ~85 Hz windowed, 165 only in fullscreen). 1 pass at size 4 holds 165 Hz. Shadows are cheap and stay on.
hl.config({ decoration = { blur = { passes = 1, size = 4 } } })

-- Optional: slowly spinning gradient on the focused border (keeps the GPU redrawing, so it costs battery). Uncomment to try.
-- hl.animation({ leaf = "borderangle", enabled = true, speed = 60, bezier = "linear", style = "loop" })

-- Home desk: Samsung Odyssey G93SC (49" OLED, 5120x1440@240) over HDMI, directly above the laptop panel, horizontally centred on it.
-- The laptop panel is 3200x2000 at scale 1.25 = 2560x1600 logical, so the 5120-wide monitor starts 1280 px left of x=0 and ends 1440 px above y=0.
-- The laptop panel is pinned to 0x0 too, otherwise "auto" places it to the right of whatever was connected first.
-- Matched by description, not port (HDMI-A-1 can change). Scale 1: at 5120x1440 that is the native size. VRR stays off (flicker on OLED).
hl.monitor({
    output = "desc:Samsung Electric Company Odyssey G93SC",
    mode = "5120x1440@240",
    position = "-1280x-1440",
    scale = 1,
})
hl.monitor({
    output = "eDP-1",
    mode = "3200x2000@165",
    position = "0x0",
    scale = 1.25,
})

-- Any other monitor (office, projector; HDMI or USB-C): its own preferred mode, automatic scale, above the laptop like the desk at home.
-- Replaces the dots' fallback in hyprland/general.lua, which forced the laptop panel's 3200x2000@165 and scale 1.25 onto every monitor.
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto-up",
    scale = "auto",
})

-- Linked workspaces (session-bin/hypr-sync-workspaces): the laptop panel always owns workspaces 1-10, so they are right from the first
-- frame however the monitors come up (booting with the Odyssey plugged in once gave it workspace 1). The helper places 11-20, 21-30, ...
-- on the other monitors itself (sorted by description), so there are no per-monitor rules to keep in sync here.
for i = 1, 10 do
    hl.workspace_rule({ workspace = tostring(i), monitor = "eDP-1", default = (i == 1) })
end
