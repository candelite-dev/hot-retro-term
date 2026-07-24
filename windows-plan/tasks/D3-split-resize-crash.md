# D3: Split中の連続ウィンドウリサイズでクラッシュ（0xC0000005 / nvwgf2umx.dll）

- Phase: D（実機検証で発覚したバグ）
- 依存: D1（描画が動く状態）。D2（WSL入力バグ、in-progress）とは無関係の別系統
- 対象ファイル: 未確定（調査タスク）。有力候補:
  - `app/qml/PaneLayout.qml`（`crtContent`/`unifiedPaneSource`/`unifiedCRT` — 統合CRTキャプチャの中心）
  - `app/qml/ShaderTerminal.qml`（`Loader{active:!splitActive}` 配下の `dynamicShader`/`staticShader`/`frameBuffer`/`noiseShaderSource` チェーン）
  - `app/qml/SplitTreeModel.qml`（`computePaneRects`/`computeSplitBoundaries` — リサイズの度に全ペイン再計算）
  - `app/qml/PreprocessedTerminal.qml`（`kterminal` の width/height 計算、`onWidthChanged`/`onHeightChanged` → `updateSources()`）
  - qmltermwidget側（`TerminalDisplay.cpp` のQQuickPaintedItemサイズ変更経路）は現時点で根拠薄いが除外はしない
- mac検証: 描画/リサイズの実挙動は不可（mac は正常）。**観測はユーザーの物理ディスプレイのみ**（D1/D2 と同じ手段）
- **重要な注意**: 2026-07-21 時点で working tree に **D2 の未コミット診断計装が5ファイル残っている**（`app/qml/TerminalWindow.qml`, `qmltermwidget/lib/PtyWin.cpp`, `qmltermwidget/lib/TerminalDisplay.cpp`, `qmltermwidget/lib/Vt102Emulation.cpp`, `qmltermwidget/lib/D2InputTrace.h`〈新規〉）。これは D2 の作業であり D3 とは無関係。**触らない・commit に巻き込まない**。D3 の調査で上記ファイルに変更が必要になった場合は、先に `git diff -- <file>` で D2 分の既存差分を確認し、自分の変更と混同しないこと（D2 diff は全て純追加、diffstat は TASKS.md 作業ログ2026-07-21付「D2 起票」以降のエントリ参照）。

## 症状（2026-07-25 実機で確認、ユーザー本人が実機で直接観測）

Windows 実機の cool-retro-term で **Split 状態のままウィンドウサイズを連続的に変更するとアプリのプロセスごと消える（クラッシュ）**。

- **再現手順**: 左右2分割 → 右側をさらに上下2分割（L字型3ペイン構成）。この状態で **komorebi**（タイリングウィンドウマネージャ、外部ツール）が cool-retro-term のウィンドウを自動的に連続リサイズした際に発生。人間が枠をドラッグする通常のリサイズとは異なり、komorebi は `SetWindowPos` 相当のAPIでプログラム的・断続的でない連続リサイズをかけると推測される。
- **再現頻度・タイミング**: 不明（何回目のリサイズで起きるか未特定、常に起きるか偶発かも未確認）。
- **証跡（イベントビューアーに記録あり）**: 例外コード **`0xC0000005`（STATUS_ACCESS_VIOLATION）**、フォールティングモジュール **`nvwgf2umx.dll`**（NVIDIA の D3D11/D3D12 ユーザーモードドライバ本体）。実機GPUは plan.md 記載の RTX 3070 Ti と整合。

## 手がかり（オーケストレータの初期調査）

- **D1 との類似性**: D1（`tasks/D1-crt-render-windows.md`）の根本原因は「`QQuickPaintedItem`→`ShaderEffectSource` キャプチャが D3D11 RHI で壊れる」という、Windows の RHI バックエンド特有の脆さだった（sampler binding 衝突で発覚）。今回もフォールティングモジュールが NVIDIA の **D3D11 UMD 内部**であり、Qt/アプリコードではなくグラフィックスドライバのユーザーモード側で AV が起きている＝**RHI のテクスチャ（再)生成・破棄まわりで異常な呼び出しパターンを踏んでいる**という仮説が最有力。GL(Linux)/Metal(mac) では同種の資源管理バグが表面化していない可能性がある（D1と同じ構図）。
- **リサイズ経路に一切のデバウンス/スロットルが無い**: `app/qml/TerminalWindow.qml`, `PaneLayout.qml`, `TerminalTabs.qml`, `TerminalContainer.qml`, `ShaderTerminal.qml` を検索した限り、リサイズに対する Timer 等の間引き機構は存在しない。`PreprocessedTerminal.qml:108-114` の `onWidthChanged`/`onHeightChanged` は毎回即 `terminalContainer.updateSources()`（`kterminal.update()`）を呼ぶ。`SplitTreeModel.qml:275-289` の `computePaneRects` はリーフノードに到達する度に **無条件の `console.log("[RECT]", ...)`（277-279行目）を出力**しており、これはリサイズの度に全ペイン分再帰実行されるホットパスに残った検証用ログと見られる（クラッシュの直接原因とは考えにくいが、「このパスがリサイズの度に無条件で高頻度実行される」ことの傍証。ついでに掃除してよい）。
- **Split中のGPUリソース構成**: `ShaderTerminal.qml:58-60` の `Loader{active:!splitActive}` により、split中は各ペイン個別のCRTエフェクトチェーン（`dynamicShader`/`staticShader`/`frameBuffer`/`noiseShaderSource`/`terminalFrameLoader`）は**アンロードされる**ため、ペイン数分の重複テクスチャは無い（3ペインでも1ペインでもここは同じ）。一方 `PaneLayout.qml:161-169` の `unifiedPaneSource`（`crtContent` 全体をキャプチャ）と、`unifiedCRT`（`splitActive: false` で自身は上記チェーンをフル稼働、PaneLayout.qml:173-189）は**ウィンドウサイズに直結して毎回リサイズされる単一の重い経路**。加えて各ペインの `kterminal`（`QQuickPaintedItem` 系、`PreprocessedTerminal.qml:121-146`）も個別に width/height 変更ごとに自前のテクスチャを再構成する。**1回のリサイズ tick で `crtContent`/`unifiedPaneSource`/`frameBuffer`/`staticShader`ターゲット/`dynamicShader`ターゲット + ペイン数分の`kterminal`テクスチャが同時に再生成される**構造で、komorebi のように人間のドラッグより高頻度・無間隔でリサイズイベントが来た場合にRHIのテクスチャ再生成が詰まる／競合する余地がある。
- **ゼロサイズ境界の可能性**: `PaneLayout.qml:112-115` の `paneSlot`（`Math.round(rectData.w * paneStack.width)` 等）には最小値ガードが無い。一方 `PreprocessedTerminal.qml:130-131` の `kterminal` 本体サイズは `Math.max(1, ...)` で下限ガードされている。ウィンドウ自体がリタイル中に一瞬 0 に近いサイズを経由する場合（komorebi のリフロー挙動次第）、`crtContent`（`anchors.fill: parent` で `paneLayout` 全体を覆う）経由で `unifiedPaneSource` が極小/ゼロサイズのテクスチャ確保を要求する可能性があり、これが D3D11 UMD 側の異常系（未検証）を踏んでいる可能性がある。
- **スレッド境界の可能性**: Qt Quick の既定（threaded）レンダーループでは GUI スレッドと RenderThread が並行動作する。komorebi 由来の高頻度リサイズで GUI スレッドのジオメトリ更新が RenderThread のテクスチャ確保/描画コマンド発行を追い越すレース（解放済み/差し替え中のリソース参照）も、ドライバ内AVの典型的な原因パターンとして排除できない。

## 観測方法（D1/D2 と同じ基盤 + クラッシュダンプ取得を追加）

- **SSHセッション0はヘッドレスで観測不能。実機の実挙動はユーザー物理ディスプレイでのみ確認**（D1/D2 と同じ制約）。
- 実機ビルド: `C:\crt-setup\build.cmd`（QML変更時は先に `C:\crt\src\app\qml\resources.qrc` を touch、ビルド前にアプリ kill）。
- スクショ: `C:\crt-setup\shot.ps1`。
- **新規: クラッシュダンプの取得を最優先で試みる**。ドライバ内AVは推測だけでは埒が明かないため、次のいずれかで実際のクラッシュ時コールスタックを取得する:
  - WER の `LocalDumps` をレジストリ設定（`HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps`）してフルダンプを自動収集
  - もしくは `cdb`/WinDbg をアタッチした状態で komorebi 配下で再現を待つ（plan.md 記載の観測ツールに `cdb アタッチ` は既存項目）
  - 取得したダンプは `nvwgf2umx.dll` 側のスタックだけでなく、**Qtアプリ側の呼び出し元フレーム**（どのQMLアイテム/どのRHI呼び出し経由か）まで遡れるか確認する
- komorebi は再現の鍵になるツールなのでユーザー環境に導入済みとして扱ってよい。Codex は「komorebiを使わずに同じ入力パターン（高頻度・無間隔の連続リサイズ）を人工的に作る」代替手段（スクリプトで `SetWindowPos` を連打する、または komorebi の設定でこのウィンドウだけ手動リタイルさせる等）も再現手順の一部として検討してよい。

## 進め方（調査 → 切り分け → 候補修正 → 実機検証ループ）

Codex は盲目実装せず、以下の順で進める。1往復で最大の情報が得られる調査を優先する。

1. **まずクラッシュダンプ取得を試みる**（上記観測方法）。ドライバ内AVの正確なコールスタックが取れれば、以降の仮説検証が大幅に効率化する。実機作業はユーザーとの1往復が必要なので、ダンプ取得用のセットアップ手順（LocalDumpsレジストリ設定 or cdbアタッチコマンド）を最初の指示としてまとめる。
2. **静的仮説の検証**: 上記「手がかり」の各仮説（ゼロサイズ境界、リサイズ無間引き、RenderThreadとのレース）についてコードを追加調査し、優先順位をつける。
3. **切り分け実験**: D1で使った「Windows限定でCRTを迂回し生kterminalを直接描画する」実験（`PreprocessedTerminal.qml` の `hideSource` と `ShaderTerminal.qml` の `Loader.active` を `Qt.platform.os!=="windows"` 等で一時ガード）を応用し、統合CRTキャプチャ（`unifiedPaneSource`/`ShaderTerminal`チェーン）を外した状態で同じリサイズ嵐がクラッシュを再現するか確認する。再現しなければRHI/ShaderEffectSource経路の濃厚な証拠、再現すれば別経路（ConPTYリサイズの多重呼び出し等）を疑う。
4. **候補修正**: 実機ログ/ダンプの結果に応じて、例えば以下を検討（あくまで例、証拠に基づいて選ぶこと）:
   - リサイズイベントのデバウンス/コアレス（短いTimerで最終サイズのみ反映）
   - `unifiedPaneSource`/`crtContent` 系に最小サイズガード（`Math.max(1, ...)`)を追加
   - `SplitTreeModel.qml:277-279` の不要な `console.log` 除去（ついでの掃除、根本原因ではない可能性が高い）
   - Windows限定でリサイズ中のCRTキャプチャを一時停止する等のRHI都合の回避策
5. working tree に diff を用意（commit しない）。オーケストレータが実機ビルド+ユーザーによるkomorebi連続リサイズ再現テストで検証する。

## 完了条件（Windows 実機）

- [ ] L字型3ペイン構成（左右分割→右を上下分割）で、komorebiによる連続リサイズを一定時間/回数（目安: 5分間 or 50回相当）継続してもクラッシュしない
- [ ] 2ペイン単純split、4ペイン（グリッド）等、他の分割構成でも同様に無退行を確認
- [ ] イベントビューアーに `0xC0000005` / `nvwgf2umx.dll` の再発が無いことを確認
- [ ] mac/Linux でCRT/split機能に無退行

## 2026-07-25 Codex 静的再調査（実機での検証待ち）

### 仮説判定と優先順位

1. **D3D11 RHI / ShaderEffectSource 経路の脆さ — supported（優先度1）**
   Split時は `needsUnifiedCRT` が真になり（`SplitTreeModel.qml:43-48`）、`crtContent` 全体を
   `unifiedPaneSource` が live capture し、その出力を `unifiedCRT` が受ける
   （`PaneLayout.qml:172-205`）。後段は `dynamicShader`、`staticShader`、
   `frameBuffer`、任意のframe/bloom用 `ShaderEffectSource` を持つ
   （`ShaderTerminal.qml:58-195`）。さらに D1 で Windows の部分更新だけ
   ShaderEffectSource 再キャプチャを誘発しなかった既知差分が残る
   （`TerminalDisplay.cpp:2034-2046`）。したがってフォールティングモジュールが
   `nvwgf2umx.dll` である事実と最も整合する。ただし今回のAVの因果はダンプ未取得のため
   **実機での検証待ち**。
2. **unifiedPaneSource 等がリサイズごとに全体再生成 — inconclusive（優先度2）**
   `crtContent` は親をfillし（`PaneLayout.qml:64-66`）、`unifiedPaneSource.live` と
   `unifiedCRT` の全面anchors、`staticShader.width/height` がウィンドウ寸法に追随する
   （`PaneLayout.qml:172-209`, `ShaderTerminal.qml:158-195`）ため、フレームに取り込まれた
   サイズ変更では複数の全面テクスチャが関与する。一方、実際に各Windowsサイズイベント
   ごとに全GPU資源が破棄・再生成されるかはQt RHI内部でありコードからは確定できない。
   また `_paneRects` のbindingはtreeだけに依存し（`PaneLayout.qml:54-57`）、
   `computePaneRects()` 自体はウィンドウ寸法を読まない（`SplitTreeModel.qml:275-317`）。
   よって「`[RECT]` がリサイズtickごとに出る」という初期推測は **refuted**。
3. **アプリ側にリサイズのデバウンス/コアレスが無い — supported（優先度3）**
   QMLはwidth/height変更のたび直接 `kterminal.update()` を要求する
   （`PreprocessedTerminal.qml:105-119`）。C++もgeometry変更ごとに
   `resizeEvent()` と `update()` を呼び（`TerminalDisplay.cpp:3768-3775`）、
   文字画像を再確保・コピー・解放する（同`:2081-2114`）。行列数が変わればSessionから
   `ResizePseudoConsole()` まで同期的に到達する（`Session.cpp:485-522`,
   `PtyWin.cpp:132-137`）。ただし `QQuickPaintedItem::update()` は即時paintでなく次frameへの
   scheduleであり、Qt側のframe単位コアレスはある。従って無条件Timer追加より先に、
   優先度1のバイパス比較とダンプ取得を行う。
4. **paneSlot / unified source の最小サイズガード欠如がゼロ寸法を踏む — inconclusive（優先度4）**
   元コードのpaneSlotは丸め値をそのまま使い、unified sourceにも有効寸法条件が無かった
   （今回の `PaneLayout.qml:37-38,121-126,172-202` のWindows限定ガードが追加差分）。
   ただしkterminal側は既に1px下限（`PreprocessedTerminal.qml:130-136`）、C++の端末行列も
   1x1下限（`TerminalDisplay.cpp:3486-3495`）、Sessionは2行2列未満をConPTYへ送らない
   （`Session.cpp:501-521`）。komorebiが実際に0pxを通知した証跡もまだ無いので、
   直接原因とは確定できず **実機での検証待ち**。
5. **GUIスレッドがRenderThreadを追い越すアプリ起因レース — refuted（優先度5）**
   アプリはrender loopを強制せず（`app/main.cpp:43-52`）、独自のscene graph同期処理や
   native graphics commandも持たない。Qtのthreaded render loopは同期フェーズでGUI threadを
   blockし、`QQuickPaintedItem::paint()` 中もGUI threadをblockする契約なので、
   コードから「GUIが追い越して解放済み資源を直接触る」経路は見つからない。
   Qt RHIまたはNVIDIAドライバ内部のレースまでは否定できないため、これはダンプの
   render-thread stackで再評価する。

補足: `TerminalDisplay.cpp:484-486` は `FramebufferObject` を指定するが、Qt 6.9以降は
OpenGL以外ではこの指定が無視される公式仕様である。Qt 6.10/D3D11上のkterminalを
「ハードウェアFBOそのもの」とみなす初期推測は不正確。ただしQImageからGPU textureへの
uploadと、その後のShaderEffectSource captureは残る。

- Qt公式: <https://doc.qt.io/qt-6/qquickpainteditem.html>
- Qt公式: <https://doc.qt.io/qt-6/qml-qtquick-shadereffectsource.html>
- Qt公式: <https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph.html>

### Working tree の切り分け実験と候補修正

- `PaneLayout.qml:32-38` の `_d3BypassUnifiedCRT` はWindowsでだけtrueになる一時実験フラグ。
- Windowsでは `unifiedPaneSource.sourceItem=null`、`live/hideSource=false` とし、
  `unifiedCRT.splitActive=true` で `ShaderTerminal.Loader` をアンロードする。
  unified burn-in/bloomも停止する。split中の各paneは既存の
  `PreprocessedTerminal.qml:443-455` の直接描画経路で生kterminalを表示する。
- `paneSlot` をWindowsのみ1px以上にし、unified source寸法が1px未満ならcapture chainを
  切り離す。POSIX側は元の式・有効条件のまま。
- `SplitTreeModel.qml:275-282` の `[RECT]` はリサイズhot pathではなかったが、
  Windowsだけ出力を止めた。POSIXの診断出力は維持。
- この実験でクラッシュしなければ unified ShaderEffectSource / ShaderTerminal chain が
  濃厚。クラッシュすれば、生kterminalのtexture upload、TerminalDisplayのCPU再確保、
  ConPTY resize、または別のwindow-level effectを次に切り分ける。いずれも
  **実機での検証待ち**。

### WER LocalDumps（推奨、管理者PowerShell）

Microsoft公式仕様では `DumpType=2` がfull dump、per-process keyがglobal設定より優先される。
物理ログオン中の **管理者PowerShell** で以下をそのまま実行する。

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$dumpDir = 'C:\crt-setup\dumps'
$werKey = 'HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\cool-retro-term.exe'

New-Item -ItemType Directory -Force -Path $dumpDir | Out-Null
reg.exe add $werKey /v DumpFolder /t REG_EXPAND_SZ /d $dumpDir /f
if ($LASTEXITCODE -ne 0) { throw 'DumpFolder registry setup failed' }
reg.exe add $werKey /v DumpType /t REG_DWORD /d 2 /f
if ($LASTEXITCODE -ne 0) { throw 'DumpType registry setup failed' }
reg.exe add $werKey /v DumpCount /t REG_DWORD /d 10 /f
if ($LASTEXITCODE -ne 0) { throw 'DumpCount registry setup failed' }
reg.exe query $werKey
```

次にD3差分を配置済みのtreeを、同じ物理ログオンのPowerShellでビルド・起動する。

```powershell
Get-Process cool-retro-term -ErrorAction SilentlyContinue | Stop-Process -Force
(Get-Item 'C:\crt\src\app\qml\resources.qrc').LastWriteTime = Get-Date
& 'C:\crt-setup\build.cmd'
if ($LASTEXITCODE -ne 0) { throw 'build.cmd failed' }

$env:QSG_INFO = '1'
$env:QT_LOGGING_RULES = 'qt.rhi.*=true;qt.scenegraph.general=true;qt.scenegraph.time.renderloop=true'
$stdout = 'C:\crt-setup\d3-stdout.txt'
$stderr = 'C:\crt-setup\d3-stderr.txt'
$p = Start-Process -FilePath 'C:\crt\src\build\cool-retro-term.exe' `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$p.Id
```

画面上で左右分割→右を上下分割し、komorebiの連続リタイルを5分または50回相当実行する。
クラッシュ後（または試験終了後）:

```powershell
Get-ChildItem 'C:\crt-setup\dumps' -Filter '*.dmp' |
    Sort-Object LastWriteTime -Descending |
    Format-Table LastWriteTime, Length, FullName -AutoSize
Get-WinEvent -FilterHashtable @{ LogName='Application'; StartTime=(Get-Date).AddMinutes(-30) } |
    Where-Object { $_.Message -match 'cool-retro-term|nvwgf2umx|0xc0000005' } |
    Select-Object TimeCreated, Id, ProviderName, Message |
    Format-List | Out-File 'C:\crt-setup\d3-eventlog.txt' -Width 400
Compress-Archive -Path 'C:\crt-setup\dumps\*' `
    -DestinationPath 'C:\crt-setup\d3-dumps.zip' -Force
```

WER設定を試験後に戻す場合だけ、管理者PowerShellで:

```powershell
reg.exe delete 'HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\cool-retro-term.exe' /f
```

- Microsoft公式: <https://learn.microsoft.com/windows/win32/wer/wer-settings>

### cdb で直接捕捉する代替手順

Windows SDKのDebugging Tools for Windowsが導入済みであることを前提とする。まず通常起動し、
同じ物理ログオンのPowerShellでattachする。

```powershell
$cdb = "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\cdb.exe"
if (-not (Test-Path $cdb)) { throw "cdb.exe not found: $cdb" }
$proc = Get-Process cool-retro-term -ErrorAction Stop | Select-Object -First 1
New-Item -ItemType Directory -Force -Path 'C:\symbols','C:\crt-setup\dumps' | Out-Null
& $cdb -p $proc.Id -lines `
    -y 'srv*C:\symbols*https://msdl.microsoft.com/download/symbols' `
    -logo 'C:\crt-setup\d3-cdb.txt'
```

cdb promptが出たら以下を1行ずつ実行し、`g` 後に画面上で再現する。

```text
.symfix C:\symbols
.sympath+ C:\crt\src\build
.reload /f
sxe av
g
```

AVで停止したら、**再度 `g` は実行せず**次を1行ずつ実行する。

```text
.ecxr
!analyze -v
kP
~* kP
lmvm nvwgf2umx
.dump /ma /u C:\crt-setup\dumps\d3-cdb.dmp
q
```

WER dumpを後から解析する場合は、最新dumpを指定して:

```powershell
$cdb = "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\cdb.exe"
$dump = Get-ChildItem 'C:\crt-setup\dumps' -Filter '*.dmp' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
& $cdb -z $dump.FullName `
    -y 'srv*C:\symbols*https://msdl.microsoft.com/download/symbols' `
    -c '.ecxr;!analyze -v;kP;~* kP;lmvm nvwgf2umx;q' |
    Tee-Object -FilePath 'C:\crt-setup\d3-dump-analysis.txt'
```

- Microsoft公式: <https://learn.microsoft.com/windows-hardware/drivers/debugger/debugging-a-user-mode-process-using-cdb>
- Microsoft公式: <https://learn.microsoft.com/windows-hardware/drivers/debugger/controlling-exceptions-and-events>
- Microsoft公式: <https://learn.microsoft.com/windows-hardware/drivers/debuggercmds/-dump--create-dump-file->

### 任意: komorebiなしのSetWindowPos連打

主試験は既知再現条件のkomorebiを優先する。補助的に、物理ログオンの別PowerShellから:

```powershell
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class D3WindowStorm {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetWindowPos(
        IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
'@
$hwnd = (Get-Process cool-retro-term -ErrorAction Stop |
    Where-Object MainWindowHandle -ne 0 |
    Select-Object -First 1).MainWindowHandle
if ($hwnd -eq 0) { throw 'cool-retro-term window not found' }
for ($i = 0; $i -lt 2000; $i++) {
    $widthPx = if (($i % 2) -eq 0) { 1500 } else { 900 }
    $heightPx = if (($i % 3) -eq 0) { 950 } else { 620 }
    [void][D3WindowStorm]::SetWindowPos(
        $hwnd, [IntPtr]::Zero, 100, 100, $widthPx, $heightPx, 0x0014)
    Start-Sleep -Milliseconds 5
}
```

どの手順も、このmacOSホスト上では実行・確認していない。結果はすべて
**Windows実機での検証待ち**。
