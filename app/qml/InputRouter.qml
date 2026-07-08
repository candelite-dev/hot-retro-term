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

// Intercepts all pointer events when the unified CRT is active and routes
// them to the correct (now-invisible) terminal underneath.
// Place this at z:3 over PaneLayout, visible only when needsUnifiedCRT.
MouseArea {
    id: inputRouter

    property var splitManager: null  // SplitTreeModel
    property var tabBarRef:    null  // AsciiTabBar — for hitTest + height

    signal zoomRequested(int delta)
    signal tabClicked(int index)
    signal addTabClicked()

    acceptedButtons: Qt.AllButtons
    hoverEnabled: true

    // ── Resize drag state ────────────────────────────────────────────────────

    property var _resizingBoundary: null

    // ── Bounds cache — invalidated by tree identity (mutations always create new objects) ──

    property var _cachedBoundsTree: undefined
    property var _cachedBounds: null
    property var _cachedBoundariesTree: undefined
    property var _cachedBoundaries: null

    cursorShape: _resizingBoundary
        ? (_resizingBoundary.orientation === Qt.Horizontal ? Qt.SplitHCursor : Qt.SplitVCursor)
        : Qt.IBeamCursor

    // ── Cached geometry helpers ───────────────────────────────────────────────

    function _getOrComputeBounds(tree) {
        if (tree !== _cachedBoundsTree) {
            _cachedBoundsTree = tree
            _cachedBounds = splitManager.computePaneBounds(tree, 0, 0, 1, 1)
        }
        return _cachedBounds
    }

    function _getOrComputeBoundaries(tree) {
        if (tree !== _cachedBoundariesTree) {
            _cachedBoundariesTree = tree
            _cachedBoundaries = splitManager.computeSplitBoundaries(tree, 0, 0, 1, 1)
        }
        return _cachedBoundaries
    }

    // ── Coordinate helpers ────────────────────────────────────────────────────

    function _stackTop() {
        return (tabBarRef && tabBarRef.visible) ? tabBarRef.height : 0
    }

    function _getBounds(paneId) {
        var tree = splitManager.splitTrees[splitManager.currentIndex]
        if (!tree) return null
        var bounds = _getOrComputeBounds(tree)
        for (var i = 0; i < bounds.length; i++) {
            if (bounds[i].paneId === paneId) return bounds[i]
        }
        return null
    }

    function _getPaneAt(relX, relY) {
        var top = _stackTop()
        if (relY < top) return null
        var tree = splitManager.splitTrees[splitManager.currentIndex]
        if (!tree) return null
        var bounds = _getOrComputeBounds(tree)
        var stackH = height - top
        var nx = relX / width
        var ny = (relY - top) / stackH
        for (var i = 0; i < bounds.length; i++) {
            var b = bounds[i]
            if (nx >= b.cx - b.w/2 && nx <= b.cx + b.w/2 &&
                ny >= b.cy - b.h/2 && ny <= b.cy + b.h/2)
                return b
        }
        return null
    }

    function _hitTestBoundary(mx, my) {
        var top = _stackTop()
        if (my < top) return null
        var tree = splitManager.splitTrees[splitManager.currentIndex]
        if (!tree) return null
        var boundaries = _getOrComputeBoundaries(tree)
        var stackH = height - top
        var nx = mx / width
        var ny = (my - top) / stackH
        var threshold = 6 / Math.max(width, stackH)
        for (var i = 0; i < boundaries.length; i++) {
            var bd = boundaries[i]
            if (bd.orientation === Qt.Horizontal) {
                if (Math.abs(nx - bd.pos) < threshold && ny >= bd.start && ny <= bd.end)
                    return bd
            } else {
                if (Math.abs(ny - bd.pos) < threshold && nx >= bd.start && nx <= bd.end)
                    return bd
            }
        }
        return null
    }

    function _toKCoords(b, mx, my) {
        var top = _stackTop()
        var stackH = height - top
        var paneX = (b.cx - b.w/2) * width
        var paneY = (b.cy - b.h/2) * stackH + top
        var pw = b.w * width
        var ph = b.h * stackH
        var t = splitManager.getTerminal(b.paneId)
        if (!t) return Qt.point(0, 0)
        var m = t.mainTerminal.margin
        return Qt.point(
            (mx - paneX - m) / pw * t.mainTerminal.totalWidth,
            (my - paneY - m) / ph * t.mainTerminal.totalHeight
        )
    }

    // ── Event handlers ────────────────────────────────────────────────────────

    onPressed: function(mouse) {
        // 1. Shared tab bar hit test
        if (tabBarRef && tabBarRef.visible && mouse.y < tabBarRef.height) {
            var tabIdx = tabBarRef.hitTest(mouse.x)
            if (tabIdx >= 0) { tabClicked(tabIdx); return }
            if (tabBarRef.hitTestAddButton(mouse.x)) { addTabClicked(); return }
            return
        }

        // 2. Resize boundary takes priority
        var boundary = _hitTestBoundary(mouse.x, mouse.y)
        if (boundary) { _resizingBoundary = boundary; return }

        // 3. Find pane and forward event
        var b = _getPaneAt(mouse.x, mouse.y)
        if (!b) return
        splitManager.focusedPaneId = b.paneId
        var t = splitManager.getTerminal(b.paneId)
        if (!t) return
        t.activate()
        var k = _toKCoords(b, mouse.x, mouse.y)
        t.mainTerminal.simulateMousePress(k.x, k.y, mouse.button, mouse.buttons, mouse.modifiers)
    }

    onReleased: function(mouse) {
        if (_resizingBoundary) { _resizingBoundary = null; return }
        var b = _getBounds(splitManager.focusedPaneId)
        var t = splitManager.getTerminal(splitManager.focusedPaneId)
        if (!b || !t) return
        var k = _toKCoords(b, mouse.x, mouse.y)
        t.mainTerminal.simulateMouseRelease(k.x, k.y, mouse.button, mouse.buttons, mouse.modifiers)
    }

    onPositionChanged: function(mouse) {
        if (_resizingBoundary) {
            var bd = _resizingBoundary
            var newRatio = bd.orientation === Qt.Horizontal
                ? (mouse.x / width  - bd.nodeX) / bd.nodeW
                : (mouse.y / height - bd.nodeY) / bd.nodeH
            newRatio = Math.max(0.1, Math.min(0.9, newRatio))
            splitManager.updateSplitRatio(bd, newRatio)
            return
        }
        var b = _getBounds(splitManager.focusedPaneId)
        var t = splitManager.getTerminal(splitManager.focusedPaneId)
        if (!b || !t) return
        var k = _toKCoords(b, mouse.x, mouse.y)
        t.mainTerminal.simulateMouseMove(k.x, k.y, mouse.button, mouse.buttons, mouse.modifiers)
    }

    onDoubleClicked: function(mouse) {
        var b = _getPaneAt(mouse.x, mouse.y)
        if (!b) return
        var t = splitManager.getTerminal(b.paneId)
        if (!t) return
        var k = _toKCoords(b, mouse.x, mouse.y)
        t.mainTerminal.simulateMouseDoubleClick(k.x, k.y, mouse.button, mouse.buttons, mouse.modifiers)
    }

    onWheel: function(wheel) {
        var b = _getPaneAt(wheel.x, wheel.y)
        if (!b) return
        var t = splitManager.getTerminal(b.paneId)
        if (!t) return
        if (wheel.modifiers & Qt.ControlModifier) {
            zoomRequested(wheel.angleDelta.y)
        } else {
            var k = _toKCoords(b, wheel.x, wheel.y)
            t.mainTerminal.simulateWheel(k.x, k.y, wheel.buttons, wheel.modifiers, wheel.angleDelta)
        }
    }
}
