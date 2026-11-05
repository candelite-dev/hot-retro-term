#pragma once

#include <QColor>
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

    // Tints the native titlebar to match the CRT's own background pixels
    // (see terminal_dynamic.frag's convertWithChroma) so the titlebar and
    // the CRT content fade together as windowOpacity changes, and applies
    // real behind-window blur at blurRadius (points; 0 disables it) via a
    // private WindowServer API — see macwindow.mm for why. At alpha 1.0
    // the titlebar is restored to the stock macOS look instead of being
    // painted flat, so full opacity doesn't look like a different window
    // style. Safe to call repeatedly (e.g. on every slider tick).
    Q_INVOKABLE void applyWindowChrome(QWindow *window, const QColor &bg, qreal alpha, int blurRadius);
};
