#include "PtyWin.h"

#include <QThread>

namespace Konsole {

class ConPtyReaderThread : public QThread
{
    Q_OBJECT

public:
    ConPtyReaderThread(HANDLE outRead, QObject *parent)
        : QThread(parent)
        , m_h(outRead)
    {
    }

signals:
    void chunk(const QByteArray &data);

protected:
    void run() override
    {
        char buffer[65536];
        DWORD bytesRead = 0;
        while (ReadFile(m_h, buffer, sizeof(buffer), &bytesRead, nullptr) && bytesRead > 0)
            emit chunk(QByteArray(buffer, int(bytesRead)));
    }

private:
    HANDLE m_h;
};

class ConPtyWriter : public QObject
{
    Q_OBJECT

public:
    explicit ConPtyWriter(HANDLE inWrite)
        : m_h(inWrite)
    {
    }

public slots:
    void writeAll(const QByteArray &data)
    {
        const char *cursor = data.constData();
        qint64 bytesLeft = data.size();
        DWORD bytesWritten = 0;
        while (bytesLeft > 0
               && WriteFile(m_h, cursor, DWORD(bytesLeft), &bytesWritten, nullptr)) {
            cursor += bytesWritten;
            bytesLeft -= bytesWritten;
        }
    }

private:
    HANDLE m_h;
};

Pty::Pty(QObject *parent)
    : KProcess(parent)
{
    setStandardInputFile(QProcess::nullDevice());
    setStandardOutputFile(QProcess::nullDevice());
    setStandardErrorFile(QProcess::nullDevice());
}

Pty::Pty(int ptyMasterFd, QObject *parent)
    : Pty(parent)
{
    Q_UNUSED(ptyMasterFd);
    qWarning("PtyWin: ptyMasterFd is ignored");
}

Pty::~Pty()
{
    if (state() != QProcess::NotRunning) {
        kill();
        waitForFinished(1000);
    }
    closePty();
}

int Pty::start(const QString &program, const QStringList &arguments,
               const QStringList &environment, ulong winid, bool /*addToUtmp*/)
{
    clearProgram();
    setProgram(program, arguments.mid(1));
    addEnvironmentVariables(environment);
    setEnv(QLatin1String("WINDOWID"), QString::number(winid));
    setEnv(QLatin1String("COLORTERM"), QLatin1String("truecolor"));

    if (!openPseudoConsole())
        return -1;
    installCreateProcessModifier();

    KProcess::start();
    if (!waitForStarted(5000)) {
        closePty();
        return -1;
    }

    m_reader = new ConPtyReaderThread(m_outRead, this);
    connect(m_reader, &ConPtyReaderThread::chunk, this, &Pty::onReaderChunk);
    m_reader->start();

    m_writerThread = new QThread(this);
    m_writer = new ConPtyWriter(m_inWrite);
    m_writer->moveToThread(m_writerThread);
    connect(m_writerThread, &QThread::finished, m_writer, &QObject::deleteLater);
    m_writerThread->start();

    return 0;
}

void Pty::setWindowSize(int lines, int cols)
{
    _windowLines = lines;
    _windowColumns = cols;
    if (m_hPC)
        ResizePseudoConsole(m_hPC, COORD { SHORT(cols), SHORT(lines) });
}

QSize Pty::windowSize() const
{
    return QSize(_windowColumns, _windowLines);
}

void Pty::setFlowControlEnabled(bool on)
{
    _xonXoff = on;
}

bool Pty::flowControlEnabled() const
{
    return _xonXoff;
}

void Pty::setErase(char erase)
{
    _eraseChar = erase;
}

char Pty::erase() const
{
    return _eraseChar;
}

int Pty::foregroundProcessGroup() const
{
    return -1;
}

void Pty::closePty()
{
    if (m_writerThread) {
        m_writer = nullptr;
        m_writerThread->quit();
        m_writerThread->wait(1000);
    }
    if (m_inWrite != INVALID_HANDLE_VALUE) {
        CloseHandle(m_inWrite);
        m_inWrite = INVALID_HANDLE_VALUE;
    }
    if (m_hPC) {
        ClosePseudoConsole(m_hPC);
        m_hPC = nullptr;
    }
    if (m_reader)
        m_reader->wait(2000);
    if (m_outRead != INVALID_HANDLE_VALUE) {
        CloseHandle(m_outRead);
        m_outRead = INVALID_HANDLE_VALUE;
    }
    if (!m_attrListBuffer.isEmpty()) {
        DeleteProcThreadAttributeList(
            reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(m_attrListBuffer.data()));
        m_attrListBuffer.clear();
    }
}

void Pty::setUtf8Mode(bool /*on*/)
{
    // ConPTY has no termios; conhost owns the line discipline.
}

void Pty::lockPty(bool /*lock*/)
{
    // ConPTY has no termios; conhost owns the line discipline.
}

void Pty::setEmptyPTYProperties()
{
    // ConPTY has no termios; conhost owns the line discipline.
}

void Pty::setWriteable(bool /*writeable*/)
{
    // ConPTY has no termios; conhost owns the line discipline.
}

void Pty::sendData(const char *buffer, int length)
{
    if (!m_writer)
        return;

    QMetaObject::invokeMethod(m_writer, "writeAll", Qt::QueuedConnection,
                              Q_ARG(QByteArray, QByteArray(buffer, length)));
}

void Pty::onReaderChunk(const QByteArray &chunk)
{
    emit receivedData(chunk.constData(), chunk.size());
}

bool Pty::openPseudoConsole()
{
    HANDLE inRead = INVALID_HANDLE_VALUE;
    HANDLE outWrite = INVALID_HANDLE_VALUE;

    if (!CreatePipe(&inRead, &m_inWrite, nullptr, 65536))
        return false;
    if (!CreatePipe(&m_outRead, &outWrite, nullptr, 65536)) {
        CloseHandle(inRead);
        CloseHandle(m_inWrite);
        m_inWrite = INVALID_HANDLE_VALUE;
        return false;
    }

    COORD size { SHORT(_windowColumns > 0 ? _windowColumns : 80),
                 SHORT(_windowLines > 0 ? _windowLines : 24) };
    const HRESULT hr = CreatePseudoConsole(size, inRead, outWrite, 0, &m_hPC);
    CloseHandle(inRead);
    CloseHandle(outWrite);

    if (FAILED(hr)) {
        CloseHandle(m_inWrite);
        CloseHandle(m_outRead);
        m_inWrite = INVALID_HANDLE_VALUE;
        m_outRead = INVALID_HANDLE_VALUE;
        m_hPC = nullptr;
        return false;
    }

    return true;
}

void Pty::installCreateProcessModifier()
{
    SIZE_T bytes = 0;
    InitializeProcThreadAttributeList(nullptr, 1, 0, &bytes);
    m_attrListBuffer.resize(qsizetype(bytes));
    auto attrs = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(m_attrListBuffer.data());
    InitializeProcThreadAttributeList(attrs, 1, 0, &bytes);
    UpdateProcThreadAttribute(attrs, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                              m_hPC, sizeof(HPCON), nullptr, nullptr);

    ZeroMemory(&m_siEx, sizeof(m_siEx));
    m_siEx.StartupInfo.cb = sizeof(STARTUPINFOEXW);
    m_siEx.lpAttributeList = attrs;

    setCreateProcessArgumentsModifier([this](QProcess::CreateProcessArguments *args) {
        args->flags |= EXTENDED_STARTUPINFO_PRESENT;
        args->flags &= ~DWORD(CREATE_NO_WINDOW);
        args->inheritHandles = false;
        args->startupInfo = &m_siEx.StartupInfo;
    });
}

void Pty::addEnvironmentVariables(const QStringList &environment)
{
    bool termEnvVarAdded = false;
    for (const QString &pair : environment) {
        const int pos = pair.indexOf(QLatin1Char('='));
        if (pos >= 0) {
            const QString variable = pair.left(pos);
            const QString value = pair.mid(pos + 1);
            setEnv(variable, value);

            if (variable == QLatin1String("TERM"))
                termEnvVarAdded = true;
        }
    }

    if (!termEnvVarAdded)
        setEnv(QStringLiteral("TERM"), QStringLiteral("xterm-256color"));
}

} // namespace Konsole

#include "PtyWin.moc"
