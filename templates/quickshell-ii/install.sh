#!/usr/bin/env bash
# Overlay for the end-4 shell: two sidebar quick toggles for the GPU passthrough setup (docs/windows-vm.md).
#   vmGpu        "Windows VM"    one button: start/stop the win11 VM on the RTX 4070; from the HDMI monitor session it restarts the desktop once
#   gpuSession   "HDMI monitor"  switch between the HDMI monitor session and the iGPU-only session (the same restart, windows come back)
# Copies the QML files over ~/.config/quickshell/ii and registers the types (chooser entries + availableToggleTypes). Idempotent;
# the two patched shell files are saved once as *.orig next to them. They then show up unused in the sidebar's edit mode.
# Rollback: restore the *.orig files and delete the four new .qml files.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QS="${QS_DIR:-$HOME/.config/quickshell/ii}"
cp -r "$HERE/modules" "$QS/"
TQ="$QS/modules/ii/sidebarRight/quickToggles"
python3 - "$TQ" <<'PY'
import sys, re, os
tq = sys.argv[1]
chooser = f"{tq}/androidStyle/AndroidToggleDelegateChooser.qml"
panel = f"{tq}/AndroidQuickPanel.qml"
block = '''    DelegateChoice { roleValue: "%s"; %s {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

'''
s = open(chooser).read()
if 'roleValue: "vmGpu"' not in s:
    if not os.path.exists(chooser + ".orig"): open(chooser + ".orig", "w").write(s)
    anchor = '    DelegateChoice { roleValue: "gameMode"'
    assert anchor in s
    s = s.replace(anchor, block % ("vmGpu", "AndroidVmGpuToggle") + block % ("gpuSession", "AndroidGpuSessionToggle") + anchor, 1)
    open(chooser, "w").write(s); print("chooser patched")
p = open(panel).read()
if '"vmGpu"' not in p:
    if not os.path.exists(panel + ".orig"): open(panel + ".orig", "w").write(p)
    assert '"antiFlashbang"]' in p
    p = p.replace('"antiFlashbang"]', '"antiFlashbang", "vmGpu", "gpuSession"]', 1)
    open(panel, "w").write(p); print("types patched")
PY
# Put the buttons in the sidebar layout (two cells each) when the layout does not have them yet; config backed up once.
CFG="$HOME/.config/illogical-impulse/config.json"
if [ -f "$CFG" ]; then
  python3 - "$CFG" <<'PY'
import json, sys, os, shutil
p = sys.argv[1]
raw = open(p).read(); c = json.loads(raw)
t = c.get("sidebar", {}).get("quickToggles", {}).get("android", {}).get("toggles")
if t is not None:
    have = {x["type"] for x in t}
    new = [x for x in ("vmGpu", "gpuSession") if x not in have]
    if new:
        if not os.path.exists(p + ".pre-vmgpu"): shutil.copy2(p, p + ".pre-vmgpu")
        t.extend({"size": 2, "type": x} for x in new)
        open(p, "w").write(json.dumps(c, indent=4, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
        print("added to the sidebar layout:", ", ".join(new))
PY
fi
echo "quick toggles installed in $QS"
