# A7: app側 CMake WIN32 整備 + アイコン + フォント fallback

- Phase: A（コンパイルゲート）
- 依存: なし
- 対象ファイル: `app/CMakeLists.txt`、`app/fontmanager.cpp`、新規 `app/icons/crt.ico`、新規 `app/icons/crt.rc`
- mac検証: 可（mac ビルド無変化。ico 生成もこの mac でできる）

## ゴール

Windows で①コンソール窓が背後に出ない GUI サブシステム化、②exe/タスクバーにアイコンが出る、③フォールバックフォントが実在する、の3点を仕込む。

## 背景

- `app/CMakeLists.txt:24` の `qt_add_executable` に WIN32 指定が無い → Windows では console サブシステムになり黒窓が同伴する。
- `if(WIN32)` 分岐が皆無でアイコンリソースも無い。既存アイコンは PNG のみ（`if(UNIX AND NOT APPLE)` の install 節 :139-148 付近で参照。mac は .icns）。
- `app/fontmanager.cpp:349-353` のフォールバックフォント `"Monospace"` は fontconfig エイリアスで Windows に実在しない。

## 手順

1. **crt.ico 生成**（この mac 上で1回だけ・コミットする）: 既存 PNG アイコンの場所を `find app -name "*.png" | grep -i icon` 等で特定し、ImageMagick で複数サイズを束ねる:

```bash
# ImageMagick が無ければ: brew install imagemagick
magick <256px>.png <128px>.png <64px>.png <48px>.png <32px>.png <16px>.png app/icons/crt.ico
```

   サイズ違いが無ければ 256px 1枚から `-define icon:auto-resize=256,128,64,48,32,16` で生成してよい。

2. **crt.rc 新規作成**（`app/icons/crt.rc`、1行）:

```rc
IDI_ICON1 ICON "crt.ico"
```

3. **app/CMakeLists.txt** に WIN32 節を追加（既存の `if(APPLE)` 節の並びに）:

```cmake
if(WIN32)
    enable_language(RC)
    set_target_properties(cool-retro-term PROPERTIES WIN32_EXECUTABLE TRUE)
    target_sources(cool-retro-term PRIVATE icons/crt.rc)
endif()
```

   ※ ターゲット名・パスは既存 CMakeLists の実物に合わせる。`qt_add_executable(... WIN32 ...)` 引数方式でも可 — どちらか一方で。
   ※ windeployqt のデプロイターゲットは**ここでは作らない**（B4 の仕事）。

4. **app/fontmanager.cpp**（:349-353 付近のフォールバック連鎖）:

```cpp
#if defined(Q_OS_MAC)
    fallbackChain.append(QStringLiteral("Menlo"));
#elif defined(Q_OS_WIN)
    fallbackChain.append(QStringLiteral("Consolas"));
    fallbackChain.append(QStringLiteral("Courier New"));
#else
    fallbackChain.append(QStringLiteral("Monospace"));
#endif
```

   ※ 既存が if/else 文なら文のまま分岐追加。変数名・構造は既存の実物に合わせる。

## 完了条件

- [ ] `git diff` が app/CMakeLists.txt と app/fontmanager.cpp のみ、新規が crt.ico / crt.rc のみ
- [ ] mac で `cmake -B build && cmake --build build -j` 成功（WIN32 節が mac に影響しないこと）
- [ ] crt.ico がマルチサイズで生成されている（`file app/icons/crt.ico` や `magick identify` で確認）
