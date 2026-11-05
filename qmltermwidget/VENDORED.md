# Terminal engine source

This directory is tracked by the main hot-retro-term repository, not a Git submodule.
It is the existing local QMLTermWidget fork at commit
`e44cec8153bf41863c7ec9d2c6da2f845e68a33e`, copied without build outputs or Git metadata.

Upstream: https://github.com/Swordfish90/qmltermwidget

Why: the old parent pin (`ce8e09a`) had no CMake build, while the locally working
commit above was absent from the configured upstream repository. Merely changing
the submodule pin made local builds work but could not make a fresh clone work.
Including this source makes terminal fixes and app changes part of the same commit.

The engine implementation is unchanged by this import. Existing license files and
source headers remain authoritative. `CMakeLists.txt` integrates the plugin with
the app; legacy qmake files are retained for upstream comparison, not the app build.

For upstream updates, review and apply individual relevant patches. Do not replace
this directory with an upstream checkout: it contains local rendering and signal changes.
The Qt 6.10 render-target option and later control-space fixes from upstream are not
part of this snapshot and need separate compatibility review.

## Local shutdown fixes after the import

- `KPtyProcess` disconnects its state-change callback before private state is freed,
  closes the PTY, and terminates/reaps an active or starting child before base teardown.
- `Session` stops process callbacks and destroys the PTY before destroying its decoder.
- `TerminalDisplay` initializes its optional session pointer to null.

The startup integration tests exercise real shells, tab/split destruction, and
process teardown without manual thread-pool drains.

## Default Backspace compatibility

The active `lib/kb-layouts/default.keytab` sends DEL (`0x7f`) for Backspace and
BS (`0x08`, Ctrl+H) for Ctrl+Backspace, matching Ghostty's default legacy encoding.
The legacy `lib/default.keytab` uses the same mapping. `Session` already initializes
the PTY erase character from the active layout, so canonical shell editing stays
in sync with the new default. Other named layouts retain their own mappings.

Keytab files are link dependencies so an incremental CMake build also refreshes
the plugin's copied layouts after a layout-only edit. The terminal input tests
check bytes received by a raw child PTY and deletion in canonical shell input.
