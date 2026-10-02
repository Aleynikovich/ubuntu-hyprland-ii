
-- Rice: blurred, translucent terminals (foot: foot.ini `alpha`; kitty: kitty.conf `background_opacity`)
hl.window_rule({match = { class = "^(foot|kitty)$" }, no_blur = false })
-- Bar: lets blur apply even when the bar is quite transparent (default 0.6 cuts blur below that)
hl.layer_rule({ match = { namespace = "bar[0-9]*" }, ignore_alpha = 0.1})
hl.layer_rule({ match = { namespace = "barcorner.*" }, ignore_alpha = 0.1})
