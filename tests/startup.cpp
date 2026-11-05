#include <QApplication>
#include <QColor>
#include <QDir>
#include <QFontMetrics>
#include <QFontMetricsF>
#include <QImage>
#include <QJSValue>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickItem>
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
    QList<QQuickItem *> visualItems(QQuickItem *parent, const QString &name) {
        QList<QQuickItem *> found;
        for (auto *child : parent->childItems()) {
            if (child->objectName() == name) found.append(child);
            found.append(visualItems(child, name));
        }
        return found;
    }
    void verifyTabFont(AppFixture &app) {
        auto *bar = app.window()->findChild<QQuickItem *>("sharedTabBar");
        QVERIFY(bar);
        auto *terminal = app.evaluate("tabs.focusedTerminal.mainTerminal").toQObject();
        QVERIFY(terminal);
        const auto cells = terminal->property("fontMetrics").toSize();
        const auto font = terminal->property("font").value<QFont>();
        const auto scale = app.evaluate("tabs.focusedTerminal.screenScaling").toNumber();
        const QSizeF displayed(cells.width() * scale, cells.height() * scale);
        QTRY_COMPARE(bar->property("charMetrics").toSizeF(), displayed);
        QCOMPARE(bar->height(), displayed.height());
        QCOMPARE(bar->property("screenScaling").toReal(), scale);

        const auto labels = visualItems(bar, "tabLabel");
        QVERIFY(!labels.isEmpty());
        for (auto *label : labels + visualItems(bar, "addTabLabel")) {
            const auto aligned = label->property("font").value<QFont>();
            auto restored = aligned;
            restored.setLetterSpacing(font.letterSpacingType(), font.letterSpacing());
            QCOMPARE(restored, font); // Includes native size, weight, kerning and hinting.
            QCOMPARE(label->property("antialiasing").toBool(), terminal->property("antialiasText").toBool());
            QCOMPARE(label->property("renderType").toInt(), 1); // Text.NativeRendering
            QCOMPARE(label->property("textFormat").toInt(), 0); // Text.PlainText
            const auto baseline = label->y() + label->property("baselineOffset").toReal();
            const auto expected = QFontMetrics(font).ascent() + terminal->property("lineSpacing").toInt();
            QVERIFY(qAbs(baseline - expected) < 0.01);
            const auto text = label->property("text").toString();
            QVERIFY(!text.isEmpty());
            const auto advance = QFontMetricsF(aligned).horizontalAdvance(text);
            QVERIFY2(qAbs(advance - text.size() * cells.width()) < 0.1,
                     qPrintable(QString("Long label drift: %1 vs %2").arg(advance).arg(text.size() * cells.width())));
            QVERIFY(qAbs(label->property("advance").toSizeF().width() - advance) < 0.1);
            const auto displayedWidth = label->mapToItem(bar, QPointF(label->width(), 0)).x()
                                      - label->mapToItem(bar, QPointF(0, 0)).x();
            QVERIFY(qAbs(displayedWidth - text.size() * displayed.width()) < 0.1);
        }
        // Active background and clipping rectangle use the same displayed grid.
        const auto tabWidth = bar->property("tabPixelWidth").toReal();
        const auto *tab = labels.first()->parentItem();
        QVERIFY(tab->clip());
        QVERIFY(qAbs(tab->width() * scale - tabWidth) < 0.01);
        QVERIFY(qAbs(tab->height() * scale - displayed.height()) < 0.01);
    }

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

    void burnInFeedbackStaysBufferedDuringResizeAndZoom_data() {
        QTest::addColumn<QString>("layout");
        QTest::newRow("single-terminal") << QString("single");
        QTest::newRow("shared-tabs") << QString("tabs");
        QTest::newRow("shared-splits") << QString("split");
    }
    void burnInFeedbackStaysBufferedDuringResizeAndZoom() {
        QFETCH(QString, layout);
        AppFixture app;
        app.load();
        QVERIFY(!app.engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(app.window());
        QVERIFY(window);
        auto *tabs = window->findChild<QObject *>("terminalTabs");
        QVERIFY(tabs);
        app.engine.globalObject().setProperty("tabs", app.engine.newQObject(tabs));
        QTRY_VERIFY(app.evaluate("tabs.focusedTerminal !== null").toBool());
        app.evaluate("root.appSettings.burnIn = 0.5");
        if (layout == "tabs") app.evaluate("tabs.addTab()");
        if (layout == "split") app.evaluate("tabs.splitPane(Qt.Horizontal)");
        auto *crt = layout == "single"
            ? app.evaluate("tabs.focusedTerminal").toQObject()
            : window->findChild<QObject *>("unifiedCRT");
        QVERIFY(crt);
        auto *burnIn = crt->property("burnInEffect").value<QObject *>();
        QVERIFY(burnIn);
        QTRY_VERIFY(burnIn->property("effectSource").value<QObject *>());
        auto *buffer = burnIn->property("effectSource").value<QObject *>();
        QVERIFY(QTest::qWaitForWindowExposed(window));
        QTRY_VERIFY(buffer->property("recursive").toBool());

        // A shader that samples its own output needs a separate previous-frame
        // texture on every frame, including while the render target changes size.
        const auto width = buffer->property("width").toReal();
        const auto height = buffer->property("height").toReal();
        window->resize(window->width() + 120, window->height() + 80);
        QTRY_VERIFY(buffer->property("width").toReal() != width);
        QTRY_VERIFY(buffer->property("height").toReal() != height);
        QVERIFY2(buffer->property("recursive").toBool(),
                 "Resize made the burn-in shader read from its active render target");
        for (const qreal zoom : {0.65, 1.5, 1.0}) {
            app.evaluate(QString("root.appSettings.fontScaling = %1").arg(zoom));
            QCoreApplication::processEvents();
            QVERIFY2(buffer->property("recursive").toBool(),
                     "Font zoom disabled previous-frame buffering");
            QVERIFY(!window->grabWindow().isNull());
        }
        QVERIFY(burnIn->property("active").toBool());
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
    void tabFontMatchesTerminal_data() {
        QTest::addColumn<QString>("fontName");
        QTest::addColumn<int>("rasterization");
        QTest::addColumn<qreal>("zoom");
        for (const auto &name : {QString("IBM_VGA_8x16"), QString("TERMINESS_SCALED"), QString("JETBRAINS_MONO")}) {
            for (const qreal zoom : {0.65, 1.0, 1.5}) {
                const auto row = QString("%1-%2").arg(name).arg(zoom);
                QTest::newRow(qPrintable(row)) << name << (name == "JETBRAINS_MONO" ? 4 : 1) << zoom;
            }
        }
    }
    void tabFontMatchesTerminal() {
        QFETCH(QString, fontName);
        QFETCH(int, rasterization);
        QFETCH(qreal, zoom);
        AppFixture app;
        app.load();
        QVERIFY(!app.engine.rootObjects().isEmpty());
        auto *tabs = app.window()->findChild<QObject *>("terminalTabs");
        QVERIFY(tabs);
        app.engine.globalObject().setProperty("tabs", app.engine.newQObject(tabs));
        QTRY_VERIFY(app.evaluate("tabs.focusedTerminal !== null").toBool());
        app.evaluate("tabs.addTab()");
        QTRY_COMPARE(app.evaluate("tabs.count").toInt(), 2);
        auto *bar = app.window()->findChild<QQuickItem *>("sharedTabBar");
        QVERIFY(bar);
        app.engine.globalObject().setProperty("bar", app.engine.newQObject(bar));
        // A long, repeated label makes even small fractional advances accumulate.
        app.evaluate("bar.tabTitles = ['MW0123456789'.repeat(100), '<b>plain</b>']");
        app.evaluate(QString("root.appSettings.loadProfileString("
                             "'{\"fontSource\":0,\"fontName\":\"%1\",\"rasterization\":%2,\"lineSpacing\":0.1}')")
                         .arg(fontName).arg(rasterization));
        app.evaluate(QString("root.appSettings.fontScaling = %1").arg(zoom));
        auto *window = qobject_cast<QQuickWindow *>(app.window());
        QVERIFY(QTest::qWaitForWindowExposed(window));
        verifyTabFont(app);
        QVERIFY(app.evaluate("bar.buildTabLabel(0).indexOf('…') >= 0").toBool());
        QCOMPARE(app.evaluate("bar.buildTabLabel(0).length === bar.charsPerTab").toBool(), true);

        // Resize, focus a split, and switch tabs without losing the font binding.
        window->resize(1000, 700);
        QTRY_VERIFY(bar->width() > 900);
        verifyTabFont(app);
        app.evaluate("tabs.splitPane(Qt.Horizontal)");
        QTRY_VERIFY(app.evaluate("tabs.isSplitMode").toBool());
        verifyTabFont(app);
        app.evaluate("tabs.currentIndex = 0");
        QTRY_COMPARE(app.evaluate("tabs.currentIndex").toInt(), 0);
        verifyTabFont(app);

        // Exercise the real InputRouter at displayed tab and [+] coordinates.
        app.evaluate("root.appSettings.screenCurvature = 0; root.appSettings.windowCurvature = 0");
        auto point = bar->mapToScene(QPointF(bar->property("tabPixelWidth").toReal() * 1.5, bar->height() / 2));
        QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, point.toPoint());
        QTRY_COMPARE(app.evaluate("tabs.currentIndex").toInt(), 1);
        const qreal addX = 2 * bar->property("tabPixelWidth").toReal() + bar->property("charMetrics").toSizeF().width() * 2;
        point = bar->mapToScene(QPointF(addX, bar->height() / 2));
        QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, point.toPoint());
        QTRY_COMPARE(app.evaluate("tabs.count").toInt(), 3);
        verifyTabFont(app);

        // Optional standard/Retina captures for desktop and offscreen review.
        const auto prefix = qEnvironmentVariable("HRT_TEST_TAB_SCREENSHOTS");
        if (!prefix.isEmpty()) {
            qInfo() << "Capture device pixel ratio:" << window->devicePixelRatio();
            app.engine.globalObject().setProperty("layout", app.engine.newQObject(bar->parentItem()->parentItem()));
            app.engine.globalObject().setProperty("shared", app.engine.newQObject(app.window()->findChild<QObject *>("unifiedCRT")));
            app.evaluate("tabs.focusedTerminal.mainTerminal.session.sendText('MW0123456789 MW0123456789 MW0123456789\\n')");
            QTRY_VERIFY(app.evaluate("tabs.focusedTerminal.mainTerminal.session.history.indexOf('MW0123456789') >= 0").toBool());
            app.evaluate("root.appSettings.loadProfileString('{\"ambientLight\":0,\"bloom\":0,\"burnIn\":0,"
                         "\"flickering\":0,\"glowingLine\":0,\"horizontalSync\":0,\"jitter\":0,\"rgbShift\":0,"
                         "\"screenCurvature\":0,\"staticNoise\":0,\"frameSize\":0,\"frameShininess\":0}')");
            for (const bool effects : {false, true}) {
                // Show the shared source directly for a comparison before CRT
                // distortion. Do not change rasterization: that selects fonts.
                app.evaluate(effects ? "layout.paneSource.hideSource = true; shared.visible = true"
                                     : "layout.paneSource.hideSource = false; shared.visible = false");
                if (effects) app.evaluate("root.appSettings.bloom = 0.3; root.appSettings.screenCurvature = 0.2");
                QTest::qWait(100);
                const auto frame = window->grabWindow();
                QVERIFY(!frame.isNull());
                QVERIFY(frame.save(QString("%1-%2-%3-%4.png").arg(prefix, fontName).arg(zoom).arg(effects ? "crt" : "plain")));
            }
        }
    }
    void tabFontFollowsLiveProfileAndSpacingChanges() {
        AppFixture app;
        app.load();
        QVERIFY(!app.engine.rootObjects().isEmpty());
        auto *tabs = app.window()->findChild<QObject *>("terminalTabs");
        QVERIFY(tabs);
        app.engine.globalObject().setProperty("tabs", app.engine.newQObject(tabs));
        app.evaluate("tabs.addTab()");
        QVERIFY(QTest::qWaitForWindowExposed(qobject_cast<QQuickWindow *>(app.window())));
        for (const auto &name : {"IBM_VGA_8x16", "JETBRAINS_MONO", "TERMINESS_SCALED"}) {
            app.evaluate(QString("root.appSettings.loadProfileString("
                                 "'{\"fontName\":\"%1\",\"rasterization\":%2,\"lineSpacing\":0.3}')")
                             .arg(name).arg(QString(name) == "JETBRAINS_MONO" ? 4 : 1));
            app.evaluate("root.appSettings.fontScaling = 0.65");
            verifyTabFont(app);
            app.evaluate("root.appSettings.fontScaling = 1.5; root.appSettings.lineSpacing = 0");
            verifyTabFont(app);
        }
    }
    void legacyTabScaleDoesNotAffectStartup() {
        AppFixture app;
        QVERIFY(app.seed("_CURRENT_SETTINGS", "{\"tabBarScale\":5,\"windowScaling\":0.8}"));
        app.load();
        QVERIFY(!app.engine.rootObjects().isEmpty());
        QCOMPARE(app.evaluate("root.appSettings.windowScaling").toNumber(), 0.8);
        QVERIFY(app.evaluate("root.appSettings.tabBarScale === undefined").toBool());
        QVERIFY(app.evaluate("root.appSettings.storeSettings()").toBool());
        QVERIFY(!app.read("_CURRENT_SETTINGS").contains("tabBarScale"));
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
