# B1: ConPTY spawn 経路の本実装

- Phase: B（ConPTY 実働）
- 依存: A8（Windows でコンパイルが通る状態）
- 対象ファイル: `qmltermwidget/lib/PtyWin.cpp`（+必要なら PtyWin.h の private 微調整）
- mac検証: 不可（コンパイルは CI、動作は Windows 実機/VM）

## ゴール

A2 のスタブを本物にする第1弾: 疑似コンソールの生成と、`QProcess::setCreateProcessArgumentsModifier` 経由での `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE` 注入により、`start()` で子プロセスが ConPTY にぶら下がって起動するところまで。I/O スレッドは B2。

## 背景（設計の要点 — plan.md「中核の設計判断」も参照）

Qt の `qprocess_win.cpp` は `CreateProcessArguments` 構造体（公開API、Qt 5.7から不変）を組み立て、**modifier 実行後の値で** `CreateProcessW` を呼ぶ。よって modifier から `flags`/`inheritHandles`/`startupInfo` を差し替えるのは契約内。これで Session が使う QProcess 表面を実物のまま使える。

3つの有名な罠を必ず踏み抜かないこと:
1. **`CREATE_NO_WINDOW` は pseudoconsole 属性と競合** — Qt が GUI アプリで自動付与するので**明示的に外す**。忘れた時の症状「出力が一切来ない」。
2. **`inheritHandles = false`** — 疑似コンソールは属性リストで渡す。ハンドル継承は不要（MS の ConPTY サンプル準拠）。
3. **conhost 側パイプ端は `CreatePseudoConsole` 直後に閉じる** — 閉じ忘れると後で EOF（ERROR_BROKEN_PIPE）が来ず、終了処理が破綻する。

## 手順

1. **ctor**: QProcess 自前のパイプ機構を無効化しておく:

```cpp
setStandardInputFile(QProcess::nullDevice());
setStandardOutputFile(QProcess::nullDevice());
setStandardErrorFile(QProcess::nullDevice());
```

2. **`openPseudoConsole()`**:

```cpp
bool Pty::openPseudoConsole()
{
    HANDLE inRead = INVALID_HANDLE_VALUE, outWrite = INVALID_HANDLE_VALUE;
    if (!CreatePipe(&inRead, &m_inWrite, nullptr, 65536))      // 既定4KBでなく64KB
        return false;
    if (!CreatePipe(&m_outRead, &outWrite, nullptr, 65536)) {
        CloseHandle(inRead); CloseHandle(m_inWrite); m_inWrite = INVALID_HANDLE_VALUE;
        return false;
    }
    COORD size { SHORT(_windowColumns > 0 ? _windowColumns : 80),
                 SHORT(_windowLines   > 0 ? _windowLines   : 24) };
    HRESULT hr = CreatePseudoConsole(size, inRead, outWrite, 0, &m_hPC);
    CloseHandle(inRead);     // conhost が複製済み。ここで閉じるのが EOF 検出の前提
    CloseHandle(outWrite);
    return SUCCEEDED(hr);
}
```

   ※ Session は `run()` の前に `setWindowSize()` を呼ぶ（Session.cpp:516 付近）ので、保存済みサイズが初期 COORD に効く。

3. **`installCreateProcessModifier()`**:

```cpp
SIZE_T bytes = 0;
InitializeProcThreadAttributeList(nullptr, 1, 0, &bytes);
m_attrListBuffer.resize(qsizetype(bytes));
auto attrs = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(m_attrListBuffer.data());
InitializeProcThreadAttributeList(attrs, 1, 0, &bytes);
UpdateProcThreadAttribute(attrs, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                          m_hPC, sizeof(HPCON), nullptr, nullptr);
ZeroMemory(&m_siEx, sizeof(m_siEx));
m_siEx.StartupInfo.cb = sizeof(STARTUPINFOEXW);   // EX サイズであること
m_siEx.lpAttributeList = attrs;

setCreateProcessArgumentsModifier([this](QProcess::CreateProcessArguments *args) {
    args->flags |= EXTENDED_STARTUPINFO_PRESENT;
    args->flags &= ~DWORD(CREATE_NO_WINDOW);       // 罠1
    args->inheritHandles = false;                  // 罠2
    args->startupInfo = &m_siEx.StartupInfo;       // Qt の STARTF_USESTDHANDLES 情報を捨てる
});
```

4. **`start()`**（POSIX 版 `Pty.cpp:164-225` の写し、termios 部分抜き）:

```cpp
int Pty::start(const QString &program, const QStringList &arguments,
               const QStringList &environment, ulong winid, bool /*addToUtmp*/)
{
    clearProgram();
    setProgram(program, arguments.mid(1));      // POSIX 版と同じ argv 規約（[0]がプログラム名）
    addEnvironmentVariables(environment);       // KProcess::setEnv ループ（Pty.cpp:136-162 を移植）
    setEnv(QLatin1String("WINDOWID"), QString::number(winid));
    setEnv(QLatin1String("COLORTERM"), QLatin1String("truecolor"));
    // TERM フォールバック: environment に TERM が無ければ xterm-256color を set
    // （POSIX 版 Pty.cpp:158-159 と同じ挙動を addEnvironmentVariables 内か直後で）

    if (!openPseudoConsole())
        return -1;
    installCreateProcessModifier();

    KProcess::start();
    if (!waitForStarted(5000)) { closePty(); return -1; }
    // m_reader->start() は B2 で追加
    return 0;
}
```

   ※ `arguments.mid(1)` の規約は POSIX 版 `Pty::start` の実物を読んで合わせること（Session が渡す arguments の [0] がプログラム名かどうかを確認）。

5. `closePty()` は暫定で: `m_hPC` があれば `ClosePseudoConsole`、パイプハンドルを `CloseHandle`、attr list を `DeleteProcThreadAttributeList`。厳密な順序制御は B3 で確定。

## 完了条件

- [ ] CI（windows job）緑
- [ ] Windows 実機/VM: アプリ起動 → タスクマネージャに `cmd.exe`（と conhost.exe）が子として出現する（画面表示はまだ真っ黒で正常 — リーダーが無いので）
- [ ] `git diff` が PtyWin.cpp（+PtyWin.h 微調整）のみ
