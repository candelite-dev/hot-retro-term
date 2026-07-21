# D2: WSL でコピー/ペースト・Ctrl+U が効かない + ペーストに bracketed paste マーカー混入

- Phase: D（実機検証で発覚したバグ）
- 依存: D1（描画が動く状態）
- 対象ファイル: 未確定（調査タスク）。有力: `qmltermwidget/lib/TerminalDisplay.cpp`（bracketText/pasteClipboard/copyClipboard/keyPressEvent）、`qmltermwidget/lib/Vt102Emulation.cpp`（`?2004h/l` 処理・キー送信）、`app/qml/TerminalWindow.qml`（copy/paste/commandPalette アクションとショートカット読込）、`app/qml/shortcuts.json`
- mac検証: 描画/入力の実挙動は不可（mac は正常）。**観測はユーザーの物理ディスプレイのみ**（D1 と同じ手段）

## 症状（2026-07-21 実機で確認）

Windows 実機の cool-retro-term で **WSL** を使用中:
1. **ペースト時に bracketed paste マーカーが制御文字として混入する**: 貼り付けると `^[[200~`（＝ESC[200~）と `^[[201~`（ESC[201~）がリテラル文字として画面に出る。本来 bracketed paste 有効時はこの囲みをシェルの readline が剥がして不可視になるべき。
2. **コピー・ペースト機能が効かない**（Ctrl+Shift+C / Ctrl+Shift+V の既定ショートカット）。
3. **Ctrl+U（ユーザー表現「Command+U」）が効かない**。WSL bash では Ctrl+U = readline の行頭まで削除（バイト 0x15）。

## 手がかり（オーケストレータの初期調査）

- **bracketed paste の付与**: `TerminalDisplay::bracketText()`（TerminalDisplay.cpp:3104-3110）は `if (bracketedPasteMode() && !_disabledBracketedPasteMode) { text.prepend("\033[200~"); text.append("\033[201~"); }`。マーカーがリテラルで出る＝`bracketedPasteMode()` が true で包んでいるが WSL 側の readline が剥がしていない＝**モード状態の不整合**が濃厚。`_bracketedPasteMode` は Vt102Emulation が `ESC[?2004h`(有効)/`ESC[?2004l`(無効) を処理して設定する（Emulation.cpp:55/88-95, setBracketedPasteMode TerminalDisplay.cpp:3029）。WSL 起動時に bash が `?2004h` を送るはず。
- **仮説**: (a) WSL の `?2004h/?2004l` シーケンスが Vt102Emulation で正しく処理されず `_bracketedPasteMode` が誤って true のまま固着、または (b) ペーストのタイミングでモードが真だが対象プログラム/文脈では剥がされない、または (c) `_disabledBracketedPasteMode`/初期化の Windows 差。**まず「WSL 起動〜ペーストまでで `_bracketedPasteMode` が実際どうなっているか」を確定する**（一時 `fileIO.write` ダンプ or qDebug で観測）。
- **copy/paste 不動作**: 既定ショートカットは `app/qml/shortcuts.json`（copy=Ctrl+Shift+C, paste=Ctrl+Shift+V, commandPalette=Ctrl+Shift+P。mac は Ctrl+C/Ctrl+V）。TerminalWindow.qml:92-96 が shortcuts.json を読んで copyAction/pasteAction/commandPaletteAction.shortcut に設定。qtermwidget.cpp:601/606 に copyClipboard/pasteClipboard。**確認点**: Windows でショートカットが実際に発火するか、copyAction/pasteAction が呼ばれるか、`TerminalDisplay::pasteClipboard()`（3154）と QClipboard アクセスが Windows で動くか、そもそもショートカットが端末のキー入力に食われていないか。
- **Ctrl+U 不動作**: D1 の Backspace 修正（Vt102Emulation.cpp:1105 で Windows の plain Backspace を 0x7f 化）と同じ入力経路。Ctrl+U は本来 0x15 を送るべき。keytab（default.keytab）と Vt102Emulation::sendKeyEvent の Ctrl 系処理、Windows での modifier 判定を確認。Backspace の時のような keytab/変換ズレの可能性。

## 観測方法（D1 と同じ）

- **SSH セッション0はヘッドレスで GUI 描画/対話が観測不能。実機の実挙動はユーザー物理ディスプレイでのみ確認**。
- 実機ビルド: `C:\crt-setup\build.cmd`（QML/keytab 変更時は先に `C:\crt\src\app\qml\resources.qrc` を touch、ビルド前にアプリ kill）。
- ランタイム観測: 一時 `fileIO.write("file:///C:/crt-setup/xxx.txt", ...)` でモード状態や送信バイトをダンプ（`console.log`/qDebug は GUI subsystem で stderr に乗らない）。
- スクショ: `C:\crt-setup\shot.ps1`。
- WSL はユーザー環境に導入済み（cool-retro-term のカスタムコマンドで `wsl.exe` を起動 or 既定シェル差し替えで再現。Codex は再現手順もタスクに含めてよい）。

## 進め方（調査 → 候補修正 → 実機検証ループ）

Codex は盲目実装せず、まず 3 症状それぞれの機序を確定 → 最小修正を提案・実装（working tree に diff、commit しない）→ オーケストレータが実機ビルド＋ユーザー目視で検証。POSIX（mac/Linux）の挙動を壊さない（必要なら `#if defined(Q_OS_WIN)` / `appSettings.isMacOS` ガード）。1 往復で最大の情報が得られる切り分けを優先（例: bracketed paste は「ペースト直前の `_bracketedPasteMode` 値」を実機ダンプで確定するのが最初）。

## 完了条件（Windows 実機）

- [ ] WSL でペーストしても `^[[200~`/`^[[201~` が混入しない（bracketed paste が正しく機能 or 適切に無効）
- [ ] コピー（Ctrl+Shift+C）・ペースト（Ctrl+Shift+V）が動作
- [ ] Ctrl+U が WSL bash で行削除として効く
- [ ] mac/Linux で無退行
