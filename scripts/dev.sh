#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
BUILD_DIR="$ROOT/build/dev"
MODE="${1:-build}"
case "$MODE" in
    build|test|run) ;;
    *) echo "Usage: $0 [build|test|run]" >&2; exit 2 ;;
esac

if [ -n "${QT_DIR:-}" ]; then
    cmake --preset dev -S "$ROOT" "-DCMAKE_PREFIX_PATH=$QT_DIR"
else
    cmake --preset dev -S "$ROOT"
fi
cmake --build "$BUILD_DIR" --parallel "${JOBS:-4}"

if [ "$MODE" = test ]; then
    ctest --test-dir "$BUILD_DIR" --output-on-failure
elif [ "$MODE" = run ]; then
    shift || true
    if [ "$(uname -s)" = Darwin ]; then
        exec "$BUILD_DIR/cool-retro-term.app/Contents/MacOS/cool-retro-term" "$@"
    else
        exec "$BUILD_DIR/cool-retro-term" "$@"
    fi
fi
