# A6: デフォルトシェル COMSPEC 化 + setenv→qputenv

- Phase: A（コンパイルゲート）
- 依存: なし
- 対象ファイル: `qmltermwidget/lib/ksession.cpp`、`qmltermwidget/src/qmltermwidget_plugin.cpp`
- mac検証: 可（`qputenv` は POSIX では `setenv(...,1)` を呼ぶだけで意味論同一）

## ゴール

① Windows のデフォルトシェルを `%COMSPEC%`（cmd.exe）にする。② MSVC に存在しない POSIX 関数 `setenv()` の呼び出し2箇所を Qt の `qputenv()` に置換する。

## 背景

- `ksession.cpp:79-84`: デフォルトシェルは `$SHELL` → 空なら `/bin/bash`。Windows には `$SHELL` が無い。方針は **COMSPEC 一択**（全 Windows で保証された環境変数。PowerShell の自動探索は Store アプリのエイリアス等の失敗モードを増やすだけで、PowerShell 派には既存のカスタムコマンド設定 `appSettings.customCommand` がある）。この修正だけで app 層 QML（PreprocessedTerminal.qml）は無修正で済む — 非 mac 分岐は元々 `startShellProgram()` を呼ぶだけ。
- `setenv()` は POSIX。`ksession.cpp:84`（`TERM=xterm`）と `qmltermwidget_plugin.cpp:35-36`（`KB_LAYOUT_DIR`/`COLORSCHEMES_DIR` — `tools.cpp:19/65` が読む）にある。後者を忘れるとキーボードレイアウト/カラースキームのリソース解決が Windows で静かに壊れる。

## 手順

1. `ksession.cpp` の `createSession()` 内（:79-82 付近）:

```cpp
#ifdef Q_OS_WIN
    const QString shellProg = qEnvironmentVariable("COMSPEC", QStringLiteral("cmd.exe"));
#else
    const QByteArray envshell = qgetenv("SHELL");
    const QString shellProg = envshell.isEmpty() ? QStringLiteral("/bin/bash")
                                                 : QString::fromUtf8(envshell);
#endif
```

2. 同ファイル :84 付近: `setenv("TERM", "xterm", 1);` → `qputenv("TERM", QByteArrayLiteral("xterm"));`（全プラットフォーム共通コードとして。ifdef不要）

3. `qmltermwidget_plugin.cpp` :35-36 付近: 2つの `setenv(...)` を `qputenv(...)` に置換。値の組み立て（QString→バイト列変換）は既存コードの形に合わせ、`.toLocal8Bit()` / `.toUtf8()` 等で `QByteArray` にして渡す。

4. `unistd.h`/`stdlib.h` の include がこれらの setenv のためだけに存在するなら整理してよい（必須ではない）。

## 完了条件

- [ ] `git diff` が上記2ファイルのみ
- [ ] mac で `cmake -B build && cmake --build build -j` 成功
- [ ] mac でアプリ起動 → シェルが従来どおり `$SHELL` で立つ / カラースキーム・kbレイアウトが読めている（設定画面でスキーム一覧が空でないこと）
