# How this app fits together

Start with `README.md` to build and run. This guide follows a terminal from startup
to the screen, then lists where to make common changes.

## 1. The application starts

`app/launchoptions.cpp` parses and validates launch flags before any GUI is created.
`app/main.cpp` handles help/errors, creates QApplication, registers the C++ QML types,
exposes one `launchOptions` map, configures plugin paths, and loads `app/qml/main.qml`.
`main.qml` owns shared settings, the effects clock, and the list of windows.
Each `TerminalWindow.qml` owns its window actions and a `TerminalTabs` item.

The executable is called `cool-retro-term` for compatibility with the original
project. The repository is called `hot-retro-term`.

## 2. A tab creates a terminal session

| File | Owns | Does not own |
|---|---|---|
| `TerminalTabs.qml` | Wiring between the model, session pool, layout, and input | Tree algorithms or session lifetime |
| `SplitTreeModel.qml` | Tabs, focus, split/close commands, title updates | Terminal construction or drawing |
| `TerminalSessionPool.qml` | Terminal objects and their lifetime-long signals | Pane coordinates or visual slots |
| `SplitTree.js` | Pure tree operations and normalized geometry | QML objects, windows, or shells |
| `TerminalPane.qml` | Placing an existing terminal in a visible slot | Starting, ending, or handling session events |
| `PaneLayout.qml` | Pane positions, dividers, tab bar, shared CRT effects | Tab mutation or shell lifetime |
| `InputRouter.qml` | Hit testing and pointer delivery in shared CRT mode | Calculating a second version of the layout |

Each tab has a binary tree:

```text
terminal: { type: "terminal", paneId: 0 }
split:    { type: "split", orientation, ratio, first, second }
```

The tree stores IDs, not terminal objects. The session pool resolves an ID to its
terminal. This is why switching tabs or resizing splits must not restart shells.
Tree changes return new objects so QML knows when to update geometry.

Only the current tab has visual slots. A hidden tab's terminal still lives in the
pool and its exit/title signals still reach the model. A pane close looks up the
pane's owning tab rather than assuming it belongs to the current tab.

## 3. A shell produces text

`TerminalContainer.qml` connects the effects renderer to `PreprocessedTerminal.qml`.
`PreprocessedTerminal` owns a QMLTermWidget and a QMLTermSession, handles per-terminal
input and font changes, and supplies textures to the effects pipeline.

The C++ terminal engine is included in `qmltermwidget/`:

```text
KSession (QML adapter)
  -> Session (shell lifecycle)
  -> Pty / kpty (operating-system pseudo-terminal)
  -> Emulation / Vt102Emulation (decode terminal escape sequences)
  -> Screen / History (character grid and scrollback)
  -> ScreenWindow (the visible part of that buffer)
  -> TerminalDisplay (paint characters and handle terminal input)
```

`TerminalDisplay.cpp` is inherited engine code and remains large. Most changes to
tabs, appearance, settings, and application shortcuts should not require touching it.
See `qmltermwidget/VENDORED.md` for the origin of the local engine fork.

## 4. The CRT effects draw it

For one terminal, `PreprocessedTerminal` captures terminal text, `BurnInEffect`
keeps a fading trail, and `ShaderTerminal` applies the static and animated effects.
For multiple panes or tabs, `PaneLayout` captures the shared content and applies
one CRT effect pipeline. `splitActive` disables the individual pipelines.

Both paths express `virtualResolution` in terminal font pixels, using the font's
`screenScaling`. The shared path includes the tab bar in that grid. `ShaderTerminal`
fades the raster mask between one and two output pixels per terminal pixel, keeping
scanline/pixel modes visible at practical font sizes while suppressing unresolved
patterns. Measuring output size uses the effect's own bounds, not the whole window.

`InputRouter` maps coordinates through `PaneLayout.paneArea` and the actual terminal
item. It must use the same margins, scaling, and tab-bar position as the renderer.
`curvatureinputfilter.cpp` handles distortion before those input events arrive.

`AsciiTabBar` uses the focused terminal's native font, line spacing, and cell metrics.
`FontManager.cellAlignedFont` copies that font and adjusts letter spacing to the
terminal's rounded cell width. Native text rendering preserves hinting and the
terminal's antialiasing choice. `screenScaling` scales the whole row to the displayed
cell size, which also drives backgrounds, truncation, and hit testing.

`app/shaders/` contains the GLSL sources and committed `.qsb` binaries. After editing
a shader, run `cmake --build build/dev --target compile_shaders`, then rebuild.
Shader regeneration is currently explicit, not automatic.

## Where to make a change

| Change | Start here |
|---|---|
| Add/change a shortcut | `app/qml/shortcuts.json`, then `TerminalWindow.qml` for the action |
| Change tabs or split behavior | `SplitTreeModel.qml`; cover the behavior in `tests/qml/` |
| Change pane placement | `SplitTree.js` and `PaneLayout.qml` |
| Change split-mode mouse handling | `InputRouter.qml` and `tests/qml/tst_InputRouter.qml` |
| Add a visual setting | Property in `ApplicationSettings.qml`, entry in `SettingsSchema.js`, corresponding settings tab |
| Change persistence/recovery | `SettingsPersistence.qml` for policy; `Storage.qml` for SQLite operations |
| Change settings validation/JSON | `SettingsCodec.js` and the types/ranges in `SettingsSchema.js` |
| Change profiles | `ProfileCatalog.qml` for the list; `ApplicationSettings.qml` exposes the UI facade |
| Change command-line behavior | `app/launchoptions.cpp`; do not parse `Qt.application.arguments` in QML |
| Add a bundled font | `fonts/manifest.json`, font file, and `resources.qrc` |
| Change font sizing | `app/fontmanager.cpp` |
| Change terminal colors/protocol/scrollback | Included terminal engine, not the tab model |
| Change dependencies/build | Root `CMakeLists.txt`, app target in `app/CMakeLists.txt`, CI |

## Dependencies

Settings responsibilities are separate too:

- `ApplicationSettings.qml` declares live properties and initializes them.
- `SettingsSchema.js` lists persisted keys, scopes, types, and constraints.
- `SettingsCodec.js` validates JSON and maps known keys to properties. It has no I/O.
- `SettingsPersistence.qml` loads independent entries, reports errors, and protects
  unreadable saved data from automatic replacement during the current session.
- `ProfileCatalog.qml` owns the profile model and validates imported entries.
- `Storage.qml` handles SQLite queries and transactions without interpreting settings.

`FontManager` owns its font-discovery thread pool and waits for its own job during
destruction. Results are delivered on the GUI thread. No worker may outlive the
manager, and shutting it down does not wait for unrelated global-pool work.

Qt provides the application framework, QML, controls, effects, SQL, and tests.
KDSingleApplication is a pinned external submodule used only by `main.cpp` to route
new-window requests to the running app. QMLTermWidget is now normal tracked source,
so its local fixes cannot be lost by updating submodules.

The UI still uses some enclosing QML IDs (`appSettings`, window actions, `timeManager`).
Those are remaining coupling, not an example to copy into new standalone components.
