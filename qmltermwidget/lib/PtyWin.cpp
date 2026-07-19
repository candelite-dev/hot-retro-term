#include "PtyWin.h"

namespace Konsole {

Pty::Pty(QObject *parent)
    : KProcess(parent)
{
}

Pty::Pty(int ptyMasterFd, QObject *parent)
    : KProcess(parent)
{
    Q_UNUSED(ptyMasterFd);
    qWarning("PtyWin: ptyMasterFd is ignored");
}

Pty::~Pty() = default;

int Pty::start(const QString &, const QStringList &, const QStringList &, ulong, bool)
{
    qWarning("PtyWin: ConPTY backend not implemented yet (task B1)");
    return -1;
}

void Pty::setWindowSize(int lines, int cols)
{
    _windowLines = lines;
    _windowColumns = cols;
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
}

void Pty::sendData(const char *, int)
{
}

void Pty::onReaderChunk(const QByteArray &)
{
}

bool Pty::openPseudoConsole()
{
    return false;
}

void Pty::installCreateProcessModifier()
{
}

void Pty::addEnvironmentVariables(const QStringList &)
{
}

} // namespace Konsole
