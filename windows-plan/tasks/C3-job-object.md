# C3:（任意）Job Object で孫プロセス tree-kill

- Phase: C（磨き＆配布）— **任意タスク**。やらなくても v1 リリース可（多くのターミナルと同水準）
- 依存: B3
- 対象ファイル: `qmltermwidget/lib/PtyWin.cpp`（+PtyWin.h）
- mac検証: 不可（動作は Windows 実機/VM）

## ゴール

タブを閉じたとき、シェルの**孫プロセス**（`cmd` から起動した長生きプログラム等）も道連れにする。現状（B3 まで）の `TerminateProcess` は直接の子しか殺さない。

## 背景

Windows に POSIX のプロセスグループ/SIGHUP 相当は無い。標準解は **Job Object**: `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` を立てた Job に子を入れると、Job ハンドルが閉じた瞬間にツリー全体が terminate される（子が作る孫も既定で Job を継承）。

## 手順

1. メンバ追加: `HANDLE m_hJob = nullptr;`
2. `start()` の `waitForStarted()` 成功後に:

```cpp
m_hJob = CreateJobObjectW(nullptr, nullptr);
if (m_hJob) {
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION info {};
    info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    SetInformationJobObject(m_hJob, JobObjectExtendedLimitInformation, &info, sizeof(info));
    HANDLE hProc = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, FALSE, DWORD(processId()));
    if (hProc) {
        AssignProcessToJobObject(m_hJob, hProc);   // spawn直後アサインの微小レースは許容
        CloseHandle(hProc);
    }
}
```

   ※ 厳密にレースを消すには CREATE_SUSPENDED で作って assign 後に resume する必要があるが、QProcess 経由では侵襲が大きい。「起動直後の数msで孫を作り切るプログラム」だけが漏れる、と割り切る（node-pty も同様の妥協をしている）。コメントで明記すること。

3. `closePty()` の最後（B3 の手順4の後）に: `if (m_hJob) { CloseHandle(m_hJob); m_hJob = nullptr; }` — **CloseHandle だけでツリーが死ぬ**のが KILL_ON_JOB_CLOSE の意味。dtor 経路でも通ることを確認。

## 完了条件（Windows 実機/VM）

- [ ] タブで `cmd /c start /b ping -t 8.8.8.8` 的な孫を作る → タブを閉じる → タスクマネージャに ping が残らない
- [ ] 通常の開閉・アプリ終了の挙動が B3 の完了条件から劣化していない
- [ ] CI 緑のまま
