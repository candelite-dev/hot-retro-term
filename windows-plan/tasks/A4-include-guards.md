# A4: POSIX include ガード + 死んだ unistd 削除

- Phase: A（コンパイルゲート）
- 依存: なし
- 対象ファイル: `qmltermwidget/lib/ProcessInfo.cpp`、`qmltermwidget/lib/Emulation.cpp`、`qmltermwidget/lib/Screen.cpp`、`qmltermwidget/lib/Vt102Emulation.cpp`
- mac検証: 可

## ゴール

MSVC でコンパイルを止める POSIX ヘッダー include を4ファイルで処理する。ロジックは一切変えない。

## 背景

- `ProcessInfo.cpp` の**ロジックは既に Windows 対応済み**: `UnixProcessInfo` は `#if !defined(Q_OS_WIN)` で包まれ、`newInstance()` は未対応プラットフォームで `NullProcessInfo` にフォールバックする（`ProcessInfo.h:347` にも対応ガードあり）。**ただしファイル先頭の include 群（:24-29 付近）だけ未ガード**で、MSVC には存在しないヘッダーが並ぶ。
- `Emulation.cpp` / `Screen.cpp` / `Vt102Emulation.cpp` の `<unistd.h>` は**使用シンボルゼロの死んだ include**（監査で確認済み）。削除してよい。

## 手順

1. `ProcessInfo.cpp` 先頭（:24-29 付近）の POSIX include 群を包む:

```cpp
#if !defined(Q_OS_WIN)
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <pwd.h>
#include <sys/param.h>
#endif
```

   ※ `Q_OS_WIN` を判定するには `<QtGlobal>`（または任意の Qt ヘッダー）が**先に** include されている必要がある。ファイルの include 順を確認し、Qt ヘッダーが後なら `#include <QtGlobal>` をガードの直前に足す。実際の include 行が監査メモと多少違っても「POSIX にしか無いヘッダー全部」を包む。

2. 3ファイルの死んだ include を削除:
   - `Emulation.cpp`（:28 付近）の `#include <unistd.h>`
   - `Screen.cpp`（:29 付近）の `#include <unistd.h>`
   - `Vt102Emulation.cpp`（:30 付近）の `#include <unistd.h>`

   削除前に各ファイルで `unistd` 由来シンボル（`read`/`write`/`close`/`usleep`/`isatty` 等の裸呼び）が本当に無いか grep で再確認。あった場合は削除でなくガードにする。

3. `Vt102Emulation.cpp` の `mac-vkcode.h` include（:25 付近）は**触らない**（自己完結ヘッダーで、使用箇所は Q_OS_MAC ガード済み）。

## 完了条件

- [ ] `git diff` が上記4ファイルのみ
- [ ] mac で `cmake -B build && cmake --build build -j` 成功
- [ ] ProcessInfo.cpp の非 include 行に変更ゼロ
