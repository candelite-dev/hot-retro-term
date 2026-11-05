# hot-retro-term

A fork of [cool-retro-term](https://github.com/Swordfish90/cool-retro-term) — a CRT-aesthetic terminal emulator — extended with split panes, a command palette, and a unified CRT rendering pipeline.

## Screenshots

![Image](<https://i.imgur.com/TNumkDn.png>)
![Image](<https://i.imgur.com/hfjWOM4.png>)
![Image](<https://i.imgur.com/GYRDPzJ.jpg>)

## What's New

### Split Panes
Divide the terminal into multiple panes, each running its own shell session.

- Split right or down (up to 16 panes per tab)
- Drag the divider to resize
- Move focus between panes with directional shortcuts
- ASCII-rendered dividers and focus border — everything stays inside the CRT effect

### Command Palette
A fuzzy-searchable command palette rendered entirely in ASCII art using your terminal font. Access all commands, toggle CRT effects, switch profiles, and more — without leaving the keyboard.

### ASCII Tab Bar
The tab bar renders inside the CRT shader pipeline, so it inherits all CRT effects including curvature, bloom, and scan lines. It appears automatically when more than one tab is open and always follows the focused terminal's font and zoom. Each character uses the terminal's displayed cell dimensions, and the bar is exactly one terminal row tall. Font and profile changes update it immediately; there is no separate tab scale setting. Older saved `tabBarScale` values are ignored. Dimensions match before CRT distortion; curvature can change their apparent size by screen position.

### Window Curvature
A barrel distortion effect applied to the entire window — including the tab bar and all split panes — giving the whole interface a single unified CRT curve.

### Unified CRT Rendering
In split or multi-tab mode, all panes are composited under a single CRT shader pass, ensuring consistent visual effects across panes rather than each pane having its own independent effect bubble.

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| New tab | Ctrl+Shift+T |
| Close tab | Ctrl+Shift+W |
| Switch to tab N | Alt+N |
| Split right | Ctrl+Shift+D |
| Split down | Ctrl+Shift+H |
| Move focus left/right/up/down | Ctrl+Shift+←/→/↑/↓ |
| Command palette | Ctrl+Shift+P |
| Zoom in / out | Ctrl++ / Ctrl+- |

Terminal input uses DEL (`0x7f`) for Backspace and Shift+Backspace, and BS (`0x08`,
Ctrl+H) for Ctrl+Backspace. This matches Ghostty's default legacy key encoding.
The shell's erase character follows the Backspace mapping. On macOS, Ctrl here
means the physical Control key.

## Build and run

Start in the **hot-retro-term root**, one level above `qmltermwidget`.
Use CMake 3.21+, a C++17 compiler, and **Qt 6.10 or newer**, including
Qt Quick/Controls, Widgets, SQL, `qt5compat`, `qtshadertools`, and Qt Test.
The `qmltermwidget` folder is included source; only KDSingleApplication is a submodule.

```bash
git submodule update --init --recursive
./scripts/dev.sh run
```

On macOS, install the prerequisites with `brew install cmake qt`. On Linux,
install a Qt 6.10+ SDK with the modules above (the Qt version in your distribution
may be older). The Linux system-package list is in `.github/workflows/build.yml`.
If Qt lives outside a standard prefix, set `QT_DIR=/path/to/Qt/6.10.x/<platform>`.

`dev.sh` always builds before launching and uses `build/dev`, avoiding stale IDE
builds from another machine or CPU architecture. `JOBS=8` changes build parallelism.
The build step uses your installed prerequisites.

```bash
./scripts/dev.sh test          # build and run regression + real-shell startup tests
./scripts/dev.sh build         # build only
./scripts/dev.sh run --default-settings
```

Equivalent CMake commands:

```bash
cmake --preset dev
cmake --build --preset dev --parallel 4
ctest --preset dev
```

For the file-by-file guide, start with [ARCHITECTURE.md](ARCHITECTURE.md).
For branches, commits, and recovering saved work, read
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Findings and remaining cleanup work are
in [docs/CLEANUP_AUDIT.md](docs/CLEANUP_AUDIT.md).

## Launch options

```bash
./scripts/dev.sh run --workdir "$HOME/projects" -p "Monochrome Green" --fullscreen
./scripts/dev.sh run -e /bin/sh -c 'printf "Hello\n"; exec /bin/sh'
```

Use `-e` last: all following arguments belong to the child command, including
anything that looks like an app flag. `-p` and `--profile` are equivalent.
`--help` and `--version` work without a graphical display. Missing option values
produce an error before the GUI starts.

Malformed saved settings no longer prevent startup. Healthy settings load while
unreadable database entries remain unchanged for that session, including on exit.
Warnings name the affected entry. `--default-settings` starts with defaults and
explicitly replaces the current general/appearance entries when the app closes;
it does not clear custom profiles.

### Windows

Windows builds require Windows 10 version 1809 or later (for ConPTY), Qt 6.10+
with the `qt5compat` and `qtshadertools` modules, MSVC 2022, and Ninja.

Open an x64 Native Tools Command Prompt for VS 2022, put the Qt MSVC x64 `bin`
directory on `PATH`, and set `CMAKE_PREFIX_PATH` to that Qt installation. CMake
3.21+, C++17, and the Ninja single-config generator are required.

```powershell
cmake --preset windows-msvc
cmake --build --preset windows-msvc --parallel
ctest --preset windows-msvc
```

To stage the application with its Qt runtime and QML dependencies using
`windeployqt`, run:

```powershell
cmake --build --preset windows-msvc --target deploy_windows
./scripts/package-windows.ps1
./scripts/test-windows-package.ps1
```

Known limitations and terminal setup notes:

- The executable keeps the Windows GUI subsystem. `--help`, `--version`, and
  argument errors can be captured through subprocess stdout/stderr; cmd.exe
  does not wait for a GUI executable by default.
- The default shell is `%COMSPEC%` (`cmd.exe`). To use PowerShell or WSL, enable
  the custom command in Settings and specify `powershell` or `wsl.exe`.
- If a child program displays garbled characters, run `chcp 65001` before
  starting it.
- WSL clipboard/input problems (D2) and the NVIDIA D3D11 split-resize crash (D3)
  remain open. See [Windows validation](docs/WINDOWS.md) for evidence and repro commands.

Deployment uses [Qt's Windows deployment tooling](https://doc.qt.io/qt-6.10/windows-deployment.html).
Only `build/windows-msvc/windows-stage` is packaged. `windeployqt` collects Qt/QML
dependencies and the compiler redistributable; on a machine without the MSVC
runtime, install the included `vc_redist.x64.exe`. Manual Windows/release workflow
runs validate artifacts without publishing a release.

## Credits

Based on [cool-retro-term](https://github.com/Swordfish90/cool-retro-term) by [Swordfish90](https://github.com/Swordfish90).
Terminal emulation via [qmltermwidget](https://github.com/Swordfish90/qmltermwidget) (Konsole-derived).

## License

GPL-2.0 / GPL-3.0 — see `gpl-2.0.txt` and `gpl-3.0.txt`.
