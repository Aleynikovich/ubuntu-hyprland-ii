#!/usr/bin/env bash
# Build Hyprland 0.56 + its stack + Quickshell into $PREFIX. No sudo; writes only to $PREFIX and $SRC.
# Resumable: finished components are stamped in $SRC/.stamps; rerun after fixing a failure.
# Usage: 30-build.sh [component ...]   (no args = everything, in order)
# Rollback: rm -rf "$PREFIX" "$SRC"
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$REPO/lib/patches.sh"

P=$PREFIX
STAMPS=$SRC/.stamps
LOGS=$SRC/logs
mkdir -p "$P" "$STAMPS" "$LOGS" "$SRC/dl"

export PATH="$P/bin:$P/tools/bin:$PATH"
export PKG_CONFIG_PATH="$P/lib/pkgconfig:$P/share/pkgconfig"
export CMAKE_PREFIX_PATH="$P"
# CMake forces PKG_CONFIG_ALLOW_SYSTEM_LIBS=1, so .pc files like libseat's put -L/usr/lib/... ahead of $P/lib and CMake
# then resolves private libs (wayland, libdisplay-info...) to the system copies. The wrapper strips those -L flags.
export PKG_CONFIG_SYSTEM_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/usr/lib:/lib/x86_64-linux-gnu:/lib
export PKG_CONFIG="$P/tools/bin/pkg-config-filtered"
export ACLOCAL_PATH="$P/share/aclocal"
# Embedded library path (DT_RPATH also covers transitive deps) instead of LD_LIBRARY_PATH in the session,
# so apps launched from Hyprland (e.g. Isaac Sim) keep using the system libraries.
export LDFLAGS="-Wl,-rpath,$P/lib -Wl,--disable-new-dtags -L$P/lib"
export CPPFLAGS="-I$P/include"
export CC=gcc CXX=g++
JOBS=$(( $(nproc) > 6 ? $(nproc) - 4 : 2 ))

MESON=(--prefix="$P" --libdir=lib --buildtype=release -Dc_link_args="$LDFLAGS" -Dcpp_link_args="$LDFLAGS")
CMAKE=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$P" -DCMAKE_INSTALL_LIBDIR=lib
       -DCMAKE_INSTALL_RPATH="$P/lib" -DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF -DCMAKE_PREFIX_PATH="$P")
# Hyprland needs C++26 (#embed): gcc 13/14 can't, clang-20 can (with Ubuntu's libstdc++ 14 + patches/).
# Module scanning off: CMake 4 + C++26 wants clang-scan-deps, and nothing here uses C++ modules.
CLANG=(-DCMAKE_C_COMPILER=clang-20 -DCMAKE_CXX_COMPILER=clang++-20 -DCMAKE_LINKER_TYPE=LLD -DCMAKE_CXX_SCAN_FOR_MODULES=OFF)

apply_patches(){ # dir: apply its patches/<dir>-*.patch once, right after cloning (patches_for: same list --check-patches uses)
  local p ps
  mapfile -t ps < <(patches_for "$1")
  for p in "${ps[@]}"; do echo "Applying $(basename "$p")"; git -C "$SRC/$1" apply "$p"; done
}
git_src(){ # url tag dir
  if [ ! -d "$SRC/$3" ]; then
    git clone -q --depth 1 --branch "$2" --recurse-submodules --shallow-submodules "$1" "$SRC/$3"
    apply_patches "$3"
  fi
  cd "$SRC/$3"
}
git_commit(){ # url commit dir
  if [ ! -d "$SRC/$3" ]; then
    git clone -q "$1" "$SRC/$3"; git -C "$SRC/$3" checkout -q "$2"; git -C "$SRC/$3" submodule update -q --init --recursive
    apply_patches "$3"
  fi
  cd "$SRC/$3"
}
fetch(){ # url -> $SRC/dl/<basename>
  [ -f "$SRC/dl/$(basename "$1")" ] || wget -q -O "$SRC/dl/$(basename "$1")" "$1"
}
# meson/cmake install overwrite files in place, which corrupts a library a running Hyprland session has mapped.
# Install into a staging dir, then replace each file with a new inode (running processes keep the old copy).
staged_install(){ local st=$SRC/stage; rm -rf "$st"; DESTDIR=$st "$@"; cp -a --remove-destination "$st$P/." "$P/"; rm -rf "$st"; }
meson_build(){ rm -rf build; meson setup build "${MESON[@]}" "$@"; ninja -C build -j$JOBS; staged_install meson install -C build; }
cmake_build(){ rm -rf build; cmake -B build "${CMAKE[@]}" "$@"; cmake --build build -j$JOBS; staged_install cmake --install build; }
auto_build(){ NOCONFIGURE=1 autoreconf -fi; ./configure --prefix="$P" "$@"; make -j$JOBS; make install; }

# ---------------- components ----------------
# lib/patches.sh (setup.sh --check-patches, maintenance/bump.sh) reads url/tag/dir from these lines without building:
# keep each `c_name(){ git_src|git_commit url tag dir` on one line.
c_tools(){ # private cmake/meson/aqtinstall (Ubuntu's cmake 3.28 is too old) + pkg-config filter
  python3 -m venv "$P/tools"
  "$P/tools/bin/pip" install -q --upgrade pip
  "$P/tools/bin/pip" install -q 'cmake>=3.31,<4.2' 'meson>=1.6' aqtinstall jinja2 attrs
  cat > "$P/tools/bin/pkg-config-filtered" <<'EOF'
#!/bin/sh
# Strip -L for system lib dirs so CMake/meson find $CMAKE_PREFIX_PATH copies before /usr/lib copies.
out=$(/usr/bin/pkg-config "$@") || exit $?
[ -n "$out" ] && printf '%s\n' "$out" | sed -E 's#(^| )-L/(usr/)?lib(/x86_64-linux-gnu)?/?( |$)#\1\4#g'
exit 0
EOF
  chmod +x "$P/tools/bin/pkg-config-filtered"
}
# Newer than Ubuntu 24.04 ships (Hyprland 0.56 minimums in parentheses)
c_wayland(){ git_src https://gitlab.freedesktop.org/wayland/wayland.git 1.26.0 wayland   # (>= 1.22.91)
  meson_build -Ddocumentation=false -Dtests=false; }
c_wayland_protocols(){ git_src https://gitlab.freedesktop.org/wayland/wayland-protocols.git 1.49 wayland-protocols  # (>= 1.49)
  meson_build -Dtests=false; }
c_xkbcommon(){ git_src https://github.com/xkbcommon/libxkbcommon xkbcommon-1.13.2 libxkbcommon  # (>= 1.11); X11 helper lib not needed
  meson_build -Denable-docs=false -Denable-tools=false -Denable-x11=false -Dxkb-config-root=/usr/share/X11/xkb -Dx-locale-root=/usr/share/X11/locale; }
c_libinput(){ git_src https://gitlab.freedesktop.org/libinput/libinput.git 1.32.0 libinput  # (>= 1.29)
  meson_build -Dlibwacom=false -Ddebug-gui=false -Dtests=false -Ddocumentation=false -Dudev-dir="$P/lib/udev"; }
c_lua(){ # Lua 5.5 for Hyprland's Lua config; upstream ships no .pc file
  fetch https://www.lua.org/ftp/lua-5.5.1.tar.gz
  rm -rf "$SRC/lua-5.5.1"; tar -xzf "$SRC/dl/lua-5.5.1.tar.gz" -C "$SRC"; cd "$SRC/lua-5.5.1"
  make -j$JOBS linux MYCFLAGS=-fPIC
  make install INSTALL_TOP="$P"
  mkdir -p "$P/lib/pkgconfig"
  cat > "$P/lib/pkgconfig/lua5.5.pc" <<EOF
prefix=$P
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: Lua
Description: Lua 5.5
Version: 5.5.1
Libs: -L\${libdir} -llua -lm -ldl
Cflags: -I\${includedir}
EOF
}
# xcb-errors (required for XWayland) isn't packaged for noble; it needs xcb-proto + util-macros, built here too.
c_util_macros(){ git_src https://gitlab.freedesktop.org/xorg/util/macros.git util-macros-1.20.2 util-macros; auto_build; }
c_xcb_proto(){ git_src https://gitlab.freedesktop.org/xorg/proto/xcbproto.git xcb-proto-1.17.0 xcbproto; auto_build; }
c_xcb_errors(){ git_src https://gitlab.freedesktop.org/xorg/lib/libxcb-errors.git xcb-util-errors-1.0.1 libxcb-errors
  PYTHONPATH="$(echo "$P"/lib/python3*/site-packages | tr ' ' ':')" auto_build; }
c_libdisplay_info(){ git_src https://gitlab.freedesktop.org/emersion/libdisplay-info.git 0.4.0 libdisplay-info; meson_build; }  # aquamarine HDR APIs
c_libei(){ git_src https://gitlab.freedesktop.org/libinput/libei.git 1.6.0 libei  # libeis-1.0
  meson_build -Dtests=disabled -Ddocumentation=[] -Dliboeffis=disabled; }
c_readline(){ # hyprctl; avoids needing libncurses-dev: link terminfo by runtime soname
  fetch https://ftp.gnu.org/gnu/readline/readline-8.3.tar.gz
  rm -rf "$SRC/readline-8.3"; tar -xzf "$SRC/dl/readline-8.3.tar.gz" -C "$SRC"; cd "$SRC/readline-8.3"
  ./configure --prefix="$P" --disable-static --with-shared-termcap-library
  make -j$JOBS SHLIB_LIBS=/usr/lib/x86_64-linux-gnu/libtinfo.so.6
  make install
  sed -i '/^Requires.private:/d' "$P/lib/pkgconfig/readline.pc"
}
# Hyprland stack
c_hyprwayland_scanner(){ git_src https://github.com/hyprwm/hyprwayland-scanner v0.4.6 hyprwayland-scanner; cmake_build "${CLANG[@]}"; }
c_hyprutils(){ git_src https://github.com/hyprwm/hyprutils v0.14.2 hyprutils; cmake_build "${CLANG[@]}"; }
c_hyprlang(){ git_src https://github.com/hyprwm/hyprlang v0.6.8 hyprlang; cmake_build "${CLANG[@]}"; }
c_hyprland_protocols(){ git_src https://github.com/hyprwm/hyprland-protocols v0.7.1 hyprland-protocols; cmake_build; }
c_hyprcursor(){ git_src https://github.com/hyprwm/hyprcursor v0.1.13 hyprcursor; cmake_build "${CLANG[@]}"; }
c_hyprgraphics(){ git_src https://github.com/hyprwm/hyprgraphics v0.5.1 hyprgraphics; cmake_build "${CLANG[@]}"; }
c_hyprwire(){ git_src https://github.com/hyprwm/hyprwire v0.3.1 hyprwire; cmake_build "${CLANG[@]}"; }
# hyprtoolkit wants iniparser.pc (noble's -dev ships none) and abseil (noble has 2022; none installed)
c_iniparser(){ git_src https://gitlab.com/iniparser/iniparser.git v4.3.0 iniparser; cmake_build -DBUILD_TESTING=OFF -DBUILD_DOCS=OFF -DBUILD_EXAMPLES=OFF; }
c_abseil(){ git_src https://github.com/abseil/abseil-cpp 20250814.2 abseil-cpp
  cmake_build -DABSL_PROPAGATE_CXX_STD=ON -DABSL_BUILD_TESTING=OFF -DCMAKE_CXX_STANDARD=20 -DBUILD_SHARED_LIBS=ON; }
c_hyprtoolkit(){ git_src https://github.com/hyprwm/hyprtoolkit v0.6.0 hyprtoolkit; cmake_build "${CLANG[@]}"; }
c_hyprland_guiutils(){ git_src https://github.com/hyprwm/hyprland-guiutils v0.2.2 hyprland-guiutils; cmake_build "${CLANG[@]}"; }  # Hyprland's permission/notice dialogs
# Debug info: aquamarine is where Hyprland's DRM/session crashes land (e.g. the VT-switch segfault); keeps them resolvable.
c_aquamarine(){ git_src https://github.com/hyprwm/aquamarine v0.15.1 aquamarine; cmake_build "${CLANG[@]}" -DCMAKE_BUILD_TYPE=RelWithDebInfo; }
c_hyprland(){ git_src https://github.com/hyprwm/Hyprland v0.56.2 Hyprland
  cmake_build "${CLANG[@]}" -DNO_TESTS=ON -DBUILD_TESTING=OFF; }
# Qt 6.10 + KDE bits for the illogical-impulse Quickshell config
c_qt(){
  "$P/tools/bin/aqt" install-qt linux desktop "$QT_VER" linux_gcc_64 -O "$P/qt" -m \
    qt5compat qtimageformats qtmultimedia qtpositioning qtquicktimeline qtsensors qtshadertools qtvirtualkeyboard
  # ~1.2 GB of static libs only Qt's own tools/tests use (QML language server, QML DOM, debugger, test utils,
  # bundled FFmpeg/spatial-audio internals); nothing built here links them. Re-run this component to restore.
  rm -f "$QT"/lib/libQt6{QmlLS,QmlDom,QmlDebug,FFmpegMediaPluginImpl,BundledResonanceAudio,ExamplesAssetDownloader,QuickTestUtils}.a
}
c_ecm(){ git_src https://invent.kde.org/frameworks/extra-cmake-modules.git v6.30.0 ecm; cmake_build -DBUILD_TESTING=OFF -DBUILD_DOC=OFF; }
c_kirigami(){ git_src https://invent.kde.org/frameworks/kirigami.git v6.30.0 kirigami
  cmake_build -DCMAKE_PREFIX_PATH="$QT;$P" -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF -DKDE_INSTALL_QMLDIR=qml -DKDE_INSTALL_USE_QT_SYS_PATHS=OFF; }
c_syntax_highlighting(){ git_src https://invent.kde.org/frameworks/syntax-highlighting.git v6.30.0 syntax-highlighting
  cmake_build -DCMAKE_PREFIX_PATH="$QT;$P" -DBUILD_TESTING=OFF -DKDE_INSTALL_QMLDIR=qml -DKDE_INSTALL_USE_QT_SYS_PATHS=OFF; }
c_cpptrace(){ git_src https://github.com/jeremy-rifkin/cpptrace v1.0.4 cpptrace  # libunwind: required by Quickshell's crash handler
  cmake_build -DBUILD_SHARED_LIBS=ON -DCPPTRACE_UNWIND_WITH_LIBUNWIND=ON; }
c_quickshell(){ git_commit https://github.com/quickshell-mirror/quickshell 7511545ee20664e3b8b8d3322c0ffe7567c56f7a quickshell  # pinned by the dots
  cmake_build "${CLANG[@]}" -DCMAKE_PREFIX_PATH="$QT;$P" -DCMAKE_INSTALL_RPATH="$P/lib;$QT/lib" \
    -DDISTRIBUTOR="local build (illogical-impulse, Ubuntu 24.04)" -DINSTALL_QML_PREFIX=qml -DNO_PCH=ON; }  # clang PCH -pthread mismatch
c_hyprland_qt_support(){ git_src https://github.com/hyprwm/hyprland-qt-support v0.1.0 hyprland-qt-support
  cmake_build "${CLANG[@]}" -DCMAKE_PREFIX_PATH="$QT;$P" -DCMAKE_INSTALL_RPATH="$P/lib;$QT/lib" -DINSTALL_QML_PREFIX=qml -DCMAKE_CXX_FLAGS="-isystem $P/include"; }
# Portal / tools
c_sdbus(){ git_src https://github.com/Kistler-Group/sdbus-cpp v2.3.1 sdbus-cpp; cmake_build "${CLANG[@]}" -DSDBUSCPP_BUILD_TESTS=OFF; }
c_pipewire(){ git_src https://gitlab.freedesktop.org/pipewire/pipewire.git 1.2.8 pipewire
  # Client library + SPA support plugins only (xdph needs >= 1.1.82; Ubuntu has 1.0.5). The system PipeWire daemon is untouched.
  meson_build -Dauto_features=disabled -Dsession-managers=[] -Dspa-plugins=enabled -Dsupport=enabled -Ddbus=enabled \
    -Dpam-defaults-install=false -Drlimits-install=false -Dexamples=disabled -Dtests=disabled -Ddocs=disabled -Dman=disabled \
    -Dudevrulesdir="$P/lib/udev/rules.d" -Dsystemd-user-unit-dir="$P/lib/systemd/user" -Dsystemd-system-unit-dir="$P/lib/systemd/system"; }
c_xdph(){ git_src https://github.com/hyprwm/xdg-desktop-portal-hyprland v1.4.1 xdph
  cmake_build "${CLANG[@]}" -DCMAKE_PREFIX_PATH="$QT;$P" -DCMAKE_INSTALL_RPATH="$P/lib;$QT/lib" -DCMAKE_INSTALL_LIBEXECDIR=libexec; }
c_hypridle(){ git_src https://github.com/hyprwm/hypridle v0.1.8 hypridle; cmake_build "${CLANG[@]}"; }
c_hyprlock(){ git_src https://github.com/hyprwm/hyprlock v0.9.6 hyprlock; cmake_build "${CLANG[@]}"; }
c_hyprpicker(){ git_src https://github.com/hyprwm/hyprpicker v0.4.7 hyprpicker; cmake_build "${CLANG[@]}"; }
c_hyprsunset(){ git_src https://github.com/hyprwm/hyprsunset v0.4.0 hyprsunset; cmake_build "${CLANG[@]}"; }
c_microtex(){ git_commit https://github.com/end-4/MicroTeX 0e3707f microtex  # AI sidebar LaTeX; the commit end-4's Arch package uses
  rm -rf build; cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release; cmake --build build -j$JOBS
  rm -rf "$P/opt/MicroTeX"; install -Dm755 build/LaTeX "$P/opt/MicroTeX/LaTeX"; cp -r build/res "$P/opt/MicroTeX/"; }  # /opt/MicroTeX -> here: phase 60
c_swappy(){ git_src https://github.com/jtheoof/swappy v1.8.0 swappy; meson_build -Dman-pages=disabled; }  # screenshot annotation (not in noble)
c_qml_links(){ # expose private QML modules inside the private Qt, so no QML_IMPORT_PATH has to leak into the session
  local d
  for d in "$P"/qml/*; do ln -sfn "$d" "$QT/qml/$(basename "$d")"; done
  ls -la "$QT/qml" | grep -- '->'
}

ALL=(tools wayland wayland_protocols xkbcommon libinput lua util_macros xcb_proto xcb_errors
     hyprwayland_scanner hyprutils hyprlang hyprland_protocols hyprcursor hyprgraphics hyprwire libdisplay_info libei readline iniparser abseil aquamarine hyprtoolkit hyprland hyprland_guiutils
     qt ecm kirigami syntax_highlighting cpptrace quickshell hyprland_qt_support
     sdbus pipewire xdph hypridle hyprlock hyprpicker hyprsunset swappy microtex qml_links)

run(){
  local c=$1
  declare -F "c_$c" >/dev/null || die "Unknown component: $c (known: ${ALL[*]})"
  if [ -f "$STAMPS/$c" ]; then echo "[skip] $c"; return; fi
  echo "[build] $c  (log: $LOGS/$c.log)"
  # Run outside `if`/`||`: bash ignores errexit in conditional contexts, which would hide failures.
  set +e
  ( set -euo pipefail; "c_$c" ) > "$LOGS/$c.log" 2>&1
  local rc=$?
  set -e
  if [ $rc -eq 0 ]; then touch "$STAMPS/$c"; echo "[ ok ] $c"
  else echo "[FAIL] $c (rc=$rc), last lines:"; tail -25 "$LOGS/$c.log"; exit 1; fi
}

[ $# -gt 0 ] && TARGETS=("$@") || TARGETS=("${ALL[@]}")
for c in "${TARGETS[@]}"; do run "$c"; done

step "Verifying library resolution"
bad=0
for f in "$P"/bin/* "$P"/libexec/* "$P"/lib/*.so; do
  [ -f "$f" ] && file -b "$f" | grep -q ELF || continue
  if ldd "$f" 2>/dev/null | grep -q 'not found'; then warn "missing libs in $f"; ldd "$f" | grep 'not found'; bad=1; fi
done
[ $bad = 0 ] && ok "All binaries resolve their libraries."
"$P/bin/Hyprland" --version | head -1
