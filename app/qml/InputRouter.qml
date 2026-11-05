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
import "SplitTree.js" as Tree

// Unified CRT input is mapped through the actual pane area and terminal items.
// Layout margins, tab-bar height, and terminal scaling stay owned by the layout.
MouseArea {
    id: router

    property var splitManager: null
    property Item tabBarRef: null
    property Item paneArea: null

    signal zoomRequested(int delta)
    signal tabClicked(int index)
    signal addTabClicked()

    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    property var _resizingBoundary: null
    property int _pressedPaneId: -1
    property int _pressedButton: Qt.NoButton
    property point _lastPosition: Qt.point(0, 0)

    readonly property var _tree: splitManager ? splitManager.splitTrees[splitManager.currentIndex] : null
    readonly property var _bounds: Tree.computePaneBounds(_tree, 0, 0, 1, 1)
    readonly property var _boundaries: Tree.computeSplitBoundaries(_tree, 0, 0, 1, 1)

    cursorShape: _resizingBoundary
        ? (_resizingBoundary.orientation === Qt.Horizontal ? Qt.SplitHCursor : Qt.SplitVCursor)
        : Qt.IBeamCursor

    function _panePoint(x, y) {
        if (!paneArea || paneArea.width <= 0 || paneArea.height <= 0) return null
        var p = paneArea.mapFromItem(router, x, y)
        return Qt.point(p.x / paneArea.width, p.y / paneArea.height)
    }

    function _getPaneAt(x, y) {
        var p = _panePoint(x, y)
        if (!p || p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1) return null
        for (var i = 0; i < _bounds.length; ++i) {
            var b = _bounds[i]
            if (p.x >= b.cx - b.w / 2 && p.x <= b.cx + b.w / 2 &&
                p.y >= b.cy - b.h / 2 && p.y <= b.cy + b.h / 2) return b
        }
        return null
    }

    function _hitTestBoundary(x, y) {
        var p = _panePoint(x, y)
        if (!p || p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1) return null
        for (var i = 0; i < _boundaries.length; ++i) {
            var b = _boundaries[i]
            if (b.orientation === Qt.Horizontal) {
                if (Math.abs(p.x - b.pos) * paneArea.width < 6 &&
                    p.y >= b.start && p.y <= b.end) return b
            } else if (Math.abs(p.y - b.pos) * paneArea.height < 6 &&
                       p.x >= b.start && p.x <= b.end) return b
        }
        return null
    }

    function _terminal(paneId) {
        return splitManager ? splitManager.getTerminal(paneId) : null
    }

    function _forward(terminal, method, event) {
        var target = terminal.mainTerminal
        var p = target.mapFromItem(router, event.x, event.y)
        target[method](p.x, p.y, event.button, event.buttons, event.modifiers)
    }

    onPressed: function(mouse) {
        _lastPosition = Qt.point(mouse.x, mouse.y)
        if (tabBarRef && tabBarRef.visible) {
            var p = tabBarRef.mapFromItem(router, mouse.x, mouse.y)
            if (p.y >= 0 && p.y < tabBarRef.height && p.x >= 0 && p.x < tabBarRef.width) {
                var index = tabBarRef.hitTest(p.x)
                if (index >= 0) tabClicked(index)
                else if (tabBarRef.hitTestAddButton(p.x)) addTabClicked()
                return
            }
        }
        var boundary = _hitTestBoundary(mouse.x, mouse.y)
        if (boundary && mouse.button === Qt.LeftButton) {
            _resizingBoundary = boundary
            return
        }
        var b = _getPaneAt(mouse.x, mouse.y)
        var terminal = b ? _terminal(b.paneId) : null
        if (!terminal) return
        _pressedPaneId = b.paneId
        _pressedButton = mouse.button
        splitManager.focusPane(b.paneId)
        terminal.activate()
        _forward(terminal, "simulateMousePress", mouse)
    }

    onReleased: function(mouse) {
        if (_resizingBoundary) { _resizingBoundary = null; return }
        var terminal = _terminal(_pressedPaneId)
        _pressedPaneId = -1
        _pressedButton = Qt.NoButton
        if (terminal) _forward(terminal, "simulateMouseRelease", mouse)
    }

    onCanceled: {
        _resizingBoundary = null
        var terminal = _terminal(_pressedPaneId)
        if (terminal) _forward(terminal, "simulateMouseRelease", {
            x: _lastPosition.x, y: _lastPosition.y, button: _pressedButton,
            buttons: Qt.NoButton, modifiers: Qt.NoModifier
        })
        _pressedPaneId = -1
        _pressedButton = Qt.NoButton
    }

    onPositionChanged: function(mouse) {
        _lastPosition = Qt.point(mouse.x, mouse.y)
        if (_resizingBoundary) {
            var p = _panePoint(mouse.x, mouse.y)
            if (!p) return
            var b = _resizingBoundary
            var ratio = b.orientation === Qt.Horizontal
                ? (p.x - b.nodeX) / b.nodeW : (p.y - b.nodeY) / b.nodeH
            splitManager.updateSplitRatio(b, ratio)
            return
        }
        var hit = _getPaneAt(mouse.x, mouse.y)
        var paneId = _pressedPaneId >= 0 ? _pressedPaneId : (hit ? hit.paneId : -1)
        var terminal = _terminal(paneId)
        if (terminal) _forward(terminal, "simulateMouseMove", mouse)
    }

    onDoubleClicked: function(mouse) {
        var b = _getPaneAt(mouse.x, mouse.y)
        var terminal = b ? _terminal(b.paneId) : null
        if (terminal) _forward(terminal, "simulateMouseDoubleClick", mouse)
    }

    onWheel: function(wheel) {
        var b = _getPaneAt(wheel.x, wheel.y)
        var terminal = b ? _terminal(b.paneId) : null
        if (!terminal) return
        if (wheel.modifiers & Qt.ControlModifier) {
            if (wheel.angleDelta.y !== 0) zoomRequested(wheel.angleDelta.y)
        } else {
            var target = terminal.mainTerminal
            var p = target.mapFromItem(router, wheel.x, wheel.y)
            target.simulateWheel(p.x, p.y, wheel.buttons, wheel.modifiers, wheel.angleDelta)
        }
    }
}
