# inbox — Human Investigation 待ち隔離場所

監査で **SUSPICIOUS** 判定になった成果物（または FAIL が3周続いた案件）の隔離場所。
**このフォルダに未解決の report がある間、該当タスクの PR・コミットは禁止。**

## 運用

1. 監査役が置く: `<YYYY-MM-DD>-<ID>.patch`（`git diff` の保全）+ `<YYYY-MM-DD>-<ID>-report.md`
2. TASKS.md の該当タスクは `needs-human` にする（メインエージェントが設定）
3. 人間が調査し、いずれかで解消:
   - **白**: report に所見を追記 → report/patch を削除 → status を `review` に戻して監査を再実行
   - **黒/グレー**: `git checkout -- <files>`（+未追跡ファイル削除）で巻き戻し → status を `todo` に戻す。
     必要ならタスクファイルの手順や codex-workflow の掟を改訂してから再委任
4. 解消したら TASKS.md 作業ログに結果を1行

## report テンプレ

```markdown
# <ID> Human Investigation Report

- 日付: YYYY-MM-DD
- タスク: <ID> <タスク名>
- 判定: SUSPICIOUS / FAIL×3
- 実装: Codex (gpt-5.6-sol) / 監査: Fable subagent

## 不審点（根拠を具体的に）
- <file:line> — 何が・なぜ不審か

## 保全物
- <YYYY-MM-DD>-<ID>.patch（git diff スナップショット）
- （未追跡ファイルがあればそのコピー）

## 監査役の推奨アクション
- 巻き戻し / 部分採用 / 白と思われるが要確認 等

## 人間の所見（調査後に記入）
-
```
