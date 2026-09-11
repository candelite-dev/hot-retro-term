#ifndef FILEIO_H
#define FILEIO_H

#include <QObject>
#include <QFile>
#include <QStandardPaths>
#include <QTextStream>
#include <QUrl>

class FileIO : public QObject
{
    Q_OBJECT

public:
    FileIO();

public slots:
    bool write(const QString& sourceUrl, const QString& data);
    QString read(const QString& sourceUrl);
    QString userShortcutsPath();
};

#endif // FILEIO_H
