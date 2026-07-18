# A2: Pty.h 振り分け + PtyWin 骨格（スタブ実装）

- Phase: A（コンパイルゲート）
- 依存: A1
- 対象ファイル: `qmltermwidget/lib/Pty.h`（ifdefラッパー化）、新規 `qmltermwidget/lib/PtyWin.h`、新規 `qmltermwidget/lib/PtyWin.cpp`
- mac検証: 可（PtyWin は mac ではコンパイルされない。Pty.h ラッパー化後も mac ビルドが通ること）。Windows 側コンパイルは A8 の CI で判明。

## ゴール

Windows ビルドで `Konsole::Pty` が ConPTY 版クラスに差し替わる骨格を作る。このタスクでは**中身はスタブでよい**（`start()` は qWarning して -1、他は空/保存のみ）。本実装は B1〜B3。

## 背景

`Session.cpp` は `Pty.h` を include し `Konsole::Pty` を使う（`Session.h:40` は前方宣言のみ）。接続はすべて文字列ベースの `SIGNAL()/SLOT()` マクロなので、同名メンバを持つ別クラスで実行時解決される。継承チェーンは POSIX 版が `Pty : KPtyProcess : KProcess : QProcess`。Windows 版は **`Pty : KProcess`** とする（`kprocess.cpp` は既に Q_OS_WIN 対応済みでそのままビルドされる）。これで Session が使う QProcess 表面（`state`/`processId`/`waitForFinished`/`exitStatus`/`finished` シグナル/`setWorkingDirectory`）と KProcess の環境ブロック構築・引数クォートを無償相続する。

## 手順

1. `Pty.h` をラッパー化（既存本文は `#else` 側に**無変更で**残す）:

```cpp
#ifndef PTY_H
#define PTY_H
#include <QtGlobal>
#ifdef Q_OS_WIN
#include "PtyWin.h"        // Windows: ConPTY 版 Konsole::Pty
#else
/* ...既存の Pty.h 本文まるごと（include群からクラス定義まで）... */
#endif
#endif // PTY_H
```

2. `PtyWin.h` 新規作成。公開表面は POSIX 版 `Pty.h` の 1:1 ミラー + KProcess 継承:

```cpp
#ifndef PTYWIN_H
#define PTYWIN_H
#include "kprocess.h"
#include <QSize>
#include <QByteArray>
#include <windows.h>   // NOMINMAX / WIN32_LEAN_AND_MEAN は CMake でターゲット全体に定義済み(A1)

namespace Konsole {

class ConPtyReaderThread;   // PtyWin.cpp 内で定義（ブロッキング ReadFile ループ）
class ConPtyWriter;         // PtyWin.cpp 内で定義（ワーカースレッド上の WriteFile スロット）

class Pty : public KProcess
{
    Q_OBJECT
public:
    explicit Pty(QObject *parent = nullptr);
    explicit Pty(int ptyMasterFd, QObject *parent = nullptr); // 互換スタブ: fd無視+qWarning
    ~Pty() override;

    int start(const QString &program, const QStringList &arguments,
              const QStringList &environment, ulong winid, bool addToUtmp);
    void setWindowSize(int lines, int cols);
    QSize windowSize() const;              // QSize(cols, lines) ← POSIX版 Pty.cpp:59 と同じ軸順。
                                           // Session.cpp:536-538 が .height()=lines として読む
    void setFlowControlEnabled(bool on);   // フラグ保存のみ（ConPTYにtermiosは無い）
    bool flowControlEnabled() const;
    void setErase(char erase);             // 保存のみ
    char erase() const;
    int  foregroundProcessGroup() const;   // 常に -1（ProcessInfo は NullProcessInfo に落ちる設計）
    void closePty();
    void setEmptyPTYProperties() {}        // 文書化された no-op
    void setWriteable(bool) {}

public slots:
    void setUtf8Mode(bool) {}              // ConPTY は常時 UTF-8
    void lockPty(bool) {}                  // POSIX 版も実質 no-op (Pty.cpp:327-336)
    void sendData(const char *buffer, int length);

signals:
    void receivedData(const char *buffer, int length);

private slots:
    void onReaderChunk(const QByteArray &chunk);

private:
    bool openPseudoConsole();
    void installCreateProcessModifier();
    void addEnvironmentVariables(const QStringList &environment);

    HPCON  m_hPC = nullptr;
    HANDLE m_inWrite = INVALID_HANDLE_VALUE;   // 入力パイプ（こちらが書く側）
    HANDLE m_outRead = INVALID_HANDLE_VALUE;   // 出力パイプ（リーダーが読む側）
    QByteArray m_attrListBuffer;               // PROC_THREAD_ATTRIBUTE_LIST 領域
    STARTUPINFOEXW m_siEx {};
    ConPtyReaderThread *m_reader = nullptr;
    QThread *m_writerThread = nullptr;
    ConPtyWriter *m_writer = nullptr;
    int  _windowColumns = 0;
    int  _windowLines = 0;
    char _eraseChar = 0;
    bool _xonXoff = true;
};

} // namespace Konsole
#endif // PTYWIN_H
```

3. `PtyWin.cpp` 新規作成 — **全メソッドをスタブで**実装:
   - ctor: メンバ初期化のみ（リーダー/ライターは B2 で生成）
   - `start()`: `qWarning("PtyWin: ConPTY backend not implemented yet (task B1)"); return -1;`
   - `sendData`/`onReaderChunk`/`closePty`/`openPseudoConsole`/`installCreateProcessModifier`/`addEnvironmentVariables`: 空 or `return false`
   - `setWindowSize`: `_windowLines/_windowColumns` に保存のみ。`windowSize()`: `QSize(_windowColumns, _windowLines)`
   - `setFlowControlEnabled`/`flowControlEnabled`/`setErase`/`erase`: メンバ保存/返却
   - `foregroundProcessGroup()`: `return -1;`
   - `ConPtyReaderThread`/`ConPtyWriter` はこの段階では**宣言すら不要**（B2 で追加）。前方宣言のままメンバが nullptr でよい
   - ファイル末尾に `// #include "PtyWin.moc"` は不要（クラス定義はヘッダー側。AUTOMOC が PtyWin.h を処理する）

## 完了条件

- [ ] `git diff` が Pty.h のみ、新規ファイルが PtyWin.h / PtyWin.cpp のみ
- [ ] Pty.h の `#else` 側（POSIX 本文）が既存と 1 バイトも違わない
- [ ] mac で `cmake -B build && cmake --build build -j` 成功
- [ ] （目視）PtyWin.h の公開メンバ名・シグネチャが POSIX 版 Pty.h と完全一致（SIGNAL/SLOT 文字列解決のため。特に `receivedData(const char*,int)` / `sendData(const char*,int)` / `setUtf8Mode(bool)` / `lockPty(bool)`）
