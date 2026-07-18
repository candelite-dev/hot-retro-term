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
| A1 | qmltermwidget CMake ソース差し替え分岐 | A | - | todo |
| A2 | Pty.h 振り分け + PtyWin 骨格（スタブ実装） | A | A1 | todo |
| A3 | Session.cpp の3箇所 ifdef | A | A2 | todo |
| A4 | POSIX include ガード + 死んだ unistd 削除 | A | - | todo |
| A5 | History/BlockArray の mmap 排除 | A | - | todo |
| A6 | デフォルトシェル COMSPEC 化 + setenv→qputenv | A | - | todo |
| A7 | app側 CMake WIN32 整備 + アイコン + フォント fallback | A | - | todo |
| A8 | CI: windows-latest ジョブ追加 + Qt 6.10 統一 | A | A1〜A7 | todo |
| B1 | ConPTY spawn 経路の本実装 | B | A8 | todo |
| B2 | リーダー/ライタースレッド（I/O 本実装） | B | B1 | todo |
| B3 | リサイズ + 終了順序 + no-op 群の確定 | B | B2 | todo |
| B4 | windeployqt デプロイターゲット + CI 起動スモーク | B | B3 | todo |
| C1 | release.yml に zip パッケージング追加 | C | B4 | todo |
| C2 | 磨き: デバッグショートカット + README | C | - | todo |
| C3 | （任意）Job Object で孫プロセス tree-kill | C | B3 | todo |

**Phase ゲート**:
- **A 完了** = GitHub Actions の windows job がコンパイル・リンク通過、**かつ ubuntu/macos job が緑のまま**
- **B 完了** = Windows 実機/VM で cmd.exe が CRT シェーダー越しに動く（詳細チェックリストは `plan.md` の検証節）
- **C 完了** = Qt 未インストールのクリーン Win10 1809+ VM で zip 配布物が起動する

## 作業ログ

- 2026-07-15: タスクシステム初期化。plan.md 正本化、A1〜C3 の15タスク定義（Claude）
