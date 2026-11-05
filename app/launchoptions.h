#pragma once

#include <QString>
#include <QStringList>
#include <QVariantMap>

// Parsed once before the GUI starts. Arguments following -e belong to the child.
struct LaunchOptions {
    QString workingDirectory;
    QString profile;
    QString command;
    QStringList commandArguments;
    bool defaultSettings = false;
    bool fullscreen = false;
    bool verbose = false;
    bool help = false;
    bool version = false;

    QVariantMap toVariantMap() const;
};

struct LaunchResult {
    LaunchOptions options;
    QString error;
    QString helpText;
    bool isValid() const { return error.isEmpty(); }
};

LaunchResult parseLaunchOptions(const QStringList &arguments, const QString &workingDirectory);
