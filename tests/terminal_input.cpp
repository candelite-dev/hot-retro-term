#include <QApplication>
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
        QVERIFY(session->setProperty("shellProgram", "/bin/sh"));
        const auto command = QString(
            "LC_ALL=C; export LC_ALL; stty -a; stty raw -echo; "
            "printf 'HRT_INPUT_READY\\n'; od -An -tx1 -N %1; "
            "printf 'HRT_INPUT_DONE\\n'; exec /bin/cat").arg(expected.size());
        QVERIFY(session->setProperty("shellProgramArgs", QStringList{"-c", command}));
        QVERIFY(QMetaObject::invokeMethod(session, "startShellProgram"));
        QTRY_VERIFY_WITH_TIMEOUT(receivedText(received).contains("HRT_INPUT_READY"), 5000);
        QVERIFY2(receivedText(received).contains(QRegularExpression("\\berase\\s*=\\s*\\^\\?")),
                 "The PTY erase character must match the Backspace byte (DEL)");

        sendKey(terminal.get(), key, modifiers, text);
        QTRY_VERIFY_WITH_TIMEOUT(receivedText(received).contains("HRT_INPUT_DONE"), 5000);
        const auto output = receivedText(received)
                                .section("HRT_INPUT_READY", 1).section("HRT_INPUT_DONE", 0, 0).trimmed();
        QCOMPARE(QByteArray::fromHex(output.toLatin1()), expected);
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
        QVERIFY(session->setProperty("shellProgram", "/bin/sh"));
        const QString command = "printf 'HRT_LINE_READY\\n'; IFS= read -r line; "
                                "printf 'HRT_LINE_RESULT[%s]\\n' \"$line\"; exec /bin/cat";
        QVERIFY(session->setProperty("shellProgramArgs", QStringList{"-c", command}));
        QVERIFY(QMetaObject::invokeMethod(session, "startShellProgram"));
        QTRY_VERIFY_WITH_TIMEOUT(receivedText(received).contains("HRT_LINE_READY"), 5000);
        sendKey(terminal.get(), Qt::Key_A, Qt::NoModifier, "a");
        sendKey(terminal.get(), Qt::Key_B, Qt::NoModifier, "b");
        sendKey(terminal.get(), Qt::Key_Backspace, Qt::NoModifier, QString(QChar(8)));
        sendKey(terminal.get(), Qt::Key_C, Qt::NoModifier, "c");
        sendKey(terminal.get(), Qt::Key_Return, Qt::NoModifier, "\r");
        QTRY_VERIFY_WITH_TIMEOUT(receivedText(received).contains("HRT_LINE_RESULT[ac]"), 5000);
    }
};

QTEST_MAIN(TerminalInputTest)
#include "terminal_input.moc"
