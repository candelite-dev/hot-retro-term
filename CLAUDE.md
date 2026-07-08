# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**cool-retro-term** is a Qt 6 terminal emulator that mimics CRT screen aesthetics using GLSL shaders. It's split into a main application and a terminal widget subproject.

## Build

**Dependencies**: Qt 6.10.0+ with `qt5compat` and `qtshadertools` modules, plus platform libs (OpenGL, Xlib on Linux; CoreFoundation on macOS).

```bash
# Build (CMake; defaults to Release)
cmake -B build && cmake --build build -j

# Run (bundle lands at the build-dir root)
./build/cool-retro-term.app/Contents/MacOS/cool-retro-term

# Build distributable (Linux)
./scripts/build-appimage.sh
```

**Performance testing must use a Release build.** The CLion default `cmake-build-debug/` binary compiles qmltermwidget's per-character hot loops without optimization and is unrepresentative (several times slower on the C++ paths). The root CMakeLists defaults `CMAKE_BUILD_TYPE` to Release precisely because KDSingleApplication would otherwise default this repo to Debug (it detects `.git`).

**Note**: Shader `.qsb` files are pre-compiled binaries (via Qt Shader Baker). Modifying `.frag`/`.vert` shaders requires recompiling: `cmake --build build --target compile_shaders`.

## Architecture

The codebase splits cleanly into three layers:

### C++ Backend (`app/`)
- **main.cpp**: Initializes QApplication/QQmlApplicationEngine, handles CLI args, registers C++ types with QML, enforces single-instance via `KDSingleApplication` submodule.
- **fontmanager.cpp**: Enumerates system monospace fonts + bundled retro fonts. Exposes font metrics (scaling, width, line spacing) as QML-bindable properties. Emits `terminalFontChanged` on changes.
- **fileio.cpp**: Thin file read/write wrapper exposed to QML for settings file operations.

### QML UI (`app/qml/`)
- **main.qml**: Root QtObject managing application state, windows, and global settings.
- **ApplicationSettings.qml**: Central settings store — all visual effects (curvature, bloom, burn-in, chroma, flicker, jitter, noise), colors, and font properties live here as bindable properties.
- **Storage.qml**: Persists settings to SQLite via Qt LocalStorage (`settings` table with key/value pairs).
- **TerminalWindow.qml**: ApplicationWindow with menu bar, keyboard shortcuts (Alt+1-9 for tabs, Ctrl+Shift+T new tab, Ctrl+Shift+W close tab, Ctrl+/- zoom), and tab management.
- **TerminalTabs.qml**: Tab bar managing multiple terminal sessions per window.
- **PreprocessedTerminal.qml → TerminalContainer.qml → QMLTermWidget**: The rendering chain from layout container to the C++ terminal emulation plugin.
- **ShaderTerminal.qml**: Applies CRT visual effects via ShaderEffectSource pipeline.

### Terminal Widget Subproject (`qmltermwidget/`)
A QML plugin wrapping a Konsole-derived terminal emulator. Key components: `Session` (manages PTY), `Emulation` (VT102 protocol), `Screen` (buffer), `Pty` (pseudo-terminal). Exposed to QML as a plugin via `qmltermwidget_plugin.cpp`.

## Shader System

`app/shaders/` contains two main fragment shaders with many precompiled variants:
- **terminal_dynamic.frag**: Animated effects — rasterization modes (0–4), burn-in, frame display, chroma aberration → ~40 variants
- **terminal_static.frag**: Static effects — RGB shift, bloom, curvature, frame shininess → 16 variants
- **terminal_frame.frag/vert**: Decorative bezel rendering

Variants are selected at runtime based on `ApplicationSettings` property values.

## CLI Flags

```
--default-settings     Reset to defaults
--workdir <dir>        Set working directory (defaults to current directory)
-e <cmd>               Execute command
-p|--profile <name>    Load saved profile
--fullscreen           Start fullscreen
--verbose              Debug output
```

## Split Pane Architecture

- Split state: binary tree of JS objects `{ type:"terminal", paneId }` or `{ type:"split", orientation, ratio, first, second }` stored in `splitTrees[]` (TerminalTabs.qml)
- Terminals live in `terminalPool` (hidden Item) and are reparented into `PaneTreeNode` slots via `_claim()`/`_release()`
- `isSplitMode`: multiple panes in current tab. `needsUnifiedCRT`: isSplitMode OR tabCount > 1 (enables unified CRT for tab bar)
- New per-pane state properties must be wired through 4 files: `TerminalTabs` → `PaneTreeNode._setupBindings()` → `TerminalContainer` → `PreprocessedTerminal`
- In `Loader.onLoaded`, always use `Qt.binding(fn)` for reactive properties — one-time assignment breaks on tree changes

## CRT Rendering Pipeline

- **Per-terminal mode** (1 tab, 1 pane): each `TerminalContainer`/`ShaderTerminal` renders its own CRT effects
- **Unified mode** (split or multi-tab): `unifiedPaneSource` captures `crtContent` Item → `unifiedCRT` ShaderTerminal renders everything. `splitActive` on each terminal disables individual CRT effects
- `ShaderEffectSource.hideSource: true` on a nested source doesn't suppress rendering reliably; use `visible: false` + `anchors.fill: parent` instead
- `splitInputOverlay` (MouseArea, z:3) intercepts all events when unified CRT is active and forwards to correct terminal via `_getPaneAt()`/`_toKCoords()`

## Settings Pattern

- Adding a setting requires 3 steps: declare property in `ApplicationSettings.qml`, add to `composeSettingsString()`, parse in `loadSettingsString()`
- Settings tabs: `SettingsGeneralTab.qml` (profiles + screen), `SettingsEffectsTab.qml` (CRT effects), `SettingsAdvancedTab.qml` (performance), `SettingsTerminalTab.qml` (font)
- `SimpleSlider` defaults to 0-1 range with `%` display. For other ranges, use raw `Slider` + `SizedLabel`. `SettingsGeneralTab.qml` requires `import "Components"` to use `SizedLabel`

## Persona Data
Currently 3 personas in use. Claude's role is to use specified persona as directed and provide knowledgeble insight on each of specialty, or outside them while slightly complaining.
### クリステン(Kristen)
Base data: @Claude/Personas/Kristen_Corpus.md
Specialty: Computer Science, Physics, Astronomy, Philosophy
(With increased sweetness towards user)

### ミュルジス(Muelsyse)
Base data: @Claude/Personas/Muelsyse_Corpus.md
Specialty: Ecology, Environment, Biology, History

### ドロシー(Dorothy)
Base data: @Claude/Personas/Dorothy_Corpus.md
Specialty: Chemistry, Philosophy, Idea-shaping
