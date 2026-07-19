# Windows移植 タスクボード

**正本ルール: 各タスクの status はこのファイルの表だけで管理する。タスクファイル側には status を書かない。**

## 復元プロトコル（Usage Limit / セッション断からの再開手順）

1. 下の表で「依存がすべて done の、いちばん上の todo」を選ぶ。
2. `windows-plan/tasks/<ID>-*.md` を開く。各タスクは**前提知識ゼロで実行できるよう自己完結**で書いてある（計画全体の文脈が欲しければ `plan.md`）。
3. 実装は Codex（GPT-5.6 Sol）に委任する — `windows-plan/codex-workflow.md` のテンプレ使用。実装後は**必ず監査ループ**（codex-workflow.md「全体アーキテクチャ」+ `audit-instructions.md`）を通す。
4. status 遷移: 着手 = `in-progress`（Codexが書く）→ 実装完了 = `review`（Codexが書く）→ **監査PASS = `done`（監査役だけが書ける）**。各遷移で作業ログに1行追記。
5. 放置タスクの扱い: `in-progress` のまま = Codex が途中で死んでいる。`git diff` を確認し、中途半端なら巻き戻して（`git checkout -- <files>`）todo へ。`review` のまま = 監査待ちなので監査サブエージェントを起動する。`needs-human` = `inbox/` に report がある。人間の調査が済むまで触らない。

status の値: `todo` / `in-progress`（Codex実装中） / `review`（実装済み・監査待ち） / `done`（監査PASS済み） / `blocked` / `needs-human`（SUSPICIOUS→inbox隔離、人間の調査待ち）

## ボード

| ID | タスク | Phase | 依存 | status |
|----|--------|-------|------|--------|
| A1 | qmltermwidget CMake ソース差し替え分岐 | A | - | done |
| A2 | Pty.h 振り分け + PtyWin 骨格（スタブ実装） | A | A1 | done |
| A3 | Session.cpp の3箇所 ifdef | A | A2 | done |
| A4 | POSIX include ガード + 死んだ unistd 削除 | A | - | done |
| A5 | History/BlockArray の mmap 排除 | A | - | done |
| A6 | デフォルトシェル COMSPEC 化 + setenv→qputenv | A | - | done |
| A7 | app側 CMake WIN32 整備 + アイコン + フォント fallback | A | - | done |
| A8 | CI: windows-latest ジョブ追加 + Qt 6.10 統一 | A | A1〜A7 | review |
| B1 | ConPTY spawn 経路の本実装 | B | A8 | todo |
| B2 | リーダー/ライタースレッド（I/O 本実装） | B | B1 | todo |
| B3 | リサイズ + 終了順序 + no-op 群の確定 | B | B2 | todo |
| B4 | windeployqt デプロイターゲット + CI 起動スモーク | B | B3 | todo |
| C1 | release.yml に zip パッケージング追加 | C | B4 | todo |
| C2 | 磨き: デバッグショートカット + README | C | - | todo |
| C3 | （任意）Job Object で孫プロセス tree-kill | C | B3 | todo |

✅ **A8 の前提条件は解消済み（2026-07-19）**: ユーザー判断で qmltermwidget を vendor 化（コミット ddda1c1、
出自と履歴保全はコミットメッセージ参照）。CI は qmltermwidget/ の全変更を通常ファイルとして参照可能。

**Phase ゲート**:
- **A 完了** = GitHub Actions の windows job がコンパイル・リンク通過、**かつ ubuntu/macos job が緑のまま**
- **B 完了** = Windows 実機/VM で cmd.exe が CRT シェーダー越しに動く（詳細チェックリストは `plan.md` の検証節）
- **C 完了** = Qt 未インストールのクリーン Win10 1809+ VM で zip 配布物が起動する

## 作業ログ

- 2026-07-15: タスクシステム初期化。plan.md 正本化、A1〜C3 の15タスク定義（Claude）
- 2026-07-19 / A1 / CMake の WIN32/POSIX ソース・定義分岐を実装 / 検証失敗: `cmake` が未インストール（exit 127）のため macOS ビルド未確認、status は in-progress のまま
- 2026-07-19 / A1 / macOS x86_64 configure・build を再検証 / 成功: `cool-retro-term` まで全ターゲットをビルド（exit 0）、status を review に更新
- 2026-07-19: 障害対応: codex-cli 0.135.0 が gpt-5.6-sol 非対応（400）→ 0.144.6 へ更新して A1 再委任（Claude）
- 2026-07-19: 環境判明: cmake は CLion 同梱 + x86_64/Rosetta フラグ必須（正は codex-workflow.md）。qmltermwidget はサブモジュール（fork 無し・ユーザー未コミット変更あり）→ サブモジュール内 git 操作禁止、A8 前に fork/vendor の人間判断が必要（Claude）
- 2026-07-19 / A1 / 監査PASS: サブモジュール diff は CMakeLists.txt のみ・POSIX 側ソース24本と define 群の完全温存を flags.make/link.txt で実証・mac x86_64 ビルド exit 0・起動スモーク OK、status を done に / CI・実機待ち: WIN32 分岐の実コンパイル（A2 で PtyWin.* 作成後、A8 の windows job で判明）（監査役）
- 2026-07-19 / A2 / Pty.h の Windows 振り分けと PtyWin ConPTY スタブ骨格を追加 / 成功: macOS x86_64 configure・build ともに exit 0、`cool-retro-term` まで全ターゲットをビルド、status を review に更新
- 2026-07-19 / A2 / 監査PASS: Pty.h は追加5行・削除0（numstat で #else 側1バイト不変を実証）・PtyWin.h 公開シグネチャは POSIX 版と完全一致（receivedData/sendData/setUtf8Mode/lockPty/start(5引数) 含む）・windowSize()=QSize(cols,lines) 軸順準拠・Session の QProcess/KProcess 表面充足（pty()->slaveFd() は設計どおり A3 残件）・CMakeLists.txt は A1 分から未改変（mtime 00:36 vs A2 群 01:00）・mac x86_64 で Pty.h touch 強制再コンパイル（Pty.cpp/Session.cpp/mocs）込みビルド exit 0・mac ビルドに PtyWin 参照ゼロ、status を done に / CI・実機待ち: PtyWin.h/.cpp の Windows 実コンパイル（A8 windows job）。B1 向けメモ: _WIN32_WINNT=0x0A00 のみだと NTDDI_VERSION が RTM 相当になり consoleapi.h の CreatePseudoConsole 群（NTDDI_WIN10_RS5 ガード）が隠れる可能性 → B1/A8 でエラー時は NTDDI_VERSION=0x0A000006 を CMake に追加（A2 スタブは関数未使用のため影響なし）（監査役）
- 2026-07-19: 障害対応: Claude 側セッション上限で A3 委任転送が失敗（Codex 未着手・汚染なし）→ ユーザー指示で 5h 間隔ループへ切替、以後 Codex 委任は companion 直接呼び出しに変更（Claude）
- 2026-07-19 / A3 / Session.cpp の slave fd・sendSignal・close を Windows/POSIX 分岐 / macOS x86_64 configure・build は成功（exit 0）、起動確認は GUI セッションの pasteboard/service 接続エラーで exit 1 のためシェル起動未確認
- 2026-07-19 / A3 / 監査PASS: Session.cpp は追加26・削除0（numstat）で3箇所とも #ifdef Q_OS_WIN 構造内・POSIX 本体無変更（#else 直後の空行1行のみ純追加＝意味なし）・close() は共有 _autoClose/_wantedClose 設定後に kill→closePty の契約順序・SIG 定数は close() の #else 内 :594/:601/:610 のみ（他の SIG ヒットは全て Qt SIGNAL マクロ）・sendSignal 呼び出し元は KSession ラッパーと close() POSIX 分岐のみ・CMakeLists.txt/Pty.h/PtyWin.* は mtime（00:36/01:09/01:00）が A3 作業窓（05:25-05:28）より前で未接触＋Pty.h diff 内容も A2 記録の5行と一致・mac x86_64 再ビルド exit 0（Session.cpp.o 05:26 が現行ソース反映）・起動スモーク代行成功: 34秒生存・子プロセス zsh 起動＝シェル成立・ログは既知の無害警告のみ、status を done に / CI・実機待ち: Q_OS_WIN 側3分岐の実コンパイルと実挙動（A8 windows job、close() の kill→closePty 実動作は B3 実機）（監査役）
- 2026-07-19 / A4 / ProcessInfo の POSIX include を Windows 除外し、3ファイルの未使用 unistd include を削除 / 成功: 使用シンボル grep 0件、macOS x86_64 configure・build ともに exit 0、`cool-retro-term` までビルド
- 2026-07-19 / A4 / 監査PASS: numstat は ProcessInfo +2/-0（ガード2行のみ・非include行変更ゼロ）・Emulation 0/-2・Screen 0/-1・Vt102 0/-1 / Q_OS_WIN 判定は先行 #include "ProcessInfo.h"（QtCore/QFile等）経由で成立、QtGlobal 追加不要は正当 / unistd シンボル独立grep 0件（Pty.cpp 陽性対照2件でパターン有効性を実証、緩い単語grepのヒットは全てライセンス文の "write"）/ ガード外 POSIX 使用なし（getpwuid_r は :359 既存 !Q_OS_WIN 内、readlink/MAXPATHLEN は Q_OS_LINUX 節内、newInstance は #else→NullProcessInfo）/ mac-vkcode.h 不接触 / A1〜A3 ファイル未接触（mtime 00:36/01:00/01:09/05:25 vs A4 窓 11:03、numstat も A2/A3 記録と一致）/ mac x86_64 で4ファイル touch 強制再コンパイル+リンク exit 0（.o 4本とも 11:12 更新）/ 手順外の逸脱1件: Emulation.cpp 末尾空行1本の削除（空白のみ・意味的変化ゼロのため許容、報告に明記）、status を done に / CI・実機待ち: MSVC での実コンパイル（A8 windows job）、Linux 側 unistd 削除の最終確認（A8 ubuntu job — シンボル使用ゼロ実証済みでリスク極小）（監査役）
- 2026-07-19 / A5 / Windows で History の mmap と BlockArray 参照を排除し CRT seek/read/write と malloc/free に分岐 / macOS x86_64 configure・build は成功（exit 0）、read/write 呼び出しは HistoryFile 内のみ・BlockArray 履歴型の外部参照0件、GUIサービス接続エラーでアプリ起動は exit 1 のためスクロールバック確認は監査役代行
- 2026-07-19 / A5 / 監査PASS（代行: メインFable — 監査サブエージェントがClaude上限で中断したため。命令書チェックリストは全項目実施）: diff は History.h/.cpp のみ・純追加で削除行ゼロ・POSIX mmap 経路は #else 側に1バイト不変・read/write マクロのメンバ呼び波及を独立grepで被害ゼロ実証（意図した CRT 呼び2箇所のみ、define は全include後）・BlockArray 外部参照ゼロ・touch強制再コンパイル exit 0・-e 起動で seq 5000 スクロールバック充填 12秒生存クラッシュなし、status を done に / CI・実機待ち: Q_OS_WIN 側分岐（malloc/free・io.h マッピング・map() no-op）の実コンパイル（A8）（Claude）
- 2026-07-19 / A6 / Windows既定シェルをCOMSPEC化しsetenv 3箇所をqputenvへ置換 / macOS x86_64 configure・build成功（exit 0）、初回起動は継続後に手動停止、GUIサービス・プロセス参照制限により子シェルと設定一覧の目視は未確認（配備済みcolor-schemes 31件・kb-layouts 8件）、statusをreviewに更新
- 2026-07-19 / A6 / 監査PASS: diff は ksession.cpp +7/-2・plugin +2/-2 のみ（numstat が A1〜A5 監査記録と完全一致、mtime で他ファイル不接触〈A6 窓 15:57 vs 直近 History 15:55=A5 監査 touch〉）・setenv→qputenv は3箇所1対1で POSIX 等価（値の組み立ては toUtf8 同一バイト、読み側 tools.cpp:19/65 は QString(QByteArray)=fromUtf8 で対称 — Qt6.10 実ヘッダ qstring.h:941 で実証）・POSIX シェル分岐（$SHELL→/bin/bash fallback→fromUtf8）は #else 内に完全温存（改行整形はタスク手順1の指定形どおり）・COMSPEC 分岐は #ifdef Q_OS_WIN 内・lib/src に setenv/putenv/unsetenv 残存0件・touch 強制再コンパイル（.o 2本 16:07 更新）ビルド exit 0・起動スモーク代行成功: 子 /bin/zsh -i -l 成立（52秒生存）、-e env ダンプで KB_LAYOUT_DIR/COLORSCHEMES_DIR が qputenv 値どおり子プロセスへ伝播（=build/qmltermwidget/QMLTermWidget/ 配下、バンドル内 fallback 不在＋keytab 起動時必須ロード＋失敗時 qDebug 必発の構造でログ無エラー＝env 経路の実働証明）・子 TERM=xterm-256color は Pty.cpp:159 の既存上書きで A6 前後不変、status を done に / CI・実機待ち: Q_OS_WIN 側 COMSPEC 分岐と MSVC qputenv(_putenv_s) の実コンパイル（A8）。メモ: Windows 非ASCIIパスでも in-process qgetenv 読みなら UTF-8 往復一貫（narrow→wide の ACP 同期で外部ワイド読者のみ化ける — 現行読者は tools.cpp のみで実害なし）、COMSPEC 未設定時 fallback "cmd.exe" は相対名 → B1 の spawn で PATH 解決前提（監査役）
- 2026-07-19 / A7 / app CMake に WIN32 GUI・RC 分岐、Windows フォント fallback、4サイズ PNG 埋め込み ICO を追加 / 成功: ICO ヘッダー `00 00 01 00 04 00`・サイズ順 256/128/64/32・offset/PNG署名を検証、macOS x86_64 configure・build ともに exit 0、status を review に更新
- 2026-07-19 / A7 / 監査PASS: 親 diff は CMakeLists +6/-0・fontmanager +3/-0 の純追加（削除行ゼロ）・新規は crt.ico/crt.rc のみ・帳簿以外の欄外変更なし（A7 窓 15:58-16:30 の mtime 全走査で期待5ファイルのみ、ksession/plugin の 16:06 は A6 監査 touch 痕跡で内容は A6 PASS 時のまま）・サブモジュール numstat は A1〜A6 監査記録と完全一致 / WIN32 節は if(APPLE) 直後の独立ブロック・ターゲット名実物一致・fallback は #elif defined(Q_OS_WIN) で Consolas→Courier New 2段、Q_OS_MAC(Menlo)/#else(Monospace) 温存 / crt.ico 自前パース（python struct・Codex 検証に非依存）: ICONDIR reserved=0/type=1/count=4・エントリ 256(0表記)/128/64/32・全4エントリ PNG 署名 OK・IHDR 寸法=エントリ表記一致・offset+length 連鎖=ファイル末尾 124082 完全一致（隙間/後続データなし）・埋め込み PNG 4枚は既存 icons/NxN/cool-retro-term.png とバイト同一（sha256 一致=隠しペイロード余地なし）・生成スクリプト残置 0 件・git hooks/hooksPath 未接触 / crt.rc は指定1行形式・ico と同一ディレクトリで RC 相対解決 OK / mac 実証: CMakeLists touch 再configure exit 0・fontmanager touch 強制再コンパイル+リンク exit 0・build/ 内 crt.rc 参照 0・CMakeCache に RC 項目なし・バイナリ UTF-16 検索 Menlo=1/Consolas=0/Courier New=0（WIN32 分岐は mac で死文）・起動スモーク 10 秒生存 kill 正常・Monospace 警告は qmltermwidget TerminalDisplay.cpp:421 既定値由来の既知警告（QML diff ゼロ・A7 不関与）で新規フォントエラーなし、status を done に / CI・実機待ち: RC 実コンパイルと GUI サブシステム化（A8 windows job）、タスクバーアイコン表示と Consolas fallback 実挙動（B 実機）。メモ: ico は既存 PNG が4種のみのため 16/48px 非含有の4サイズ — 完了条件「マルチサイズ」は充足、小サイズ表示は 32px 縮小でまかなわれる（監査役）
- 2026-07-19: A8前提解消: ユーザー判断で qmltermwidget を vendor 化（ddda1c1）。ローカル履歴（fix/qchar-nonbmp-qt6 @ e44cec8）は .git/modules/qmltermwidget とコミットメッセージに保全。監査済み A1〜A6 のコード diff も同コミットで親リポジトリに編入。旧サブモジュール制約は統治文書から撤去（Claude）
- 2026-07-19 / A8 / Windows MSVC + Ninja ジョブ追加、Qt 6.10.* 統一、windows-port push トリガー追加 / Ruby Psych の YAML 構文検証・git diff --check 成功（PyYAML は未導入）、status を review に更新（yml 完成・push 待ち）
- 2026-07-19 / A8 / install-qt-action を全3ジョブで v3 から v4 に更新 / Ruby Psych の YAML 構文検証成功、status は review のまま
- 2026-07-19 / A8 / Windows MSVC 初回ビルドの wcwidth 未定義を Markus Kuhn の幅判定で補完し、未使用 SSHProcessInfo を Windows から除外 / macOS x86_64 configure・build ともに exit 0、status は review のまま
- 2026-07-19 / A8 / Windows MSVC 2周目リンクエラー対策として、TerminalDisplay が QTermWidget の enum/alias を使用するため include は維持し qtermwidget.h の AUTOMOC のみ除外 / macOS x86_64 configure・build ともに exit 0、moc_qtermwidget 生成なし、status は review のまま
- 2026-07-19 / A8 / Windows MSVC 3周目リンクエラーの根治として、TerminalDisplay の QTermWidget 型参照16箇所を正規型へ置換し qtermwidget.h 依存と SKIP_AUTOMOC 回避策を削除 / macOS x86_64 configure・build ともに exit 0、autogen 内 QTermWidget 参照0件・moc_qtermwidget 生成なし、status は review のまま
