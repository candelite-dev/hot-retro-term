#include <QTest>
#include <QDir>
#include <QTemporaryDir>
#include "launchoptions.h"

class LaunchOptionsTest : public QObject {
    Q_OBJECT
private slots:
    void defaults() {
        auto result = parseLaunchOptions({"hrt"}, QDir::tempPath());
        QVERIFY(result.isValid());
        QCOMPARE(result.options.workingDirectory, QDir::tempPath());
        QVERIFY(result.options.command.isEmpty());
        QVERIFY(!result.options.fullscreen);
    }
    void childArgumentsAreOpaque() {
        auto result = parseLaunchOptions({"hrt", "--verbose", "-e", "printf", "--profile", "child", "--fullscreen", "--workdir"}, QDir::tempPath());
        QVERIFY(result.isValid());
        QCOMPARE(result.options.command, "printf");
        QCOMPARE(result.options.commandArguments, (QStringList{"--profile", "child", "--fullscreen", "--workdir"}));
        QVERIFY(result.options.profile.isEmpty());
        QVERIFY(!result.options.fullscreen);
        QVERIFY(result.options.verbose);
    }
    void profileAliases_data() {
        QTest::addColumn<QString>("flag");
        QTest::newRow("short") << "-p";
        QTest::newRow("long") << "--profile";
    }
    void profileAliases() {
        QFETCH(QString, flag);
        auto result = parseLaunchOptions({"hrt", "--fullscreen", flag, "Monochrome Green", "--default-settings"}, QDir::tempPath());
        QVERIFY(result.isValid());
        QCOMPARE(result.options.profile, "Monochrome Green");
        QVERIFY(result.options.fullscreen);
        QVERIFY(result.options.defaultSettings);
        QCOMPARE(result.options.toVariantMap().value("profile").toString(), "Monochrome Green");
    }
    void invalidArguments_data() {
        QTest::addColumn<QStringList>("args");
        QTest::newRow("missing-directory") << QStringList{"--workdir"};
        QTest::newRow("missing-profile") << QStringList{"--profile"};
        QTest::newRow("missing-short-profile") << QStringList{"-p"};
        QTest::newRow("missing-command") << QStringList{"-e"};
        QTest::newRow("empty-command") << QStringList{"-e", ""};
        QTest::newRow("empty-directory") << QStringList{"--workdir="};
        QTest::newRow("empty-profile") << QStringList{"--profile="};
        QTest::newRow("unknown") << QStringList{"--fullscren"};
        QTest::newRow("positional") << QStringList{"sh"};
        QTest::newRow("no-such-directory") << QStringList{"--workdir", "/this-directory-does-not-exist-hrt"};
    }
    void invalidArguments() {
        QFETCH(QStringList, args);
        args.prepend("hrt");
        const auto result = parseLaunchOptions(args, QDir::tempPath());
        QVERIFY(!result.isValid());
        QVERIFY(!result.error.isEmpty());
    }
    void valueMayBeNamedLikeCommandOption() {
        auto result = parseLaunchOptions({"hrt", "-p", "-e"}, QDir::tempPath());
        QVERIFY(result.isValid());
        QCOMPARE(result.options.profile, "-e");
        QVERIFY(result.options.command.isEmpty());
    }
    void helpAndVersionCanFollowOtherFlags() {
        for (const auto &flag : {"-h", "--help", "--help-all"}) {
            const auto help = parseLaunchOptions({"hrt", "--verbose", flag}, QDir::tempPath());
            QVERIFY(help.isValid());
            QVERIFY(help.options.help);
            QVERIFY(help.helpText.startsWith("Usage: hrt "));
            QVERIFY(help.helpText.contains("-e"));
        }
        const auto version = parseLaunchOptions({"hrt", "--verbose", "--version"}, QDir::tempPath());
        QVERIFY(version.isValid());
        QVERIFY(version.options.version);
    }
    void relativeDirectory() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QVERIFY(QDir(dir.path()).mkdir("space in name"));
        auto result = parseLaunchOptions({"hrt", "--workdir", "space in name"}, dir.path());
        QVERIFY(result.isValid());
        QCOMPARE(result.options.workingDirectory, dir.path() + "/space in name");
    }
};
QTEST_GUILESS_MAIN(LaunchOptionsTest)
#include "launchoptions_test.moc"
