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
