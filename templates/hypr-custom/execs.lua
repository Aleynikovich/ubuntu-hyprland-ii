-- Linked workspaces across monitors (session-bin/hypr-sync-workspaces, see README)
hl.on("hyprland.start", function ()
    hl.exec_cmd("hypr-sync-workspaces")
end)
