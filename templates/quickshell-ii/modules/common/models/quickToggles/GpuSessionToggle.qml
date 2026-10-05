import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common.functions

// Which session you are in (bin/hii-session, docs/windows-vm.md). On = the HDMI monitor session: the 4070 draws the desktop, an HDMI monitor works,
// the Windows VM needs a restart to start. Off = the iGPU-only session: the 4070 sleeps or belongs to the VM, no HDMI monitor.
// Tap (twice within 8 s): the desktop restarts once, your windows are saved and come back. The "Windows VM" button does the same on its own
// when it needs the other session.
QuickToggleModel {
    id: root
    name: Translation.tr("HDMI monitor")
    icon: "monitor"
    toggled: false   // this session is the HDMI monitor session
    statusText: busy ? Translation.tr("Restarting…") : (armed ? Translation.tr("Tap again to restart") : (toggled ? Translation.tr("On") : Translation.tr("Off")))
    tooltipText: Translation.tr("HDMI monitor session (the 4070 draws the desktop, no Windows VM) or iGPU-only session (Windows VM possible). Switching restarts the desktop once and reopens your windows.")

    property bool busy: false
    property bool armed: false
    readonly property string home: Quickshell.env("HOME")
    readonly property string path: home + "/.local/bin:" + Quickshell.env("PATH")

    mainAction: () => {
        if (root.busy) return;
        if (!root.armed) {
            root.armed = true;
            armTimer.restart();
            Quickshell.execDetached(["notify-send", Translation.tr("HDMI monitor"), root.toggled
                ? Translation.tr("Switch to the iGPU-only desktop (Windows VM possible, no HDMI monitor)? The desktop restarts once and your windows come back. Tap the button again within 8 seconds.")
                : Translation.tr("Switch to the HDMI monitor session (no Windows VM)? The desktop restarts once and your windows come back. Tap the button again within 8 seconds."), "-a", "Shell"]);
            return;
        }
        root.armed = false;
        root.busy = true;
        switchProc.command = ["env", "PATH=" + root.path, root.home + "/.local/bin/hii-session", "prepare", root.toggled ? "igpu" : "monitor"];
        switchProc.running = true;
    }

    Timer { id: armTimer; interval: 8000; onTriggered: root.armed = false }

    Process {
        id: switchProc
        stderr: StdioCollector { id: errOut }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                Session.logout();
            } else {
                root.busy = false;
                Quickshell.execDetached(["notify-send", Translation.tr("HDMI monitor"), errOut.text.trim() || Translation.tr("Could not prepare the switch (exit code %1)").arg(exitCode), "-a", "Shell"]);
            }
        }
    }

    // a two-GPU list (a colon) in AQ_DRM_DEVICES = the session draws on the 4070 and can drive the HDMI monitor
    Process {
        id: stateProc
        command: ["bash", "-c", "e=$(tr '\\0' '\\n' < /proc/$(pgrep -u $USER -x Hyprland | head -1)/environ 2>/dev/null | sed -n 's/^AQ_DRM_DEVICES=//p'); echo \"$e\""]
        stdout: StdioCollector {
            onStreamFinished: { if (!root.busy) root.toggled = (text.trim().indexOf(":") >= 0); }
        }
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!root.busy) stateProc.running = true
    }
}
