import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common.functions

// Which GPUs Hyprland uses, chosen at login (docs/windows-vm.md): "on" = both, so an HDMI monitor (wired to the 4070) works and the Windows
// VM cannot start; "off" = iGPU only, the 4070 stays free for the VM. A tap saves the mode for the next login; right-click (or long-press) logs out
// to apply it. Keep this one a single cell: on a wider button a tap on the body runs altAction (the logout), only the icon toggles.
QuickToggleModel {
    id: root
    name: Translation.tr("HDMI monitor")
    icon: pending ? "logout" : "monitor"   // the logout symbol: the saved mode needs a logout to apply
    toggled: false   // saved mode for the next login
    statusText: pending ? Translation.tr("Right-click: log out") : (toggled ? Translation.tr("On") : Translation.tr("Off"))
    tooltipText: Translation.tr("HDMI monitor: both GPUs (no Windows VM). Off: iGPU only, Windows VM possible. Applies at the next login; right-click to log out now.")

    property bool sessionMonitor: false   // what the running session does
    readonly property bool pending: root.toggled !== root.sessionMonitor
    readonly property string home: Quickshell.env("HOME")

    mainAction: () => {
        root.toggled = !root.toggled;
        setProc.command = ["env", "PATH=" + root.home + "/.local/bin:" + Quickshell.env("PATH"), root.home + "/.local/bin/vm-gpu", "mode", root.toggled ? "normal" : "vm"];
        setProc.running = true;
    }
    altAction: () => Session.logout()

    Process {
        id: setProc
        stderr: StdioCollector { id: errOut }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                Quickshell.execDetached(["notify-send", Translation.tr("HDMI monitor"), errOut.text.trim() || Translation.tr("vm-gpu mode failed (exit code %1)").arg(exitCode), "-a", "Shell"]);
            } else {
                Quickshell.execDetached(["notify-send", Translation.tr("HDMI monitor"), root.toggled ? Translation.tr("Saved: HDMI monitor works, Windows VM off. Log out to apply (right-click the button).") : Translation.tr("Saved: Windows VM possible, no HDMI monitor. Log out to apply (right-click the button)."), "-a", "Shell"]);
            }
            stateProc.running = true;
        }
    }

    // "<saved mode>|<AQ_DRM_DEVICES of the running Hyprland>": two GPUs listed (a colon) = this session can drive the HDMI monitor
    Process {
        id: stateProc
        command: ["bash", "-c", "s=$(" + root.home + "/.local/bin/vm-gpu mode show); e=$(tr '\\0' '\\n' < /proc/$(pgrep -u $USER -x Hyprland | head -1)/environ 2>/dev/null | sed -n 's/^AQ_DRM_DEVICES=//p'); echo \"$s|$e\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|");
                if (setProc.running) return;
                root.toggled = (parts[0] === "normal");
                root.sessionMonitor = (parts.length > 1 && parts[1].indexOf(":") >= 0) || (parts[1] === "" && parts[0] === "normal");
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!setProc.running) stateProc.running = true
    }
}
