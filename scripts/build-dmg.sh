#!/usr/bin/env bash
set -euo pipefail
set -x

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
OLD_CWD="$(pwd -P)"
BUILD_DIR="$REPO_ROOT/build/dmg"
APP="cool-retro-term.app"
QML_DIR="$REPO_ROOT/app/qml"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
VERSION="$(git -C "$REPO_ROOT" describe --tags --always --dirty=-dirty 2>/dev/null || true)"
if [ -z "$VERSION" ]; then
    VERSION="unknown"
fi

CMAKE="${CMAKE:-cmake}"
if ! command -v "$CMAKE" >/dev/null; then
    echo "cmake not found in PATH (or set CMAKE=/path/to/cmake)." >&2
    exit 1
fi
if [ -z "${QT_DIR:-}" ]; then
    if ! command -v qmake >/dev/null; then
        echo "qmake not found in PATH; set QT_DIR to the Qt prefix (needed to locate macdeployqt)." >&2
        exit 1
    fi
    QT_DIR="$(qmake -query QT_INSTALL_PREFIX)"
fi
QT_BIN="${QT_DIR%/}/bin"

mkdir -p "$BUILD_DIR"
rm -f "$BUILD_DIR/${APP%.app}.dmg"

"$CMAKE" -S "$REPO_ROOT" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$QT_DIR" \
    ${CMAKE_OSX_ARCHITECTURES:+-DCMAKE_OSX_ARCHITECTURES="$CMAKE_OSX_ARCHITECTURES"}
"$CMAKE" --build "$BUILD_DIR" -j"$JOBS"

pushd "$BUILD_DIR"

PLUGIN_DST="$APP/Contents/PlugIns/qmltermwidget"
rm -rf "$PLUGIN_DST"
mkdir -p "$APP/Contents/PlugIns"
cp -R qmltermwidget/QMLTermWidget "$PLUGIN_DST"

export QML_IMPORT_PATH="$PWD/$APP/Contents/PlugIns"
"$QT_BIN/macdeployqt" "$APP" -qmldir="$QML_DIR"

rm -f "$APP/Contents/PlugIns/sqldrivers/"libqsql{odbc,psql,mimer}.dylib 2>/dev/null || true

# Remove stale signatures and ad-hoc sign so Gatekeeper doesn't report corruption.
codesign --remove-signature "$APP" 2>/dev/null || true
rm -rf "$APP/Contents/_CodeSignature"
codesign --force --deep --sign - "$APP"
DMG_OUT="${APP%.app}-${VERSION}.dmg"
hdiutil create -volname "${APP%.app}" -srcfolder "$APP" -ov -format UDZO "$DMG_OUT"
mv "$BUILD_DIR/$DMG_OUT" "$OLD_CWD/$DMG_OUT"
popd
