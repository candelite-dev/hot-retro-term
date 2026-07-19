# cool-retro-term Windows対応 — 規模感評価と移植ロードマップ

> **このフォルダの使い方**
> - `plan.md`（このファイル）= 移植計画の正本。計画が変わったらここを更新する。
> - `TASKS.md` = タスクボード。**進捗の正本はこちら**。再開時はまずTASKS.mdを読む。
> - `tasks/*.md` = 個別タスクの自己完結な実装指示書（Codex/Claude/人間の誰が拾っても動く粒度）。
> - `codex-workflow.md` = Codex（GPT-5.6 Sol）へのコーディング委任手順 + 実装→監査ループの全体アーキテクチャ。
> - `audit-instructions.md` = 監査サブエージェント（Fable）用の命令書。Codexの成果物を PASS/FAIL/SUSPICIOUS で判定。
> - `inbox/` = SUSPICIOUS 判定の隔離場所（patch+report）。ここに未解決 report がある間、該当タスクの PR/コミット禁止。

## Context

「Windows対応にはどれくらいの変更が必要か？Complete Rewriteが必要か？」への回答。
コードベース全体（app層 + qmltermwidget ~16,750行）をPOSIX依存の観点で監査した。

**結論: Complete Rewriteは不要。** コードの約9割はそのままWindowsで動く。移植作業は
qmltermwidgetのPTY層（~1,640行、全体の約10%）の ConPTY 置換に集中しており、
残りは小さな ifdef 修正とビルド整備だけ。X11依存はゼロ、シェーダーは既にHLSL入り。

## 規模感サマリ

| 区分 | 割合 | 内容 |
|---|---|---|
| 純ポータブル（無修正） | ~64% (~10,700行) | VT102エミュレーション、Screen、TerminalDisplay（QQuickPaintedItem）、KeyboardTranslator、ColorScheme、Filter 等 |
| 軽微な修正（ifdef/数行） | ~26% (~4,100行のうち実修正は数十行) | Session.cpp（~15行）、ProcessInfo.cpp（includeガード）、History/BlockArray（mmap→代替）、ksession.cpp |
| 完全置換（Windows新実装） | ~10% (~1,640行) | kpty.cpp / kptydevice.cpp / kptyprocess.cpp / Pty.cpp → ConPTY バックエンド新規作成 |

**見積り: 新規C++ ~550–750行（`PtyWin.h/.cpp` の1ファイルペア）+ CMake/CI/パッケージング少々。変更ファイル計 ~21（既存16修正 + 新規5）。工数 8–13人日（Windows実機を常用できれば7–9人日寄り）。**

## そのまま動くもの（意外と多い）

- **シェーダー全部**: `app/CMakeLists.txt:90` の qsb フラグに `--hlsl 50` が既にあり、コミット済み `.qsb` にHLSL 50バイトコードが焼き込み済み（`qsb --dump` で確認）。QtのWindows既定RHI（D3D11）でそのまま動く。RHIバックエンド強制も無し。CRT演出はWindowsでも無修正。
- **KDSingleApplication**: `Q_OS_WIN` 分岐実装済み（`kdsingleapplication_localsocket.cpp:36-37,78-127`）、WIN32でkernel32リンク済み。単一インスタンス制御はそのまま。
- **設定永続化**: `Storage.qml`（Qt LocalStorage/SQLite）— クロスプラットフォーム。
- **フォント**: QRC同梱フォント + `QFontDatabase` 列挙（`app/fontmanager.cpp`）— ポータブル。
- **ショートカット**: `shortcuts.json` の mac/default 分岐で、WindowsはCtrl+Shift系defaultを自動取得。
- **メニューバー**: ネイティブでなく Qt Quick Controls の in-window MenuBar — 問題なし。
- **fileio**: `QStandardPaths::AppConfigLocation` ベース、ハードコードパス無し。
- **文字コード**: エミュレーションは既に双方向UTF-8固定（`Emulation.cpp:57` / `:201`）— ConPTYが話すのもまさにUTF-8。コーデック作業ゼロ。
- **X11/xkb/xcb 依存: ゼロ**（grep確認済み。唯一の名残は cosmetic な `WINDOWID` 環境変数のみ）。

## 完全置換が必要な核心: PTY層（~1,640行 → ConPTY）

| ファイル | 行数 | 現状のPOSIX依存 |
|---|---|---|
| `qmltermwidget/lib/kpty.cpp` | 728 | openpty/grantpt/ioctl(TIOCSWINSZ)/termios/utmp |
| `qmltermwidget/lib/kptydevice.cpp` | 422 | master fd上のQIODevice、QSocketNotifier、FIONREAD、O_NONBLOCK |
| `qmltermwidget/lib/kptyprocess.cpp` | 130 | setChildProcessModifier + dup2（fork子プロセスでslave→stdio接続） |
| `qmltermwidget/lib/Pty.cpp` | 358 | tcgetattr/tcsetattr、sigaction、setWinSize |

置換先は Windows **ConPTY** API（`CreatePseudoConsole` / `ResizePseudoConsole` /
`ClosePseudoConsole` + 匿名パイプ、Windows 10 1809+）。winptyフォールバックは不要。

**保持すべき契約**（Session→Ptyの継ぎ目、ここを守れば上位は無傷）:
`start(program, args, env, winid, addToUtmp)` / slot `sendData(const char*, int)` /
signal `receivedData(const char*, int)` / `setWindowSize(lines, cols)` / `closePty()` /
QProcess表面（`state()` `processId()` `waitForFinished()` `exitStatus()` signal `finished`）。
termios系setter（setFlowControlEnabled/setErase/setUtf8Mode等）はWindowsでは文書化されたno-opにする。
`foregroundProcessGroup()` は -1 を返すスタブ（ProcessInfoは元々NullProcessInfoにフォールバックする設計）。

## 軽微な修正で済むもの

- `qmltermwidget/lib/Session.cpp` — 実質~15行: `::kill(pid,sig)`（:548）と SIGKILL/SIGHUP 定数（:567-587）の抽象化、`pty()->slaveFd()`（:87）のガード。
- `qmltermwidget/lib/ProcessInfo.cpp:24-29` — ロジックは既にWindows対応（NullProcessInfoフォールバック実装済み）だが、先頭のPOSIX includeが未ガード → `#if !defined(Q_OS_WIN)` で包むだけ。
- `qmltermwidget/lib/History.h:296-305` — CompactHistoryBlockの mmap(MAP_ANON) → malloc代替が**コメントアウトで既に書いてある**。ifdefで切替。
- `qmltermwidget/lib/History.cpp` — HistoryFileのmmapは lseek/read フォールバックが既存 → Windowsでは常にそちらを使う（`<io.h>` の `_read`/`_lseek` マッピング追加）。`BlockArray.cpp`（379行）は**外部参照ゼロを確認済み → WIN32ではコンパイル除外**（移植不要。アプリが実際に使う履歴は `HistoryTypeBuffer` のみ、`ksession.cpp:94`）。
- `qmltermwidget/lib/ksession.cpp:79-84` — デフォルトシェルを `%COMSPEC%`（cmd.exe）にifdef分岐。PowerShell自動探索はしない（COMSPECは全Windowsで保証され、PowerShell派は既存のカスタムコマンド設定で足りる。Storeアプリのエイリアス等、探索は失敗モードを増やすだけ）。**ここで直すので `PreprocessedTerminal.qml:318-337` は無修正で済む**（非mac分岐は元々 `startShellProgram()` を呼ぶだけ）。加えて :84 の `setenv("TERM","xterm",1)` はPOSIX関数でMSVC不可 → `qputenv` に置換（追加発見）。
- `qmltermwidget/src/qmltermwidget_plugin.cpp:35-36` — 同じく `setenv`（`KB_LAYOUT_DIR`/`COLORSCHEMES_DIR` 設定）→ `qputenv`。放置するとMSVCで通らない上、直しても忘れるとキーボードレイアウト/カラースキームが静かに死にます（設計フェーズで追加発見）。
- Screen.cpp / Vt102Emulation.cpp / Emulation.cpp — 使われていない `<unistd.h>` include削除（3ファイル）。
- `app/fontmanager.cpp:349-353` — フォールバックフォント `"Monospace"`（X11エイリアス）→ Windowsでは `Consolas`。
- `app/qml/PaneTreeNode.qml:184` — デバッグ用 `Meta+Shift+D`（WinキーとOS衝突、低優先）。

## ビルド/配布まわり（現状Windows分岐ゼロ）

- `app/CMakeLists.txt:24` — `qt_add_executable` に WIN32 フラグ無し → コンソール窓が背後に出る。
- `if(WIN32)` 分岐が皆無: `.ico`/`.rc` アイコン、windeployqt、QMLプラグイン（qmltermwidget）を
  exe 隣へステージする処理（`app/main.cpp:136-140` のimport path解決に合わせる）が必要。
- qmltermwidget側 CMakeLists は pty ソースを無条件コンパイル + `HAVE_POSIX_OPENPT` 定義
  → `if(WIN32)` でソース差し替えする分岐が必要。
- ツールチェーン推奨: MSVC + 公式Qt 6バイナリ。CI: GitHub Actions windows-latest（現状ubuntu/macosのみ）。

## 実装ロードマップ（概要）

### 中核の設計判断: Windows版Ptyの正体

`Pty` はWindowsでも **KProcess（=QProcess）サブクラスのまま**とし、公開API
`QProcess::setCreateProcessArgumentsModifier` で `CreateProcessW` の引数に
`PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE`（`STARTUPINFOEXW` + `EXTENDED_STARTUPINFO_PRESENT`）を注入する。

- 新規ファイルは `qmltermwidget/lib/PtyWin.h/.cpp`（Windows専用コンパイル）のみ。`Pty.h` はifdefで振り分けるだけ。`Session.h` はPtyを前方宣言しているので差し替えはドロップイン。
- 決め手: Sessionが依存するQProcess表面（`state`/`processId`/`waitForFinished`/`exitStatus`/`finished`シグナル）と、KProcessの環境ブロック構築・Win32引数クォート（`kprocess.cpp` は既にQ_OS_WIN対応済み）を**全部無償で相続**できる。対案（QObjectでダックタイピング）はこの一番バグりやすい~200行を自前再実装する羽目になる。
- 読み取り: ConPTY出力パイプにFIONREAD相当は無い → 専用リーダーQThreadでブロッキング`ReadFile`、QByteArrayをqueued接続でGUIスレッドへ。既存シグナル `receivedData(const char*,int)` の生ポインタ寿命モデルはPOSIX実装と同型のまま安全。
- 書き込み: ライタースレッド経由（ConPTY入力バッファ満杯＋巨大ペーストでのUI凍結を構造的に排除）。
- リサイズ: `ResizePseudoConsole`。終了順序: **子プロセスkill → ClosePseudoConsole（リーダー生存中に）** — 逆順は pre-Win11 conhost の既知ハング。
- POSIX側ソース（kpty/kptydevice/kptyprocess/Pty/BlockArray）はWIN32では**コンパイル対象から外すだけ**でディスク上は無傷 = mac/Linux無リグレッションが構造的に保証される。

### Phase A — Windows CIでコンパイル・リンクが通る（2–3人日）
qmltermwidget CMakeのソース差し替え分岐、`PtyWin` の骨格（中身スタブ可）、Session 3箇所のifdef（:87 slaveFd / sendSignal / close）、includeガード群、`qputenv` 置換×2ファイル、`WIN32_EXECUTABLE` + `.ico`/`.rc`、CIに windows-latest（MSVC + Ninja + install-qt-action）追加。既存 `build.yml` のQt 6.7指定が `find_package(Qt6 6.10 REQUIRED)` と食い違っている問題もここで是正。
**ゲート: windows job緑 かつ ubuntu/macos jobが緑のまま。**

### Phase B — ConPTYが実際に動く（3–5人日）
`PtyWin` 本実装（spawn/reader/writer/resize/shutdown、パイプは既定4KBでなく64KB明示）。CIに起動15秒生存スモーク（DLL欠落=0xC0000135、QMLプラグイン配置ミス=main.cppのEXIT_FAILUREを両方検出）。
**検証はお手元のWindows実機/VM**: cmd.exe起動・エコー・リサイズreflow・タブclose後にconhost孤児なし・大量出力/1MBペーストで固まらない。

### Phase C — 磨き＆配布（2–3人日）
windeployqtステージング（`--qmldir` 2本: app/qml と plugin側、Qt5Compat.GraphicalEffects/LocalStorage/Sqlプラグインを拾わせる）、`release.yml` にzipパッケージング、README、デバッグショートカット修正、（任意）Job Objectによる孫プロセスtree-kill。
**ゲート: Qt未インストールのクリーンWin10 1809+ VMでzipが起動する。**

計 **8–13人日**（ConPTY初見のQt経験者、CI駆動イテレーション込み。実機常用なら7–9人日）。

## オプション拡張: シェルプロファイル（Windows Terminal風の cmd/PowerShell/WSL 切替）

**起動能力そのものは移植だけで手に入る（追加コストゼロ）。** ConPTYはWindows Terminalが使うのと同一基盤で、起動するプログラムを選ばない — cmd.exe / powershell.exe / pwsh / wsl.exe / ssh すべて動く。移植直後でも既存のカスタムコマンド設定や `-e wsl.exe` で WSL 運用は可能（ただし全タブ共通のグローバル設定）。

**Windows Terminal風の「タブごとにプロファイル選択」UXは別途の新機能**（移植と独立、目安 **+2–4人日**）。アーキテクチャ上の障害は無し:
- 各タブは既に独自の `KSession` を持ち、`shellProgram`/`shellProgramArgs` はセッション単位の書込可能Q_PROPERTY（`ksession.h:42-43`）。今グローバル設定を読んでいるのは `PreprocessedTerminal.qml:318-337` の `startSession()` だけ。
- 必要な作業: ①プロファイルモデル（名前+コマンド+引数、Storage.qmlの既存永続化に相乗り）②「+」ボタンのドロップダウン/メニュー項目（`TerminalTabs.qml:286-310` の addTabBtn、`TerminalWindow.qml:173` の newTabAction）③ `addTab()` にprofile引数を追加し、CLAUDE.md記載の4ファイル per-pane 配線パターン（TerminalTabs → PaneTreeNode → TerminalContainer → PreprocessedTerminal）で `startSession()` へ ④シェル自動検出: cmd（`%COMSPEC%`）、powershell/pwsh（PATH）、WSLディストロ列挙（`wsl.exe -l -q`）。
- 副産物としてクロスプラットフォームに効く（Unix側でも bash/zsh/fish プロファイルとして同じUIが使える）。
- 用語注意: 本プロジェクト既存の「プロファイル」は**見た目**（シェーダー設定）のプロファイル。UI文言は「シェル」等に分けて衝突回避。

## 検証（Windows実機/VMあり前提）

**検証環境（2026-07-20 確立、SSH 常用可）**: ホスト `windows`（`~/.ssh/config` 登録済み、Tailscale 経由、Win11 build 26200 AMD64。SSH ユーザーは管理者・リモート既定シェルは cmd）。
- ツールチェーン: VS Build Tools 2022（VCTools ワークロード + Win SDK、サイレント導入）+ CMake + Ninja（winget）
- Qt **6.10.3** = `C:\Qt\6.10.3\msvc2022_64`（aqt 導入。CI と同構成: `qt5compat` + `qtshadertools`）
- リポジトリ: `C:\crt\src`（windows-port ブランチ、KDSingleApplication submodule 込み）
- セットアップのログ/完了マーカー: `C:\crt-setup\`（`setup2.log`、`*.done`）
- 実機ビルドの正（cmd から）: `call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" && cmake -S C:\crt\src -B C:\crt\src\build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=C:\Qt\6.10.3\msvc2022_64 && cmake --build C:\crt\src\build --parallel`
- 注意: SSH 経由の GUI 起動は非対話セッション扱いになり画面には出ない。スモークは「プロセス存在確認（子 cmd.exe / conhost.exe）」か `-platform offscreen` を基本にし、描画目視はユーザーの物理ログオンで行う。SSH のリモートコマンドは cmd 解釈なので複雑な `&` 連結や二重引用符入れ子は quoting 事故のもと — 1 コマンドずつ素直に投げる。

1. ビルド: MSVC + Qt 6.10 で `cmake -B build && cmake --build build`（シェーダー再コンパイル不要 — HLSL焼き込み済み）。
2. スモーク: cmd.exe / PowerShell 起動、キー入力・エコー、ウィンドウリサイズ（ResizePseudoConsole反映）、256色表示。
3. 実戦: ssh接続して vim / htop（VT102エミュレーションの検証）。スクロールバック。
4. UI: タブ複数・split pane、CRTエフェクト全種（D3D11で描画確認）、設定変更→再起動で永続化確認。
5. 単一インスタンス動作（二重起動）。

## リスク

- ConPTY特有の癖: `ClosePseudoConsole` 順序ハング（→ kill先行＋リーダー生存のまま close）、パイプ詰まり（→ 64KBパイプ＋専用スレッド）、**`CREATE_NO_WINDOW` とpseudoconsole属性の競合**（QtがGUIアプリで自動付与するのでmodifier内で明示クリア。忘れた時の症状は「出力が一切来ない」）。
- QProcessのmodifier契約がQt将来版で変わる可能性 — Qt 5.7→6.10で不変の公開APIなので低リスク。万一の時は `PtyWin` 内の2プライベートメソッドを生 `CreateProcessW` に差し替えれば済む設計（Session無影響、~1日）。
- Konsole系コードのGNU拡張: 掃引済みで `#warning`/VLA/`usleep` は無し。History.cppの `read`/`write`/`lseek` は `<io.h>` マッピングで対処。実リスク低。
- multi-config generator（Visual Studio直）だと出力ディレクトリに `/Release` が付きプラグイン配置が崩れる → **Ninja単一構成を標準に**（CIもNinja）。
- ConPTYはWindows 10 1809+ 必須（2026年現在、実質問題なし）。
- `TerminateProcess` は直接の子しか殺さない（cmd配下の孫が残り得る）→ v1許容、Phase CのJob Objectで対処可。
