#pragma once

#include <QObject>

class QWindow;

// Qt's Cocoa platform plugin does not reliably mark the NSWindow backing a
// translucent QQuickWindow as non-opaque — the alpha buffer is allocated
// (QWindow::format().alphaBufferSize() == 8) but the compositor still treats
// the window as opaque. This bypasses that by reaching through winId() to
// the NSView/NSWindow and setting the native transparency flags directly.
class MacWindowHelper : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;

    Q_INVOKABLE void makeTranslucent(QWindow *window);
};
