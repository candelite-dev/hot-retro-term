#include "PtyWin.h"
#include <QSignalSpy>
#include <QRegularExpression>
#include <QTest>

class ConPtyTest : public QObject {
    Q_OBJECT
    QByteArray output;
    void observe(Konsole::Pty &pty) {
        output.clear();
        connect(&pty, &Konsole::Pty::receivedData, this, [this](const char *data, int size) {
            output.append(data, size);
        });
    }
    int start(Konsole::Pty &pty, const QStringList &args) {
        const QString helper = QStringLiteral(TEST_CONSOLE_HELPER);
        return pty.start(helper, QStringList{helper} + args, {}, 0, false);
    }
private slots:
    void outputAndResize() {
        Konsole::Pty pty;
        observe(pty);
        QCOMPARE(start(pty, {"--resize"}), 0);
        QTRY_VERIFY_WITH_TIMEOUT(output.contains("HRT_RESIZE_READY"), 5000);
        for (int i = 0; i < 100; ++i) pty.setWindowSize(24 + i % 5, 80 + i % 7);
        pty.setWindowSize(37, 113);
        QCOMPARE(pty.windowSize(), QSize(113, 37));
        // ResizePseudoConsole queues resize notifications to the client. Ask
        // again until the real console viewport has applied the final size.
        const auto resized = [&]() {
            pty.sendData("x", 1);
            return output.contains("HRT_SIZE[113,37]");
        };
        QTRY_VERIFY2_WITH_TIMEOUT(resized(), output.constData(), 5000);
    }
    void repeatedClosure() {
        for (int i = 0; i < 12; ++i) {
            Konsole::Pty pty;
            observe(pty);
            QCOMPARE(start(pty, {"--output"}), 0);
            QTRY_VERIFY_WITH_TIMEOUT(output.contains("HRT_OUTPUT_DONE"), 5000);
            QVERIFY(output.count("HRT_OUTPUT_LINE") >= 2048);
            pty.kill();
            QVERIFY(pty.waitForFinished(3000));
            pty.closePty();
            pty.closePty();
        }
    }
    void descendantsAreKilled() {
        HANDLE child = nullptr;
        {
            Konsole::Pty pty;
            observe(pty);
            QCOMPARE(start(pty, {"--tree"}), 0);
            const QRegularExpression pattern("HRT_CHILD\\[(\\d+)\\]");
            QTRY_VERIFY_WITH_TIMEOUT(pattern.match(QString::fromLatin1(output)).hasMatch(), 5000);
            const DWORD pid = pattern.match(QString::fromLatin1(output)).captured(1).toULong();
            child = OpenProcess(SYNCHRONIZE, FALSE, pid);
            QVERIFY(child);
        }
        const DWORD result = WaitForSingleObject(child, 5000);
        CloseHandle(child);
        QCOMPARE(result, DWORD(WAIT_OBJECT_0));
    }
    void failedLaunch() {
        Konsole::Pty pty;
        QCOMPARE(pty.start("hrt-no-such-program.exe", {"hrt-no-such-program.exe"}, {}, 0, false), -1);
        QCOMPARE(pty.state(), QProcess::NotRunning);
        pty.closePty();
        pty.closePty();
    }
    void closeWithPendingInput() {
        Konsole::Pty pty;
        QCOMPARE(start(pty, {"--wait"}), 0);
        const QByteArray paste(4 * 1024 * 1024, 'x');
        pty.sendData(paste.constData(), paste.size());
        QTest::qWait(100);
        pty.closePty();
        QCOMPARE(pty.state(), QProcess::NotRunning);
    }
};
QTEST_GUILESS_MAIN(ConPtyTest)
#include "conpty.moc"
