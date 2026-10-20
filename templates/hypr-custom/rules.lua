

-- Rice: blurred, translucent terminals (foot: foot.ini `alpha`; kitty: kitty.conf `background_opacity`)
-- Skipped while Quickshell game mode is on (it creates this flag file, then runs `hyprctl reload`)
if not is_file_exists(HOME .. "/.local/state/hypr-gamemode") then
    hl.window_rule({match = { class = ".*" }, no_blur = false, opacity = 0.96})
end
hl.window_rule({match = { class = "^floating-kitty$" }, float = true})
-- Isaac Sim (XWayland + NVIDIA): goes black when the tiler resizes it, so float it at a fixed size, opaque, no blur
hl.window_rule({match = { class = "^Isaac Sim.*$" }, no_blur = true, opacity = 1.0})
hl.window_rule({match = { class = "^Isaac Sim.*$" }, float = true})
hl.window_rule({match = { class = "^Isaac Sim.*$" }, center = true})
hl.window_rule({match = { class = "^Isaac Sim.*$" }, size = {"(monitor_w*0.75)", "(monitor_h*0.80)"} })
hl.window_rule({match = { class = "^looking-glass-client*$" }, no_blur = true, opacity = 1.0})
hl.window_rule({match = { class = "^vivaldi-stable*$" }, no_blur = true, opacity = 1})
-- Bar: lets blur apply even when the bar is quite transparent (default 0.6 cuts blur below that)
hl.layer_rule({ match = { namespace = "bar[0-9]*" }, ignore_alpha = 0.1})
hl.layer_rule({ match = { namespace = "barcorner.*" }, ignore_alpha = 0.1})