# A3: Session.cpp の3箇所 ifdef

- Phase: A（コンパイルゲート）
- 依存: A2（PtyWin の `closePty()`/`kill()` 表面が存在すること）
- 対象ファイル: `qmltermwidget/lib/Session.cpp`
- mac検証: 可（POSIX 側パスが 1 バイトも変わらないこと）

## ゴール

Session.cpp に残る POSIX 前提3箇所（slave fd 取得 / `::kill` / SIGHUP・SIGKILL 定数）を `#ifdef Q_OS_WIN` で分岐する。**これが Session.cpp の全差分（~17行）**。他は触らない。

## 背景

Session は Pty 層のオーケストレータで、ほぼポータブル。POSIX の fd/pid/シグナルモデルに触れるのは3箇所だけ、と監査済み。行番号は監査時点のもの — 前後にズレていたらパターンで探すこと。

## 手順

1. **slave fd 取得（:87 付近、`_shellProcess->pty()->slaveFd()`）**:

```cpp
#ifdef Q_OS_WIN
    ptySlaveFd = -1;   // Windows に slave fd の概念は無い。getPtySlaveFd() の消費者は
                       // qtermwidget.cpp のみで、QML ビルドには含まれない（CMakeLists 確認済み）
#else
    ptySlaveFd = _shellProcess->pty()->slaveFd();
#endif
```

2. **`sendSignal(int signal)`（:541-558 付近、`::kill(pid, signal)` を含む関数）** — 関数本体を分岐:

```cpp
#ifdef Q_OS_WIN
    Q_UNUSED(signal);
    if (processId() <= 0)
        return false;
    _shellProcess->kill();                       // = TerminateProcess
    return _shellProcess->waitForFinished(1000);
#else
    /* 既存の ::kill 本体を無変更で */
#endif
```

   ※ 既存コードが `_shellProcess->processId()` でなく別の取得方法なら既存に合わせる。

3. **`close()`（:560-598 付近、SIGHUP → waitForFinished → SIGKILL の段階的終了ロジック）** — 関数冒頭に Windows パスを追加し、POSIX 本体は無変更で残す:

```cpp
#ifdef Q_OS_WIN
    _wantedClose = true;   // 既存 POSIX パスと同じ状態遷移を踏むこと（変数名は既存に合わせる）
    if (_shellProcess->state() == QProcess::Running) {
        _shellProcess->kill();                       // 先に子を殺す（ConPTY の掟: kill → ClosePseudoConsole の順）
        if (!_shellProcess->waitForFinished(1000))
            QTimer::singleShot(1, this, SIGNAL(finished()));
        _shellProcess->closePty();                   // リーダー稼働中に ClosePseudoConsole（PtyWin 側 B3 が保証）
    } else {
        QTimer::singleShot(1, this, SIGNAL(finished()));
    }
    return;
#endif
    /* 既存の POSIX 本体を無変更で */
```

   ※ 既存 `close()` の状態フラグ操作（`_wantedClose` 等）を**先に読み**、POSIX パスと同じフラグを同じ順で立てること。終了通知の正常系は QProcess の `finished(int,ExitStatus)` → `Session::done`（:628-654 付近）経由で、これは Windows でもそのまま機能する。

4. SIGHUP/SIGKILL 等のシグナル定数参照が上記2関数の外にもないか `grep -n "SIG" Session.cpp` で確認。あれば同様にガード（監査では :567-587 のみ）。

## 完了条件

- [ ] `git diff` が Session.cpp のみ、追加行はすべて `#ifdef Q_OS_WIN` ブロック内
- [ ] POSIX 側の既存行に変更ゼロ（diff で削除・変更行が無いこと）
- [ ] mac で `cmake -B build && cmake --build build -j` 成功、アプリ起動してシェルが立つ（`./build/cool-retro-term.app/Contents/MacOS/cool-retro-term`）
