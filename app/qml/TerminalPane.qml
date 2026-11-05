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

// A visual slot borrows a terminal from the session pool. It never owns session events.
Item {
    id: slot

    property int paneId: -1
    property var splitManager: null
    property Item terminalPool: null
    property var _terminal: null
    readonly property bool paneActive: splitManager && paneId === splitManager.focusedPaneId

    onPaneIdChanged: Qt.callLater(claim)
    onSplitManagerChanged: Qt.callLater(claim)
    onWidthChanged: if (!_terminal) Qt.callLater(claim)
    onHeightChanged: if (!_terminal) Qt.callLater(claim)
    onVisibleChanged: { if (visible) Qt.callLater(claim); else release() }
    onPaneActiveChanged: if (paneActive && _terminal) _terminal.activate()
    Component.onCompleted: Qt.callLater(claim)
    Component.onDestruction: release()

    function claim() {
        if (!visible || !splitManager || paneId < 0 || width <= 0 || height <= 0) return
        var terminal = splitManager.getTerminal(paneId)
        if (_terminal === terminal) return
        release()
        if (!terminal) return
        _terminal = terminal
        terminal.parent = slot
        terminal.x = 0
        terminal.y = 0
        terminal.width = Qt.binding(function() { return slot.width })
        terminal.height = Qt.binding(function() { return slot.height })
        terminal.isActive = Qt.binding(function() { return slot.paneActive })
        terminal.splitActive = Qt.binding(function() { return slot.splitManager.needsUnifiedCRT })
        terminal.isSplitLayout = Qt.binding(function() { return slot.splitManager.isSplitMode })
        terminal.visible = true
        terminal.refresh()
        if (paneActive) terminal.activate()
    }

    function release() {
        var terminal = _terminal
        _terminal = null
        if (!terminal || terminal.parent !== slot) return
        // Drop bindings to this slot before it is destroyed by the Repeater.
        terminal.isActive = false
        terminal.width = terminal.width
        terminal.height = terminal.height
        terminal.splitActive = terminal.splitActive
        terminal.isSplitLayout = terminal.isSplitLayout
        terminal.visible = false
        terminal.parent = terminalPool
    }
}
