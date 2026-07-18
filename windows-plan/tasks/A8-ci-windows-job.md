# A8: CI windows-latest ジョブ追加 + Qt 6.10 統一 【Phase A ゲート】

- Phase: A（コンパイルゲート — このタスクの緑が Phase A 完了）
- 依存: A1〜A7 すべて
- 対象ファイル: `.github/workflows/build.yml`
- mac検証: 不可（push → GitHub Actions で判定）。**push は人間/Claude が行う（Codex は commit 禁止）**

## ゴール

GitHub Actions に MSVC + Ninja の Windows ビルドジョブを追加し、A1〜A7 の Windows 側コンパイルエラーを洗い出して潰す。同時に既存ジョブの Qt バージョン食い違いを是正する。

## 背景

- 現状の build.yml は ubuntu-22.04/24.04 + macos-latest のみ。しかも **Qt `6.7.*` を指定**（:25 付近）しており、ルート CMakeLists の `find_package(Qt6 6.10 REQUIRED)` と矛盾している（release.yml は 6.10.0 で正しい）。
- このタスクは「一発で緑」を期待しない。**A1〜A7 の Windows 側の綻び（MSVC の細かい非互換）がここで初めて可視化される**。CI ログ → 修正 → push の反復が本体。修正が特定タスクの領分（例: PtyWin.h の構文）なら該当ファイルを直してよいが、修正内容を作業ログに残すこと。

## 手順

1. 既存ジョブの Qt 指定を `6.10.*` に統一。
2. windows ジョブを追加:

```yaml
  build-windows:
    name: Windows (MSVC)
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: jurplel/install-qt-action@v4
        with:
          version: '6.10.*'
          arch: win64_msvc2022_64
          modules: 'qt5compat qtshadertools'
          cache: true
      - uses: ilammy/msvc-dev-cmd@v1
      - name: Configure
        run: cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_COMPILE_WARNING_AS_ERROR=OFF
      - name: Build
        run: cmake --build build --parallel
      - name: Check outputs exist
        shell: pwsh
        run: |
          if (!(Test-Path build\cool-retro-term.exe)) { throw "exe missing" }
          if (!(Test-Path build\qmltermwidget\QMLTermWidget\qmltermwidget.dll)) { throw "plugin dll missing" }
```

   ※ actions のバージョンや checkout の流儀は**既存 build.yml の他ジョブに合わせる**。exe/dll の出力パスが違ったら実ログで確認して修正（single-config Ninja なら `${CMAKE_BINARY_DIR}` 直下と plugin 出力ディレクトリのはず）。
   ※ 起動スモークとwindeployqt は**ここではやらない**（B4）。Phase A はコンパイル+リンク+成果物存在まで。

3. push → 3系統（ubuntu/macos/windows）の結果を確認。Windows の失敗はログを読み、原因タスクのファイルを修正して再push（このループは「--resume で続き」で回すのが効率的）。

## 完了条件

- [ ] windows job 緑（Configure/Build/成果物チェックまで）
- [ ] **ubuntu / macos job が緑のまま**（Phase A の無リグレッションゲート）
- [ ] build.yml 内の Qt バージョンがすべて 6.10.* に統一
