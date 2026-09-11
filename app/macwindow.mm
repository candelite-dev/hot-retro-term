#include "macwindow.h"

#include <QWindow>

#import <AppKit/AppKit.h>

// CGSSetWindowBackgroundBlurRadius is a private WindowServer API (part of
// "CoreGraphics Services", not exposed in any public header) — it's what
// Dock/Spotlight/Notification Center use for behind-window blur. Adopted
// here (confirmed with the user first, see CLAUDE.md's "Private APIs"
// section) because the public alternative, NSVisualEffectView, only offers
// a handful of fixed material presets — it has no API for a continuously
// adjustable blur radius, which is what a user-facing slider needs. Ghostty
// uses the same call (src/apprt/embedded.zig, ghostty_set_window_background_blur).
extern "C" {
    void *CGSDefaultConnectionForThread(void);
    int CGSSetWindowBackgroundBlurRadius(void *cid, NSInteger windowNumber, int radius);
}

void MacWindowHelper::applyWindowChrome(QWindow *window, const QColor &bg, qreal alpha, int blurRadius)
{
    // handle() is present only once the native window has actually been
    // created. winId() would force-create it, which is wrong to do from a
    // property-change handler that can fire before the window is shown.
    if (!window || !window->handle())
        return;

    NSView *view = reinterpret_cast<NSView *>(window->winId());
    NSWindow *nsWindow = view.window;
    if (!nsWindow)
        return;

    alpha = qBound(0.0, alpha, 1.0);

    // The content view stays translucent (this is what lets the CRT
    // shader's own per-pixel alpha show the desktop through the
    // background) — only the titlebar strip's appearance and the
    // WindowServer blur radius change here. Deliberately never sets
    // NSFullSizeContentViewWindowMask: that would move the content view
    // under the titlebar and defeat the mechanism this relies on (the
    // titlebar revealing NSWindow.backgroundColor).
    nsWindow.opaque = NO;

    if (alpha < 1.0) {
        nsWindow.titlebarAppearsTransparent = YES;
        // sRGB, not device color — a colorspace mismatch here shows up as
        // the titlebar being a slightly different shade than the CRT
        // background at the same alpha.
        nsWindow.backgroundColor = [NSColor colorWithSRGBRed:bg.redF()
                                                         green:bg.greenF()
                                                          blue:bg.blueF()
                                                         alpha:alpha];
    } else {
        // Fully opaque: restore the stock macOS titlebar material instead
        // of painting it flat, so windowOpacity == 1.0 doesn't look like a
        // different window style.
        nsWindow.titlebarAppearsTransparent = NO;
        nsWindow.backgroundColor = [NSColor windowBackgroundColor];
    }

    int radius = (alpha < 1.0) ? qMax(0, blurRadius) : 0;
    CGSSetWindowBackgroundBlurRadius(CGSDefaultConnectionForThread(), nsWindow.windowNumber, radius);
}
