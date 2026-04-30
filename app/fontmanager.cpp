#include "fontmanager.h"

#include <QFile>
#include <QFont>
#include <QFontDatabase>
#include <QFontMetricsF>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QThreadPool>
#include <QtGlobal>
#include <QtMath>

namespace {
constexpr int kModernRasterization = 4;
constexpr int kBaseFontPixelHeight = 32;
constexpr int kSystemFontPixelSize = 32;
}

FontManager::FontManager(QObject *parent)
    : QObject(parent)
    , m_fontListModel(this)
    , m_filteredFontListModel(this)
{
    populateBundledFonts();
    m_fontListModel.setFonts(m_allFonts);
    updateFilteredFonts();
    updateComputedFont();

    // Enumerate system fonts off the startup path — QFontDatabase::families() can be slow
    // (100ms+ on macOS). Bundled fonts are already available; system fonts appear shortly after.
    QThreadPool::globalInstance()->start([this]() {
        QStringList families = retrieveMonospaceFonts();
        QMetaObject::invokeMethod(this, [this, families]() {
            for (const QString &family : families) {
                if (m_bundledFamilies.contains(family))
                    continue;
                FontEntry entry;
                entry.name = family;
                entry.text = family;
                entry.source = QString();
                entry.baseWidth = 1.0;
                entry.pixelSize = kSystemFontPixelSize;
                entry.lowResolutionFont = false;
                entry.isSystemFont = true;
                entry.family = family;
                m_allFonts.append(entry);
            }
            m_fontListModel.setFonts(m_allFonts);
            updateFilteredFonts();
            emit systemFontsReady();
        }, Qt::QueuedConnection);
    });
}

QStringList FontManager::retrieveMonospaceFonts()
{
    QStringList result;
    for (const QString &family : QFontDatabase::families()) {
        if (QFontDatabase::isFixedPitch(family))
            result.append(family);
    }
    return result;
}

void FontManager::refresh()
{
    updateFilteredFonts();
    updateComputedFont();
}

FontListModel *FontManager::fontList()
{
    return &m_fontListModel;
}

FontListModel *FontManager::filteredFontList()
{
    return &m_filteredFontListModel;
}

int FontManager::fontSource() const
{
    return m_fontSource;
}

void FontManager::setFontSource(int fontSource)
{
    if (m_fontSource == fontSource) {
        return;
    }
    m_fontSource = fontSource;
    emit fontSourceChanged();
    updateFilteredFonts();
    updateComputedFont();
}

int FontManager::rasterization() const
{
    return m_rasterization;
}

void FontManager::setRasterization(int rasterization)
{
    if (m_rasterization == rasterization) {
        return;
    }
    m_rasterization = rasterization;
    emit rasterizationChanged();
    updateFilteredFonts();
    updateComputedFont();
}

QString FontManager::fontName() const
{
    return m_fontName;
}

void FontManager::setFontName(const QString &fontName)
{
    if (m_fontName == fontName) {
        return;
    }
    m_fontName = fontName;
    emit fontNameChanged();
    updateFilteredFonts();
    updateComputedFont();
}

qreal FontManager::fontScaling() const
{
    return m_fontScaling;
}

void FontManager::setFontScaling(qreal fontScaling)
{
    if (qFuzzyCompare(m_fontScaling, fontScaling)) {
        return;
    }
    m_fontScaling = fontScaling;
    emit fontScalingChanged();
    updateComputedFont();
}

qreal FontManager::fontWidth() const
{
    return m_fontWidth;
}

void FontManager::setFontWidth(qreal fontWidth)
{
    if (qFuzzyCompare(m_fontWidth, fontWidth)) {
        return;
    }
    m_fontWidth = fontWidth;
    emit fontWidthChanged();
    updateComputedFont();
}

qreal FontManager::lineSpacing() const
{
    return m_lineSpacing;
}

void FontManager::setLineSpacing(qreal lineSpacing)
{
    if (qFuzzyCompare(m_lineSpacing, lineSpacing)) {
        return;
    }
    m_lineSpacing = lineSpacing;
    emit lineSpacingChanged();
    updateComputedFont();
}

qreal FontManager::baseFontScaling() const
{
    return m_baseFontScaling;
}

void FontManager::setBaseFontScaling(qreal baseFontScaling)
{
    if (qFuzzyCompare(m_baseFontScaling, baseFontScaling)) {
        return;
    }
    m_baseFontScaling = baseFontScaling;
    emit baseFontScalingChanged();
    updateComputedFont();
}

bool FontManager::lowResolutionFont() const
{
    return m_lowResolutionFont;
}

void FontManager::setFontSubstitutions(const QString &family, const QStringList &substitutes)
{
    if (family.isEmpty()) {
        return;
    }

    QFont::removeSubstitutions(family);

    if (substitutes.isEmpty()) {
        return;
    }

    QFont::insertSubstitutions(family, substitutes);
}

void FontManager::removeFontSubstitution(const QString &family)
{
    if (family.isEmpty()) {
        return;
    }

    QFont::removeSubstitutions(family);
}

void FontManager::populateBundledFonts()
{
    m_allFonts.clear();

    QFile f(QStringLiteral(":/fonts/manifest.json"));
    if (!f.open(QIODevice::ReadOnly)) {
        qWarning("FontManager: could not open :/fonts/manifest.json");
        return;
    }
    const QJsonArray arr = QJsonDocument::fromJson(f.readAll()).array();
    for (const QJsonValue &v : arr) {
        const QJsonObject obj = v.toObject();
        addBundledFont(
            obj.value(QLatin1String("name")).toString(),
            obj.value(QLatin1String("text")).toString(),
            obj.value(QLatin1String("source")).toString(),
            obj.value(QLatin1String("baseWidth")).toDouble(1.0),
            obj.value(QLatin1String("pixelSize")).toInt(32),
            obj.value(QLatin1String("lowResolution")).toBool(false),
            obj.value(QLatin1String("fallback")).toString());
    }
}

void FontManager::addBundledFont(const QString &name,
                                 const QString &text,
                                 const QString &source,
                                 qreal baseWidth,
                                 int pixelSize,
                                 bool lowResolutionFont,
                                 const QString &fallbackName)
{
    FontEntry entry;
    entry.name = name;
    entry.text = text;
    entry.source = source;
    entry.pixelSize = pixelSize;
    entry.lowResolutionFont = lowResolutionFont;
    entry.isSystemFont = false;
    entry.fallbackName = fallbackName;
    entry.family = resolveFontFamily(source);
    entry.baseWidth = lowResolutionFont
        ? computeBaseWidth(entry.family, pixelSize, baseWidth)
        : baseWidth;
    m_allFonts.append(entry);
}

void FontManager::updateFilteredFonts()
{
    QVector<FontEntry> filtered;
    bool fontNameFound = false;
    const bool modernMode = (m_rasterization == kModernRasterization);

    for (const FontEntry &font : m_allFonts) {
        const bool isBundled = !font.isSystemFont;
        const bool matchesSource = (m_fontSource == 0 && isBundled)
            || (m_fontSource == 1 && font.isSystemFont);

        if (!matchesSource) {
            continue;
        }

        const bool matchesRasterization = font.isSystemFont
            || (modernMode == !font.lowResolutionFont);

        if (!matchesRasterization) {
            continue;
        }

        filtered.append(font);
        if (font.name == m_fontName) {
            fontNameFound = true;
        }
    }

    if (!fontNameFound && !filtered.isEmpty()) {
        if (m_fontName != filtered.first().name) {
            m_fontName = filtered.first().name;
            emit fontNameChanged();
        }
    }

    m_filteredFontListModel.setFonts(filtered);
    emit filteredFontListChanged();
}

void FontManager::updateComputedFont()
{
    const FontEntry *font = findFontByName(m_fontName);
    if (!font) {
        const QVector<FontEntry> &filteredFonts = m_filteredFontListModel.fonts();
        if (!filteredFonts.isEmpty()) {
            font = &filteredFonts.first();
        }
    }

    if (!font) {
        return;
    }

    const qreal totalFontScaling = m_baseFontScaling * m_fontScaling;
    const qreal targetPixelHeight = kBaseFontPixelHeight * totalFontScaling;
    const qreal lineSpacingFactor = m_lineSpacing;

    const int lineSpacing = qRound(targetPixelHeight * lineSpacingFactor);
    const int pixelSize = font->lowResolutionFont
        ? font->pixelSize
        : static_cast<int>(targetPixelHeight);

    const qreal nativeLineHeight = font->pixelSize + qRound(font->pixelSize * lineSpacingFactor);
    const qreal targetLineHeight = targetPixelHeight + lineSpacing;
    const qreal screenScaling = font->lowResolutionFont
        ? (nativeLineHeight > 0 ? targetLineHeight / nativeLineHeight : 1.0)
        : 1.0;

    const qreal fontWidth = font->baseWidth * m_fontWidth;

    QString fontFamily = font->family.isEmpty() ? font->name : font->family;
    QString fallbackFontFamily;

    if (!font->fallbackName.isEmpty() && font->fallbackName != font->name) {
        const FontEntry *fallback = findFontByName(font->fallbackName);
        if (fallback) {
            fallbackFontFamily = fallback->family.isEmpty() ? fallback->name : fallback->family;
        }
    }

    QStringList fallbackChain;
    if (!fallbackFontFamily.isEmpty()) {
        fallbackChain.append(fallbackFontFamily);
    }
#if defined(Q_OS_MAC)
    fallbackChain.append(QStringLiteral("Menlo"));
#else
    fallbackChain.append(QStringLiteral("Monospace"));
#endif
    setFontSubstitutions(fontFamily, fallbackChain);

    if (m_lowResolutionFont != font->lowResolutionFont) {
        m_lowResolutionFont = font->lowResolutionFont;
        emit lowResolutionFontChanged();
    }

    m_cachedFontFamily = fontFamily;
    m_cachedPixelSize = pixelSize;
    m_cachedLineSpacing = lineSpacing;
    m_cachedScreenScaling = screenScaling;
    m_cachedFontWidth = fontWidth;
    m_cachedFallbackFontFamily = fallbackFontFamily;
    m_cachedLowResolutionFont = font->lowResolutionFont;
    m_fontCacheValid = true;

    emit terminalFontChanged(fontFamily,
                             pixelSize,
                             lineSpacing,
                             screenScaling,
                             fontWidth,
                             fallbackFontFamily,
                             font->lowResolutionFont);
}

void FontManager::emitCurrentFont()
{
    if (m_fontCacheValid) {
        emit terminalFontChanged(m_cachedFontFamily,
                                 m_cachedPixelSize,
                                 m_cachedLineSpacing,
                                 m_cachedScreenScaling,
                                 m_cachedFontWidth,
                                 m_cachedFallbackFontFamily,
                                 m_cachedLowResolutionFont);
    } else {
        updateComputedFont();
    }
}

const FontEntry *FontManager::findFontByName(const QString &name) const
{
    for (const FontEntry &font : m_allFonts) {
        if (font.name == name) {
            return &font;
        }
    }
    return nullptr;
}

QString FontManager::resolveFontFamily(const QString &sourcePath)
{
    const auto cached = m_loadedFamilies.constFind(sourcePath);
    if (cached != m_loadedFamilies.constEnd()) {
        return cached.value();
    }

    const int fontId = QFontDatabase::addApplicationFont(sourcePath);
    QString family;
    if (fontId != -1) {
        const QStringList families = QFontDatabase::applicationFontFamilies(fontId);
        if (!families.isEmpty()) {
            family = families.first();
        }
    }

    if (!family.isEmpty()) {
        m_bundledFamilies.insert(family);
    }

    m_loadedFamilies.insert(sourcePath, family);
    return family;
}

qreal FontManager::computeBaseWidth(const QString &family, int pixelSize, qreal fallbackWidth) const
{
    if (family.isEmpty()) {
        return fallbackWidth;
    }

    QFont font(family);
    font.setPixelSize(pixelSize);
    QFontMetricsF metrics(font);

    const qreal glyphWidth = metrics.horizontalAdvance(QLatin1String("M"));
    const qreal glyphHeight = metrics.height();
    if (glyphWidth <= 0.0 || glyphHeight <= 0.0) {
        return fallbackWidth;
    }

    const qreal targetRatio = 0.5;
    qreal computedWidth = (targetRatio * glyphHeight) / glyphWidth;
    return qBound(0.25, computedWidth, 2.0);
}
