#include <QApplication>
#include <QColor>
#include <QDir>
#include <QImage>
#include <QJSValue>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QResource>
#include <QRegularExpression>
#include <QSemaphore>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QThreadPool>
#include <memory>
#include "fileio.h"
#include "fontmanager.h"
#include "fontlistmodel.h"
#include "curvatureinputfilter.h"
#include "launchoptions.h"

// Native window chrome is outside a headless test's remit.
class TestChrome : public QObject {
    Q_OBJECT
public:
    Q_INVOKABLE void applyWindowChrome(QWindow *, const QColor &, qreal, int) {}
};

// Each case uses the real QML/resources, plugin, SQLite, and a controlled shell.
// Declare the engine last so its context objects outlive it during destruction.
struct AppFixture {
    QTemporaryDir directory;
    FileIO files;
    TestChrome chrome;
    QQmlApplicationEngine engine;
    std::unique_ptr<QObject> storage;

    explicit AppFixture(const QStringList &flags = {}) {
        // Qt LocalStorage caches connections by database name across engines.
        // Keep its private directory alive for the process and clear rows per case.
        static QTemporaryDir offlineStorage;
        engine.setOfflineStoragePath(offlineStorage.path());
        engine.addImportPath(QStringLiteral(TEST_PLUGIN_PATH));
        auto *context = engine.rootContext();
        context->setContextProperty("appVersion", "test");
        context->setContextProperty("fileIO", &files);
        context->setContextProperty("macWindowHelper", &chrome);
        const auto arguments = QStringList{"test"} + flags + QStringList{
            "-e", "/bin/sh", "-c", "printf HRT_SMOKE_READY; exec /bin/cat"};
        const auto launch = parseLaunchOptions(arguments, directory.path());
        Q_ASSERT(launch.isValid());
        context->setContextProperty("launchOptions", launch.options.toVariantMap());
        QQmlComponent component(&engine, QUrl("qrc:/Storage.qml"));
        storage.reset(component.create());
        storedCall("dropSettings");
    }
    ~AppFixture() {
        // Avoid invoking the application's last-window Qt.quit() in the runner.
        if (!engine.rootObjects().isEmpty()) {
            const int count = evaluate("root.windowsModel.count").toInt();
            for (int i = count - 1; i >= 0; --i) delete window(i);
        }
    }
    QJSValue evaluate(const QString &script) {
        auto result = engine.evaluate(script);
        if (result.isError()) qWarning().noquote() << result.toString();
        return result;
    }
    void load() {
        engine.load(QUrl("qrc:/main.qml"));
        if (!engine.rootObjects().isEmpty())
            engine.globalObject().setProperty("root", engine.newQObject(engine.rootObjects().first()));
    }
    QObject *window(int index = 0) {
        return evaluate(QString("root.windowsModel.get(%1).window").arg(index)).toQObject();
    }
    QJSValue storedCall(const char *method, const QJSValueList &args = {}) {
        if (!storage) return {};
        auto object = engine.newQObject(storage.get());
        return object.property(method).callWithInstance(object, args);
    }
    bool seed(const QString &key, const QString &value) {
        const auto result = storedCall("setSetting", {key, value});
        return !result.isError() && result.toString() == "OK";
    }
    QString read(const QString &key) { return storedCall("getSetting", {key}).toString(); }
};

class StartupTest : public QObject {
    Q_OBJECT
private slots:
    void init() {
        QTest::failOnWarning(QRegularExpression("QProcess: Destroyed while process.*"));
        QTest::failOnWarning(QRegularExpression(".*(ReferenceError|TypeError|Cannot assign|Conflicting properties).*"));
    }
    void startsAndKeepsSessionsAcrossLayouts() {
        AppFixture app;
        QVERIFY(app.directory.isValid());
        app.load();
        QVERIFY2(!app.engine.rootObjects().isEmpty(), "The application QML failed to load");
        QTRY_COMPARE(app.evaluate("root.windowsModel.count").toInt(), 1);
        auto *window = app.window();
        QVERIFY(window);
        auto *tabs = window->findChild<QObject *>("terminalTabs");
        QVERIFY(tabs);
        app.engine.globalObject().setProperty("tabs", app.engine.newQObject(tabs));
        QTRY_VERIFY(app.evaluate("tabs.focusedTerminal !== null").toBool());
        QTRY_VERIFY(app.evaluate("tabs.focusedTerminal.mainTerminal.session.history.indexOf('HRT_SMOKE_READY') >= 0").toBool());
        auto *quickWindow = qobject_cast<QQuickWindow *>(window);
        QVERIFY(quickWindow);
        QVERIFY(QTest::qWaitForWindowExposed(quickWindow));
        const auto frame = quickWindow->grabWindow();
        QVERIFY2(!frame.isNull(), "The renderer did not produce a frame");
        const auto screenshot = qEnvironmentVariable("HRT_TEST_SCREENSHOT");
        if (!screenshot.isEmpty()) QVERIFY(frame.save(screenshot));
        const int firstPid = app.evaluate("tabs.focusedTerminal.mainTerminal.session.getShellPID()").toInt();
        QVERIFY(firstPid > 0);
        app.evaluate("tabs.splitPane(Qt.Horizontal)");
        QTRY_VERIFY(app.evaluate("tabs.isSplitMode").toBool());
        QTRY_VERIFY(app.evaluate("tabs.focusedTerminal.mainTerminal.session.getShellPID() > 0").toBool());
        app.evaluate("tabs.addTab()");
        QTRY_COMPARE(app.evaluate("tabs.count").toInt(), 2);
        app.evaluate("tabs.currentIndex = 0");
        QTRY_COMPARE(app.evaluate("tabs.focusedTerminal.mainTerminal.session.getShellPID()").toInt(), firstPid);
        app.evaluate("tabs.closeTab(1)");
        QTRY_COMPARE(app.evaluate("tabs.count").toInt(), 1);
        app.evaluate("tabs.moveFocus('right'); tabs.closeFocusedPane()");
        QTRY_VERIFY(!app.evaluate("tabs.isSplitMode").toBool());
        QTRY_COMPARE(app.evaluate("tabs.focusedTerminal.mainTerminal.session.getShellPID()").toInt(), firstPid);
        QTRY_VERIFY(app.evaluate("tabs.focusedTerminal.mainTerminal.width > 0 && tabs.terminalSize.width > 0").toBool());
    }

    void smallRetinaFontKeepsSelectedRasterization() {
        AppFixture app;
        app.load();
        QVERIFY(!app.engine.rootObjects().isEmpty());
        auto *tabs = app.window()->findChild<QObject *>("terminalTabs");
        QVERIFY(tabs);
        app.engine.globalObject().setProperty("tabs", app.engine.newQObject(tabs));
        app.evaluate("root.appSettings.fontScaling = 0.65; root.appSettings.loadProfileString("
                     "'{\"fontSource\":0,\"fontName\":\"IBM_VGA_8x16\",\"rasterization\":1,\"lineSpacing\":0.1}')");
        QTRY_VERIFY(app.evaluate("tabs.focusedTerminal !== null").toBool());
        QVERIFY(QTest::qWaitForWindowExposed(qobject_cast<QQuickWindow *>(app.window())));
        // Model a Retina output independently of the headless runner's screen.
        app.evaluate("tabs.focusedTerminal.screenResolution = Qt.size("
                     "tabs.focusedTerminal.width * 2, tabs.focusedTerminal.height * 2)");
        const auto density = app.evaluate("tabs.focusedTerminal._screenDensity").toNumber();
        QVERIFY(density > 1.9 && density < 2.0);
        QObject *effect = nullptr;
        for (auto *item : tabs->findChildren<QObject *>()) {
            if (item->property("rasterMode").isValid()) { effect = item; break; }
        }
        QVERIFY(effect);
        app.engine.globalObject().setProperty("effect", app.engine.newQObject(effect));
        const auto strength = app.evaluate("effect.rasterizationIntensity").toNumber();
        QVERIFY2(strength > 0.9, "Selected scanlines disappear at a usable 65% font scale on Retina");
        app.evaluate("tabs.focusedTerminal.screenResolution = Qt.size("
                     "tabs.focusedTerminal.virtualResolution.width * 0.5,"
                     "tabs.focusedTerminal.virtualResolution.height * 0.5)");
        QCOMPARE(app.evaluate("effect.rasterizationIntensity").toNumber(), 0.0);
    }
    void sharedRasterizationKeepsFontPixelGrid_data() {
        QTest::addColumn<bool>("split");
        QTest::addColumn<qreal>("fontScale");
        QTest::newRow("split-small") << true << qreal(0.65);
        QTest::newRow("split-large") << true << qreal(1.5);
        QTest::newRow("tabs-small") << false << qreal(0.65);
        QTest::newRow("tabs-large") << false << qreal(1.5);
    }
    void sharedRasterizationKeepsFontPixelGrid() {
        QFETCH(bool, split);
        QFETCH(qreal, fontScale);
        AppFixture app;
        app.load();
        QVERIFY(!app.engine.rootObjects().isEmpty());
        auto *tabs = app.window()->findChild<QObject *>("terminalTabs");
        QVERIFY(tabs);
        app.engine.globalObject().setProperty("tabs", app.engine.newQObject(tabs));
        app.evaluate(QString("root.appSettings.fontScaling = %1").arg(fontScale));
        app.evaluate("root.appSettings.loadProfileString("
                     "'{\"fontSource\":0,\"fontName\":\"IBM_VGA_8x16\",\"rasterization\":1,\"lineSpacing\":0.1}')");
        QTRY_VERIFY(app.evaluate("tabs.focusedTerminal !== null").toBool());
        QVERIFY(QTest::qWaitForWindowExposed(qobject_cast<QQuickWindow *>(app.window())));
        const auto horizontal = app.evaluate("tabs.focusedTerminal.virtualResolution.width / tabs.focusedTerminal.width").toNumber();
        const auto vertical = app.evaluate("tabs.focusedTerminal.virtualResolution.height / tabs.focusedTerminal.height").toNumber();
        app.evaluate(split ? "tabs.splitPane(Qt.Horizontal)" : "tabs.addTab()");
        QTRY_VERIFY(app.evaluate("tabs.needsUnifiedCRT").toBool());
        auto *shared = app.window()->findChild<QObject *>("unifiedCRT");
        QVERIFY(shared);
        app.engine.globalObject().setProperty("shared", app.engine.newQObject(shared));
        QTRY_VERIFY(app.evaluate("shared.visible").toBool());
        QVERIFY(qAbs(app.evaluate("shared.virtualResolution.width / shared.width").toNumber() - horizontal) < 0.005);
        QVERIFY(qAbs(app.evaluate("shared.virtualResolution.height / shared.height").toNumber() - vertical) < 0.005);
    }
    void corruptedSettingsStillOpenWindow_data() {
        QTest::addColumn<QString>("key");
        QTest::addColumn<QString>("raw");
        QTest::newRow("general-syntax") << "_CURRENT_SETTINGS" << "{broken";
        QTest::newRow("general-type") << "_CURRENT_SETTINGS" << "{\"windowScaling\":\"invalid\"}";
        QTest::newRow("profile-null") << "_CURRENT_PROFILE" << "null";
        QTest::newRow("profile-value") << "_CURRENT_PROFILE" << "{\"fontColor\":\"broken\"}";
        QTest::newRow("custom-profile-syntax") << "_CUSTOM_PROFILES" << "{broken";
        QTest::newRow("custom-profile-shape") << "_CUSTOM_PROFILES" << "{}";
    }
    void corruptedSettingsStillOpenWindow() {
        QFETCH(QString, key);
        QFETCH(QString, raw);
        AppFixture app;
        QVERIFY(app.storage);
        QVERIFY(app.seed("_CURRENT_SETTINGS", "{\"windowScaling\":0.8}"));
        QVERIFY(app.seed("_CURRENT_PROFILE", "{\"bloom\":0.8}"));
        QVERIFY(app.seed(key, raw));
        app.load();
        QVERIFY(!app.engine.rootObjects().isEmpty());
        QTRY_COMPARE(app.evaluate("root.windowsModel.count").toInt(), 1);
        if (key != "_CURRENT_SETTINGS") QCOMPARE(app.evaluate("root.appSettings.windowScaling").toNumber(), 0.8);
        if (key != "_CURRENT_PROFILE") QCOMPARE(app.evaluate("root.appSettings.bloom").toNumber(), 0.8);
        app.evaluate("root.appSettings.storeSettings(); root.appSettings.storeCustomProfiles()");
        QCOMPARE(app.read(key), raw);
    }
    void settingsLoadWhenAppearanceEntryIsMissing() {
        AppFixture app;
        QVERIFY(app.seed("_CURRENT_SETTINGS", "{\"windowScaling\":0.8}"));
        app.load();
        QVERIFY(!app.engine.rootObjects().isEmpty());
        QCOMPARE(app.evaluate("root.appSettings.windowScaling").toNumber(), 0.8);
    }
    void defaultSettingsExplicitlyReplaceCorruptCurrentEntries() {
        AppFixture app({"--default-settings"});
        QVERIFY(app.seed("_CURRENT_SETTINGS", "{broken"));
        QVERIFY(app.seed("_CURRENT_PROFILE", "null"));
        app.load();
        QVERIFY(!app.engine.rootObjects().isEmpty());
        QCOMPARE(app.evaluate("root.appSettings.windowScaling").toNumber(), 1.0);
        QVERIFY(app.evaluate("root.appSettings.storeSettings()").toBool());
        QVERIFY(app.read("_CURRENT_SETTINGS").contains("windowScaling"));
        QVERIFY(app.read("_CURRENT_PROFILE").contains("bloom"));
    }
    void profileAndFullscreenReachQml() {
        AppFixture app({"-p", "Monochrome Green", "--fullscreen"});
        app.load();
        QVERIFY(!app.engine.rootObjects().isEmpty());
        QTRY_VERIFY(app.window());
        QCOMPARE(app.evaluate("root.appSettings._fontColor").toString(), "#0ccc68");
        auto *window = qobject_cast<QWindow *>(app.window());
        QVERIFY(window);
        QTRY_COMPARE(window->visibility(), QWindow::FullScreen);
    }
    void storageCanBeUsedAfterDroppingSettings() {
        AppFixture app;
        QVERIFY(app.storage);
        QVERIFY(app.seed("old", "one"));
        app.storedCall("dropSettings");
        QVERIFY(app.storedCall("getSetting", {"old"}).isUndefined());
        QVERIFY(app.seed("new", "two"));
        QCOMPARE(app.read("new"), "two");
    }
    void fontDiscoveryDeliversOnce() {
        FontManager manager;
        QSignalSpy ready(&manager, &FontManager::systemFontsReady);
        QVERIFY(ready.wait(5000));
        QCOMPARE(ready.count(), 1);
    }
    void fontManagerMayBeDestroyedWithDiscoveryPending() {
        // Queue unrelated work on the global pool. Destroying a manager must
        // neither wait for that work nor leave a job using a deleted manager.
        struct BusyGlobalPool {
            QThreadPool *pool = QThreadPool::globalInstance();
            int previousLimit = pool->maxThreadCount();
            QSemaphore entered;
            QSemaphore release;
            BusyGlobalPool() {
                pool->setMaxThreadCount(1);
                pool->start([this] { entered.release(); release.tryAcquire(1, 5000); });
            }
            ~BusyGlobalPool() {
                release.release();
                pool->waitForDone();
                pool->setMaxThreadCount(previousLimit);
            }
        } busy;
        QVERIFY(busy.entered.tryAcquire(1, 5000));
        for (int i = 0; i < 3; ++i) {
            auto manager = std::make_unique<FontManager>();
            manager.reset();
            QCoreApplication::sendPostedEvents(nullptr, QEvent::MetaCall);
        }
    }
};

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(false);
    QQuickStyle::setStyle("Fusion");
    if (!QResource::registerResource(QStringLiteral(TEST_RESOURCES))) return 1;
    qmlRegisterType<FontManager>("CoolRetroTerm", 1, 0, "FontManager");
    qmlRegisterUncreatableType<FontListModel>("CoolRetroTerm", 1, 0, "FontListModel", "Owned by FontManager");
    qmlRegisterType<CurvatureInputFilter>("CoolRetroTerm", 1, 0, "CurvatureInputFilter");
    StartupTest test;
    return QTest::qExec(&test, argc, argv);
}
#include "startup.moc"
