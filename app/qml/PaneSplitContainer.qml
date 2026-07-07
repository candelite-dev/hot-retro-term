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
import QtQuick.Layouts

// Renders a split node from a PaneTreeNode.
// treeNode is the parent PaneTreeNode item.
Item {
    id: container
    anchors.fill: parent  // Fix A: Loader はロードされたアイテムをリサイズしないため明示指定

    // Set by PaneTreeNode's Loader.onLoaded
    property var treeNode: null

    readonly property var data_: treeNode ? treeNode.treeData : null
    readonly property var mgr:   treeNode ? treeNode.splitManager : null
    readonly property bool isHorizontal: data_ ? data_.orientation === Qt.Horizontal : true
    readonly property real ratio: data_ ? data_.ratio : 0.5

    // First child data with divider flag
    readonly property var firstData: {
        if (!data_ || !data_.first) return null
        var d = Object.assign({}, data_.first)
        if (isHorizontal) d._showDividerRight  = true
        else              d._showDividerBottom = true
        return d
    }
    readonly property var secondData: data_ ? data_.second : null

    function bindLoadedNode(loader, dataProvider) {
        if (!loader.item)
            return
        loader.item.x = 0
        loader.item.y = 0
        loader.item.width = Qt.binding(function() { return loader.width })
        loader.item.height = Qt.binding(function() { return loader.height })
        loader.item.treeData = Qt.binding(dataProvider)
        loader.item.splitManager = Qt.binding(function() { return container.mgr })
    }

    Loader {
        id: firstLoader
        x: 0
        y: 0
        width:  container.isHorizontal ? container.width * container.ratio : container.width
        height: container.isHorizontal ? container.height : container.height * container.ratio
        source: container.firstData ? "PaneTreeNode.qml" : ""
        onLoaded: container.bindLoadedNode(firstLoader, function() { return container.firstData })
    }

    Loader {
        id: secondLoader
        x: container.isHorizontal ? firstLoader.width : 0
        y: container.isHorizontal ? 0 : firstLoader.height
        width:  container.isHorizontal ? container.width - firstLoader.width : container.width
        height: container.isHorizontal ? container.height : container.height - firstLoader.height
        source: container.secondData ? "PaneTreeNode.qml" : ""
        onLoaded: container.bindLoadedNode(secondLoader, function() { return container.secondData })
    }

    // Invisible drag handle at the split boundary for resize
    MouseArea {
        id: resizeHandle
        z: 100
        x: isHorizontal ? parent.width * ratio - 4 : 0
        y: isHorizontal ? 0 : parent.height * ratio - 4
        width:  isHorizontal ? 8 : parent.width
        height: isHorizontal ? parent.height : 8
        cursorShape: isHorizontal ? Qt.SplitHCursor : Qt.SplitVCursor

        onPositionChanged: function(mouse) {
            if (!pressed || !mgr || !data_) return
            var mapped = mapToItem(container, mouse.x, mouse.y)
            var newRatio = isHorizontal
                ? mapped.x / container.width
                : mapped.y / container.height
            newRatio = Math.max(0.1, Math.min(0.9, newRatio))
            mgr.updateSplitRatio(mgr.findFirstTerminal(data_.first), newRatio)
        }
    }
}
