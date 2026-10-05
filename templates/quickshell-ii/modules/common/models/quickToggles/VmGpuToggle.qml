import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Windows 11 VM with the RTX 4070 passed through (bin/vm-gpu, docs/windows-vm.md). On starts it and opens Looking Glass, off shuts it down.
QuickToggleModel {
    id: root
    name: Translation.tr("Windows VM")
    icon: "desktop_windows"
    toggled: false
    statusText: busy ? (starting ? Translation.tr("Starting…") : Translation.tr("Stopping…")) : (toggled ? Translation.tr("Running") : Translation.tr("Off"))
    tooltipText: Translation.tr("Windows 11 VM on the RTX 4070 (vm-gpu start / stop)")

    property bool busy: false
    property bool starting: false
    readonly property string home: Quickshell.env("HOME")
    readonly property string path: home + "/.local/bin:" + Quickshell.env("PATH")

    mainAction: () => {
        if (root.busy) return;
        root.starting = !root.toggled;
        root.busy = true;
        actionProc.command = ["env", "PATH=" + root.path, root.home + "/.local/bin/vm-gpu", root.starting ? "start" : "stop"];
        actionProc.running = true;
    }

    Process {
        id: actionProc
        stderr: StdioCollector { id: errOut }
        onExited: (exitCode, exitStatus) => {
            root.busy = false;
            if (exitCode !== 0) {
                Quickshell.execDetached(["notify-send", Translation.tr("Windows VM"), errOut.text.trim() || Translation.tr("vm-gpu failed (exit code %1)").arg(exitCode), "-a", "Shell"]);
            }
            stateProc.running = true;
        }
    }

    Process {
        id: stateProc
        command: ["virsh", "-c", "qemu:///system", "domstate", "win11"]
        stdout: StdioCollector {
            onStreamFinished: root.toggled = (text.trim() === "running")
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!root.busy) stateProc.running = true
    }
}
