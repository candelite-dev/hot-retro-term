# Windows integration and validation

PR #5 merges `master` (`77eca9c`) into `windows-port`; neither branch is rebased.
The original checkout and its locally modified shader binaries are preserved.
The vendored engine starts from master's source, retaining its session ownership,
launch parsing, font discovery, shutdown ordering, keytabs, and buffered burn-in.
Windows adds ConPTY, resource/icon compilation, COMSPEC, font fallbacks, shader
binding fixes, cursor repainting, and the boot-overlay safety timer.

## Build and package

Use Windows x64, MSVC 2022's x64 Native Tools environment, Ninja, CMake 3.21+,
and Qt 6.10+ MSVC x64 with `qt5compat` and `qtshadertools`. Put Qt's `bin` on
`PATH` and its installation prefix in `CMAKE_PREFIX_PATH`.

```powershell
git submodule update --init --recursive
cmake --preset windows-msvc
cmake --build --preset windows-msvc --target compile_shaders
cmake --build --preset windows-msvc --parallel
ctest --preset windows-msvc
cmake --build --preset windows-msvc --target deploy_windows
./scripts/package-windows.ps1
./scripts/test-windows-package.ps1
```

`deploy_windows` depends on both application and QML plugin and uses their target
paths. Missing `windeployqt` is a deployment error. Cleanup is restricted to the
validated `windows-stage` child of the build tree. Staging explicitly copies the
application, custom QML plugin/assets, and licenses, then uses
[windeployqt](https://doc.qt.io/qt-6.10/windows-deployment.html) for Qt libraries,
QML imports, plugins and the compiler redistributable. Build/test objects are not
packaged. Install the included `vc_redist.x64.exe` if the MSVC runtime is absent.

The ZIP check extracts to a temporary directory outside the build tree, including
spaces in its path. Its child processes receive only Windows system paths on
`PATH`, no Qt/QML SDK environment overrides, isolated settings, the shipped
`qwindows` platform plugin, and software Quick rendering. It checks captured help
and version, a controlled cmd.exe shell writing a readiness file, clean exit, and
the absence of build/test debris. This checks distribution startup; it does not
establish D3D11 correctness or replace a clean-machine runtime installation check.

Windows packaging is shared by build and release CI through `windows.yml`.
`workflow_dispatch` on that workflow runs package validation alone. Manual runs of
`release.yml` build artifacts and skip publishing; existing push/tag release
behavior is preserved. Do not push a release tag to validate this PR.

## Local evidence — 2026-11-06

- Windows 11, MSVC 19.44 (VS 2022), Ninja, Qt 6.10.3 x64 Release build succeeded.
- All eight CTest suites passed: QML model/layout/settings/input regressions,
  application startup/font/session checks, launch options, native terminal input,
  ConPTY lifecycle, captured CLI streams, help, and version.
- Input checks preserve POSIX byte/line-discipline cases and use a native Windows
  helper for DEL/BS/Delete bytes plus cmd.exe for canonical Backspace editing.
- ConPTY tests cover output, asynchronous client resize acknowledgement, twelve
  repeated closures, descendant termination, failed launches, and closing during
  a 4 MiB pending paste. Shutdown joins workers before releasing their pipes.
- Deployment, ZIP packaging, and extracted-ZIP startup with SDK paths removed
  passed. Normal desktop closure also returned zero.
- Native desktop screenshots showed CRT output and the L-shaped three-pane layout
  on the NVIDIA GeForce RTX 3070 Ti (driver 32.0.16.1074).
- **D3 reproduced:** `threePaneResizeStress` using native D3D11 selected the RTX
  3070 Ti and crashed with `0xC0000005`, nearby symbol `NVENCODEAPI_Thunk`, in
  NVIDIA code. This remains unresolved; no speculative driver workaround is added.
- WSL/input follow-up and CI results are recorded in the task ledger.

For the hardware resize reproduction, start in the same build environment:

```powershell
$env:QT_QPA_PLATFORM = 'windows'
Remove-Item Env:QT_QUICK_BACKEND -ErrorAction SilentlyContinue
$env:QSG_RHI_BACKEND = 'd3d11'
$env:QSG_INFO = '1'
./build/windows-msvc/tests/hrt_startup_test.exe threePaneResizeStress -o native-resize.txt,txt
```

The same regression runs with offscreen/software rendering in CTest. Passing that
case does not close D3. The hardware check resizes the L-shaped three-pane window
60 times and captures frames, covering the original layout without requiring
komorebi. It is a reproduction tool, not a fix.

An opt-in Windows/WSL diagnostic checks readline Ctrl+U followed by bracketed paste:

```powershell
$env:QT_QPA_PLATFORM = 'windows'
$env:QT_QUICK_BACKEND = 'software'
$env:HRT_TEST_WSL_DISTRO = 'Ubuntu-24.04'
./build/windows-msvc/tests/hrt_terminal_input_test.exe wslReadlineInput -o wsl-input.txt,txt
```

D2's physical-key shortcut and WSL paste reports remain open until reproduced and
a fix is verified. Cursor blink timing and physical clipboard shortcuts require
separate native interaction checks; static frames alone do not establish them.
MinGW, Windows ARM64, engine redesign, and driver workarounds are outside this PR.
