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

// Tab/pane state and commands. Sessions and geometry have independent owners.
QtObject {
    id: model

    property var tabsModel: null
    property var sessionPool: null
    property var splitTrees: []
    property int nextPaneId: 0
    property int focusedPaneId: -1
    property int currentIndex: 0
    property int titleRevision: 0

    signal lastTabClosed()

    readonly property bool isSplitMode: Tree.countTerminals(splitTrees[currentIndex]) > 1
    readonly property bool needsUnifiedCRT: isSplitMode || (tabsModel && tabsModel.count > 1)

    onCurrentIndexChanged: focusCurrentTab()

    property Connections sessionConnections: Connections {
        target: model.sessionPool
        function onSessionFinished(paneId) { model.closePane(paneId) }
        function onTitleChanged(paneId, title) { model.updateTitle(paneId, title) }
        function onPaneClicked(paneId) { model.focusPane(paneId) }
    }

    function getTerminal(paneId) {
        return sessionPool ? sessionPool.getTerminal(paneId) : null
    }

    function tabForPane(paneId) {
        for (var i = 0; i < splitTrees.length; ++i)
            if (Tree.collectTerminals(splitTrees[i]).indexOf(paneId) >= 0) return i
        return -1
    }

    function focusCurrentTab() {
        var tree = splitTrees[currentIndex]
        if (Tree.collectTerminals(tree).indexOf(focusedPaneId) < 0)
            focusedPaneId = Tree.findFirstTerminal(tree)
    }

    function focusPane(paneId) {
        var index = tabForPane(paneId)
        if (index < 0) return
        currentIndex = index
        focusedPaneId = paneId
    }

    function updateTitle(paneId, title) {
        var index = tabForPane(paneId)
        if (index < 0) return
        tabsModel.setProperty(index, "title", title ? String(title).trim() : "")
        titleRevision++
    }

    function collectTitles() {
        titleRevision
        var titles = []
        if (!tabsModel) return titles
        for (var i = 0; i < tabsModel.count; ++i)
            titles.push(tabsModel.get(i).title || "cool-retro-term")
        return titles
    }

    function addTab() {
        if (!tabsModel || !sessionPool) return
        var paneId = nextPaneId
        var terminal = sessionPool.createTerminal(paneId)
        if (!terminal) return
        nextPaneId++
        tabsModel.append({ title: terminal.title || "" })
        splitTrees = splitTrees.concat([{ type: "terminal", paneId: paneId }])
        currentIndex = tabsModel.count - 1
        focusedPaneId = paneId
    }

    function closeTab(index) {
        if (!tabsModel || index < 0 || index >= splitTrees.length) return
        var paneIds = Tree.collectTerminals(splitTrees[index])
        var nextIndex = currentIndex - (index < currentIndex ? 1 : 0)
        var trees = splitTrees.slice()
        trees.splice(index, 1)
        splitTrees = trees
        tabsModel.remove(index)
        currentIndex = Math.max(0, Math.min(nextIndex, trees.length - 1))
        focusCurrentTab()
        for (var i = 0; i < paneIds.length; ++i)
            sessionPool.destroyTerminal(paneIds[i])
        if (trees.length === 0) lastTabClosed()
    }

    function splitPane(orientation) {
        var tree = splitTrees[currentIndex]
        var panes = Tree.collectTerminals(tree)
        if (!sessionPool || panes.indexOf(focusedPaneId) < 0 || panes.length >= 16) return
        if (orientation !== Qt.Horizontal && orientation !== Qt.Vertical) return
        var paneId = nextPaneId
        if (!sessionPool.createTerminal(paneId)) return
        nextPaneId++
        var trees = splitTrees.slice()
        trees[currentIndex] = Tree.replaceNode(tree, focusedPaneId, {
            type: "split", orientation: orientation, ratio: 0.5,
            first: { type: "terminal", paneId: focusedPaneId },
            second: { type: "terminal", paneId: paneId }
        })
        splitTrees = trees
        focusedPaneId = paneId
    }

    function closePane(paneId) {
        var index = tabForPane(paneId)
        if (index < 0) return
        var tree = splitTrees[index]
        if (Tree.countTerminals(tree) === 1) { closeTab(index); return }
        var trees = splitTrees.slice()
        trees[index] = Tree.removeNode(tree, paneId)
        splitTrees = trees
        focusCurrentTab()
        sessionPool.destroyTerminal(paneId)
    }

    function moveFocus(direction) {
        var tree = splitTrees[currentIndex]
        if (!tree) return
        var bounds = Tree.computePaneBounds(tree, 0, 0, 1, 1)
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
            var allPanes = Tree.collectTerminals(tree)
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
        if (!tree || !boundary || !isFinite(newRatio)) return
        var trees = splitTrees.slice()
        trees[currentIndex] = Tree.updateRatio(tree, boundary,
                                               Math.max(0.1, Math.min(0.9, newRatio)),
                                               0, 0, 1, 1)
        splitTrees = trees
    }
}
