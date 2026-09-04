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
import QtQuick
import QtQuick.Window
import QtQuick.Controls

import "menus"

ApplicationWindow {
    id: terminalWindow

    width: 1024
    height: 768

    minimumWidth: 320
    minimumHeight: 240

    visible: false

    property bool fullscreen: false
    onFullscreenChanged: visibility = (fullscreen ? Window.FullScreen : Window.Windowed)

    // Keeps appRoot.anyWindowVisible current so the render loop can stop
    // while every window is minimized or hidden.
    onVisibilityChanged: appRoot.recomputeWindowVisibility()

    // Qt's alpha-buffered surface format isn't enough on macOS — the NSWindow
    // itself still reports opaque to the compositor. Flip it natively once
    // the native window exists (i.e. once shown).
    onVisibleChanged: {
        if (visible && appSettings.isMacOS) {
            Qt.callLater(function() { macWindowHelper.makeTranslucent(terminalWindow) })
        }
    }

    menuBar: WindowMenu { }

    property real normalizedWindowScale: 1024 / ((0.5 * width + 0.5 * height))

    color: "#00000000"

    // Fusion style's default ApplicationWindow background is an opaque
    // Rectangle filled with palette.window — it paints under the CRT
    // content and defeats per-pixel window alpha even though `color`
    // above is transparent.
    background: null

    title: terminalTabs.currentTitle

    // Keyboard shortcut bindings — loaded from shortcuts.json at startup.
    // To rebind: copy shortcuts.json to ~/.config/cool-retro-term/shortcuts.json
    // and edit; the user file is merged over the bundled defaults at startup.
    property var _sc: ({})

    function _loadShortcuts() {
        var mac = Qt.platform.os === "osx"
        var bundledShortcuts = fileIO.read("qrc:/shortcuts.json")
        if (bundledShortcuts === "") {
            console.log("Unable to load bundled shortcuts from qrc:/shortcuts.json")
            return
        }
        var raw = JSON.parse(bundledShortcuts)

        // Optional user override — gracefully ignored if absent
        var userPath = fileIO.userShortcutsPath()
        if (userPath !== "") {
            try {
                var userFile = fileIO.read(userPath)
                if (userFile !== "") {
                    var userRaw = JSON.parse(userFile)
                    for (var uk in userRaw) raw[uk] = userRaw[uk]
                }
            } catch(e) { console.log("shortcuts override parse error:", e) }
        }

        var result = {}
        for (var key in raw) {
            var entry = raw[key]
            result[key] = mac ? entry.mac : entry["default"]
        }
        _sc = result
    }

    Component.onCompleted: {
        _loadShortcuts()

        // Apply to Action objects
        newWindowAction.shortcut      = _sc.newWindow      || ""
        quitAction.shortcut           = _sc.quit           || ""
        copyAction.shortcut           = _sc.copy           || ""
        pasteAction.shortcut          = _sc.paste          || ""
        newTabAction.shortcut         = _sc.newTab         || ""
        closeTabAction.shortcut       = _sc.closeTab       || ""
        commandPaletteAction.shortcut = _sc.commandPalette || ""
        splitVerticalAction.shortcut  = _sc.splitRight     || ""
        splitHorizontalAction.shortcut= _sc.splitDown      || ""

        // Apply to directional focus Shortcuts
        focusLeft.sequence  = _sc.focusLeft  || ""
        focusRight.sequence = _sc.focusRight || ""
        focusUp.sequence    = _sc.focusUp    || ""
        focusDown.sequence  = _sc.focusDown  || ""

        // Apply tab-switch shortcuts (1-9)
        var template = _sc.switchTab || ""
        for (var i = 0; i < tabShortcuts.count; i++) {
            var s = tabShortcuts.objectAt(i)
            if (s) s.sequence = template.replace("{n}", String(i + 1))
        }

        visible = true
    }

    Action {
        id: fullscreenAction
        text: qsTr("Fullscreen")
        enabled: !appSettings.isMacOS
        shortcut: StandardKey.FullScreen
        onTriggered: fullscreen = !fullscreen
        checkable: true
        checked: fullscreen
    }
    Action {
        id: newWindowAction
        text: qsTr("New Window")
    }
    Action {
        id: quitAction
        text: qsTr("Quit")
        onTriggered: terminalWindow.close()
    }
    Action {
        id: showsettingsAction
        text: qsTr("Settings")
        onTriggered: {
            settingsWindow.show()
            settingsWindow.requestActivate()
            settingsWindow.raise()
        }
    }
    Action {
        id: copyAction
        text: qsTr("Copy")
    }
    Action {
        id: pasteAction
        text: qsTr("Paste")
    }
    Action {
        id: zoomIn
        text: qsTr("Zoom In")
        shortcut: StandardKey.ZoomIn
        onTriggered: appSettings.incrementScaling()
    }
    Action {
        id: zoomOut
        text: qsTr("Zoom Out")
        shortcut: StandardKey.ZoomOut
        onTriggered: appSettings.decrementScaling()
    }
    Action {
        id: showAboutAction
        text: qsTr("About")
        onTriggered: {
            aboutDialog.show()
            aboutDialog.requestActivate()
            aboutDialog.raise()
        }
    }
    Action {
        id: newTabAction
        text: qsTr("New Tab")
        onTriggered: terminalTabs.addTab()
    }
    Action {
        id: closeTabAction
        text: qsTr("Close Tab")
        onTriggered: terminalTabs.closeFocusedPane()
    }
    Action {
        id: commandPaletteAction
        text: qsTr("Command Palette")
    }
    Action {
        id: splitVerticalAction
        text: qsTr("Split Right")
        onTriggered: terminalTabs.splitPane(Qt.Horizontal)
    }
    Action {
        id: splitHorizontalAction
        text: qsTr("Split Down")
        onTriggered: terminalTabs.splitPane(Qt.Vertical)
    }

    Shortcut { id: focusLeft;  context: Qt.WindowShortcut; onActivated: terminalTabs.moveFocus("left") }
    Shortcut { id: focusRight; context: Qt.WindowShortcut; onActivated: terminalTabs.moveFocus("right") }
    Shortcut { id: focusUp;    context: Qt.WindowShortcut; onActivated: terminalTabs.moveFocus("up") }
    Shortcut { id: focusDown;  context: Qt.WindowShortcut; onActivated: terminalTabs.moveFocus("down") }

    // Tab-switching shortcuts 1-9, sequences set in Component.onCompleted
    Instantiator {
        id: tabShortcuts
        model: 9
        delegate: Shortcut {
            context: Qt.WindowShortcut
            onActivated: if (terminalTabs.count > index) terminalTabs.currentIndex = index
        }
    }

    TerminalTabs {
        id: terminalTabs
        width: parent.width
        height: (parent.height + Math.abs(y))
    }
    Loader {
        anchors.centerIn: parent
        active: appSettings.showTerminalSize
        sourceComponent: SizeOverlay {
            z: 3
            terminalSize: terminalTabs.terminalSize
        }
    }
    onClosing: {
        appRoot.closeWindow(terminalWindow)
    }
}
