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
