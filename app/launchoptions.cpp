#include "launchoptions.h"

#include <QCommandLineParser>
#include <QDir>
#include <QFileInfo>

QVariantMap LaunchOptions::toVariantMap() const
{
    return {{"workingDirectory", workingDirectory}, {"profile", profile},
            {"command", command}, {"commandArguments", commandArguments},
            {"defaultSettings", defaultSettings}, {"fullscreen", fullscreen}, {"verbose", verbose}};
}

LaunchResult parseLaunchOptions(const QStringList &arguments, const QString &workingDirectory)
{
    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("CRT terminal emulator. Use -e last; everything after it is passed to the command."));
    parser.addOption({QStringList{"h", "help", "help-all"}, "Show these options."});
    parser.addOption({QStringList{"v", "version"}, "Print the application version."});
    parser.addOptions({
        {QStringList{"workdir"}, "Start the shell in this directory.", "directory"},
        {QStringList{"p", "profile"}, "Load a saved profile.", "name"},
        {QStringList{"default-settings"}, "Start with default settings."},
        {QStringList{"fullscreen"}, "Start fullscreen."},
        {QStringList{"verbose"}, "Print diagnostic information."}
    });
    parser.addPositionalArgument(QStringLiteral("-e <command> [args...]"),
                                 QStringLiteral("Execute a command and pass all remaining arguments unchanged."),
                                 QStringLiteral("[-e <command> [args...]]"));

    LaunchResult result;
    result.options.workingDirectory = workingDirectory;
    // Find -e only before the end-of-options marker; never interpret the child's flags.
    int commandIndex = -1;
    for (int i = 1; i < arguments.size(); ++i) {
        if (arguments[i] == QStringLiteral("--")) break;
        if (arguments[i] == QStringLiteral("-e")) { commandIndex = i; break; }
        // A value can itself be '-e' (for example a profile name).
        if (arguments[i] == QStringLiteral("--workdir") || arguments[i] == QStringLiteral("--profile") ||
            arguments[i] == QStringLiteral("-p")) ++i;
    }
    const auto appArguments = commandIndex < 0 ? arguments : arguments.mid(0, commandIndex);
    if (!parser.parse(appArguments)) result.error = parser.errorText();
    // No QCoreApplication exists yet, so supply the executable name ourselves.
    result.helpText = QStringLiteral("Usage: %1 [options] [-e <command> [args...]]\n")
        .arg(QFileInfo(arguments.value(0, QStringLiteral("cool-retro-term"))).fileName())
        + parser.helpText().section(QLatin1Char('\n'), 1);
    result.options.help = parser.isSet(QStringLiteral("help"));
    result.options.version = parser.isSet(QStringLiteral("version"));
    if (!result.isValid() || result.options.help || result.options.version) return result;
    if (!parser.positionalArguments().isEmpty()) {
        result.error = QStringLiteral("Unexpected arguments. Use -e before a command.");
        return result;
    }
    if (parser.isSet(QStringLiteral("workdir"))) {
        const auto path = parser.value(QStringLiteral("workdir"));
        if (path.isEmpty() || !QFileInfo(QDir(workingDirectory).filePath(path)).isDir()) {
            result.error = QStringLiteral("--workdir must name an existing directory.");
            return result;
        }
        result.options.workingDirectory = QDir(workingDirectory).absoluteFilePath(path);
    }
    result.options.profile = parser.value(QStringLiteral("profile"));
    if (parser.isSet(QStringLiteral("profile")) && result.options.profile.isEmpty()) {
        result.error = QStringLiteral("--profile requires a name.");
        return result;
    }
    if (commandIndex >= 0) {
        if (commandIndex + 1 >= arguments.size() || arguments[commandIndex + 1].isEmpty()) {
            result.error = QStringLiteral("-e requires a command.");
            return result;
        }
        result.options.command = arguments[commandIndex + 1];
        result.options.commandArguments = arguments.mid(commandIndex + 2);
    }
    result.options.defaultSettings = parser.isSet(QStringLiteral("default-settings"));
    result.options.fullscreen = parser.isSet(QStringLiteral("fullscreen"));
    result.options.verbose = parser.isSet(QStringLiteral("verbose"));
    return result;
}
