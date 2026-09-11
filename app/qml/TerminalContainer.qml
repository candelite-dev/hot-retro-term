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
import Qt5Compat.GraphicalEffects

import "utils.js" as Utils

ShaderTerminal {
    property alias title: terminal.title
    property alias terminalSize: terminal.terminalSize
    property alias mainTerminal: terminal.mainTerminal
    property bool isActive: false
    signal sessionFinished()
    signal paneClicked()

    property bool showDividerRight: false
    property bool showDividerBottom: false
    property bool isSplitLayout: false
    property int paneId: -1

    property bool loadBloomEffect: (appSettings.bloom > 0 || appSettings._frameShininess > 0) && !splitActive

    id: mainShader

    // windowOpacity now drives real per-pixel window alpha (see
    // terminal_dynamic.frag's windowAlpha uniform) instead of fading
    // this item toward the opaque window background.
    source: terminal.mainSource
    burnInEffect: terminal.burnInEffect
    virtualResolution: terminal.virtualResolution
    screenResolution: Qt.size(
        terminalWindow.width * Screen.devicePixelRatio * appSettings.windowScaling,
        terminalWindow.height * Screen.devicePixelRatio * appSettings.windowScaling
    )
    bloomSource: bloomSourceLoader.item

    PreprocessedTerminal {
        id: terminal
        anchors.fill: parent
        isActive: mainShader.isActive
        onSessionFinished: mainShader.sessionFinished()
        onPaneClicked: mainShader.paneClicked()
        showDividerRight: mainShader.showDividerRight
        showDividerBottom: mainShader.showDividerBottom
        splitActive: mainShader.splitActive
        isSplitLayout: mainShader.isSplitLayout
        paneId: mainShader.paneId
    }

    function activate() {
        terminal.mainTerminal.forceActiveFocus()
    }

    function refresh() {
        terminal.mainTerminal.update()
        var src = terminal.mainSource
        src.live = false
        src.scheduleUpdate()
        src.live = true

        // // Force kterminal geometryChange so the PTY rows/cols sync to the new pane size.
        // // 0 → bound value guarantees newGeometry != oldGeometry inside TerminalDisplay.
        // var kt = terminal.mainTerminal
        // var savedW = kt.width, savedH = kt.height
        // kt.width = 0
        // kt.height = 0
        // kt.width = savedW
        // kt.height = savedH
    }

    //  EFFECTS  ////////////////////////////////////////////////////////////////
    Loader {
        id: bloomEffectLoader
        active: loadBloomEffect
        asynchronous: true
        width: parent.width * appSettings.bloomQuality
        height: parent.height * appSettings.bloomQuality

        sourceComponent: FastBlur {
            radius: Utils.lint(16, 64, appSettings.bloomQuality)
            source: terminal.mainSource
            transparentBorder: true
        }
    }
    Loader {
        id: bloomSourceLoader
        active: loadBloomEffect
        asynchronous: true
        sourceComponent: ShaderEffectSource {
            id: _bloomEffectSource
            sourceItem: bloomEffectLoader.item
            wrapMode: ShaderEffectSource.Repeat
            hideSource: true
            smooth: true
            visible: false
        }
    }
}
