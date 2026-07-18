# A1: qmltermwidget CMake ソース差し替え分岐

- Phase: A（コンパイルゲート）
- 依存: なし
- 対象ファイル: `qmltermwidget/CMakeLists.txt`
- mac検証: 可（macビルドが従来どおり通ること）。Windows側の実コンパイルは A8 のCIで判明。

## ゴール

WIN32 ビルドでは POSIX 専用ソース5本を**コンパイル対象から外し**、代わりに `lib/PtyWin.cpp`（A2で新規作成）を入れる。POSIX ビルドは1バイトも挙動を変えない。

## 背景（このタスクだけ読む人向け）

qmltermwidget は Konsole 派生の QML プラグイン。PTY 層（kpty/kptydevice/kptyprocess/Pty）は openpty/termios/fork 前提で Windows に存在しない API の塊。Windows では ConPTY ベースの新実装 `PtyWin` に丸ごと差し替える方針（設計は `windows-plan/plan.md` 参照）。POSIX ソースはディスク上無傷のままビルドから外すだけなので、mac/Linux のリグレッションは構造的に起きない。

## 手順

1. `qmltermwidget/CMakeLists.txt` を読む。現状はソース一覧が無条件で並び（ファイル先頭〜:30 付近）、`HAVE_POSIX_OPENPT` などが無条件 define されている。プラグイン出力先 `LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qmltermwidget/QMLTermWidget"`（:60-62 付近）は**変更しない**（Windows でもこの配置が main.cpp の import path と一致する）。
2. ソース一覧を共通部と分岐部に再構成する:

```cmake
set(QMLTERMWIDGET_SOURCES
    lib/ColorScheme.cpp lib/Emulation.cpp lib/Filter.cpp lib/History.cpp
    lib/HistorySearch.cpp lib/KeyboardTranslator.cpp lib/konsole_wcwidth.cpp
    lib/kprocess.cpp lib/ProcessInfo.cpp lib/Screen.cpp lib/ScreenWindow.cpp
    lib/Session.cpp lib/ShellCommand.cpp lib/TerminalCharacterDecoder.cpp
    lib/TerminalDisplay.cpp lib/tools.cpp lib/Vt102Emulation.cpp
    lib/ksession.cpp src/qmltermwidget_plugin.cpp
)
if(WIN32)
    list(APPEND QMLTERMWIDGET_SOURCES lib/PtyWin.cpp lib/PtyWin.h)
else()
    list(APPEND QMLTERMWIDGET_SOURCES
        lib/BlockArray.cpp lib/kpty.cpp lib/kptydevice.cpp lib/kptyprocess.cpp lib/Pty.cpp)
endif()
```

   ※ 既存 CMakeLists のソース列挙と食い違いがあれば**既存を正**とし、上記の「共通/POSIX/WIN32 への振り分け」だけを適用する。ヘッダーの列挙有無も既存流儀に合わせる。

3. compile definitions を分岐する（既存の define 群を正確に温存すること。特に Apple の utmpx 系 define がある場合は else 側に残す）:

```cmake
if(WIN32)
    target_compile_definitions(qmltermwidget PRIVATE
        QTERMWIDGET_LIBRARY NOMINMAX WIN32_LEAN_AND_MEAN
        _WIN32_WINNT=0x0A00 WINVER=0x0A00)   # 0x0A00 で consoleapi.h の CreatePseudoConsole が見える
else()
    # 既存の定義（QTERMWIDGET_LIBRARY HAVE_POSIX_OPENPT HAVE_SYS_TIME_H + プラットフォーム別）をそのまま
endif()
```

4. `lib.pri` / `qmltermwidget.pro`（qmake残骸）は**触らない**（CMakeビルドのみが正）。

## 完了条件

- [ ] `git diff` が `qmltermwidget/CMakeLists.txt` のみ
- [ ] mac で `cmake -B build && cmake --build build -j` が従来どおり成功（POSIX ソースが今までどおり全部コンパイルされている）
- [ ] WIN32 分岐に PtyWin.cpp が入っている（A2 完了までは Windows ビルド不可で正常 — 誰も Windows でビルドしないので問題ない）
