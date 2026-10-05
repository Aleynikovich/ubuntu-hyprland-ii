-- Linked workspaces across monitors (session-bin/hypr-sync-workspaces, see README)
hl.on("hyprland.start", function ()
    hl.exec_cmd("hypr-sync-workspaces")
end)

-- After a session switch (bin/hii-session): reopen the windows that were open and start the Windows VM when the button asked for it.
-- Does nothing on a normal login. Absolute path: Hyprland's PATH has no ~/.local/bin.
hl.on("hyprland.start", function ()
    hl.exec_cmd("$HOME/.local/bin/hii-session after-login")
end)
