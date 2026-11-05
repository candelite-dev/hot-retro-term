.pragma library
// Settings schema — single source of truth for serialisation.
// k = JSON key, p = QML property name (may differ for private _ prefixed properties)
// scope: "settings" = general/window prefs; "profile" = CRT visual profile
//
// To add a setting: declare the property in ApplicationSettings.qml,
// then add ONE entry here. No other file needs editing.
var schema = [
    { k: "effectsFrameSkip",  p: "effectsFrameSkip",  scope: "settings", type: "int", min: 1 },
    { k: "windowScaling",     p: "windowScaling",     scope: "settings", type: "real", positive: true },
    { k: "showTerminalSize",  p: "showTerminalSize",  scope: "settings", type: "bool" },
    { k: "fontScaling",       p: "fontScaling",       scope: "settings", type: "real", positive: true },
    { k: "showMenubar",       p: "showMenubar",       scope: "settings", type: "bool" },
    { k: "bloomQuality",      p: "bloomQuality",      scope: "settings", type: "real", positive: true },
    { k: "burnInQuality",     p: "burnInQuality",     scope: "settings", type: "real", positive: true },
    { k: "useCustomCommand",  p: "useCustomCommand",  scope: "settings", type: "bool" },
    { k: "customCommand",     p: "customCommand",     scope: "settings", type: "string" },
    { k: "windowCurvature",   p: "windowCurvature",   scope: "settings", type: "real", min: 0, max: 1 },
    { k: "backgroundColor",   p: "_backgroundColor",  scope: "profile", type: "color" },
    { k: "fontColor",         p: "_fontColor",        scope: "profile", type: "color" },
    { k: "flickering",        p: "flickering",        scope: "profile", type: "real", min: 0, max: 1 },
    { k: "horizontalSync",    p: "horizontalSync",    scope: "profile", type: "real", min: 0, max: 1 },
    { k: "staticNoise",       p: "staticNoise",       scope: "profile", type: "real", min: 0, max: 1 },
    { k: "chromaColor",       p: "chromaColor",       scope: "profile", type: "real", min: 0, max: 1 },
    { k: "saturationColor",   p: "saturationColor",   scope: "profile", type: "real", min: 0, max: 1 },
    { k: "screenCurvature",   p: "screenCurvature",   scope: "profile", type: "real", min: 0, max: 1 },
    { k: "glowingLine",       p: "glowingLine",       scope: "profile", type: "real", min: 0, max: 1 },
    { k: "burnIn",            p: "burnIn",            scope: "profile", type: "real", min: 0, max: 1 },
    { k: "bloom",             p: "bloom",             scope: "profile", type: "real", min: 0, max: 1 },
    { k: "rasterization",     p: "rasterization",     scope: "profile", type: "int", min: 0, max: 4 },
    { k: "jitter",            p: "jitter",            scope: "profile", type: "real", min: 0, max: 1 },
    { k: "rgbShift",          p: "rgbShift",          scope: "profile", type: "real", min: 0, max: 1 },
    { k: "brightness",        p: "brightness",        scope: "profile", type: "real", min: 0, max: 1 },
    { k: "contrast",          p: "contrast",          scope: "profile", type: "real", min: 0, max: 1 },
    { k: "ambientLight",      p: "ambientLight",      scope: "profile", type: "real", min: 0, max: 1 },
    { k: "windowOpacity",     p: "windowOpacity",     scope: "profile", type: "real", min: 0, max: 1 },
    { k: "backgroundBlurRadius", p: "backgroundBlurRadius", scope: "profile", type: "int", min: 0 },
    { k: "fontName",          p: "fontName",          scope: "profile", type: "string" },
    { k: "fontSource",        p: "fontSource",        scope: "profile", type: "int", min: 0, max: 1 },
    { k: "fontWidth",         p: "fontWidth",         scope: "profile", type: "real", positive: true },
    { k: "lineSpacing",       p: "lineSpacing",       scope: "profile", type: "real", min: 0, max: 1 },
    { k: "margin",            p: "_margin",           scope: "profile", type: "real", min: 0, max: 1 },
    { k: "blinkingCursor",    p: "blinkingCursor",    scope: "profile", type: "bool" },
    { k: "frameSize",         p: "_frameSize",        scope: "profile", type: "real", min: 0, max: 1 },
    { k: "screenRadius",      p: "_screenRadius",     scope: "profile", type: "real", min: 0, max: 1 },
    { k: "frameColor",        p: "_frameColor",       scope: "profile", type: "color" },
    { k: "frameShininess",    p: "_frameShininess",   scope: "profile", type: "real", min: 0, max: 1 }
]
