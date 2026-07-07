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
import "SettingsSchema.js" as Schema

QtObject {
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

    property real tabBarScale: 3.0

    property bool blinkingCursor: false


    // PROFILE SETTINGS ///////////////////////////////////////////////////////
    property real windowOpacity: 1.0
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
        baseFontScaling: baseFontScaling
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

    property Storage storage: Storage {}

    // Settings schema — loaded from SettingsSchema.js (single source of truth).
    // To add a setting: declare the property above, then add one line to SettingsSchema.js.
    readonly property var _settingsSchema: Schema.schema

    function stringify(obj) {
        var replacer = function (key, val) {
            return val.toFixed ? Number(val.toFixed(4)) : val
        }
        return JSON.stringify(obj, replacer, 2)
    }

    function _schemaCompose(scope) {
        var obj = {}
        for (var i = 0; i < _settingsSchema.length; i++) {
            var e = _settingsSchema[i]
            if (e.scope === scope) obj[e.k] = this[e.p]
        }
        return obj
    }

    function _schemaLoad(obj, scope) {
        for (var i = 0; i < _settingsSchema.length; i++) {
            var e = _settingsSchema[i]
            if (e.scope === scope && obj[e.k] !== undefined)
                this[e.p] = obj[e.k]
        }
    }

    function composeSettingsString() { return stringify(_schemaCompose("settings")) }
    function composeProfileObject()  { return _schemaCompose("profile") }
    function composeProfileString()  { return stringify(composeProfileObject()) }

    function loadSettings() {
        var settingsString = storage.getSetting("_CURRENT_SETTINGS")
        var profileString = storage.getSetting("_CURRENT_PROFILE")
        if (!settingsString || !profileString) return
        loadSettingsString(settingsString)
        loadProfileString(profileString)
        if (verbose)
            console.log("Loading settings: " + settingsString + profileString)
    }

    function storeSettings() {
        var settingsString = composeSettingsString()
        var profileString = composeProfileString()
        storage.setSetting("_CURRENT_SETTINGS", settingsString)
        storage.setSetting("_CURRENT_PROFILE", profileString)
        if (verbose) {
            console.log("Storing settings: " + settingsString)
            console.log("Storing profile: " + profileString)
        }
    }

    function loadSettingsString(settingsString) {
        _schemaLoad(JSON.parse(settingsString), "settings")
    }

    function loadProfileString(profileString) {
        _schemaLoad(JSON.parse(profileString), "profile")
    }

    function storeCustomProfiles() {
        storage.setSetting("_CUSTOM_PROFILES", composeCustomProfilesString())
    }

    function loadCustomProfiles() {
        var customProfileString = storage.getSetting("_CUSTOM_PROFILES")
        if (customProfileString === undefined)
            customProfileString = "[]"
        loadCustomProfilesString(customProfileString)
    }

    function loadCustomProfilesString(customProfilesString) {
        var customProfiles = JSON.parse(customProfilesString)
        for (var i = 0; i < customProfiles.length; i++) {
            var profile = customProfiles[i]

            if (verbose)
                console.log("Loading custom profile: " + stringify(profile))

            profilesList.append(profile)
        }
    }

    function composeCustomProfilesString() {
        var customProfiles = []
        for (var i = 0; i < profilesList.count; i++) {
            var profile = profilesList.get(i)
            if (profile.builtin)
                continue
            customProfiles.push({
                                    "text": profile.text,
                                    "obj_string": profile.obj_string,
                                    "builtin": false
                                })
        }
        return stringify(customProfiles)
    }

    function loadProfile(index) {
        var profile = profilesList.get(index)
        loadProfileString(profile.obj_string)
    }

    function appendCustomProfile(name, profileString) {
        profilesList.append({
                                "text": name,
                                "obj_string": profileString,
                                "builtin": false
                            })
    }

    // PROFILES ///////////////////////////////////////////////////////////////
    // Populated at startup from profiles/builtin_profiles.json (QRC).
    // To add a built-in profile: add an entry to that JSON file and rebuild.
    property ListModel profilesList: ListModel {}

    function _loadBuiltinProfiles() {
        var rawProfiles = fileIO.read("qrc:/profiles/builtin_profiles.json")
        if (rawProfiles === "") {
            console.log("Unable to load built-in profiles from qrc:/profiles/builtin_profiles.json")
            return
        }
        var items = JSON.parse(rawProfiles)
        for (var i = 0; i < items.length; i++)
            profilesList.append(items[i])
    }

    function getProfileIndexByName(name) {
        for (var i = 0; i < profilesList.count; i++) {
            if (profilesList.get(i).text === name)
                return i
        }
        return -1
    }

    Component.onCompleted: {
        _loadBuiltinProfiles()

        // Manage the arguments from the QML side.
        var args = Qt.application.arguments
        if (args.indexOf("--verbose") !== -1) {
            verbose = true
        }
        if (args.indexOf("--default-settings") === -1) {
            loadSettings()
        }

        loadCustomProfiles()

        var profileArgPosition = args.indexOf("--profile")
        if (profileArgPosition !== -1) {
            var profileIndex = getProfileIndexByName(args[profileArgPosition + 1])
            if (profileIndex !== -1) {
                loadProfile(profileIndex)
            } else {
                console.log("Warning: selected profile is not valid; ignoring it")
            }
        }

        initializedSettings()
    }

    // VARS ///////////////////////////////////////////////////////////////////
    property Label _sampleLabel: Label {
        text: "100%"
    }
    property real labelWidth: _sampleLabel.width
}
