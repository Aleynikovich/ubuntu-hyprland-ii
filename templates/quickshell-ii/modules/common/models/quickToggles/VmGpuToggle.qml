import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common.functions

// Windows 11 VM on the RTX 4070 (bin/vm-gpu, bin/hii-session, docs/windows-vm.md): one button for everything.
//   VM running                     tap: shut it down (offers to go back to the HDMI monitor session if one is plugged in)
//   VM off, iGPU-only session      tap: start it (Looking Glass opens)
//   VM off, monitor session        tap: arms; tap again within 8 s: your windows are saved, the session restarts, the windows come back and
//                                  Windows starts by itself. (Hyprland has to restart to let go of the 4070; there is no way around that.)
QuickToggleModel {
    id: root
    name: Translation.tr("Windows VM")
    icon: "desktop_windows"
    toggled: false   // the VM is running
    statusText: busy ? busyText : (armed ? Translation.tr("Tap again to restart") : (toggled ? Translation.tr("Running") : Translation.tr("Off")))
    tooltipText: Translation.tr("Windows 11 VM on the RTX 4070. From the HDMI monitor session the desktop restarts once (your windows come back).")

    property bool busy: false
    property string busyText: ""
    property bool armed: false
    property bool sessionMonitor: false   // this session draws on the 4070 (HDMI monitor works), so the VM cannot start without a restart
    readonly property string home: Quickshell.env("HOME")
    readonly property string path: home + "/.local/bin:" + Quickshell.env("PATH")
    readonly property string vmGpu: home + "/.local/bin/vm-gpu"
    readonly property string session: home + "/.local/bin/hii-session"

    function notify(body) {
        Quickshell.execDetached(["notify-send", Translation.tr("Windows VM"), body, "-a", "Shell"]);
    }
    function switchAndLogout(target) {
        root.busy = true;
        root.busyText = Translation.tr("Restarting…");
        switchProc.command = ["env", "PATH=" + root.path, root.session, "prepare", target];
        switchProc.running = true;
    }

    mainAction: () => {
        if (root.busy) return;
        if (root.toggled) {
            root.busy = true;
            root.busyText = Translation.tr("Stopping…");
            actionProc.stopping = true;
            actionProc.command = ["env", "PATH=" + root.path, root.vmGpu, "stop"];
            actionProc.running = true;
        } else if (!root.sessionMonitor) {
            root.busy = true;
            root.busyText = Translation.tr("Starting…");
            actionProc.stopping = false;
            actionProc.command = ["env", "PATH=" + root.path, root.vmGpu, "start"];
            actionProc.running = true;
        } else if (!root.armed) {
            root.armed = true;
            armTimer.restart();
            root.notify(Translation.tr("To run Windows the desktop restarts once: your windows are saved and reopened, and Windows starts by itself. Tap the button again within 8 seconds to continue."));
        } else {
            root.armed = false;
            root.switchAndLogout("vm");
        }
    }

    Timer { id: armTimer; interval: 8000; onTriggered: root.armed = false }

    // start / stop
    Process {
        id: actionProc
        property bool stopping: false
        stderr: StdioCollector { id: errOut }
        onExited: (exitCode, exitStatus) => {
            root.busy = false;
            if (exitCode !== 0) {
                root.notify(errOut.text.trim() || Translation.tr("vm-gpu failed (exit code %1)").arg(exitCode));
            } else if (stopping) {
                offerProbe.running = true;   // Windows is off: is an HDMI monitor waiting?
            }
            stateProc.running = true;
        }
    }

    // prepare (save windows, flags, after-login actions), then log out
    Process {
        id: switchProc
        stderr: StdioCollector { id: switchErr }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                Session.logout();
            } else {
                root.busy = false;
                root.notify(switchErr.text.trim() || Translation.tr("Could not prepare the switch (exit code %1)").arg(exitCode));
            }
        }
    }

    // after a stop: offer the way back to the HDMI monitor session when a monitor is plugged in
    Process {
        id: offerProbe
        command: ["bash", "-c", "cat /sys/class/drm/card*-HDMI-A-*/status 2>/dev/null | grep -q '^connected'"]
        onExited: (exitCode, exitStatus) => { if (exitCode === 0) offerProc.running = true; }
    }
    Process {
        id: offerProc
        command: ["notify-send", "-A", "switch=" + Translation.tr("Switch to the HDMI monitor"), "-t", "60000", "-a", "Shell",
                  Translation.tr("Windows is off"), Translation.tr("An HDMI monitor is plugged in. Switch to the HDMI monitor session? The desktop restarts once and your windows come back.")]
        stdout: StdioCollector { id: offerOut }
        onExited: (exitCode, exitStatus) => { if (offerOut.text.trim() === "switch") root.switchAndLogout("monitor"); }
    }

    // state: VM running?  session mode?
    Process {
        id: stateProc
        command: ["bash", "-c", "v=$(virsh -c qemu:///system domstate win11 2>/dev/null); e=$(tr '\\0' '\\n' < /proc/$(pgrep -u $USER -x Hyprland | head -1)/environ 2>/dev/null | sed -n 's/^AQ_DRM_DEVICES=//p'); echo \"$v|$e\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|");
                if (root.busy) return;
                root.toggled = (parts[0] === "running");
                root.sessionMonitor = (parts.length > 1 && parts[1].indexOf(":") >= 0);
            }
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
