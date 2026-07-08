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

import QMLTermWidget 2.0

import "menus"
import "utils.js" as Utils

Item{
    id: terminalContainer
    signal sessionFinished()
    signal paneClicked()

    property size virtualResolution: Qt.size(kterminal.totalWidth, kterminal.totalHeight)
    property alias mainTerminal: kterminal

    property ShaderEffectSource mainSource: kterminalSource
    property BurnInEffect burnInEffect: burnInEffect
    property real fontWidth: 1.0
    property real screenScaling: 1.0
    property real scaleTexture: 1.0
    property alias title: ksession.title
    property alias kterminal: kterminal
    property bool isActive: false
    onIsActiveChanged: {
        if (!isActive && commandPalette.isOpen) commandPalette.close()
    }

    property size terminalSize: kterminal.terminalSize
    property size fontMetrics: kterminal.fontMetrics

    property bool showDividerRight: false
    property bool showDividerBottom: false
    property bool splitActive: false
    property bool isSplitLayout: false
    property int paneId: -1

    // Manage copy and paste
    Connections {
        target: copyAction

        onTriggered: {
            if (terminalContainer.isActive) {
                kterminal.copyClipboard()
            }
        }
    }
    Connections {
        target: pasteAction

        onTriggered: {
            if (terminalContainer.isActive) {
                kterminal.pasteClipboard()
            }
        }
    }
    Connections {
        target: commandPaletteAction

        onTriggered: {
            if (terminalContainer.isActive) {
                commandPalette.toggle()
            }
        }
    }
    Connections {
        target: kterminal
        function onUrlActivated(url) {
            Qt.openUrlExternally(url)
        }
    }

    //When settings are updated sources need to be redrawn.
    Connections {
        target: appSettings

        onFontScalingChanged: {
            terminalContainer.updateSources()
        }

        onFontWidthChanged: {
            terminalContainer.updateSources()
        }
    }
    Connections {
        target: terminalContainer

        onWidthChanged: {
            terminalContainer.updateSources()
        }

        onHeightChanged: {
            terminalContainer.updateSources()
        }
    }

    function updateSources() {
        kterminal.update()
    }

    QMLTermWidget {
        id: kterminal

        property int textureResolutionScale: appSettings.lowResolutionFont ? Screen.devicePixelRatio : 1
        property int margin: terminalContainer.splitActive ? 0 : appSettings.margin / screenScaling
        property int totalWidth: Math.floor(parent.width / screenScaling)
        property int totalHeight: Math.floor(parent.height / screenScaling)
        property bool sessionStarted: false

        property int rawWidth: Math.max(1, totalWidth - 2 * margin)
        property int rawHeight: Math.max(1, totalHeight - 2 * margin)

        textureSize: Qt.size(width / textureResolutionScale, height / textureResolutionScale)

        width: ensureMultiple(rawWidth, Screen.devicePixelRatio)
        height: ensureMultiple(rawHeight, Screen.devicePixelRatio)

        // In split mode kterminal renders directly (no FBO stretch pass), but the item
        // is sized at 1/screenScaling — scale it back up to fill the pane.
        transformOrigin: Item.TopLeft
        scale: terminalContainer.splitActive ? screenScaling : 1

        /** Ensure size is a multiple of factor. This is needed for pixel perfect scaling on highdpi screens. */
        function ensureMultiple(size, factor) {
            return Math.round(size / factor) * factor;
        }

        fullCursorHeight: true
        blinkingCursor: appSettings.blinkingCursor

        colorScheme: "cool-retro-term"

        session: QMLTermSession {
            id: ksession

            onFinished: {
                terminalContainer.sessionFinished()
            }
        }

        QMLTermScrollbar {
            id: kterminalScrollbar
            terminal: kterminal
            anchors.margins: width * 0.5
            width: terminal.fontMetrics.width * 0.75
            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 1
                anchors.bottomMargin: 1
                color: "white"
                opacity: 0.7
            }
        }

        AsciiDivider {
            id: rightDivider
            visible: terminalContainer.showDividerRight
            orientation: Qt.Horizontal
            anchors.right: parent.right
            y: 0
            width: kterminal.fontMetrics.width
            height: kterminal.height
            fontColor: appSettings.fontColor
            backgroundColor: appSettings.backgroundColor
            charMetrics: kterminal.fontMetrics
            termFont: kterminal.font
            z: 10
        }

        AsciiDivider {
            id: bottomDivider
            visible: terminalContainer.showDividerBottom
            orientation: Qt.Vertical
            anchors.bottom: parent.bottom
            x: 0
            width: kterminal.width
            height: kterminal.fontMetrics.height
            fontColor: appSettings.fontColor
            backgroundColor: appSettings.backgroundColor
            charMetrics: kterminal.fontMetrics
            termFont: kterminal.font
            z: 10
        }

        AsciiFocusBorder {
            anchors.fill: parent
            visible: terminalContainer.isActive && terminalContainer.isSplitLayout
            fontColor: appSettings.fontColor
            charMetrics: kterminal.fontMetrics
            termFont: kterminal.font
            opacity: 0.6
            z: 12
        }

        CommandPalette {
            id: commandPalette
            anchors.horizontalCenter: parent.horizontalCenter
            y: kterminal.fontMetrics.height * 3
            width: Math.min(paletteWidthChars * kterminal.fontMetrics.width, kterminal.width)
            fontColor: appSettings.fontColor
            backgroundColor: appSettings.backgroundColor
            charMetrics: kterminal.fontMetrics
            termFont: kterminal.font

            onCommandTriggered: function(actionId) {
                var actions = {
                    "newWindow":  newWindowAction,
                    "newTab":     newTabAction,
                    "closeTab":   closeTabAction,
                    "copy":       copyAction,
                    "paste":      pasteAction,
                    "fullscreen": fullscreenAction,
                    "settings":   showsettingsAction,
                    "zoomIn":     zoomIn,
                    "zoomOut":    zoomOut,
                    "quit":       quitAction,
                    "splitRight": splitVerticalAction,
                    "splitDown":  splitHorizontalAction
                }
                if (actionId in actions) actions[actionId].trigger()
            }
            onProfileRequested: function(index) {
                appSettings.loadProfile(index)
            }
            onToggleRequested: function(prop) {
                var defaults = {
                    bloom: 0.55, burnIn: 0.25, staticNoise: 0.12, jitter: 0.2,
                    glowingLine: 0.2, screenCurvature: 0.5, flickering: 0.1,
                    horizontalSync: 0.1, rgbShift: 0.2, chromaColor: 0.2, ambientLight: 0.3
                }
                appSettings[prop] = appSettings[prop] > 0 ? 0.0 : (defaults[prop] || 0.5)
            }
            onClosed: kterminal.forceActiveFocus()
        }

        // Boot overlay: shows a blinking cursor immediately on terminal creation,
        // disappears as soon as the first data arrives from the shell process.
        Item {
            id: bootOverlay
            anchors.fill: parent
            visible: true
            z: 5

            Text {
                x: 0
                y: 0
                text: "\u2588"
                font: kterminal.font
                color: appSettings.fontColor

                SequentialAnimation on opacity {
                    running: bootOverlay.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0; duration: 500 }
                    NumberAnimation { to: 1; duration: 500 }
                }
            }

            Connections {
                target: kterminal
                // Only needed until the first output; without this gate the
                // handler would run for every PTY block for the session's life.
                enabled: bootOverlay.visible
                function onReceivedData(text) {
                    bootOverlay.visible = false
                }
            }
        }

        function handleFontChanged(fontFamily, pixelSize, lineSpacing, screenScaling, fontWidth, fallbackFontFamily, lowResolutionFont) {
            kterminal.lineSpacing = lineSpacing;
            kterminal.antialiasText = !lowResolutionFont;
            kterminal.smooth = !lowResolutionFont;
            kterminal.enableBold = !lowResolutionFont;
            kterminal.enableItalic = !lowResolutionFont;

            kterminal.font = Qt.font({
                family: fontFamily,
                pixelSize: pixelSize
            });

            terminalContainer.fontWidth = fontWidth;
            terminalContainer.screenScaling = screenScaling;
            scaleTexture = Math.max(1.0, Math.floor(screenScaling * appSettings.windowScaling));
        }

        Connections {
            target: appSettings

            onWindowScalingChanged: {
                scaleTexture = Math.max(1.0, Math.floor(terminalContainer.screenScaling * appSettings.windowScaling));
            }
        }

        onWidthChanged: maybeStartSession()
        onHeightChanged: maybeStartSession()

        function startSession() {
            // Retrieve the variable set in main.cpp if arguments are passed.
            if (defaultCmd) {
                ksession.setShellProgram(defaultCmd);
                ksession.setArgs(defaultCmdArgs);
            } else if (appSettings.useCustomCommand) {
                var args = Utils.tokenizeCommandLine(appSettings.customCommand);
                ksession.setShellProgram(args[0]);
                ksession.setArgs(args.slice(1));
            } else if (!defaultCmd && appSettings.isMacOS) {
                // OSX Requires the following default parameters for auto login.
                ksession.setArgs(["-i", "-l"]);
            }

            if (workdir)
                ksession.initialWorkingDirectory = workdir;

            ksession.startShellProgram();
            forceActiveFocus();
        }

        function maybeStartSession() {
            if (sessionStarted || width <= 0 || height <= 0)
                return
            sessionStarted = true
            startSession()
        }

        Component.onCompleted: {
            appSettings.fontManager.terminalFontChanged.connect(handleFontChanged);
            appSettings.fontManager.emitCurrentFont();
            maybeStartSession();
        }
        Component.onDestruction: {
            appSettings.fontManager.terminalFontChanged.disconnect(handleFontChanged);
        }
    }

    Component {
        id: shortContextMenu
        ShortContextMenu { }
    }

    Component {
        id: fullContextMenu
        FullContextMenu { }
    }

    Loader {
        id: menuLoader
        sourceComponent: (appSettings.isMacOS || (appSettings.showMenubar && !terminalWindow.fullscreen) ? shortContextMenu : fullContextMenu)
    }
    property alias contextmenu: menuLoader.item

    MouseArea {
        property real margin: terminalContainer.splitActive ? 0 : appSettings.margin
        property real frameSize: appSettings.frameSize * terminalWindow.normalizedWindowScale

        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        anchors.fill: parent
        cursorShape: kterminal.terminalUsesMouse ? Qt.ArrowCursor : Qt.IBeamCursor
        onWheel: function(wheel) {
            if (wheel.modifiers & Qt.ControlModifier) {
               wheel.angleDelta.y > 0 ? zoomIn.trigger() : zoomOut.trigger();
            } else {
                var coord = correctDistortion(wheel.x, wheel.y);
                kterminal.simulateWheel(coord.x, coord.y, wheel.buttons, wheel.modifiers, wheel.angleDelta);
            }
        }
        onDoubleClicked: function(mouse) {
            var coord = correctDistortion(mouse.x, mouse.y);
            kterminal.simulateMouseDoubleClick(coord.x, coord.y, mouse.button, mouse.buttons, mouse.modifiers);
        }
        onPressed: function(mouse) {
            terminalContainer.paneClicked()
            var coord = correctDistortion(mouse.x, mouse.y);
            // If palette is open, consume click and close if outside palette bounds
            if (commandPalette.isOpen) {
                var px = commandPalette.x
                var py = commandPalette.y
                var pw = commandPalette.width
                var ph = commandPalette.totalHeight
                if (coord.x < px || coord.x > px + pw || coord.y < py || coord.y > py + ph) {
                    commandPalette.close()
                }
                return
            }
            kterminal.forceActiveFocus()
            if ((!kterminal.terminalUsesMouse || mouse.modifiers & Qt.ShiftModifier) && mouse.button == Qt.RightButton) {
                contextmenu.popup();
            } else {
                kterminal.simulateMousePress(coord.x, coord.y, mouse.button, mouse.buttons, mouse.modifiers)
            }
        }
        onReleased: function(mouse) {
            var coord = correctDistortion(mouse.x, mouse.y);
            kterminal.simulateMouseRelease(coord.x, coord.y, mouse.button, mouse.buttons, mouse.modifiers);
        }
        onPositionChanged: function(mouse) {
            var coord = correctDistortion(mouse.x, mouse.y);
            kterminal.simulateMouseMove(coord.x, coord.y, mouse.button, mouse.buttons, mouse.modifiers);
        }

        function correctDistortion(x, y) {
            x = (x - margin) / width;
            y = (y - margin) / height;

            x = x * (1 + frameSize * 2) - frameSize;
            y = y * (1 + frameSize * 2) - frameSize;

            var cc = Qt.size(0.5 - x, 0.5 - y);
            var distortion = (cc.height * cc.height + cc.width * cc.width)
                    * appSettings.screenCurvature * appSettings.screenCurvatureSize
                    * terminalWindow.normalizedWindowScale;

            return Qt.point((x - cc.width  * (1+distortion) * distortion) * (kterminal.totalWidth),
                           (y - cc.height * (1+distortion) * distortion) * (kterminal.totalHeight))
        }
    }
    ShaderEffectSource{
        id: kterminalSource
        sourceItem: kterminal
        // In split mode the per-pane CRT and burn-in are disabled, so kterminal can render
        // directly into crtContent without an FBO — eliminates N per-pane FBO captures.
        hideSource: !terminalContainer.splitActive
        live: !terminalContainer.splitActive
        wrapMode: ShaderEffectSource.Repeat
        visible: false
        anchors.fill: parent
        textureSize: Qt.size(kterminal.totalWidth * scaleTexture, kterminal.totalHeight * scaleTexture)
        sourceRect: Qt.rect(-kterminal.margin, -kterminal.margin, kterminal.totalWidth, kterminal.totalHeight)
    }

    Item {
        id: burnInContainer

        property int burnInScaling: scaleTexture * appSettings.burnInQuality

        width: Math.round(appSettings.lowResolutionFont
               ? kterminal.totalWidth * Math.max(1, burnInScaling)
               : kterminal.totalWidth * scaleTexture * appSettings.burnInQuality)

        height: Math.round(appSettings.lowResolutionFont
                ? kterminal.totalHeight * Math.max(1, burnInScaling)
                : kterminal.totalHeight * scaleTexture * appSettings.burnInQuality)


        BurnInEffect {
            id: burnInEffect
            textSource: kterminalSource
            triggerTarget: kterminal
            active: appSettings.burnIn !== 0 && !terminalContainer.splitActive
        }
    }
}
