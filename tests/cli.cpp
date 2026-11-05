#include <QProcess>
#include <QTest>

class CliTest : public QObject {
    Q_OBJECT
private slots:
    void capturedStreams_data() {
        QTest::addColumn<QStringList>("args");
        QTest::addColumn<int>("exitCode");
        QTest::addColumn<QByteArray>("out");
        QTest::addColumn<QByteArray>("err");
        QTest::newRow("help") << QStringList{"--verbose", "--help"} << 0
                             << QByteArray("Usage: cool-retro-term") << QByteArray();
        QTest::newRow("version") << QStringList{"--verbose", "--version"} << 0
                                << QByteArray("cool-retro-term") << QByteArray();
        QTest::newRow("invalid") << QStringList{"--hrt-invalid"} << 1
                                << QByteArray() << QByteArray("Use --help");
        QTest::newRow("missing-command") << QStringList{"-e"} << 1
                                        << QByteArray() << QByteArray("Use --help");
    }
    void capturedStreams() {
        QFETCH(QStringList, args);
        QFETCH(int, exitCode);
        QFETCH(QByteArray, out);
        QFETCH(QByteArray, err);
        QProcess process;
        auto env = QProcessEnvironment::systemEnvironment();
        env.insert("QT_QPA_PLATFORM", "hrt-no-such-platform");
        process.setProcessEnvironment(env);
        process.start(QStringLiteral(TEST_APP_BINARY), args);
        QVERIFY(process.waitForStarted());
        QVERIFY(process.waitForFinished(10000));
        QCOMPARE(process.exitStatus(), QProcess::NormalExit);
        QCOMPARE(process.exitCode(), exitCode);
        const auto stdoutBytes = process.readAllStandardOutput();
        const auto stderrBytes = process.readAllStandardError();
        if (out.isEmpty()) QVERIFY(stdoutBytes.isEmpty());
        else QVERIFY2(stdoutBytes.contains(out), stdoutBytes.constData());
        if (err.isEmpty()) QVERIFY2(stderrBytes.isEmpty(), stderrBytes.constData());
        else QVERIFY2(stderrBytes.contains(err), stderrBytes.constData());
    }
};
QTEST_GUILESS_MAIN(CliTest)
#include "cli.moc"
