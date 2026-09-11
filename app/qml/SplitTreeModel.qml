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

// Pure data model for the split-pane tree.
// Owns splitTrees, terminal pool, and all tree/tab/pane operations.
// PaneTreeNode uses the splitManager interface exposed here.
QtObject {
    id: splitModel

    // ── External refs — set by TerminalTabs ──────────────────────────────────
    property var  tabsModel:    null   // ListModel
    property Item terminalPool: null   // hidden Item — terminals are parented here

    // ── State ────────────────────────────────────────────────────────────────
    property var  splitTrees:   []
    property int  nextPaneId:   0
    property int  focusedPaneId: -1
    property int  currentIndex: 0
    property bool isCurrentTab: true
    property int  titleRevision: 0

    onCurrentIndexChanged: Qt.callLater(refreshTerminalRenderMode)

    // ── Derived ──────────────────────────────────────────────────────────────
    readonly property bool isSplitMode: {
        var tree = splitTrees[currentIndex]
        return tree ? countTerminals(tree) > 1 : false
    }
    readonly property bool needsUnifiedCRT:
        isSplitMode || (tabsModel ? tabsModel.count > 1 : false)

    // ── Terminal pool ─────────────────────────────────────────────────────────

    property var _terminals: ({})
    property var _terminalComponent: null

    function createTerminal(paneId) {
        if (!_terminalComponent)
            _terminalComponent = Qt.createComponent("TerminalContainer.qml")
        if (_terminalComponent.status !== Component.Ready) {
            console.error("SplitTreeModel: failed to create component:", _terminalComponent.errorString())
            return null
        }
        var obj = _terminalComponent.createObject(terminalPool, {
            paneId: paneId
        })
        _terminals[paneId] = obj
        Qt.callLater(refreshTerminalRenderMode)
        return obj
    }

    function getTerminal(paneId) { return _terminals[paneId] || null }

    function destroyTerminal(paneId) {
        var t = _terminals[paneId]
        if (t) { t.destroy(); delete _terminals[paneId] }
        Qt.callLater(refreshTerminalRenderMode)
    }

    function refreshTerminalRenderMode() {
        // splitActive / isSplitLayout are driven by Qt.bindings in PaneTreeNode._setupBindings —
        // no imperative sync needed here.
    }

    // ── Title helpers ─────────────────────────────────────────────────────────

    function normalizeTitle(rawTitle) {
        if (rawTitle === undefined || rawTitle === null) return ""
        return String(rawTitle).trim()
    }

    function collectTitles() {
        titleRevision // binding dependency — incremented on title changes
        var titles = []
        if (!tabsModel)
            return titles
        for (var i = 0; i < tabsModel.count; i++) {
            var tab = tabsModel.get(i)
            titles.push(tab && tab.title ? tab.title : "cool-retro-term")
        }
        return titles
    }

    // ── Tab operations ────────────────────────────────────────────────────────

    function addTab() {
        var paneId = nextPaneId++
        createTerminal(paneId)
        tabsModel.append({ title: "" })
        var newTrees = splitTrees.slice()
        newTrees.push({ type: "terminal", paneId: paneId })
        splitTrees = newTrees
        currentIndex = tabsModel.count - 1
        focusedPaneId = paneId
        Qt.callLater(refreshTerminalRenderMode)
    }

    function closeTab(index) {
        var tree = splitTrees[index]
        if (tree) {
            var paneIds = collectTerminals(tree)
            for (var i = 0; i < paneIds.length; i++)
                destroyTerminal(paneIds[i])
        }
        if (tabsModel.count <= 1) {
            terminalWindow.close()
            return
        }
        var newTrees = splitTrees.slice()
        newTrees.splice(index, 1)
        splitTrees = newTrees
        tabsModel.remove(index)
        currentIndex = Math.min(currentIndex, tabsModel.count - 1)
        if (splitTrees[currentIndex])
            focusedPaneId = findFirstTerminal(splitTrees[currentIndex])
        Qt.callLater(refreshTerminalRenderMode)
    }

    // ── Pane operations ───────────────────────────────────────────────────────

    function splitPane(orientation) {
        var tree = splitTrees[currentIndex]
        if (!tree) return
        if (countTerminals(tree) >= 16) return
        var newPaneId = nextPaneId++
        createTerminal(newPaneId)
        var newTrees = splitTrees.slice()
        newTrees[currentIndex] = replaceNode(tree, focusedPaneId, {
            type: "split", orientation: orientation, ratio: 0.5,
            first:  { type: "terminal", paneId: focusedPaneId },
            second: { type: "terminal", paneId: newPaneId }
        })
        splitTrees = newTrees
        focusedPaneId = newPaneId
    }

    function closePane(paneId) {
        var tree = splitTrees[currentIndex]
        if (!tree) return
        if (countTerminals(tree) <= 1) { closeTab(currentIndex); return }
        destroyTerminal(paneId)
        var newTrees = splitTrees.slice()
        newTrees[currentIndex] = removeNode(tree, paneId)
        splitTrees = newTrees
        focusedPaneId = findFirstTerminal(splitTrees[currentIndex])
        Qt.callLater(refreshTerminalRenderMode)
    }

    function moveFocus(direction) {
        var tree = splitTrees[currentIndex]
        if (!tree) return
        var bounds = computePaneBounds(tree, 0, 0, 1, 1)
        if (bounds.length <= 1) return
        var cur = null
        for (var i = 0; i < bounds.length; i++) {
            if (bounds[i].paneId === focusedPaneId) { cur = bounds[i]; break }
        }
        if (!cur) return
        var best = null
        var bestDist = Infinity
        for (var j = 0; j < bounds.length; j++) {
            var b = bounds[j]
            if (b.paneId === focusedPaneId) continue
            var dx = b.cx - cur.cx
            var dy = b.cy - cur.cy
            var yOv = Math.min(cur.cy + cur.h/2, b.cy + b.h/2) - Math.max(cur.cy - cur.h/2, b.cy - b.h/2)
            var xOv = Math.min(cur.cx + cur.w/2, b.cx + b.w/2) - Math.max(cur.cx - cur.w/2, b.cx - b.w/2)
            var valid = false; var dist = 0
            if      (direction === "right" && dx >  0.001 && yOv > 0) { valid = true; dist =  dx }
            else if (direction === "left"  && dx < -0.001 && yOv > 0) { valid = true; dist = -dx }
            else if (direction === "down"  && dy >  0.001 && xOv > 0) { valid = true; dist =  dy }
            else if (direction === "up"    && dy < -0.001 && xOv > 0) { valid = true; dist = -dy }
            if (valid && dist < bestDist) { bestDist = dist; best = b }
        }
        if (!best) {
            var allPanes = collectTerminals(tree)
            var curIdx = allPanes.indexOf(focusedPaneId)
            if (curIdx < 0) return
            var wrapIdx = (direction === "right" || direction === "down")
                ? (curIdx + 1) % allPanes.length
                : (curIdx - 1 + allPanes.length) % allPanes.length
            focusedPaneId = allPanes[wrapIdx]
            return
        }
        focusedPaneId = best.paneId
    }

    function updateSplitRatio(boundary, newRatio) {
        var tree = splitTrees[currentIndex]
        if (!tree) return
        var newTrees = splitTrees.slice()
        newTrees[currentIndex] = _updateRatioInTree(tree, boundary, newRatio, 0, 0, 1, 1)
        splitTrees = newTrees
    }

    // ── Tree helpers (pure functions) ─────────────────────────────────────────

    function _updateRatioInTree(node, boundary, newRatio, x, y, w, h) {
        if (!node || node.type === "terminal") return node
        // Identify the target split node by its bounding rect + orientation.
        // paneId alone is ambiguous when nested splits share the same first leaf.
        var eps = 1e-6
        var matches = node.orientation === boundary.orientation
                   && Math.abs(x - boundary.nodeX) < eps
                   && Math.abs(y - boundary.nodeY) < eps
                   && Math.abs(w - boundary.nodeW) < eps
                   && Math.abs(h - boundary.nodeH) < eps
        if (matches)
            return { type: "split", orientation: node.orientation,
                     ratio: newRatio, first: node.first, second: node.second }
        var r = node.ratio
        if (node.orientation === Qt.Horizontal)
            return { type: "split", orientation: node.orientation, ratio: r,
                     first:  _updateRatioInTree(node.first,  boundary, newRatio, x,       y, w * r,     h),
                     second: _updateRatioInTree(node.second, boundary, newRatio, x + w*r, y, w * (1-r), h) }
        return { type: "split", orientation: node.orientation, ratio: r,
                 first:  _updateRatioInTree(node.first,  boundary, newRatio, x, y,       w, h * r),
                 second: _updateRatioInTree(node.second, boundary, newRatio, x, y + h*r, w, h * (1-r)) }
    }

    function computeSplitBoundaries(node, x, y, w, h) {
        if (!node || node.type === "terminal") return []
        var r = node.ratio
        var result = []
        if (node.orientation === Qt.Horizontal) {
            result.push({ orientation: Qt.Horizontal,
                          pos: x + w * r, start: y, end: y + h,
                          firstLeafPaneId: findFirstTerminal(node.first),
                          nodeX: x, nodeY: y, nodeW: w, nodeH: h })
            result = result
                .concat(computeSplitBoundaries(node.first,  x,       y, w * r,     h))
                .concat(computeSplitBoundaries(node.second, x + w*r, y, w * (1-r), h))
        } else {
            result.push({ orientation: Qt.Vertical,
                          pos: y + h * r, start: x, end: x + w,
                          firstLeafPaneId: findFirstTerminal(node.first),
                          nodeX: x, nodeY: y, nodeW: w, nodeH: h })
            result = result
                .concat(computeSplitBoundaries(node.first,  x, y,       w, h * r))
                .concat(computeSplitBoundaries(node.second, x, y + h*r, w, h * (1-r)))
        }
        return result
    }

    function computePaneBounds(node, x, y, w, h) {
        if (!node) return []
        if (node.type === "terminal")
            return [{ paneId: node.paneId, cx: x + w/2, cy: y + h/2, w: w, h: h }]
        var r = node.ratio
        if (node.orientation === Qt.Horizontal)
            return computePaneBounds(node.first,  x,       y, w * r,     h)
                  .concat(computePaneBounds(node.second, x + w*r, y, w * (1-r), h))
        return computePaneBounds(node.first,  x, y,       w, h * r)
              .concat(computePaneBounds(node.second, x, y + h*r, w, h * (1-r)))
    }

    function computePaneRects(node, x, y, w, h) {
        if (node.type === "terminal") {
            console.log("[RECT]",
                "paneId=", node.paneId,
                "x=", x, "y=", y, "w=", w, "h=", h)
            return [{
                type: "terminal",
                paneId: node.paneId,
                x: x,
                y: y,
                w: w,
                h: h,
                _showDividerRight: node._showDividerRight || false,
                _showDividerBottom: node._showDividerBottom || false
            }]
        }
        if (!node) return []
        if (node.type === "terminal") {
            return [{
                paneId: node.paneId,
                x: x, y: y, w: w, h: h,
                showDividerRight: node._showDividerRight || false,
                showDividerBottom: node._showDividerBottom || false
            }]
        }

        var r = node.ratio
        var first = cloneNode(node.first)
        var second = cloneNode(node.second)
        if (node.orientation === Qt.Horizontal)
            first._showDividerRight = true
        else
            first._showDividerBottom = true

        if (node.orientation === Qt.Horizontal)
            return computePaneRects(first,  x,       y, w * r,     h)
                  .concat(computePaneRects(second, x + w*r, y, w * (1-r), h))
        return computePaneRects(first,  x, y,       w, h * r)
              .concat(computePaneRects(second, x, y + h*r, w, h * (1-r)))
    }

    function countTerminals(node) {
        if (!node) return 0
        if (node.type === "terminal") return 1
        return countTerminals(node.first) + countTerminals(node.second)
    }

    function collectTerminals(node) {
        if (!node) return []
        if (node.type === "terminal") return [node.paneId]
        return collectTerminals(node.first).concat(collectTerminals(node.second))
    }

    function findFirstTerminal(node) {
        if (!node) return -1
        if (node.type === "terminal") return node.paneId
        return findFirstTerminal(node.first)
    }

    function cloneNode(node) {
        if (!node) return node
        if (node.type === "terminal")
            return {
                type: "terminal",
                paneId: node.paneId,
                _showDividerRight: node._showDividerRight || false,
                _showDividerBottom: node._showDividerBottom || false
            }
        return {
            type: "split",
            orientation: node.orientation,
            ratio: node.ratio,
            first: cloneNode(node.first),
            second: cloneNode(node.second),
            _showDividerRight: node._showDividerRight || false,
            _showDividerBottom: node._showDividerBottom || false
        }
    }

    function replaceNode(node, paneId, newNode) {
        if (!node) return node
        if (node.type === "terminal") return node.paneId === paneId ? newNode : node
        return { type: "split", orientation: node.orientation, ratio: node.ratio,
                 first:  replaceNode(node.first,  paneId, newNode),
                 second: replaceNode(node.second, paneId, newNode) }
    }

    function removeNode(node, paneId) {
        if (!node) return node
        if (node.type === "terminal") return node
        if (node.first  && node.first.type  === "terminal" && node.first.paneId  === paneId) return node.second
        if (node.second && node.second.type === "terminal" && node.second.paneId === paneId) return node.first
        return { type: "split", orientation: node.orientation, ratio: node.ratio,
                 first:  removeNode(node.first,  paneId),
                 second: removeNode(node.second, paneId) }
    }

    function dumpSplitDebug() {
        var tree = splitTrees[currentIndex]
        console.log("=== SplitTree Debug ===")
        console.log("currentIndex:", currentIndex,
            "focusedPaneId:", focusedPaneId,
            "isSplitMode:", isSplitMode,
            "needsUnifiedCRT:", needsUnifiedCRT)

        console.log("terminals:", JSON.stringify(collectTerminals(tree)))
        console.log("paneRects:", JSON.stringify(computePaneRects(tree, 0, 0, 1, 1)))
        console.log("boundaries:", JSON.stringify(computeSplitBoundaries(tree, 0, 0, 1, 1)))

        for (var paneId in _terminals) {
            var t = _terminals[paneId]
            console.log("terminal", paneId,
                "obj=", t,
                "parent=", t ? t.parent : null,
                "visible=", t ? t.visible : null,
                "x=", t ? t.x : null,
                "y=", t ? t.y : null,
                "w=", t ? t.width : null,
                "h=", t ? t.height : null,
                "splitActive=", t ? t.splitActive : null,
                "ktermSize=", (t && t.mainTerminal)
                    ? t.mainTerminal.width + "x" + t.mainTerminal.height : null)
        }
    }


}
