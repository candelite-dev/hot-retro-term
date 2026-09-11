#!/usr/bin/env bash
set -euo pipefail
set -x

REPO_ROOT="$(readlink -f "$(dirname "$(dirname "$0")")")"
OLD_CWD="$(readlink -f .)"
BUILD_DIR="$REPO_ROOT/build/appimage"
TOOLS_DIR="$BUILD_DIR/tools"
VERSION="$(git -C "$REPO_ROOT" describe --tags --always --dirty=-dirty 2>/dev/null || true)"
if [ -z "$VERSION" ]; then
    VERSION="unknown"
fi

CMAKE="${CMAKE:-cmake}"
if ! command -v "$CMAKE" >/dev/null; then
    echo "cmake not found in PATH (or set CMAKE=/path/to/cmake)." >&2
    exit 1
fi
# linuxdeploy-plugin-qt locates Qt via qmake in PATH (or $QMAKE).
if ! command -v qmake >/dev/null; then
    echo "qmake not found in PATH." >&2
    exit 1
fi
QTDIR="$(qmake -query QT_INSTALL_PREFIX)"

APPDIR="$BUILD_DIR/AppDir"
CMAKE_BUILD="$BUILD_DIR/cmake"

mkdir -p "$BUILD_DIR"
rm -rf "$APPDIR"

"$CMAKE" -S "$REPO_ROOT" -B "$CMAKE_BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_PREFIX_PATH="$QTDIR"
"$CMAKE" --build "$CMAKE_BUILD" -j"$(nproc)"
DESTDIR="$APPDIR" "$CMAKE" --install "$CMAKE_BUILD"

# Relocate QMLTermWidget into the standard AppDir QML import path.
# qmltermwidget installs to <prefix>/<libdir>/qt6/qml (libdir may be lib or lib64).
QML_ROOT=""
for d in "$APPDIR/usr/lib"*/qt6/qml; do
    if [ -d "$d" ]; then
        QML_ROOT="$d"
        break
    fi
done
if [ -n "$QML_ROOT" ]; then
    mkdir -p "$APPDIR/usr/qml"
    rsync -a "$QML_ROOT/" "$APPDIR/usr/qml/"
    rm -rf "$QML_ROOT"
    QML_PARENT="$(dirname "$QML_ROOT")"
    while [ "$QML_PARENT" != "$APPDIR" ] && rmdir "$QML_PARENT" 2>/dev/null; do
        QML_PARENT="$(dirname "$QML_PARENT")"
    done
fi


# Build AppImage using linuxdeploy and linuxdeploy-plugin-qt.
mkdir -p "$TOOLS_DIR"
LINUXDEPLOY="$TOOLS_DIR/linuxdeploy-x86_64.AppImage"
LINUXDEPLOY_QT="$TOOLS_DIR/linuxdeploy-plugin-qt-x86_64.AppImage"
if [ ! -x "$LINUXDEPLOY" ]; then
    wget -c -O "$LINUXDEPLOY" https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
    chmod +x "$LINUXDEPLOY"
fi
if [ ! -x "$LINUXDEPLOY_QT" ]; then
    wget -c -O "$LINUXDEPLOY_QT" https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage
    chmod +x "$LINUXDEPLOY_QT"
fi

export QML_SOURCES_PATHS="$REPO_ROOT/app"

pushd "$BUILD_DIR"

export EXTRA_PLATFORM_PLUGINS="libqwayland.so;"
export EXTRA_QT_MODULES="sql;waylandcompositor;waylandclient"
export DEPLOY_PLATFORM_THEMES=true
export LINUXDEPLOY_EXCLUDED_LIBRARIES="libmysqlclient.so;libqsqlmimer.so;libqsqlmysql.so;libqsqlodbc.so;libqsqlpsql.so;libqsqloci.so;libqsqlibase.so"

"$LINUXDEPLOY" \
    --appdir "$APPDIR" \
    -e "$APPDIR/usr/bin/cool-retro-term" \
    -i "$REPO_ROOT/app/icons/256x256/cool-retro-term.png" \
    -d "$REPO_ROOT/cool-retro-term.desktop" \
    --plugin qt \
    --output appimage

APPIMAGE_PATH="$(ls -1 ./*.AppImage | head -n 1)"
APPIMAGE_OUT="cool-retro-term-${VERSION}.AppImage"
mv "$APPIMAGE_PATH" "$OLD_CWD/$APPIMAGE_OUT"
popd
