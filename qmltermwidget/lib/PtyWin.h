#ifndef PTYWIN_H
#define PTYWIN_H

#include "kprocess.h"

#include <QByteArray>
#include <QSize>
#include <windows.h>

namespace Konsole {

class ConPtyReaderThread;
class ConPtyWriter;

class Pty : public KProcess
{
    Q_OBJECT

public:
    explicit Pty(QObject *parent = nullptr);
    explicit Pty(int ptyMasterFd, QObject *parent = nullptr);
    ~Pty() override;

    int start(const QString &program, const QStringList &arguments,
              const QStringList &environment, ulong winid, bool addToUtmp);
    void setWindowSize(int lines, int cols);
    QSize windowSize() const;
    void setFlowControlEnabled(bool on);
    bool flowControlEnabled() const;
    void setErase(char erase);
    char erase() const;
    int foregroundProcessGroup() const;
    void closePty();
    void setEmptyPTYProperties() {}
    void setWriteable(bool) {}

public slots:
    void setUtf8Mode(bool) {}
    void lockPty(bool) {}
    void sendData(const char *buffer, int length);

signals:
    void receivedData(const char *buffer, int length);

private slots:
    void onReaderChunk(const QByteArray &chunk);

private:
    bool openPseudoConsole();
    void installCreateProcessModifier();
    void addEnvironmentVariables(const QStringList &environment);

    HPCON m_hPC = nullptr;
    HANDLE m_inWrite = INVALID_HANDLE_VALUE;
    HANDLE m_outRead = INVALID_HANDLE_VALUE;
    QByteArray m_attrListBuffer;
    STARTUPINFOEXW m_siEx {};
    ConPtyReaderThread *m_reader = nullptr;
    QThread *m_writerThread = nullptr;
    ConPtyWriter *m_writer = nullptr;
    int _windowColumns = 0;
    int _windowLines = 0;
    char _eraseChar = 0;
    bool _xonXoff = true;
};

} // namespace Konsole

#endif // PTYWIN_H
