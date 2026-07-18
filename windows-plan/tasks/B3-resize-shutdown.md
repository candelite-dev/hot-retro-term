# B3: リサイズ + 終了順序 + no-op 群の確定

- Phase: B（ConPTY 実働）
- 依存: B2
- 対象ファイル: `qmltermwidget/lib/PtyWin.cpp`（+PtyWin.h 微調整）
- mac検証: 不可（動作は Windows 実機/VM）

## ゴール

ウィンドウリサイズの反映と、**ハングも孤児プロセスも出さない**終了処理を完成させる。これで PtyWin は機能完成。

## 背景（設計の要点）

ConPTY 終了処理の既知の罠が2つ:
1. **`ClosePseudoConsole` は、出力パイプが排水されないと pre-Win11 conhost でブロックし得る** → リーダーを先に止めるのが典型的デッドロック。正解は「**リーダーを生かしたまま** close し、リーダーが ERROR_BROKEN_PIPE で自然に抜けるのを待つ」。
2. **プロセス kill と pseudoconsole close の順序**: 先に pseudoconsole を閉じると Win10 でクライアントが detached で生き残る/teardown レースになる → **TerminateProcess が先、ClosePseudoConsole が後**（node-pty / Windows Terminal が収斂した順序）。Session 側の `close()`（A3 で実装済み）もこの順で `kill()` → `closePty()` を呼ぶ。

## 手順

1. **リサイズ**:

```cpp
void Pty::setWindowSize(int lines, int cols)
{
    _windowLines = lines;
    _windowColumns = cols;
    if (m_hPC)
        ResizePseudoConsole(m_hPC, COORD{ SHORT(cols), SHORT(lines) });  // GUIスレッドから呼んで安全
}
```

   `windowSize()` は `QSize(_windowColumns, _windowLines)` — **軸順注意**: Session.cpp:536-538 は `.height()` を lines として読む（POSIX 版 Pty.cpp:59 と同一規約）。

2. **`closePty()`** — 冪等に（2回呼ばれても安全）:

```cpp
void Pty::closePty()
{
    // 1. ライター停止 → 入力パイプを閉じる
    if (m_writerThread) {
        m_writerThread->quit();
        m_writerThread->wait(1000);
    }
    if (m_inWrite != INVALID_HANDLE_VALUE) { CloseHandle(m_inWrite); m_inWrite = INVALID_HANDLE_VALUE; }

    // 2. リーダーは生かしたまま ClosePseudoConsole（罠1: 排水しながら閉じる）
    if (m_hPC) { ClosePseudoConsole(m_hPC); m_hPC = nullptr; }

    // 3. リーダーが ERROR_BROKEN_PIPE で run() を抜けるのを待つ
    if (m_reader) { m_reader->wait(2000); }

    // 4. 残りの後片付け
    if (m_outRead != INVALID_HANDLE_VALUE) { CloseHandle(m_outRead); m_outRead = INVALID_HANDLE_VALUE; }
    if (!m_attrListBuffer.isEmpty()) {
        DeleteProcThreadAttributeList(
            reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(m_attrListBuffer.data()));
        m_attrListBuffer.clear();
    }
}
```

3. **dtor**: 子が生きていれば `kill(); waitForFinished(1000);`（罠2: kill が先）→ `closePty()` → QProcess の破棄に任せる（子が死んでいれば "destroyed while running" 警告は出ない）。

4. **no-op 群の最終化**: `setUtf8Mode`/`lockPty`/`setEmptyPTYProperties`/`setWriteable` に「ConPTY に termios は無い。conhost が line discipline を持つ」旨のコメントを付けて空実装で確定。`setFlowControlEnabled`/`flowControlEnabled` はフラグ round-trip（Session.cpp:292/821 が読み返す）。`foregroundProcessGroup()` は `-1` 確定（消費者は `KSession::hasActiveProcess` と `updateForegroundProcessInfo` のみで、後者は Windows では元々 NullProcessInfo に落ちる — app QML はどちらも未使用）。

## 完了条件（Windows 実機/VM）

- [ ] ウィンドウをドラッグでリサイズ → シェル内で桁数が変わる（cmd で `mode con` の Columns/Lines が追従）
- [ ] `exit` 入力でタブが閉じる（finished 伝播）
- [ ] タブを×で閉じる → タスクマネージャに cmd.exe / conhost.exe の孤児が残らない
- [ ] タブ3枚 + split で同時セッション → ランダム順で閉じてもハング無し
- [ ] アプリ終了（ウィンドウclose）が3秒以内に完了（ClosePseudoConsole ハングしていない）
- [ ] 外部からシェルを kill（タスクマネージャ）→ タブが終了挙動、アプリはハングしない
