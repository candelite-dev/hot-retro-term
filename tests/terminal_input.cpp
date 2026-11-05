#include <QApplication>
#include <QClipboard>
#include <QMimeData>
#include <QScopeGuard>
#include <QKeyEvent>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QRegularExpression>
#include <QSignalSpy>
#include <QTest>
#include <memory>

// Load the same plugin and copied keytabs as the app, then observe bytes in a
// real child PTY. This covers key translation and the session's erase setting.
class TerminalInputTest : public QObject {
    Q_OBJECT

#ifdef Q_OS_MACOS
    // Qt names the physical Control key Meta on macOS.
    static constexpr auto controlModifier = Qt::MetaModifier;
#else
    static constexpr auto controlModifier = Qt::ControlModifier;
#endif

    void sendKey(QObject *terminal, int key, Qt::KeyboardModifiers modifiers, const QString &text) {
        QKeyEvent event(QEvent::KeyPress, key, modifiers, text);
        QApplication::sendEvent(terminal, &event);
    }

    QString receivedText(const QSignalSpy &output) {
        QString text;
        for (const auto &chunk : output) text += chunk.at(0).toString();
        return text;
    }

private slots:
    void inputBytes_data() {
        QTest::addColumn<int>("key");
        QTest::addColumn<Qt::KeyboardModifiers>("modifiers");
        QTest::addColumn<QString>("text");
        QTest::addColumn<QByteArray>("expected");
        const QString backspace(QChar(8));
        QTest::newRow("backspace") << int(Qt::Key_Backspace) << Qt::KeyboardModifiers{}
                                   << backspace << QByteArray(1, '\x7f');
        QTest::newRow("shift-backspace") << int(Qt::Key_Backspace) << Qt::KeyboardModifiers(Qt::ShiftModifier)
                                         << backspace << QByteArray(1, '\x7f');
        QTest::newRow("control-backspace") << int(Qt::Key_Backspace) << Qt::KeyboardModifiers(controlModifier)
                                           << backspace << QByteArray(1, '\x08');
        QTest::newRow("control-h") << int(Qt::Key_H) << Qt::KeyboardModifiers(controlModifier)
                                   << backspace << QByteArray(1, '\x08');
        QTest::newRow("plain-h") << int(Qt::Key_H) << Qt::KeyboardModifiers{}
                                 << QString("h") << QByteArray("h");
        QTest::newRow("forward-delete") << int(Qt::Key_Delete) << Qt::KeyboardModifiers{}
                                        << QString(QChar(0x7f)) << QByteArray("\x1b[3~");
    }

    void inputBytes() {
        QFETCH(int, key);
        QFETCH(Qt::KeyboardModifiers, modifiers);
        QFETCH(QString, text);
        QFETCH(QByteArray, expected);

        QQmlEngine engine;
        engine.addImportPath(QStringLiteral(TEST_PLUGIN_PATH));
        QQmlComponent component(&engine);
        component.setData(R"(
            import QtQuick
            import QMLTermWidget 2.0
            QMLTermWidget {
                width: 640; height: 480
                session: QMLTermSession {}
            }
        )", QUrl());
        std::unique_ptr<QObject> terminal(component.create());
        QVERIFY2(terminal, qPrintable(component.errorString()));
        auto *session = terminal->property("session").value<QObject *>();
        QVERIFY(session);
        QSignalSpy received(session, SIGNAL(receivedData(QString)));
        QVERIFY(received.isValid());
        QCOMPARE(session->property("kbScheme").toString(), "default");
#ifdef Q_OS_WIN
        QVERIFY(session->setProperty("shellProgram", QStringLiteral(TEST_CONSOLE_HELPER)));
        QVERIFY(session->setProperty("shellProgramArgs", QStringList{"--bytes", QString::number(expected.size())}));
#else
        QVERIFY(session->setProperty("shellProgram", "/bin/sh"));
        const auto command = QString(
            "LC_ALL=C; export LC_ALL; stty -a; stty raw -echo; "
            "printf 'HRT_INPUT_READY\\n'; od -An -tx1 -N %1; "
            "printf 'HRT_INPUT_DONE\\n'; exec /bin/cat").arg(expected.size());
        QVERIFY(session->setProperty("shellProgramArgs", QStringList{"-c", command}));
#endif
        QVERIFY(QMetaObject::invokeMethod(session, "startShellProgram"));
        QTRY_VERIFY_WITH_TIMEOUT(receivedText(received).contains("HRT_INPUT_READY"), 5000);
#ifndef Q_OS_WIN
        QVERIFY2(receivedText(received).contains(QRegularExpression("\\berase\\s*=\\s*\\^\\?")),
                 "The PTY erase character must match the Backspace byte (DEL)");
#endif

        sendKey(terminal.get(), key, modifiers, text);
        QTRY_VERIFY_WITH_TIMEOUT(receivedText(received).contains("HRT_INPUT_DONE"), 5000);
#ifdef Q_OS_WIN
        // ConPTY adds VT cursor/title sequences around the console's output.
        const auto result = QRegularExpression("HRT_INPUT_RESULT\\[([0-9a-f]+)\\]")
                                .match(receivedText(received));
        QVERIFY2(result.hasMatch(), qPrintable(receivedText(received)));
        QCOMPARE(QByteArray::fromHex(result.captured(1).toLatin1()), expected);
#else
        const auto output = receivedText(received)
                                .section("HRT_INPUT_READY", 1).section("HRT_INPUT_DONE", 0, 0).trimmed();
        QCOMPARE(QByteArray::fromHex(output.toLatin1()), expected);
#endif
    }

    void canonicalErase() {
        QQmlEngine engine;
        engine.addImportPath(QStringLiteral(TEST_PLUGIN_PATH));
        QQmlComponent component(&engine);
        component.setData(R"(
            import QtQuick
            import QMLTermWidget 2.0
            QMLTermWidget {
                width: 640; height: 480
                session: QMLTermSession {}
            }
        )", QUrl());
        std::unique_ptr<QObject> terminal(component.create());
        QVERIFY2(terminal, qPrintable(component.errorString()));
        auto *session = terminal->property("session").value<QObject *>();
        QVERIFY(session);
        QSignalSpy received(session, SIGNAL(receivedData(QString)));
        QVERIFY(received.isValid());
#ifdef Q_OS_WIN
        QVERIFY(session->setProperty("shellProgram", qEnvironmentVariable("COMSPEC", "cmd.exe")));
        const QString command = "echo HRT_LINE_READY & set /p HRT_LINE= & echo HRT_LINE_RESULT[!HRT_LINE!]";
        QVERIFY(session->setProperty("shellProgramArgs", QStringList{"/D", "/Q", "/V:ON", "/K", command}));
#else
        QVERIFY(session->setProperty("shellProgram", "/bin/sh"));
        const QString command = "printf 'HRT_LINE_READY\\n'; IFS= read -r line; "
                                "printf 'HRT_LINE_RESULT[%s]\\n' \"$line\"; exec /bin/cat";
        QVERIFY(session->setProperty("shellProgramArgs", QStringList{"-c", command}));
#endif
        QVERIFY(QMetaObject::invokeMethod(session, "startShellProgram"));
        QTRY_VERIFY_WITH_TIMEOUT(receivedText(received).contains("HRT_LINE_READY"), 5000);
        sendKey(terminal.get(), Qt::Key_A, Qt::NoModifier, "a");
        sendKey(terminal.get(), Qt::Key_B, Qt::NoModifier, "b");
        sendKey(terminal.get(), Qt::Key_Backspace, Qt::NoModifier, QString(QChar(8)));
        sendKey(terminal.get(), Qt::Key_C, Qt::NoModifier, "c");
        sendKey(terminal.get(), Qt::Key_Return, Qt::NoModifier, "\r");
        QTRY_VERIFY2_WITH_TIMEOUT(receivedText(received).contains("HRT_LINE_RESULT[ac]"),
                                 qPrintable(receivedText(received)), 5000);
    }
#ifdef Q_OS_WIN
    void wslReadlineInput() {
        const auto distro = qEnvironmentVariable("HRT_TEST_WSL_DISTRO");
        if (distro.isEmpty()) QSKIP("Set HRT_TEST_WSL_DISTRO to run the optional WSL readline check");
        QQmlEngine engine;
        engine.addImportPath(QStringLiteral(TEST_PLUGIN_PATH));
        QQmlComponent component(&engine);
        component.setData(R"(
            import QtQuick
            import QMLTermWidget 2.0
            QMLTermWidget { width: 640; height: 480; session: QMLTermSession {} }
        )", QUrl());
        std::unique_ptr<QObject> terminal(component.create());
        QVERIFY2(terminal, qPrintable(component.errorString()));
        auto *session = terminal->property("session").value<QObject *>();
        QVERIFY(session);
        QSignalSpy received(session, SIGNAL(receivedData(QString)));
        QVERIFY(session->setProperty("shellProgram", "wsl.exe"));
        const QString script = "bind 'set enable-bracketed-paste on'; "
                               "read -e -p HRT_WSL_READY line; printf 'HRT_WSL_RESULT[%s]\\n' \"$line\"; sleep 30";
        QVERIFY(session->setProperty("shellProgramArgs", QStringList{
            "-d", distro, "--", "bash", "--noprofile", "--norc", "-ic", script}));
        QVERIFY(QMetaObject::invokeMethod(session, "startShellProgram"));
        QTRY_VERIFY2_WITH_TIMEOUT(receivedText(received).contains("HRT_WSL_READY"),
                                 qPrintable(receivedText(received)), 15000);
        QVERIFY(QMetaObject::invokeMethod(session, "sendText", Q_ARG(QString, QString("discard"))));
        sendKey(terminal.get(), Qt::Key_U, controlModifier, QString(QChar(0x15)));
        auto previousClipboard = std::make_unique<QMimeData>();
        const auto *clipboardData = QApplication::clipboard()->mimeData();
        if (clipboardData) {
            for (const auto &format : clipboardData->formats())
                previousClipboard->setData(format, clipboardData->data(format));
        }
        const auto restoreClipboard = qScopeGuard([&]() {
            QApplication::clipboard()->setMimeData(previousClipboard.release());
        });
        QApplication::clipboard()->setText("HRT_PASTE_CHECK");
        QVERIFY(QMetaObject::invokeMethod(terminal.get(), "pasteClipboard"));
        sendKey(terminal.get(), Qt::Key_Return, Qt::NoModifier, "\r");
        QTRY_VERIFY2_WITH_TIMEOUT(receivedText(received).contains("HRT_WSL_RESULT[HRT_PASTE_CHECK]"),
                                 qPrintable(receivedText(received)), 5000);
    }
#endif
};

QTEST_MAIN(TerminalInputTest)
#include "terminal_input.moc"
