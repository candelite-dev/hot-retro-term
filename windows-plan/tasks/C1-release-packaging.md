# C1: release.yml に zip パッケージング追加 【Phase C ゲート】

- Phase: C（磨き＆配布）
- 依存: B4
- 対象ファイル: `.github/workflows/release.yml`、新規 `scripts/package-windows.ps1`
- mac検証: 不可（CI）。push/タグ打ちは人間/Claude。

## ゴール

リリース時に `cool-retro-term-win64.zip` を成果物として吐く。AppImage（Linux）/ DMG（macOS）と並ぶ第3の配布物。NSIS/MSIX インストーラは**やらない**（明示的にスコープ外、必要になったら別タスク）。

## 背景

release.yml は現在 ubuntu-22.04 で AppImage、macos-14 で DMG を作る2ジョブ構成。Windows ジョブは B4 のビルド+deploy を流用し、ステージ済みディレクトリを zip するだけ。

## 手順

1. **scripts/package-windows.ps1** 新規作成:

```powershell
param(
    [string]$BuildDir = "build",
    [string]$OutZip   = "cool-retro-term-win64.zip"
)
$ErrorActionPreference = "Stop"
$stage = Join-Path $BuildDir "stage"
New-Item -ItemType Directory -Force -Path $stage | Out-Null

# exe + windeployqt が配置した一式 + QML プラグイン
Copy-Item (Join-Path $BuildDir "cool-retro-term.exe") $stage
foreach ($d in @("plugins", "qml", "qmltermwidget")) {
    $src = Join-Path $BuildDir $d
    if (Test-Path $src) { Copy-Item $src (Join-Path $stage $d) -Recurse }
}
Copy-Item (Join-Path $BuildDir "*.dll") $stage -ErrorAction SilentlyContinue

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $OutZip -Force
Write-Host "Packaged -> $OutZip"
```

   ※ windeployqt の実際の出力レイアウト（`plugins/` か直下か、`qml/` の位置）は B4 の artifact を見て**実物に合わせて調整**する。この script が正本、CI からは1行で呼ぶ。

2. **release.yml** に windows ジョブ追加: A8/B4 の setup（checkout+submodules / install-qt-action 6.10 / msvc-dev-cmd / Ninja configure+build / deploy_windows）をコピーし、最後に:

```yaml
      - name: Package
        shell: pwsh
        run: ./scripts/package-windows.ps1
      - name: Upload release asset
        # 既存ジョブが AppImage/DMG をリリースに添付しているのと同じ方式に合わせる
```

   ※ 既存2ジョブのリリース添付方法（`softprops/action-gh-release` か `gh release upload` か）を確認し、**同じ方式**で `cool-retro-term-win64.zip` を追加。

## 完了条件

- [ ] タグ push（またはworkflow_dispatch）で zip がリリース成果物に並ぶ
- [ ] zip を**クリーンな Win10 1809+ VM**（Qt なし）に展開 → 起動して cmd.exe が動く
- [ ] Explorer/タスクバーにアイコン（crt.ico）が表示される
