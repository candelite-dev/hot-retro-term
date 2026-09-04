#include "macwindow.h"

#include <QWindow>

#import <AppKit/AppKit.h>

void MacWindowHelper::makeTranslucent(QWindow *window)
{
    if (!window)
        return;

    NSView *view = reinterpret_cast<NSView *>(window->winId());
    NSWindow *nsWindow = view.window;
    if (!nsWindow)
        return;

    nsWindow.opaque = NO;
    nsWindow.backgroundColor = [NSColor clearColor];

    // The titlebar is drawn by AppKit, not Qt — it stays opaque unless told
    // otherwise, even once the content view below it is translucent.
    nsWindow.titlebarAppearsTransparent = YES;
}
