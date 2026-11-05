# Cleanup audit — 2026-11-03

## Build and startup blockers

- The checked-out parent commit pins QMLTermWidget `ce8e09a`, which has no CMakeLists.txt.
- The locally checked-out `e44cec8` fork builds, but GitHub's configured upstream
  returned “No commit found” for that SHA. Changing only the pin is insufficient
  for reproducible clones. The working source is now included in the parent repo.
- The README still instructed users to run qmake, although the app has a CMake build.
- Build CI selected Qt 6.7 while CMake requires at least 6.10. CI now uses 6.10.
- The existing local debug executable is x86_64 and links `/usr/local/opt/qtbase`,
  which does not exist on this machine. A fresh arm64 build uses `/opt/homebrew`.
- The local `build/` CMake cache names a previous source path, `/Users/keyness/d/hrt`.
  The documented development workflow now uses a fresh `build/dev` directory.
- The DMG script copied the QML plugin to a directory whose name did not match its
  import URI. The directory is now `Contents/PlugIns/QMLTermWidget`.

## Responsibility and behavior changes

The previous “pure data model” also constructed terminal components, managed their
lifetime, computed geometry, logged debug layouts, and closed a window through an
enclosing ID. An unused legacy tab bar and recursive split renderer remained live
code beside the flat renderer. Session exit/title handlers belonged to temporary
visual slots, so hidden tabs lost those handlers.

The cleanup extracts immutable tree geometry, gives a session pool ownership of
terminal signals, makes visual slots borrow terminals, removes the obsolete
renderers, and lets the model request window closure with a signal.

Regression coverage includes background session exits/title updates, pane ownership,
selected-tab stability, invalid closes, failed terminal creation, pane limits,
nested geometry, mouse coordinate scaling/margins, drag capture, and divider resizing.
The startup test loads the real QML/plugin with temporary settings and a controlled
shell command, then exercises tab/split transitions while checking process identity.

## Second pass: startup and shutdown

- Command-line parsing is now owned by `launchoptions.cpp`. Missing values and
  invalid working directories fail before creating the GUI. `-p` works like
  `--profile`; fullscreen reaches the window; `-e` arguments are kept intact and
  are not passed through Qt's application-argument parser.
- Settings properties, JSON validation, profile catalogue, SQLite access, and
  recovery policy now have separate owners. General and appearance entries load
  independently. Corrupt entries no longer interrupt `initializedSettings()` and
  are preserved during automatic saves; valid entries still load and save.
- Imported profiles are validated before entering the catalogue, and custom entries
  cannot claim the built-in flag. Profile removal uses the Qt 6 ListView API.
- SQLite writes for current settings/profile use a transaction; dropping the table
  resets initialization so it can be used again.
- Font discovery belongs to a manager-owned pool. Destruction joins that job before
  member data is freed, and queued results cannot reach a deleted QObject.
- Removing the startup test's global thread-pool drain exposed a PTY shutdown crash.
  LLDB located the callback reading freed KPtyProcess private data. The callback is
  disconnected before teardown, the PTY is closed before waiting for child termination,
  and process callbacks stop before the session decoder is destroyed.
- Fullscreen startup no longer assigns conflicting visibility properties.

Tests cover corrupt database records reaching a real first window, preservation of
saved bytes, explicit default reset, profile/fullscreen propagation, table recreation,
font results and pending-job destruction, missing CLI values, opaque child arguments,
and help/version without a graphical platform. Startup tests reject QML type/reference
errors, visibility conflicts, and destruction of a still-running QProcess.

Native desktop verification remains unavailable: the native run reported no screens,
and the computer-use service could not start. Headless rendering, shell startup, and
layout transitions are tested; GPU appearance and packaged distribution are not yet verified.

## Rasterization follow-up — 2026-11-04

The longstanding raster-mask fade ran from two to four output pixels per font
pixel. At 65% scaling on Retina, a 16px IBM VGA font has about 1.96 output pixels
per font pixel, so its selected scanline effect was entirely disabled. A 12px
font at the same scale still received a partial effect, making font changes look
like rendering regressions. The fade now runs from one to two pixels.

The shared CRT pass also used unscaled window dimensions as its virtual grid,
losing the terminal font's scale. It now uses the same font-pixel grid as the
single-pane path, includes the tab bar, and measures output from its own bounds.
Five startup regression cases reproduce the old failures and verify the 65%
Retina case and consistent grids through tab/split transitions at small/large
font scales. These test QML values; native GPU appearance still needs desktop review.

## Tab font matching follow-up — 2026-11-04

The tab bar now follows the focused terminal's font and zoom automatically. It uses
one displayed terminal row, native font rendering with matching antialiasing, and
letter spacing aligned to the terminal's integer cell width. The separate tab scale
control and persisted key have been removed; legacy values are ignored.

Startup regressions cover IBM VGA, Terminess, and JetBrains Mono at 65%, 100%, and
150%, including long-label advances, baselines, cell dimensions, profile/spacing
changes, resizing, split/tab transitions, and real tab/add-button clicks. Settings
tests verify that legacy scale values do not block healthy settings or survive the
next save. The full five-suite headless regression run passes.

## Remaining work, in priority order

1. **TerminalDisplay boundaries.** Its ~4,000 lines mix painting, selection, input,
   clipboard, URLs, geometry, and the QML adapter. Establish focused engine tests
   before extracting those subsystems. Session reassignment also needs coverage.
2. **Rendering and packaging.** Verify GPU effects, native transparency/titlebar,
   and DMG/AppImage portability on real desktops. Review upstream Qt 6.10
   render-target changes separately.
3. **Tabs and shaders.** The active ASCII tab bar lacks an overflow strategy.
   Shader binaries still need explicit regeneration after source edits.
4. **Secondary launches.** The single-instance message still requests only a new
   window. Per-invocation workdir/command options need a deliberate per-window
   model and IPC payload before they can be honored by an already-running instance.
5. **TOML settings migration.** Preserve and reconcile the saved SettingsStore work
   on its own branch. This pass retains SQLite and the existing persisted format.
6. **Windows integration.** Preserve the ConPTY/Windows work; this branch uses a
   POSIX engine. Review its changes individually before integration.

This remains an incremental cleanup, with legacy engine and platform work listed above.
