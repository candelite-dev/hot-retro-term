.pragma library
// Settings schema — single source of truth for serialisation.
// k = JSON key, p = QML property name (may differ for private _ prefixed properties)
// scope: "settings" = general/window prefs; "profile" = CRT visual profile
//
// To add a setting: declare the property in ApplicationSettings.qml,
// then add ONE entry here. No other file needs editing.
var schema = [
    { k: "effectsFrameSkip",  p: "effectsFrameSkip",  scope: "settings" },
    { k: "windowScaling",     p: "windowScaling",     scope: "settings" },
    { k: "showTerminalSize",  p: "showTerminalSize",  scope: "settings" },
    { k: "fontScaling",       p: "fontScaling",       scope: "settings" },
    { k: "showMenubar",       p: "showMenubar",       scope: "settings" },
    { k: "bloomQuality",      p: "bloomQuality",      scope: "settings" },
    { k: "burnInQuality",     p: "burnInQuality",     scope: "settings" },
    { k: "useCustomCommand",  p: "useCustomCommand",  scope: "settings" },
    { k: "customCommand",     p: "customCommand",     scope: "settings" },
    { k: "windowCurvature",   p: "windowCurvature",   scope: "settings" },
    { k: "tabBarScale",       p: "tabBarScale",       scope: "settings" },
    { k: "backgroundColor",   p: "_backgroundColor",  scope: "profile"  },
    { k: "fontColor",         p: "_fontColor",        scope: "profile"  },
    { k: "flickering",        p: "flickering",        scope: "profile"  },
    { k: "horizontalSync",    p: "horizontalSync",    scope: "profile"  },
    { k: "staticNoise",       p: "staticNoise",       scope: "profile"  },
    { k: "chromaColor",       p: "chromaColor",       scope: "profile"  },
    { k: "saturationColor",   p: "saturationColor",   scope: "profile"  },
    { k: "screenCurvature",   p: "screenCurvature",   scope: "profile"  },
    { k: "glowingLine",       p: "glowingLine",       scope: "profile"  },
    { k: "burnIn",            p: "burnIn",            scope: "profile"  },
    { k: "bloom",             p: "bloom",             scope: "profile"  },
    { k: "rasterization",     p: "rasterization",     scope: "profile"  },
    { k: "jitter",            p: "jitter",            scope: "profile"  },
    { k: "rgbShift",          p: "rgbShift",          scope: "profile"  },
    { k: "brightness",        p: "brightness",        scope: "profile"  },
    { k: "contrast",          p: "contrast",          scope: "profile"  },
    { k: "ambientLight",      p: "ambientLight",      scope: "profile"  },
    { k: "windowOpacity",     p: "windowOpacity",     scope: "profile"  },
    { k: "fontName",          p: "fontName",          scope: "profile"  },
    { k: "fontSource",        p: "fontSource",        scope: "profile"  },
    { k: "fontWidth",         p: "fontWidth",         scope: "profile"  },
    { k: "lineSpacing",       p: "lineSpacing",       scope: "profile"  },
    { k: "margin",            p: "_margin",           scope: "profile"  },
    { k: "blinkingCursor",    p: "blinkingCursor",    scope: "profile"  },
    { k: "frameSize",         p: "_frameSize",        scope: "profile"  },
    { k: "screenRadius",      p: "_screenRadius",     scope: "profile"  },
    { k: "frameColor",        p: "_frameColor",       scope: "profile"  },
    { k: "frameShininess",    p: "_frameShininess",   scope: "profile"  }
]
