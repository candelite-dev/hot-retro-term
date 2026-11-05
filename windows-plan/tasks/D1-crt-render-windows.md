# D1: Windows で端末内容が描画されない（CRT 描画パイプライン バグ調査）

- Phase: D（実機検証で発覚したバグ。Phase A〜C は実装・CI 完了済み、これは実機 GUI での実挙動バグ）
- 依存: B4（実機で起動する状態）
- 対象ファイル: 未確定（調査タスク）。有力なのは `app/qml/PreprocessedTerminal.qml`（ShaderEffectSource `kterminalSource`）、`qmltermwidget/lib/TerminalDisplay.cpp`（QQuickPaintedItem の paint/updateImage）、`app/qml/ShaderTerminal.qml` + `app/shaders/*`（CRT シェーダー/.qsb）、`app/qml/TimeManager.qml`（描画駆動）
- mac検証: 描画は不可（mac は正常動作）。**唯一の観測点はユーザーの物理ディスプレイ**（下記）

## 症状（2026-07-21 実機で確認）

Windows 実機（直結モニター、RTX 3070 Ti、3440×1440、スケーリング100%）で cool-retro-term を起動すると:
- ウィンドウ・ベゼル（CRT フレーム）・タイトルバー・アイコン（crt.ico）は**正常に描画される**
- **端末の内容（cmd のバナー/プロンプト/入力エコー）が一切描画されない**。CRT スクリーン部は黒いまま
- 画面には**静止した白い矩形が1つ**だけ（約36文字×1.5行ぶんの単色白ブロック。琥珀色に着色されていない＝CRT のカラー着色も乗っていない）
- **入力しても画面は一切変化しない**。効果（Flickering/StaticNoise）を上げても**チラつき一つ起きない**＝初回1フレーム以降まったく再描画されていない

**重要**: 端末バッファには内容が存在する（**全選択→コピーでクリップボードに端末内容が取れる**）。つまり **PTY・VT102 エミュレーション・Screen バッファは正常。純粋に「描画されない」バグ**。

## 切り分け済み（証拠付きで除外されたもの）

1. **PTY/ConPTY/エミュレーション**: 正常（内容がコピーできる。B1〜B3 で ConPTY 入出力も実証済み）
2. **フォント**: 正常。バンドルフォント（Terminess/Hack/FiraCode Nerd Font Mono）は Windows/DirectWrite で等幅・非ゼロ幅と実測（FontLoader+TextMetrics プローブで M幅=i幅・>0 を確認）。「variable-width font」警告は Nerd Font の pitch フラグ由来の良性警告（実グリフは等幅）
3. **スクリーン/DPI メトリクス**: 正常。`Screen.devicePixelRatio=1`、`3440x1440`、`pixelDensity=4.31`（正）。仮想モニターは Qt から見えず SCREEN_COUNT=1
4. **描画スロットル/ゲーティング**: **無罪**。`TimeManager.frameDriver` を `running: true` に強制連続化してビルドしても端末は出ない。効果を上げても再描画されない＝`time` 駆動でも内容駆動でも1フレーム以降描画されない
5. **低解像度フォントの FBO 引き伸ばしパス**: 無関係。非 lowRes フォント（Hack、`screenScaling=1`）でも同症状

## 有力仮説

**QQuickPaintedItem（`qmltermwidget` の TerminalDisplay = `kterminal`）→ ShaderEffectSource（`kterminalSource`, `live:true`）のキャプチャが Windows RHI/D3D11 で空テクスチャを生んでいる。** ベゼル/フレームは別シェーダー（`terminal_frame`）で描画されるため出るが、端末内容を運ぶ ShaderEffectSource→CRT シェーダー経路だけが終端の絵を出せていない。

副次仮説（要検証）:
- QQuickPaintedItem の `renderTarget`（Image vs FramebufferObject）が RHI/D3D11 で ShaderEffectSource から読めない
- 端末が実際には paint() されていない（paint 呼び出しか、描画先サーフェスの問題）
- CRT シェーダー（`terminal_dynamic/static.frag` の .qsb 焼き込み HLSL）の変種が D3D11 でテクスチャを正しくサンプルできない（HLSL register/binding 不整合）
- スレッド化レンダーループが初回フレーム後に停止/デッドロック（起動時に**タイミング依存のフリーズ**も観測されており、初期化順のレースが疑われる）

**副次バグ（別途・低優先）**: `kterminal.terminalSize` の桁/行が入れ替わって報告される。実測 `parentPx≈1644x1274` / `ktermPx≈1610x1240` / セル `14x30` に対し、本来 114桁×41行のところ `terminalSize=41x114`（width=行, height=桁）。描画バグとは別の QSize 軸順問題。

## 調査環境と観測方法（重要）

- **SSH の実機（ホスト `windows`）はセッション0のヘッドレスで、GUI が可視にならないため描画ループが止まり、描画バグを再現できない**（プロセスは動くが絵は観測不可）。過去タスクの「実機スモーク」は全てプロセス生存/子プロセス確認どまりで、**描画は誰も見ていなかった**（これが Phase B で見逃された理由）。
- **観測はユーザーの物理ログオンのみ**。手順:
  - スクショ: `C:\crt-setup\shot.ps1`（`powershell -ExecutionPolicy Bypass -File C:\crt-setup\shot.ps1` → `C:\crt-setup\screen.png`）をユーザーが実行 → オーケストレータが `scp` で回収して目視
  - ランタイム値ダンプ: QML に一時 `fileIO.write("file:///C:/crt-setup/xxx.txt", ...)` を仕込む（`fileIO` は context property で全域可視。`console.log` は GUI subsystem では stderr に乗らないので `fileIO` 経由が確実）
  - 実機ビルド: `C:\crt-setup\build.cmd`（vcvars→cmake Ninja→build）。**QML 変更時は先に `C:\crt\src\app\qml\resources.qrc` を touch**（RCC 再実行のため）。**ビルド前にアプリを kill**（起動中だと LNK1104 で exe 上書き失敗）
- Qt: `C:\Qt\6.10.3\msvc2022_64`。既定 RHI は D3D11。`QSG_INFO=1` / `QT_LOGGING_RULES=qt.rhi.*=true` でシェーダー/RHI ログ（ただし GUI subsystem の stderr 捕捉は要 `-RedirectStandardError`）

## 進め方（調査 → 候補修正 → 実機検証ループ）

これは**盲目実装ではなく調査優先**。Codex は:
1. 描画パイプライン（PreprocessedTerminal の `kterminalSource`、ShaderTerminal、TerminalDisplay の QQuickPaintedItem 描画、CRT シェーダーの texture sampling）を読み、**「なぜ QQuickPaintedItem→ShaderEffectSource キャプチャが D3D11 で空になるか」の仮説をランク付け**する
2. **最小の切り分け実験**を提案する。例: kterminal を**シェーダーを迂回して直接 visible 描画**する一時変更で「QQuickPaintedItem が Windows で paint しているか（=絵が出るか）」を isolate（出れば shader/source 問題、出なければ painted item 問題）
3. 候補変更は**1つずつ小さく**。実機検証（オーケストレータがビルド＋ユーザーが目視）が唯一の確認手段なので、1往復で最大の情報が得られる変更にする
4. **POSIX（mac/Linux）側の挙動を壊さない**。修正は Windows でも mac でも成立する形（RHI 共通 API）で。`#ifdef Q_OS_WIN` の QML 等価物が要る場合は既存の `appSettings.isMacOS` 等のパターンに倣う

## 完了条件

- [ ] Windows 実機で cmd.exe のプロンプト/出力が CRT シェーダー越しに描画される
- [ ] 入力エコー・出力更新がリアルタイムに描画される
- [ ] mac/Linux で無退行（描画・CRT 効果が従来どおり）
- [ ] （副次バグ）terminalSize の桁/行入れ替わりも直せれば直す（別コミット可）
