# Architecture

## Repository layout

```
hot-retro-term/
├── app/                      C++ backend + QML UI
│   ├── main.cpp              QApplication bootstrap, CLI args, single-instance guard
│   ├── fontmanager.cpp/.h    Bundled + system font catalogue; async system enumeration
│   ├── fontlistmodel.cpp/.h  QAbstractListModel wrapping FontEntry vector
│   ├── fileio.cpp/.h         Thin QRC/local file read-write helper exposed to QML
│   ├── curvatureinputfilter  Mouse-position un-distortion for CRT curvature
│   ├── qml/                  All QML and GLSL source
│   │   ├── main.qml          Root QtObject: manages windows and global appSettings
│   │   ├── ApplicationSettings.qml   Central settings store (see Settings section)
│   │   ├── Storage.qml       SQLite persistence via Qt.LocalStorage
│   │   ├── TerminalWindow.qml        ApplicationWindow + shortcuts + menu
│   │   ├── TerminalTabs.qml          Split-pane tree, unified CRT, tab bar
│   │   ├── PreprocessedTerminal.qml  Per-terminal FBO chain + burn-in
│   │   ├── TerminalContainer.qml     Thin adapter connecting PreprocessedTerminal to ShaderTerminal
│   │   ├── ShaderTerminal.qml        CRT shader pipeline (static + dynamic passes)
│   │   ├── shaders/          GLSL sources; two uber-shaders + supporting passes
│   │   ├── profiles/         Built-in CRT profiles (JSON)
│   │   ├── fonts/            Bundled fonts + manifest.json catalogue
│   │   └── shortcuts.json    Default keyboard bindings (mac / non-mac variants)
│   └── CMakeLists.txt
├── qmltermwidget/            Konsole-derived terminal emulator (git submodule / fork)
├── KDSingleApplication/      Single-instance enforcement (git submodule)
└── .github/workflows/        CI: build.yml (PR+push), release.yml (tag)
```

---

## CRT Rendering Pipeline

### Per-terminal mode (1 tab, 1 pane)

```
QMLTermWidget (kterminal)
    │  hideSource: true  →  renders into FBO
    ▼
kterminalSource  (ShaderEffectSource, FBO)
    │
    ├──→  BurnInEffect  (accumulation FBO, live: false, triggered on paint)
    │
    ▼
staticShader  (ShaderEffect: curvature, RGB shift, bloom, brightness, frame shine)
    │  visible: false
    ▼
frameBuffer  (ShaderEffectSource — captures staticShader)
    │
    ▼
dynamicShader  (ShaderEffect: rasterization, noise, jitter, h-sync, flicker, burn-in blend)
    │  visible: !splitActive
    ▼
Screen
```

### Unified mode (split panes or multi-tab)

When `needsUnifiedCRT` is true, `splitActive = true` on every per-terminal ShaderTerminal.
Individual CRT passes are disabled. Each `kterminal` renders directly (no per-pane FBO).

```
[kterminal₁]  [kterminal₂]  …   (render in-place inside crtContent Item)
        └─────────┬─────────┘
                  ▼
            crtContent  (Item: shared tab bar + StackLayout of PaneTreeNodes)
                  │
                  ▼
         unifiedPaneSource  (ShaderEffectSource, live: needsUnifiedCRT)
                  │
                  ▼
          unifiedCRT  (ShaderTerminal, splitActive: false — full CRT effects once)
                  │
                  ▼
               Screen
```

**Key invariant:** The `splitActive` flag disables `kterminalSource.live` and
`kterminalSource.hideSource`, letting `kterminal` render directly into the scene
and eliminating N per-pane FBO captures.

---

## Split-pane Tree

Split state is a binary tree of JS objects stored in `splitTrees[currentIndex]`
(one tree per tab).

```
Node = { type: "terminal", paneId: N }
     | { type: "split", orientation: Qt.Horizontal|Vertical, ratio: 0..1,
         first: Node, second: Node }
```

Terminals live in `terminalPool` (hidden Item) and are reparented into
`PaneTreeNode` slots via `_claim(paneId)` / `_release(paneId)`.

Tree mutations (`splitPane`, `closePane`, `_updateRatioInTree`) always create new
objects — they never mutate existing nodes. This means identity comparison
(`newTree !== cachedTree`) correctly detects changes for the bounds cache in
`splitInputOverlay`.

`splitInputOverlay` (MouseArea, z:3) intercepts all pointer events when unified CRT
is active. `_getPaneAt(x, y)` maps normalized coordinates to the focused pane using
`computePaneBounds`, whose result is cached by tree identity.

---

## Settings

`ApplicationSettings.qml` is a `QtObject` (not a visual item) that holds all
runtime knobs as bindable QML properties.

### Schema-driven serialisation

A single `_settingsSchema` array drives all four I/O operations:

```
{ k: "bloom",   p: "bloom",   scope: "profile"  }
{ k: "tabBarScale", p: "tabBarScale", scope: "settings" }
```

- `k` = JSON key  
- `p` = QML property name (may differ for private `_` prefixed properties)  
- `scope` = `"settings"` (window/general) or `"profile"` (CRT visual)

`_schemaCompose(scope)` builds a JSON-serialisable object from current property values.  
`_schemaLoad(obj, scope)` applies a parsed JSON object back to properties.

**Adding a new setting:** declare the QML property, then add one entry to `_settingsSchema`.

### Persistence

Settings are stored in SQLite via `Storage.qml` (Qt LocalStorage). Two keys:
`_CURRENT_SETTINGS` (general) and `_CURRENT_PROFILE` (visual/profile).

### Profiles

Built-in profiles live in `app/qml/profiles/builtin_profiles.json` (QRC).
Loaded at startup via synchronous XMLHttpRequest. Each entry has the same shape
as a serialised profile object (`obj_string` field).

Custom user profiles are saved to the same SQLite DB under `_CUSTOM_PROFILES`.

---

## Font Catalogue

`FontManager` (C++) maintains a `QVector<FontEntry>`.

On startup:
1. Bundled fonts are loaded synchronously from `app/qml/fonts/manifest.json` (QRC).
2. System monospace fonts are enumerated on `QThreadPool` and appended asynchronously;
   `systemFontsReady` signal is emitted when done.

**Adding a bundled font:** drop the TTF into `app/qml/fonts/`, reference it in
`app/qml/resources.qrc`, add one JSON object to `fonts/manifest.json`.

---

## Shader System

Two uber-shaders replace what was 113 pre-compiled variant files:

| File | Role |
|---|---|
| `terminal_static.frag` | Curvature, RGB shift, bloom, brightness, frame shine |
| `terminal_dynamic.frag` | Rasterization, noise, jitter, h-sync, flicker, burn-in composite |
| `terminal_static.vert` / `terminal_dynamic.vert` | Matching vertex stages |
| `burn_in.frag/.vert` | Burn-in accumulation pass |
| `terminal_frame.frag/.vert` | Decorative bezel |
| `passthrough.vert` | Identity vertex pass |
| `window_curvature.frag/.vert` | Window-level barrel distortion |

Shader variants are selected at **runtime** via uniform branches
(e.g. `if (rasterMode == 1) { ... }`). The `rasterMode` uniform is added to
both vertex and fragment UBOs to keep `layout(std140, binding=0)` in sync.

Pre-compiled `.qsb` files are committed to the repo. To recompile after editing
a `.frag`/`.vert` source:

```bash
cmake --build build --target compile_shaders
```

---

## Keyboard Shortcuts

Default bindings are in `app/qml/shortcuts.json` (QRC). Each entry:
```json
"newTab": { "mac": "Meta+T", "default": "Ctrl+Shift+T" }
```

`TerminalWindow.qml` loads this JSON synchronously in `Component.onCompleted`,
merges an optional user override from
`~/.config/cool-retro-term/shortcuts.json`, then assigns sequences to `Action`
and `Shortcut` objects. Tab-switch shortcuts (1–9) are generated by an
`Instantiator { model: 9 }`.

**Rebinding:** copy `shortcuts.json` to the user config path, edit, restart.

---

## qmltermwidget

`qmltermwidget/` is a local fork of the Konsole terminal emulator exposed as a
QML plugin. Key components:

- `QMLTermWidget` (QML type) — top-level terminal item
- `Session` — manages the PTY (`kpty`)
- `Emulation` / `Vt102Emulation` — VT102 protocol state machine
- `Screen` — character grid buffer
- `TerminalDisplay` — Qt Quick painted item; `updateImage()` is the per-frame
  hot path (redraws changed cells, uses member-reused `_disstrU`/`_dirtyMask`
  buffers to avoid per-frame heap allocation)

The submodule tracks a local branch diverged from upstream
`Swordfish90/qmltermwidget` (branch `unstable`). See `qmltermwidget/` git log
for local patches.
