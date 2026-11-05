/*******************************************************************************
* Copyright (c) 2013-2021 "Filippo Scognamiglio"
* https://github.com/Swordfish90/cool-retro-term
*
* This file is part of cool-retro-term.
*
* cool-retro-term is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*******************************************************************************/
import QtQuick 2.2
import QtQuick.Controls 2.0
import CoolRetroTerm 1.0

import "utils.js" as Utils
import "SettingsCodec.js" as Codec

QtObject {
    id: settings
    readonly property string version: appVersion
    readonly property int profileVersion: 2

    // STATIC CONSTANTS ////////////////////////////////////////////////////////
    readonly property real screenCurvatureSize: 0.6
    readonly property real minimumFontScaling: 0.25
    readonly property real maximumFontScaling: 2.50

    readonly property int defaultMargin: 16

    readonly property real minBurnInFadeTime: 0.16
    readonly property real maxBurnInFadeTime: 1.6

    property bool isMacOS: Qt.platform.os === "osx"

    // GENERAL SETTINGS ///////////////////////////////////////////////////////
    property bool showMenubar: false

    property bool showTerminalSize: true
    property real windowScaling: 1.0

    property int effectsFrameSkip: 3
    property bool verbose: false

    property real bloomQuality: 0.5
    property real burnInQuality: 0.5

    property real windowCurvature: 0.0

    property bool blinkingCursor: false


    // PROFILE SETTINGS ///////////////////////////////////////////////////////
    // Real per-pixel window alpha (requires the RGBA surface format set in
    // main.cpp). Below 1.0, desktop content shows through the whole window;
    // on compositors that blur translucent surfaces (e.g. Hyprland, KWin)
    // this is enough to trigger their blur — no protocol code needed here.
    property real windowOpacity: 1.0
    // Behind-window blur radius in points (macOS only, 0 disables it).
    // Only takes effect while windowOpacity < 1 — see macwindow.mm.
    property int backgroundBlurRadius: 20
    property real ambientLight: 0.2
    property real contrast: 0.80
    property real brightness: 0.5

    property bool useCustomCommand: false
    property string customCommand: ""

    property string _backgroundColor: "#000000"
    property string _fontColor: "#ff8100"
    property string _frameColor: "#ffffff"
    property string saturatedColor: Utils.mix(Utils.strToColor(_fontColor), Utils.strToColor("#FFFFFF"), (saturationColor * 0.5))
    property color fontColor: Utils.mix(Utils.strToColor(_backgroundColor), Utils.strToColor(saturatedColor), (0.7 + (contrast * 0.3)))
    property color backgroundColor: Utils.mix(Utils.strToColor(saturatedColor), Utils.strToColor(_backgroundColor), (0.7 + (contrast * 0.3)))
    property color frameColor: Utils.strToColor(_frameColor)

    property real staticNoise: 0.12
    property real screenCurvature: 0.3
    property real glowingLine: 0.2
    property real burnIn: 0.25
    property real bloom: 0.55

    property real chromaColor: 0.25
    property real saturationColor: 0.25

    property real jitter: 0.2

    property real horizontalSync: 0.08
    property real flickering: 0.1

    property real rgbShift: 0.0

    property real _frameShininess: 0.2
    property real frameShininess: _frameShininess * 0.5

    property real _frameSize: 0.2
    property real frameSize: _frameSize * 0.05

    property real _screenRadius: 0.2
    property real screenRadius: Utils.lint(4.0, 120.0, _screenRadius)

    property real _margin: 0.5
    property real margin: Utils.lint(1.0, 40.0, _margin) + (1.0 - Math.SQRT1_2) * screenRadius

    readonly property bool frameEnabled: ambientLight > 0 || _frameSize > 0 || screenCurvature > 0

    readonly property int no_rasterization: 0
    readonly property int scanline_rasterization: 1
    readonly property int pixel_rasterization: 2
    readonly property int subpixel_rasterization: 3
    readonly property int modern_rasterization: 4

    property alias rasterization: fontManager.rasterization

    readonly property int bundled_fonts: 0
    readonly property int system_fonts: 1

    property alias fontSource: fontManager.fontSource

    // FONTS //////////////////////////////////////////////////////////////////
    readonly property real baseFontScaling: 0.75
    property alias fontScaling: fontManager.fontScaling
    property real totalFontScaling: baseFontScaling * fontScaling

    property alias fontWidth: fontManager.fontWidth
    property alias lineSpacing: fontManager.lineSpacing

    property alias lowResolutionFont: fontManager.lowResolutionFont

    property alias fontName: fontManager.fontName
    property alias filteredFontList: fontManager.filteredFontList

    property FontManager fontManager: FontManager {
        id: fontManager
        baseFontScaling: settings.baseFontScaling
    }

    signal initializedSettings

    function incrementScaling() {
        fontScaling = Math.min(fontScaling + 0.05, maximumFontScaling)
    }

    function decrementScaling() {
        fontScaling = Math.max(fontScaling - 0.05, minimumFontScaling)
    }

    function close() {
        storeSettings()
        storeCustomProfiles()
        Qt.quit()
    }

    property var startupOptions: launchOptions
    property Storage storage: Storage {}
    property SettingsPersistence persistence: SettingsPersistence {
        settingsTarget: settings
        storage: settings.storage
        onWarning: function(message) { console.warn(message) }
    }
    property ProfileCatalog profileCatalog: ProfileCatalog {
        id: catalog
        onWarning: function(message) { console.warn("Profile: " + message) }
    }
    property alias profilesList: catalog.model

    // Public facade for settings controls; serialization, I/O, and the profile model
    // live in their respective components.
    function stringify(value) { return Codec.stringify(value) }
    function composeSettingsString() { return Codec.stringify(Codec.compose(settings, "settings")) }
    function composeProfileObject() { return Codec.compose(settings, "profile") }
    function composeProfileString() { return Codec.stringify(composeProfileObject()) }
    function loadSettings() { persistence.loadCurrent() }
    function storeSettings() { return persistence.storeCurrent() }
    function loadCustomProfiles() { persistence.loadCustomProfiles(profileCatalog) }
    function storeCustomProfiles() { return persistence.storeCustomProfiles(profileCatalog) }
    function composeCustomProfilesString() { return profileCatalog.customProfilesString() }
    function loadCustomProfilesString(text) { return profileCatalog.load(text, false) }
    function appendCustomProfile(name, text) { return profileCatalog.append(name, text) }
    function getProfileIndexByName(name) { return profileCatalog.find(name) }

    function loadValues(text, scope) {
        try {
            Codec.apply(settings, Codec.parseSettings(text, scope), scope)
            return true
        } catch (error) {
            console.warn("Unable to load " + scope + ": " + error.message)
            return false
        }
    }
    function loadSettingsString(text) { return loadValues(text, "settings") }
    function loadProfileString(text) { return loadValues(text, "profile") }
    function loadProfile(index) {
        if (index < 0 || index >= profilesList.count) return false
        return loadProfileString(profilesList.get(index).obj_string)
    }

    Component.onCompleted: {
        profileCatalog.load(fileIO.read("qrc:/profiles/builtin_profiles.json"), true)
        verbose = startupOptions.verbose
        if (!startupOptions.defaultSettings) loadSettings()
        loadCustomProfiles()
        if (startupOptions.profile) {
            var index = getProfileIndexByName(startupOptions.profile)
            if (index >= 0) loadProfile(index)
            else console.warn("Unknown profile: " + startupOptions.profile)
        }
        initializedSettings()
    }

    // VARS ///////////////////////////////////////////////////////////////////
    property Label _sampleLabel: Label {
        text: "100%"
    }
    property real labelWidth: _sampleLabel.width
}
