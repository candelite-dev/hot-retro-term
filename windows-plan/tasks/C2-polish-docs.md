# C2: 磨き — デバッグショートカット + README

- Phase: C（磨き＆配布）
- 依存: なし（いつでも実行可。ただし README の記述は A8/B4 確定後が正確）
- 対象ファイル: `app/qml/PaneTreeNode.qml`、`README.md`
- mac検証: 可（QML は mac でも動作確認できる）

## ゴール

Windows で问题になる細部2点: ① Win キー衝突するデバッグショートカット、② Windows ビルド手順のドキュメント化。

## 手順

1. **PaneTreeNode.qml:184 付近** — ハードコードの `Meta+Shift+D`（Windows では Win+Shift+D で OS 予約領域と衝突）:

```qml
sequence: appSettings.isMacOS ? "Meta+Shift+D" : "Ctrl+Shift+F12"
```

   ※ `appSettings` がそのスコープで見えるかを周辺コードで確認（PaneTreeNode 内の既存参照に倣う）。
   ※ **QML 変更の後は `touch app/resources.qrc` してからビルド**（このリポジトリの既知のビルド罠: QML は qrc 埋め込みで、qrc を touch しないと再ビルドに取り込まれないことがある）。

2. **README.md** に Windows 節を追加:
   - 要件: Windows 10 1809+（ConPTY）、Qt 6.10+（`qt5compat` + `qtshadertools` モジュール）、MSVC 2022、Ninja
   - ビルド: `cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build --parallel`
   - 配置: `cmake --build build --target deploy_windows`（windeployqt 一式）
   - **Ninja（single-config）必須**の注意: Visual Studio ジェネレータだと出力に `/Release` が付いて QML プラグインの相対配置が崩れる
   - 既知の制約: GUI サブシステムのため `--help`/`--version` はコンソールに出力されない / デフォルトシェルは `%COMSPEC%`（cmd.exe）、PowerShell/WSL は Settings → カスタムコマンドで `powershell` や `wsl.exe` を指定 / 文字化けする子プログラムは `chcp 65001`
   - 該当があれば FAQ に ConPTY 由来の挙動を追記

## 完了条件

- [ ] mac で `touch app/resources.qrc && cmake --build build -j` → アプリ起動 → mac 側ショートカット（Meta+Shift+D）が従来どおり
- [ ] README の手順が A8/B4 で実際に通った手順と一致している（絵空事を書かない）
