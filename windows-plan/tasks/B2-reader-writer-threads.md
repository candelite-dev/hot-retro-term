# B2: リーダー/ライタースレッド（I/O 本実装）

- Phase: B（ConPTY 実働）
- 依存: B1
- 対象ファイル: `qmltermwidget/lib/PtyWin.cpp`（+PtyWin.h の private 追記）
- mac検証: 不可（動作は Windows 実機/VM）

## ゴール

ConPTY のパイプ I/O を Qt のイベントループに繋ぎ、**画面に出力が出て、タイプが効く**状態にする。

## 背景（設計の要点）

- **読み**: ConPTY 出力パイプに FIONREAD 相当は無い → 専用スレッドでブロッキング `ReadFile` が標準設計。EOF は `ClosePseudoConsole` 時の `ERROR_BROKEN_PIPE` として届く（B1 で conhost 側端を閉じてあるから）。
- **スレッド境界の marshaling**: 既存シグナル `receivedData(const char*, int)` は生ポインタを運ぶが、これは**同期 direct 接続中のみ有効**という寿命モデル（POSIX 版 Pty.cpp:317-325 もスタックローカル QByteArray から emit している）。よって: リーダー → `chunk(QByteArray)` を **queued 接続**（スレッド跨ぎで deep copy される）→ GUI スレッドの `onReaderChunk` が `receivedData(chunk.constData(), chunk.size())` を再emit → Session::onReceiveBlock → Emulation が即コピー（Session.cpp:943-950）。Session 側は無変更でこの寿命モデルが成立する。
- **書き**: conhost はクライアントの入力バッファ満杯時に入力パイプの吸い込みを止める。GUI スレッドで同期 `WriteFile` すると巨大ペースト時に UI が凍る → ワーカースレッドの queued スロット経由なら構造的に起きない。
- 入力は UTF-8 のまま流してよい（Emulation.cpp:201 が UTF-8 を送ってくる。ConPTY の入力もUTF-8。DA1/CPR 等の VT 応答も同経路で、ConPTY はそれを必要とする）。

## 手順

1. `PtyWin.cpp` 内にクラスを定義（ヘッダー公開不要。Q_OBJECT を使うのでファイル末尾に `#include "PtyWin.moc"` を置き、AUTOMOC に処理させる）:

```cpp
class ConPtyReaderThread : public QThread
{
    Q_OBJECT
public:
    ConPtyReaderThread(HANDLE outRead, QObject *parent) : QThread(parent), m_h(outRead) {}
signals:
    void chunk(const QByteArray &data);
protected:
    void run() override {
        char buf[65536];
        DWORD n = 0;
        while (ReadFile(m_h, buf, sizeof(buf), &n, nullptr) && n > 0)
            emit chunk(QByteArray(buf, int(n)));       // deep copy → queued で安全に渡る
        // ERROR_BROKEN_PIPE = ClosePseudoConsole 由来の正常 EOF
    }
private:
    HANDLE m_h;
};

class ConPtyWriter : public QObject
{
    Q_OBJECT
public:
    explicit ConPtyWriter(HANDLE inWrite) : m_h(inWrite) {}
public slots:
    void writeAll(const QByteArray &data) {
        const char *p = data.constData();
        qint64 left = data.size();
        DWORD written = 0;
        while (left > 0 && WriteFile(m_h, p, DWORD(left), &written, nullptr)) {
            p += written; left -= written;
        }
    }
private:
    HANDLE m_h;
};
```

2. `start()` 成功後（B1 の `return 0` 直前）に配線:

```cpp
m_reader = new ConPtyReaderThread(m_outRead, this);
connect(m_reader, &ConPtyReaderThread::chunk, this, &Pty::onReaderChunk);  // AutoConnection → queued
m_reader->start();

m_writerThread = new QThread(this);
m_writer = new ConPtyWriter(m_inWrite);
m_writer->moveToThread(m_writerThread);
connect(m_writerThread, &QThread::finished, m_writer, &QObject::deleteLater);
m_writerThread->start();
```

3. 実スロット:

```cpp
void Pty::onReaderChunk(const QByteArray &chunk)
{
    emit receivedData(chunk.constData(), chunk.size());   // direct 接続中のみ有効な寿命 = POSIX と同型
}

void Pty::sendData(const char *buffer, int length)
{
    if (!m_writer) return;
    QMetaObject::invokeMethod(m_writer, "writeAll", Qt::QueuedConnection,
                              Q_ARG(QByteArray, QByteArray(buffer, length)));
}
```

## 完了条件（Windows 実機/VM）

- [ ] cmd.exe のプロンプトが CRT シェーダー越しに表示される
- [ ] タイプがエコーされ、`dir` / `cls` / `echo テスト` が正しく動く
- [ ] `ping -t 8.8.8.8` の連続出力が流れ、Ctrl+C で止まる
- [ ] 1MB 級のテキストをペーストしても UI が固まらない（ライタースレッドの検証）
- [ ] `type <大きいファイル>` で大量出力しても詰まらない（リーダーの検証）
- [ ] CI（windows job）緑のまま
