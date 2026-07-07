#include "fileio.h"

FileIO::FileIO()
{
}

QString FileIO::userShortcutsPath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    if (dir.isEmpty()) return QString();
    return dir + QStringLiteral("/shortcuts.json");
}

bool FileIO::write(const QString& sourceUrl, const QString& data) {
    if (sourceUrl.isEmpty())
        return false;

    QUrl url(sourceUrl);
    QFile file(url.toLocalFile());
    if (!file.open(QFile::WriteOnly | QFile::Truncate))
        return false;

    QTextStream out(&file);
    out << data;
    file.close();
    return true;
}

QString FileIO::read(const QString& sourceUrl) {
    if (sourceUrl.isEmpty())
        return "";

    QUrl url(sourceUrl);
    QString filePath;
    if (url.scheme() == QStringLiteral("qrc")) {
        filePath = QStringLiteral(":") + url.path();
    } else if (url.isLocalFile()) {
        filePath = url.toLocalFile();
    } else {
        filePath = sourceUrl;
    }

    QFile file(filePath);
    if (!file.open(QFile::ReadOnly))
        return "";

    QTextStream in(&file);
    QString result = in.readAll();

    file.close();

    return result;
}
