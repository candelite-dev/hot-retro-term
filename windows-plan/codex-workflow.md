# Codex（GPT-5.6 Sol）へのコーディング委任手順

## 前提（2026-07-15 時点で確認済み）

- codex-cli 0.135.0 インストール済み、ChatGPT ログイン有効（`/codex:setup` で `ready: true`）
- `~/.codex/config.toml`: `model = "gpt-5.6-sol"`、`model_reasoning_effort = "xhigh"`
  （旧値 `"ultra"` は 0.135.0 の不正値で全機能をブロックしていた。再発したら xhigh に直す）
- このリポジトリは Codex 側で `trust_level = "trusted"` 登録済み
- モデルは**未指定なら config の gpt-5.6-sol が使われる**。委任時に `--model` を付ける必要はない

## 全体アーキテクチャ（実装フェーズのループ）

**Fable（メイン）は基本アイドルのオーケストレータ。自分では実装も監査もしない。**

```
Fable（メイン）: 委任と中継のみ
   │ ①タスク委任（下記テンプレ、1委任=1タスク）
   ▼
Codex（サブエージェント）: 実装担当
   │ 実装 + mac検証 + TASKS.md を status=review へ
   ▼
Fable（サブエージェント）: 監査役
   │ 起動方法: Agent(general-purpose) に
   │ 「windows-plan/audit-instructions.md を読み、その命令書に従ってタスク <ID> を監査せよ」
   ▼ 判定
 ┌─ PASS ──────→ 監査役が status=done → メインがコミット（下記規約）→ 次のタスクへ
 ├─ FAIL ──────→ メインが監査報告をそのまま Codex に「--resume で続き」で差し戻し → 実装へ戻る
 │               （このループは上限3周。超えたら FAIL×3 として inbox 行き + 人間へ）
 └─ SUSPICIOUS → 監査役が windows-plan/inbox/ に patch+report を隔離、
                 メインが status=needs-human にして即・人間へエスカレーション。PR/コミット禁止
```

### コミット / PR 規約

- 作業ブランチ: `windows-port`（実装開始時に現ブランチから切る。`windows-plan/` を含むため）
- **監査 PASS したタスクごとに1コミット**: `windows-port: <ID> <要約>`。コミットするのはメイン（or 人間）。Codex のコミット禁止は不変
- A8 以降は push して CI を回す。**Phase A ゲート緑で draft PR を作成**、Phase C 完了（クリーンVM検証済み）で ready に昇格
- inbox に未解決 report がある間は、該当タスクに触れる PR/コミットを一切行わない

## 呼び出し方（3通り）

### 1. Claude Code から（通常はこれ）
Claude に「**タスク A1 を Codex にやらせて**」と言う。Claude が `codex:codex-rescue`
サブエージェント経由で下記テンプレのプロンプトを書き込み許可付き（`--write`）で転送する。
- 前回の続きから: 「**--resume で続き**」（直前の Codex セッションを再開。CI エラー修正の往復に便利）
- まっさらでやり直し: 「**--fresh で**」
- 思考の深さ指定: 「**--effort high で**」（none / minimal / low / medium / high / xhigh）

### 2. /codex:rescue スキルを直接叩く
```
/codex:rescue <下記テンプレを貼る> --write
```

### 3. ターミナルから直接（Claude の Usage Limit 中でも移植を止めない手段）
```bash
cd /Users/keyness/Developer/hot-retro-term
codex "<下記テンプレを貼る>"        # 対話モード
codex exec "<下記テンプレを貼る>"   # 非対話・投げっぱなし
```

## タスク委任プロンプトのテンプレ

`<ID>` を差し替えて使う。タスクファイルが自己完結なので、これだけで動く。

```
リポジトリ /Users/keyness/Developer/hot-retro-term で Windows 移植タスクを1件実行して。

1. まず windows-plan/TASKS.md と windows-plan/tasks/<ID>-*.md を読み、
   TASKS.md の該当行の status を in-progress に書き換えること（着手宣言）。
2. タスクファイルの「手順」に従って実装する。「対象ファイル」欄に無いファイルの変更は禁止。
3. 鉄の掟:
   - POSIX（macOS/Linux）側の挙動を一切変えない。変更は #ifdef Q_OS_WIN / if(WIN32) の
     内側か、タスクファイルが明示した箇所だけ。POSIX側の既存コードは1バイトも書き換えない。
   - git commit はしない。working tree に diff を残すだけ。
   - このマシンは macOS。C++/CMake を触ったら mac 側ビルドが壊れていないことを確認する。
     ビルドコマンドの正（cmake は PATH に無い・Qt は x86_64/Rosetta なので必ずこの形。
     タスクファイル内の `cmake -B build ...` 表記はすべてこれに読み替える）:
       /Applications/CLion.app/Contents/bin/cmake/mac/aarch64/bin/cmake -B build -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_PREFIX_PATH=/usr/local
       /Applications/CLion.app/Contents/bin/cmake/mac/aarch64/bin/cmake --build build -j
     （QMLのみの変更なら省略可）
   - qmltermwidget/ は **2026-07-19 に vendor 化済み**（通常のトラッキング対象。旧サブモジュール制約は消滅）。
     KDSingleApplication/ だけは今もサブモジュール — そちらは触らない。
4. 完了したら windows-plan/TASKS.md の該当行の status を review に書き換え、
   末尾の作業ログに1行（日付 / ID / 要約 / 検証結果）を追記する。
   done にするのは監査役の仕事なので、あなたは done にしない。
5. 最後に報告: 変更ファイル一覧、各変更の要約、実行した検証とその結果。
   完了条件を満たせなかった場合は、status を in-progress のままにして、何が残っているかを報告する。
```

## 運用ルール

- **1回の委任 = 1タスク。** まとめて渡さない。タスク境界＝復元ポイントであり、
  Usage Limit で切れても TASKS.md を見れば正確に再開できる状態を常に保つ。
- **Codex の報告を鵜呑みにしない。** status=review になったら必ず監査サブエージェント
  （`audit-instructions.md`）を起動し、PASS するまで次のタスクへ進まない。
- **Codex が途中で死んだ場合**: status が review に達していなければ未完扱い。
  「--resume で続き」で再開するか、`git checkout -- <files>` で巻き戻して「--fresh で」。
- **CI 待ちのタスク（A8/B4）**: push は人間か Claude が行う（Codex は commit 禁止のため）。
  CI の失敗ログを貼って「--resume で続き」を回すのが最短ループ。
- **サブモジュール制約 → 解消済み（2026-07-19）**: ユーザー判断により qmltermwidget を **vendor 化**
  （コミット ddda1c1。upstream/ローカル履歴の出自はコミットメッセージと .git/modules/qmltermwidget に保全）。
  以後 qmltermwidget/ の diff は親リポジトリの通常 diff として扱い、監査 PASS 後のコミットにコードを含める。
  A8 の前提は満たされた。KDSingleApplication のみ引き続きサブモジュール。
