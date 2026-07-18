# A5: History/BlockArray の mmap 排除

- Phase: A（コンパイルゲート）
- 依存: なし（A1 が BlockArray.cpp を WIN32 ビルドから外す — 本タスクはヘッダー/実装側の参照を塞ぐ）
- 対象ファイル: `qmltermwidget/lib/History.h`、`qmltermwidget/lib/History.cpp`
- mac検証: 可

## ゴール

スクロールバック履歴実装から Windows に無い `mmap`/`munmap` と、WIN32 ビルドから外される `BlockArray` への参照を ifdef で排除する。

## 背景

- 履歴には3系統ある: `HistoryTypeBuffer`（メモリ、**アプリが実際に使う唯一の系統** — `ksession.cpp:94` の `HistoryTypeBuffer(1000)`）、`HistoryTypeFile`（一時ファイル、`setHistorySize(-1)` API 経由でのみ到達可能）、`HistoryTypeBlockArray`（**外部参照ゼロ** — History.h/.cpp と BlockArray.* 以外に使用者なし）。
- `CompactHistoryBlock`（History.h 内、メモリ履歴のアロケータ）は `mmap(MAP_ANON)` を使うが、**malloc 版がコメントアウトで併記されている**（:296-305 付近）。
- `HistoryFile`（History.cpp）は QTemporaryFile の fd に対する mmap を読みキャッシュに使うが、**mmap 失敗時の lseek+read フォールバックが既にある**（:169-177 付近）→ Windows では常時フォールバック。

## 手順

1. **History.h**:
   - `#include <sys/mman.h>`（:38 付近）→ `#ifndef Q_OS_WIN` で包む。
   - `BlockArray.h` の include（:34 付近）と、`HistoryScrollBlockArray` / `HistoryTypeBlockArray` のクラス宣言（:240-260 付近と :427 以降付近）を `#ifndef Q_OS_WIN` で包む。
   - `CompactHistoryBlock` の ctor/dtor（:294-306 付近）を分岐:

```cpp
#ifdef Q_OS_WIN
    head = (quint8*) malloc(blockLength);
    Q_ASSERT(head != nullptr);
#else
    head = (quint8*) mmap(nullptr, blockLength, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0);
    Q_ASSERT(head != MAP_FAILED);
#endif
```

   dtor 側も同様に `free(blockStart)` ↔ `munmap(...)`。変数名・確保サイズは**既存コードの実物に合わせる**（上記は形の見本）。

2. **History.cpp**:
   - 先頭に Windows 用 CRT マッピングを追加:

```cpp
#ifdef Q_OS_WIN
#include <io.h>
// QTemporaryFile::handle() は Windows でも CRT fd を返す
#define KDE_lseek _lseek
#define read  _read
#define write _write
#endif
```

     ※ 既存の `KDE_lseek` 定義（:42 付近）や lseek ラッパーの流儀を先に確認し、**既存の集約点に乗せる**こと（雑な `#define read` がファイル全域に波及しないか、`read`/`write` の裸呼びが HistoryFile 以外に無いか grep で確認。他にあれば defineでなく明示 `_read` 置換 + ifdef にする）。
   - `HistoryFile::map()` を Windows では即 return（`fileMap = nullptr` のまま）にし、`unmap()` と mmap 呼び出しをガード → `get()` が既存の lseek/read フォールバック（:169-177 付近）を常用する。
   - `sys/mman.h` include があればガード。
   - `HistoryScrollBlockArray` / `HistoryTypeBlockArray` の実装ブロック（:464 以降付近）を `#ifndef Q_OS_WIN` で包む。

3. `BlockArray.cpp` / `BlockArray.h` 自体は**触らない**（A1 で WIN32 ビルドから除外済み）。

## 完了条件

- [ ] `git diff` が History.h / History.cpp のみ
- [ ] mac で `cmake -B build && cmake --build build -j` 成功
- [ ] mac でアプリ起動 → 大量出力（`yes | head -5000` 等）→ スクロールバックが従来どおり動く（POSIX 側フォールバック無変更の確認）
