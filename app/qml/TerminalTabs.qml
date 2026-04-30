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
import QtQuick.Controls
import QtQuick.Layouts
import QtQml.Models
import Qt5Compat.GraphicalEffects
import CoolRetroTerm 1.0

import "utils.js" as Utils

Item {
    id: tabsRoot

    readonly property int innerPadding: 6
    readonly property string currentTitle: tabsModel.get(currentIndex).title ?? "cool-retro-term"
    property int currentIndex: 0
    readonly property int count: tabsModel.count
    property size terminalSize: Qt.size(0, 0)

    readonly property int tabWidth: 160
    readonly property int tabBarHeight: 28
    property real scrollTargetX: 0

    property int titleRevision: 0

    // Split pane state
    property var splitTrees: []
    property int nextPaneId: 0
    property int focusedPaneId: -1
    property bool isCurrentTab: true

    readonly property bool isSplitMode: {
        var tree = splitTrees[currentIndex]
        return tree ? countTerminals(tree) > 1 : false
    }
    readonly property bool needsUnifiedCRT: isSplitMode || count > 1

    // Terminal pool — terminals live here and are reparented into PaneTreeNode slots
    property alias terminalPool: terminalPool
    property var _terminals: ({})
    property var _terminalComponent: null

    Item {
        id: terminalPool
        visible: false
    }

    function createTerminal(paneId) {
        if (!_terminalComponent) {
            _terminalComponent = Qt.createComponent("TerminalContainer.qml")
        }
        if (_terminalComponent.status !== Component.Ready) {
            console.error("TerminalPool: failed to create component:", _terminalComponent.errorString())
            return null
        }
        var obj = _terminalComponent.createObject(terminalPool, { paneId: paneId })
        _terminals[paneId] = obj
        return obj
    }

    function getTerminal(paneId) {
        return _terminals[paneId] || null
    }

    function destroyTerminal(paneId) {
        var t = _terminals[paneId]
        if (t) {
            t.destroy()
            delete _terminals[paneId]
        }
    }

    function collectTitles() {
        titleRevision; // binding dependency — incremented on title changes
        var titles = []
        for (var i = 0; i < tabsModel.count; i++)
            titles.push(tabsModel.get(i).title || "cool-retro-term")
        return titles
    }

    function normalizeTitle(rawTitle) {
        if (rawTitle === undefined || rawTitle === null) {
            return ""
        }
        return String(rawTitle).trim()
    }

    function addTab() {
        var paneId = nextPaneId++
        createTerminal(paneId)
        tabsModel.append({ title: "" })
        var newTrees = splitTrees.slice()
        newTrees.push({ type: "terminal", paneId: paneId })
        splitTrees = newTrees
        tabsRoot.currentIndex = tabsModel.count - 1
        focusedPaneId = paneId
    }

    function closeTab(index) {
        // Destroy all terminals belonging to this tab
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
        tabsRoot.currentIndex = Math.min(tabsRoot.currentIndex, tabsModel.count - 1)
        if (splitTrees[tabsRoot.currentIndex]) {
            focusedPaneId = findFirstTerminal(splitTrees[tabsRoot.currentIndex])
        }
    }

    function splitPane(orientation) {
        var tree = splitTrees[currentIndex]
        if (!tree) return
        if (countTerminals(tree) >= 16) return
        var newPaneId = nextPaneId++
        createTerminal(newPaneId)
        var newTrees = splitTrees.slice()
        newTrees[currentIndex] = replaceNode(tree, focusedPaneId, {
            type: "split", orientation: orientation, ratio: 0.5,
            first: { type: "terminal", paneId: focusedPaneId },
            second: { type: "terminal", paneId: newPaneId }
        })
        splitTrees = newTrees
        focusedPaneId = newPaneId
    }

    function closePane(paneId) {
        var tree = splitTrees[currentIndex]
        if (!tree) return
        var termCount = countTerminals(tree)
        if (termCount <= 1) {
            closeTab(currentIndex)
            return
        }
        destroyTerminal(paneId)
        var newTrees = splitTrees.slice()
        newTrees[currentIndex] = removeNode(tree, paneId)
        splitTrees = newTrees
        focusedPaneId = findFirstTerminal(splitTrees[currentIndex])
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
            var yOverlap = Math.min(cur.cy + cur.h/2, b.cy + b.h/2) - Math.max(cur.cy - cur.h/2, b.cy - b.h/2)
            var xOverlap = Math.min(cur.cx + cur.w/2, b.cx + b.w/2) - Math.max(cur.cx - cur.w/2, b.cx - b.w/2)
            var valid = false
            var dist = 0
            if (direction === "right" && dx > 0.001 && yOverlap > 0) { valid = true; dist = dx }
            else if (direction === "left"  && dx < -0.001 && yOverlap > 0) { valid = true; dist = -dx }
            else if (direction === "down"  && dy > 0.001 && xOverlap > 0) { valid = true; dist = dy }
            else if (direction === "up"    && dy < -0.001 && xOverlap > 0) { valid = true; dist = -dy }
            if (valid && dist < bestDist) { bestDist = dist; best = b }
        }
        // Wrap around if no spatial candidate
        if (!best) {
            var allPanes = collectTerminals(tree)
            var curIdx = allPanes.indexOf(focusedPaneId)
            if (curIdx < 0) return
            var wrapIdx
            if (direction === "right" || direction === "down")
                wrapIdx = (curIdx + 1) % allPanes.length
            else
                wrapIdx = (curIdx - 1 + allPanes.length) % allPanes.length
            focusedPaneId = allPanes[wrapIdx]
            return
        }
        focusedPaneId = best.paneId
    }

    function updateSplitRatio(firstLeafPaneId, newRatio) {
        var tree = splitTrees[currentIndex]
        if (!tree) return
        var newTrees = splitTrees.slice()
        newTrees[currentIndex] = _updateRatioInTree(tree, firstLeafPaneId, newRatio)
        splitTrees = newTrees
    }

    function _updateRatioInTree(node, firstLeafPaneId, newRatio) {
        if (!node || node.type === "terminal") return node
        if (findFirstTerminal(node.first) === firstLeafPaneId) {
            return { type: "split", orientation: node.orientation,
                     ratio: newRatio, first: node.first, second: node.second }
        }
        return { type: "split", orientation: node.orientation, ratio: node.ratio,
                 first: _updateRatioInTree(node.first, firstLeafPaneId, newRatio),
                 second: _updateRatioInTree(node.second, firstLeafPaneId, newRatio) }
    }

    function computeSplitBoundaries(node, x, y, w, h) {
        if (!node || node.type === "terminal") return []
        var r = node.ratio
        var result = []
        if (node.orientation === Qt.Horizontal) {
            result.push({
                orientation: Qt.Horizontal,
                pos: x + w * r,
                start: y, end: y + h,
                firstLeafPaneId: findFirstTerminal(node.first),
                nodeX: x, nodeY: y, nodeW: w, nodeH: h
            })
            result = result
                .concat(computeSplitBoundaries(node.first,  x,       y, w * r,     h))
                .concat(computeSplitBoundaries(node.second, x + w*r, y, w * (1-r), h))
        } else {
            result.push({
                orientation: Qt.Vertical,
                pos: y + h * r,
                start: x, end: x + w,
                firstLeafPaneId: findFirstTerminal(node.first),
                nodeX: x, nodeY: y, nodeW: w, nodeH: h
            })
            result = result
                .concat(computeSplitBoundaries(node.first,  x, y,       w, h * r))
                .concat(computeSplitBoundaries(node.second, x, y + h*r, w, h * (1-r)))
        }
        return result
    }

    function computePaneBounds(node, x, y, w, h) {
        if (!node) return []
        if (node.type === "terminal") {
            return [{ paneId: node.paneId, cx: x + w/2, cy: y + h/2, w: w, h: h }]
        }
        var r = node.ratio
        if (node.orientation === Qt.Horizontal) {
            return computePaneBounds(node.first,  x,       y, w * r,     h)
                  .concat(computePaneBounds(node.second, x + w*r, y, w * (1-r), h))
        } else {
            return computePaneBounds(node.first,  x, y,       w, h * r)
                  .concat(computePaneBounds(node.second, x, y + h*r, w, h * (1-r)))
        }
    }

    // --- Tree helpers ---

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

    function replaceNode(node, paneId, newNode) {
        if (!node) return node
        if (node.type === "terminal") return node.paneId === paneId ? newNode : node
        return {
            type: "split", orientation: node.orientation, ratio: node.ratio,
            first: replaceNode(node.first, paneId, newNode),
            second: replaceNode(node.second, paneId, newNode)
        }
    }

    function removeNode(node, paneId) {
        if (!node) return node
        if (node.type === "terminal") return node
        if (node.first && node.first.type === "terminal" && node.first.paneId === paneId)
            return node.second
        if (node.second && node.second.type === "terminal" && node.second.paneId === paneId)
            return node.first
        return {
            type: "split", orientation: node.orientation, ratio: node.ratio,
            first: removeNode(node.first, paneId),
            second: removeNode(node.second, paneId)
        }
    }

    function ensureTabVisible(idx) {
        var x = idx * tabWidth
        if (x < scrollTargetX) {
            scrollTargetX = x
        } else if (x + tabWidth > scrollTargetX + tabsFlickable.width) {
            scrollTargetX = x + tabWidth - tabsFlickable.width
        }
        tabsFlickable.contentX = scrollTargetX
    }

    onCurrentIndexChanged: {
        ensureTabVisible(currentIndex)
        isCurrentTab = true
        if (splitTrees[currentIndex]) {
            focusedPaneId = findFirstTerminal(splitTrees[currentIndex])
        }
    }

    // Expose tabsModel so PaneTreeNode can reference it via splitManager
    property alias tabsModel: tabsModel

    ListModel {
        id: tabsModel
    }

    Component.onCompleted: addTab()

    CurvatureInputFilter {
        targetItem: contentColumn
        curvature: appSettings.windowCurvature > 0
            ? appSettings.windowCurvature * appSettings.screenCurvatureSize * (1024 / (0.5 * contentColumn.width + 0.5 * contentColumn.height))
            : 0
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: 0

        layer.enabled: appSettings.windowCurvature > 0
        layer.effect: ShaderEffect {
            property real screenCurvature: appSettings.windowCurvature * appSettings.screenCurvatureSize * (1024 / (0.5 * width + 0.5 * height))
            vertexShader: "qrc:/shaders/window_curvature.vert.qsb"
            fragmentShader: "qrc:/shaders/window_curvature.frag.qsb"
        }

        Rectangle {
            id: tabRow
            Layout.fillWidth: true
            Layout.preferredHeight: 0
            height: 0
            color: appSettings.backgroundColor
            visible: false

            RowLayout {
                anchors.fill: parent
                spacing: 0

                Flickable {
                    id: tabsFlickable
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    contentWidth: tabsContainer.width
                    contentHeight: height
                    interactive: false

                    Behavior on contentX {
                        SmoothedAnimation { velocity: 1600; duration: -1 }
                    }

                    Item {
                        id: tabsContainer
                        width: Math.max(tabsFlickable.width, tabsModel.count * tabWidth)
                        height: tabBarHeight

                        property int draggingIndex: -1
                        property real draggingX: 0

                        Repeater {
                            model: tabsModel

                            Item {
                                id: tabDelegate
                                width: tabWidth
                                height: tabBarHeight

                                property bool isCurrentTab: index === tabsRoot.currentIndex
                                property bool isDragging: tabsContainer.draggingIndex === index

                                property real baseX: {
                                    if (tabsContainer.draggingIndex < 0 || index === tabsContainer.draggingIndex)
                                        return index * tabWidth
                                    var di = tabsContainer.draggingIndex
                                    var targetIdx = Math.max(0, Math.min(tabsModel.count - 1,
                                                             Math.round(tabsContainer.draggingX / tabWidth)))
                                    if (di < targetIdx) {
                                        if (index > di && index <= targetIdx)
                                            return (index - 1) * tabWidth
                                    } else if (di > targetIdx) {
                                        if (index >= targetIdx && index < di)
                                            return (index + 1) * tabWidth
                                    }
                                    return index * tabWidth
                                }

                                x: isDragging ? tabsContainer.draggingX : baseX

                                Behavior on x {
                                    enabled: !tabDelegate.isDragging
                                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                                }

                                z: isDragging ? 10 : 1

                                Rectangle {
                                    id: tabBg
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    color: isCurrentTab
                                        ? Qt.rgba(appSettings.fontColor.r, appSettings.fontColor.g, appSettings.fontColor.b, 0.15)
                                        : "transparent"
                                    border.color: Qt.rgba(appSettings.fontColor.r, appSettings.fontColor.g, appSettings.fontColor.b,
                                                          isCurrentTab ? 1.0 : 0.35)
                                    border.width: 1

                                    layer.enabled: isCurrentTab
                                    layer.effect: Glow {
                                        radius: 6
                                        samples: 13
                                        color: appSettings.fontColor
                                        spread: 0.1
                                    }
                                }

                                Label {
                                    anchors.left: parent.left
                                    anchors.right: closeBtn.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: innerPadding
                                    anchors.rightMargin: 2
                                    text: model.title || "cool-retro-term"
                                    elide: Text.ElideRight
                                    color: Qt.rgba(appSettings.fontColor.r, appSettings.fontColor.g, appSettings.fontColor.b,
                                                   isCurrentTab ? 1.0 : 0.5)
                                    font.pixelSize: 11
                                    font.family: "monospace"
                                }

                                Text {
                                    id: closeBtn
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.rightMargin: innerPadding
                                    text: "\u00d7"
                                    color: Qt.rgba(appSettings.fontColor.r, appSettings.fontColor.g, appSettings.fontColor.b,
                                                   closeBtnArea.containsMouse ? 1.0 : (isCurrentTab ? 0.8 : 0.4))
                                    font.pixelSize: 13
                                    font.family: "monospace"

                                    MouseArea {
                                        id: closeBtnArea
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        onClicked: tabsRoot.closeTab(index)
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.rightMargin: closeBtn.width + innerPadding * 2
                                    onClicked: tabsRoot.currentIndex = index
                                }

                                DragHandler {
                                    id: dragHandler
                                    yAxis.enabled: false
                                    target: null

                                    property real startX: 0

                                    onActiveChanged: {
                                        if (active) {
                                            startX = index * tabWidth
                                            tabsRoot.currentIndex = index
                                            tabsContainer.draggingIndex = index
                                            tabsContainer.draggingX = startX
                                        } else if (tabsContainer.draggingIndex === index) {
                                            var targetIdx = Math.max(0, Math.min(tabsModel.count - 1,
                                                                     Math.round(tabsContainer.draggingX / tabWidth)))
                                            if (targetIdx !== index) {
                                                tabsModel.move(index, targetIdx, 1)
                                                tabsRoot.currentIndex = targetIdx
                                            }
                                            tabsContainer.draggingIndex = -1
                                        }
                                    }

                                    onCentroidChanged: {
                                        if (active && tabsContainer.draggingIndex === index) {
                                            var delta = centroid.position.x - centroid.pressPosition.x
                                            tabsContainer.draggingX = Math.max(0,
                                                Math.min((tabsModel.count - 1) * tabWidth, startX + delta))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: addTabBtn
                    width: tabBarHeight - 4
                    height: tabBarHeight - 4
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: 4
                    Layout.leftMargin: 4
                    color: "transparent"
                    border.color: Qt.rgba(appSettings.fontColor.r, appSettings.fontColor.g, appSettings.fontColor.b,
                                          addBtnArea.containsMouse ? 1.0 : 0.4)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: Qt.rgba(appSettings.fontColor.r, appSettings.fontColor.g, appSettings.fontColor.b,
                                       addBtnArea.containsMouse ? 1.0 : 0.5)
                        font.pixelSize: 14
                        font.family: "monospace"
                    }

                    MouseArea {
                        id: addBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: tabsRoot.addTab()
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: function(wheel) {
                    var delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
                    var maxX = Math.max(0, tabsFlickable.contentWidth - tabsFlickable.width)
                    tabsRoot.scrollTargetX = Math.max(0, Math.min(maxX, tabsRoot.scrollTargetX - delta))
                    tabsFlickable.contentX = tabsRoot.scrollTargetX
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // crtContent: contains shared tab bar + stack, captured as unified CRT source
            Item {
                id: crtContent
                anchors.fill: parent

                // Font metrics derived from focused terminal (all terminals share the same font)
                property var _ft: getTerminal(focusedPaneId)
                property size _charMetrics: _ft && _ft.mainTerminal ? _ft.mainTerminal.fontMetrics : Qt.size(8, 16)
                property font _termFont: _ft && _ft.mainTerminal ? _ft.mainTerminal.font : Qt.font({family: "monospace", pixelSize: 16})

                AsciiTabBar {
                    id: sharedTabBar
                    anchors.top: parent.top
                    anchors.left: parent.left
                    width: parent.width
                    visible: tabsRoot.count > 1
                    tabCount: tabsRoot.count
                    activeTabIndex: tabsRoot.currentIndex
                    tabTitles: tabsRoot.collectTitles()
                    fontColor: appSettings.fontColor
                    backgroundColor: appSettings.backgroundColor
                    height: visible ? crtContent._charMetrics.height * appSettings.tabBarScale : 0
                    charMetrics: Qt.size(crtContent._charMetrics.width * appSettings.tabBarScale, crtContent._charMetrics.height * appSettings.tabBarScale)
                    termFont: Qt.font({
                        family: crtContent._termFont.family,
                        pixelSize: (crtContent._termFont.pixelSize > 0 ? crtContent._termFont.pixelSize : 16) * appSettings.tabBarScale
                    })
                    z: 5

                    MouseArea {
                        anchors.fill: parent
                        visible: !needsUnifiedCRT
                        onClicked: function(mouse) {
                            var idx = sharedTabBar.hitTest(mouse.x)
                            if (idx >= 0) { tabsRoot.currentIndex = idx; return }
                            if (sharedTabBar.hitTestAddButton(mouse.x)) { tabsRoot.addTab() }
                        }
                    }
                }

                StackLayout {
                    id: stack
                    anchors.top: sharedTabBar.visible ? sharedTabBar.bottom : parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    currentIndex: tabsRoot.currentIndex

                    Repeater {
                        model: tabsModel
                        PaneTreeNode {
                            treeData: tabsRoot.splitTrees[index] || { type: "terminal", paneId: 0 }
                            splitManager: tabsRoot
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                        }
                    }
                }
            }

            // Unified source capture — hideSource:needsUnifiedCRT hides crtContent when
            // unified CRT is active (split or multi-tab) to avoid double-drawing.
            ShaderEffectSource {
                id: unifiedPaneSource
                sourceItem: crtContent
                hideSource: needsUnifiedCRT
                visible: false
                live: needsUnifiedCRT
                format: ShaderEffectSource.RGBA
                smooth: true
            }

            // Unified CRT overlay — enabled:false so input passes through to raw terminals
            ShaderTerminal {
                id: unifiedCRT
                anchors.fill: parent
                visible: needsUnifiedCRT
                enabled: false
                z: 2
                splitActive: false

                source: unifiedPaneSource
                burnInEffect: unifiedBurnIn
                bloomSource: unifiedBloomSourceLoader.item
                virtualResolution: Qt.size(stack.width, stack.height)
                screenResolution: Qt.size(
                    terminalWindow.width * Screen.devicePixelRatio * appSettings.windowScaling,
                    terminalWindow.height * Screen.devicePixelRatio * appSettings.windowScaling
                )
            }

            // Mouse-forwarding overlay — intercepts events when unified CRT is active
            // and routes them to the correct (now-invisible) terminal underneath.
            MouseArea {
                id: splitInputOverlay
                anchors.fill: parent
                visible: needsUnifiedCRT
                z: 3
                acceptedButtons: Qt.AllButtons
                hoverEnabled: true

                // Drag-to-resize state
                property var _resizingBoundary: null

                // Bounds cache — invalidated by tree identity change (split/close creates new objects)
                property var _cachedBoundsTree: undefined
                property var _cachedBounds: null
                property var _cachedBoundariesTree: undefined
                property var _cachedBoundaries: null

                function _getOrComputeBounds(tree) {
                    if (tree !== _cachedBoundsTree) {
                        _cachedBoundsTree = tree
                        _cachedBounds = computePaneBounds(tree, 0, 0, 1, 1)
                    }
                    return _cachedBounds
                }

                function _getOrComputeBoundaries(tree) {
                    if (tree !== _cachedBoundariesTree) {
                        _cachedBoundariesTree = tree
                        _cachedBoundaries = computeSplitBoundaries(tree, 0, 0, 1, 1)
                    }
                    return _cachedBoundaries
                }

                cursorShape: _resizingBoundary
                    ? (_resizingBoundary.orientation === Qt.Horizontal ? Qt.SplitHCursor : Qt.SplitVCursor)
                    : Qt.IBeamCursor

                // ── helpers ──────────────────────────────────────────────

                function _getBounds(paneId) {
                    var tree = splitTrees[currentIndex]
                    if (!tree) return null
                    var bounds = _getOrComputeBounds(tree)
                    for (var i = 0; i < bounds.length; i++) {
                        if (bounds[i].paneId === paneId) return bounds[i]
                    }
                    return null
                }

                // Y offset in overlay coords where the pane area starts (below shared tab bar)
                function _stackTop() {
                    return sharedTabBar.visible ? sharedTabBar.height : 0
                }

                function _getPaneAt(relX, relY) {
                    var top = _stackTop()
                    if (relY < top) return null
                    var tree = splitTrees[currentIndex]
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
                    var tree = splitTrees[currentIndex]
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
                    var t = getTerminal(b.paneId)
                    if (!t) return Qt.point(0, 0)
                    var m = t.mainTerminal.margin
                    return Qt.point(
                        (mx - paneX - m) / pw * t.mainTerminal.totalWidth,
                        (my - paneY - m) / ph * t.mainTerminal.totalHeight
                    )
                }

                // ── event handlers ───────────────────────────────────────

                onPressed: function(mouse) {
                    // 1. Shared tab bar hit test (top of content area, only in split mode)
                    if (sharedTabBar.visible && mouse.y < sharedTabBar.height) {
                        var tabIdx = sharedTabBar.hitTest(mouse.x)
                        if (tabIdx >= 0) { tabsRoot.currentIndex = tabIdx; return }
                        if (sharedTabBar.hitTestAddButton(mouse.x)) { tabsRoot.addTab(); return }
                        return
                    }

                    // 2. Resize boundary takes priority
                    var boundary = _hitTestBoundary(mouse.x, mouse.y)
                    if (boundary) {
                        _resizingBoundary = boundary
                        return
                    }

                    // 3. Find pane and forward
                    var b = _getPaneAt(mouse.x, mouse.y)
                    if (!b) return
                    focusedPaneId = b.paneId
                    var t = getTerminal(b.paneId)
                    if (!t) return
                    t.activate()
                    var k = _toKCoords(b, mouse.x, mouse.y)
                    t.mainTerminal.simulateMousePress(k.x, k.y, mouse.button, mouse.buttons, mouse.modifiers)
                }

                onReleased: function(mouse) {
                    if (_resizingBoundary) {
                        _resizingBoundary = null
                        return
                    }
                    var b = _getBounds(focusedPaneId)
                    var t = getTerminal(focusedPaneId)
                    if (!b || !t) return
                    var k = _toKCoords(b, mouse.x, mouse.y)
                    t.mainTerminal.simulateMouseRelease(k.x, k.y, mouse.button, mouse.buttons, mouse.modifiers)
                }

                onPositionChanged: function(mouse) {
                    if (_resizingBoundary) {
                        var bd = _resizingBoundary
                        var newRatio
                        if (bd.orientation === Qt.Horizontal)
                            newRatio = (mouse.x / width - bd.nodeX) / bd.nodeW
                        else
                            newRatio = (mouse.y / height - bd.nodeY) / bd.nodeH
                        newRatio = Math.max(0.1, Math.min(0.9, newRatio))
                        updateSplitRatio(bd.firstLeafPaneId, newRatio)
                        return
                    }
                    var b = _getBounds(focusedPaneId)
                    var t = getTerminal(focusedPaneId)
                    if (!b || !t) return
                    var k = _toKCoords(b, mouse.x, mouse.y)
                    t.mainTerminal.simulateMouseMove(k.x, k.y, mouse.button, mouse.buttons, mouse.modifiers)
                }

                onDoubleClicked: function(mouse) {
                    var b = _getPaneAt(mouse.x, mouse.y)
                    if (!b) return
                    var t = getTerminal(b.paneId)
                    if (!t) return
                    var k = _toKCoords(b, mouse.x, mouse.y)
                    t.mainTerminal.simulateMouseDoubleClick(k.x, k.y, mouse.button, mouse.buttons, mouse.modifiers)
                }

                onWheel: function(wheel) {
                    var b = _getPaneAt(wheel.x, wheel.y)
                    if (!b) return
                    var t = getTerminal(b.paneId)
                    if (!t) return
                    if (wheel.modifiers & Qt.ControlModifier) {
                        wheel.angleDelta.y > 0 ? zoomIn.trigger() : zoomOut.trigger()
                    } else {
                        var k = _toKCoords(b, wheel.x, wheel.y)
                        t.mainTerminal.simulateWheel(k.x, k.y, wheel.buttons, wheel.modifiers, wheel.angleDelta)
                    }
                }
            }

            // Unified burn-in effect (timer-driven since there is no single kterminal)
            BurnInEffect {
                id: unifiedBurnIn
                anchors.fill: parent
                textSource: unifiedPaneSource
                triggerTarget: unifiedBurnInTrigger
                active: appSettings.burnIn !== 0 && isSplitMode
            }
            Timer {
                id: unifiedBurnInTrigger
                interval: 16
                running: isSplitMode && appSettings.burnIn !== 0
                repeat: true
                signal imagePainted()
                onTriggered: imagePainted()
            }

            // Unified bloom
            Loader {
                id: unifiedBloomLoader
                active: isSplitMode && (appSettings.bloom > 0 || appSettings._frameShininess > 0)
                width: stack.width * appSettings.bloomQuality
                height: stack.height * appSettings.bloomQuality
                sourceComponent: FastBlur {
                    radius: Utils.lint(16, 64, appSettings.bloomQuality)
                    source: unifiedPaneSource
                    transparentBorder: true
                }
            }
            Loader {
                id: unifiedBloomSourceLoader
                active: isSplitMode && (appSettings.bloom > 0 || appSettings._frameShininess > 0)
                sourceComponent: ShaderEffectSource {
                    sourceItem: unifiedBloomLoader.item
                    wrapMode: ShaderEffectSource.Repeat
                    hideSource: true
                    smooth: true
                    visible: false
                }
            }
        }
    }

    // Curvature input correction for split mode (unified CRT applies curvature over the pane area)
    CurvatureInputFilter {
        targetItem: tabsRoot
        curvature: isSplitMode
            ? appSettings.screenCurvature * appSettings.screenCurvatureSize * terminalWindow.normalizedWindowScale
            : 0
    }
}
