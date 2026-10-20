import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.models.hyprland
import qs.services

// Replaces upstream's GameModeToggle. On top of upstream's keywords (no animations, blur, shadows, gaps, rounding;
// tearing allowed) it also:
// - drops the custom/rules.lua blur + translucency window rule while ~/.local/state/hypr-gamemode exists
//   (window rules aren't affected by the decoration:* keywords, so every window stayed at 0.96 opacity and was composited)
// - forces opacity 1.0 globally
// - switches the power profile to performance, then restores the previous one (stored in the flag file) on exit
// Changes are written to the shell overrides file, followed by one `hyprctl reload` so the rule change applies to windows
// that are already open.
QuickToggleModel {
    id: root
    name: Translation.tr("Game mode")
    toggled: !confOpt.value
    icon: "gamepad"

    readonly property string flagFile: `${Quickshell.env("HOME")}/.local/state/hypr-gamemode`
    readonly property var gameKeys: ({
        "animations:enabled": 0,
        "decoration:shadow:enabled": 0,
        "decoration:blur:enabled": 0,
        "decoration:active_opacity": 1.0,
        "decoration:inactive_opacity": 1.0,
        "decoration:fullscreen_opacity": 1.0,
        "general:gaps_in": 0,
        "general:gaps_out": 0,
        "general:border_size": 1,
        "decoration:rounding": 0,
        "general:allow_tearing": 1
    })

    function configurator(args) {
        return `"${HyprlandConfig.configuratorScriptPath}" --file "${HyprlandConfig.shellOverridesPath}" ${args}`;
    }

    mainAction: () => {
        root.toggled = !root.toggled;
        let cmd;
        if (root.toggled) {
            let args = "";
            for (let key in root.gameKeys)
                args += `--set "${key}" "${root.gameKeys[key]}" `;
            cmd = `mkdir -p "$(dirname "${root.flagFile}")"
                   powerprofilesctl get > "${root.flagFile}" 2>/dev/null || : > "${root.flagFile}"
                   powerprofilesctl set performance 2>/dev/null
                   ${root.configurator(args)}
                   hyprctl reload`;
        } else {
            let args = "";
            for (let key in root.gameKeys)
                args += `--reset "${key}" `;
            cmd = `prev=$(cat "${root.flagFile}" 2>/dev/null)
                   rm -f "${root.flagFile}"
                   [ -n "$prev" ] && powerprofilesctl set "$prev" 2>/dev/null
                   ${root.configurator(args)}
                   hyprctl reload`;
        }
        Quickshell.execDetached(["bash", "-c", cmd]);
    }

    HyprlandConfigOption {
        id: confOpt
        key: "animations:enabled"
    }

    tooltipText: Translation.tr("Game mode: no blur/translucency/animations, performance power profile")
}
