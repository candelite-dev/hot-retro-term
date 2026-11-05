#include <QtQml/QQmlApplicationEngine>
#include <QtGui/QGuiApplication>

#include <QQmlContext>
#include <QStringList>

#include <QDir>

#include <QtWidgets/QApplication>
#include <QIcon>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QtQml/qqml.h>
#include <QSurfaceFormat>

#include <kdsingleapplication.h>

#include <QDebug>
#include <stdlib.h>

#include <QLoggingCategory>

#include <fileio.h>
#include <fontlistmodel.h>
#include <fontmanager.h>
#include <curvatureinputfilter.h>
#include "launchoptions.h"
#include <QTextStream>

#if defined(Q_OS_MAC)
#include <CoreFoundation/CoreFoundation.h>
#include <QStyleFactory>
#include <QMenu>
#include <macwindow.h>
#endif

int main(int argc, char *argv[])
{
    QStringList arguments;
    for (int i = 0; i < argc; ++i) arguments.append(QString::fromLocal8Bit(argv[i]));
    const auto launch = parseLaunchOptions(arguments, QDir::currentPath());
    if (!launch.isValid()) {
        QTextStream(stderr) << launch.error << "\nUse --help for usage.\n";
        return EXIT_FAILURE;
    }
    if (launch.options.help) {
        QTextStream(stdout) << launch.helpText;
        return EXIT_SUCCESS;
    }
    const QString appVersion(QStringLiteral(APP_VERSION));
    if (launch.options.version) {
        QTextStream(stdout) << "cool-retro-term " << appVersion << Qt::endl;
        return EXIT_SUCCESS;
    }

    // Some environmental variable are necessary on certain platforms.
    // Disable Connections slot warnings
    QLoggingCategory::setFilterRules("qt.qml.connections.warning=false");
    QGuiApplication::setHighDpiScaleFactorRoundingPolicy(Qt::HighDpiScaleFactorRoundingPolicy::Round);

    // Reserve an alpha channel on the default surface format so the CRT
    // shader's per-pixel alpha (ApplicationSettings.windowOpacity) reaches
    // the window compositor instead of being discarded as opaque. Must be
    // set before QApplication is constructed — later is a silent no-op.
    QSurfaceFormat translucentFormat = QSurfaceFormat::defaultFormat();
    translucentFormat.setAlphaBufferSize(8);
    QSurfaceFormat::setDefaultFormat(translucentFormat);

    // Also required: without this, Qt Quick's scene graph allocates its
    // render targets without an alpha channel regardless of the surface
    // format above, and the compositor never sees per-pixel transparency.
    QQuickWindow::setDefaultAlphaBuffer(true);

// #if defined (Q_OS_LINUX)
//     setenv("QSG_RENDER_LOOP", "threaded", 0);
// #endif

#if defined(Q_OS_MAC)
    // This allows UTF-8 characters usage in OSX.
    setenv("LC_CTYPE", "UTF-8", 1);

    // Ensure key repeat works for letter keys (disable macOS press-and-hold for this app).
    CFPreferencesSetAppValue(CFSTR("ApplePressAndHoldEnabled"), kCFBooleanFalse, kCFPreferencesCurrentApplication);
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);

    // Qt6 macOS default look is still lacking, so let's force Fusion for now
    QQuickStyle::setStyle(QStringLiteral("Fusion"));
#endif

    // Qt must not consume options belonging to the command after -e.
    int guiArgc = 1;
    char *guiArgv[] = {argv[0], nullptr};
    QApplication app(guiArgc, guiArgv);
    app.setAttribute(Qt::AA_MacDontSwapCtrlAndMeta, true);
    app.setApplicationName(QStringLiteral("cool-retro-term"));
    app.setOrganizationName(QStringLiteral("cool-retro-term"));
    app.setOrganizationDomain(QStringLiteral("cool-retro-term"));
    app.setApplicationVersion(appVersion);

    KDSingleApplication singleApp(QStringLiteral("cool-retro-term"));

    if (!singleApp.isPrimaryInstance()) {
        if (singleApp.sendMessage("new-window"))
            return 0;
        qWarning() << "KDSingleApplication: primary not reachable, continuing as independent instance.";
    }

    QQmlApplicationEngine engine;
    FileIO fileIO;

    qmlRegisterType<FontManager>("CoolRetroTerm", 1, 0, "FontManager");
    qmlRegisterUncreatableType<FontListModel>("CoolRetroTerm", 1, 0, "FontListModel", "FontListModel is created by FontManager");
    qmlRegisterType<CurvatureInputFilter>("CoolRetroTerm", 1, 0, "CurvatureInputFilter");

#if !defined(Q_OS_MAC)
    app.setWindowIcon(QIcon::fromTheme("cool-retro-term", QIcon(":../icons/32x32/cool-retro-term.png")));
#if defined(Q_OS_LINUX)
    QGuiApplication::setDesktopFileName(QStringLiteral("cool-retro-term"));
#endif
#else
    app.setWindowIcon(QIcon(":../icons/32x32/cool-retro-term.png"));
#endif

    engine.rootContext()->setContextProperty("appVersion", appVersion);
    engine.rootContext()->setContextProperty("launchOptions", launch.options.toVariantMap());
    engine.rootContext()->setContextProperty("fileIO", &fileIO);

#if defined(Q_OS_MAC)
    MacWindowHelper macWindowHelper;
    engine.rootContext()->setContextProperty("macWindowHelper", &macWindowHelper);
#endif

    // Manage import paths for Linux and OSX.
    QStringList importPathList = engine.importPathList();
    importPathList.append(QCoreApplication::applicationDirPath() + "/qmltermwidget");
    importPathList.append(QCoreApplication::applicationDirPath() + "/../PlugIns");
    importPathList.append(QCoreApplication::applicationDirPath() + "/../../../qmltermwidget");
    engine.setImportPathList(importPathList);

    engine.load(QUrl(QStringLiteral ("qrc:/main.qml")));

    if (engine.rootObjects().isEmpty()) {
        qDebug() << "Cannot load QML interface";
        return EXIT_FAILURE;
    }

    // Quit the application when the engine closes.
    QObject::connect((QObject*) &engine, SIGNAL(quit()), (QObject*) &app, SLOT(quit()));

    auto requestNewWindow = [&engine]() {
        if (engine.rootObjects().isEmpty())
            return;

        QObject *rootObject = engine.rootObjects().constFirst();
        QMetaObject::invokeMethod(rootObject, "createWindow", Qt::QueuedConnection);
    };

    QObject::connect(&singleApp, &KDSingleApplication::messageReceived, &app,
                     [&requestNewWindow](const QByteArray &message) {
        if (message.isEmpty() || message == QByteArray("new-window"))
            requestNewWindow();
    });

#if defined(Q_OS_MAC)
    QMenu *dockMenu = new QMenu(nullptr);
    dockMenu->addAction(QObject::tr("New Window"), [&requestNewWindow]() { requestNewWindow(); });
    dockMenu->setAsDockMenu();
#endif

    return app.exec();
}
