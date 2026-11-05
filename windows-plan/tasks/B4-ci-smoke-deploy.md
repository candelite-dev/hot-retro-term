# B4: windeployqt デプロイターゲット + CI 起動スモーク 【Phase B ゲート】

- Phase: B（ConPTY 実働）
- 依存: B3
- 対象ファイル: `app/CMakeLists.txt`、`.github/workflows/build.yml`
- mac検証: 不可（CI と Windows 実機/VM）。push は人間/Claude。

## ゴール

Qt ランタイム一式を exe の隣にステージする `deploy_windows` ターゲットを作り、CI で「起動して15秒生きている」ことを自動検証する。

## 背景

- アプリは qmltermwidget を**リンクせず**、実行時に QML import path で読む（`app/main.cpp:136-140` が `applicationDirPath()/qmltermwidget` 等を追加）。既存ビルドは plugin を `${CMAKE_BINARY_DIR}/qmltermwidget/QMLTermWidget` に出力し、exe は `${CMAKE_BINARY_DIR}` 直下 — **single-config（Ninja）ならこの相対配置がそのまま Windows でも import path に一致する**。
- windeployqt は exe の依存 Qt DLL と、`--qmldir` で指定した QML ソースが import するモジュール（QtQuick.Controls、**Qt5Compat.GraphicalEffects**、QtQuick.LocalStorage → Qt6Sql + sqlite プラグイン）を配置する。plugin DLL の依存も別途配置が要る。
- 起動スモークは本物のゲート: DLL 欠落なら exit 0xC0000135、QML プラグイン配置ミスなら main.cpp:144-147 が "Cannot load QML interface" で EXIT_FAILURE。GPU 無し runner でも D3D11 WARP（ソフトウェア）で描画は走る。シェーダーは `.qsb` に HLSL 焼き込み済みで CI での再コンパイル無し。

## 手順

1. **app/CMakeLists.txt** の WIN32 節（A7 で作成済み）に追加:

```cmake
if(WIN32)
    find_program(WINDEPLOYQT_EXECUTABLE windeployqt HINTS "${Qt6_DIR}/../../../bin")
    add_custom_target(deploy_windows
        COMMAND ${WINDEPLOYQT_EXECUTABLE} --release
                --qmldir ${CMAKE_CURRENT_SOURCE_DIR}/qml
                --qmldir ${CMAKE_SOURCE_DIR}/qmltermwidget/src
                $<TARGET_FILE:cool-retro-term>
        COMMAND ${WINDEPLOYQT_EXECUTABLE} --release --no-translations
                --dir ${CMAKE_BINARY_DIR}
                ${CMAKE_BINARY_DIR}/qmltermwidget/QMLTermWidget/qmltermwidget.dll
        COMMENT "windeployqt: staging Qt runtime next to the exe")
endif()
```

   ※ plugin DLL の実ファイル名は CI 成果物で確認して合わせる（`qmltermwidget.dll` 想定）。2回目の呼び出しは plugin の依存 DLL を exe と同じルートに置く（Win32 の DLL 探索順で exe ディレクトリが最初に解決される）。

2. **build.yml の windows ジョブ**（A8 で作成済み）に追加:

```yaml
      - name: Deploy Qt runtime
        run: cmake --build build --target deploy_windows
      - name: Smoke test - launch and stay alive
        shell: pwsh
        run: |
          $p = Start-Process build\cool-retro-term.exe -PassThru
          Start-Sleep -Seconds 15
          if ($p.HasExited) { throw "exited early with code $($p.ExitCode)" }
          Stop-Process -Id $p.Id -Force
      - name: Upload staged build
        uses: actions/upload-artifact@v4
        with:
          name: cool-retro-term-windows-staging
          path: build/
```

   ※ upload はデバッグ用（実機/VM 検証にも使える）。サイズが問題なら exe+dll+qml だけに絞ってよい。

## 完了条件

- [ ] CI windows job が deploy + smoke まで緑
- [ ] artifact を Windows 実機/VM に展開 → **Qt をインストールしていない環境で**起動し、cmd.exe が動く
- [ ] ubuntu / macos job 緑のまま
- [ ] ここまで来たら plan.md の「検証」節のフルチェックリスト（ssh+vim/htop、split、全シェーダープロファイル、設定永続化、単一インスタンス）を実機で一巡 → 結果を TASKS.md 作業ログへ
