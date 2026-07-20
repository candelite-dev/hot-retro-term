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

Item {
    id: node

    property var treeData          // JS object { type, paneId } or { type, orientation, ratio, first, second }
    property var splitManager      // reference to TerminalTabs

    readonly property bool isSplit: treeData && treeData.type === "split"

    // Top-level handlers ensure _claim() runs when properties arrive from a parent Loader's onLoaded.
    // Qt 6 では underscore-prefixed プロパティのハンドラ命名（on_SplitMgrChanged 等）が
    // 正しく発火しない場合があるため、標準名プロパティのハンドラで確実にカバーする。
    onSplitManagerChanged: Qt.callLater(function() {
        if (!isSplit) terminalSlot._attemptClaim()
    })
    onTreeDataChanged: Qt.callLater(function() {
        if (!isSplit) terminalSlot._attemptClaim()
    })

    // Terminal leaf — claims terminal from pool by paneId
    Item {
        id: terminalSlot
        anchors.fill: parent
        visible: !node.isSplit

        property int _paneId: (!node.isSplit && node.treeData) ? node.treeData.paneId : -1
        property var _claimedTerminal: null
        property bool _claimPending: false

        onWidthChanged: if (_claimPending) _attemptClaim()
        onHeightChanged: if (_claimPending) _attemptClaim()

        onVisibleChanged: {
            if (visible) _attemptClaim()
            else _release()
        }

        on_PaneIdChanged: _attemptClaim()

        Component.onCompleted: _attemptClaim()

        Component.onDestruction: _release()

        function _attemptClaim() {
            if (_claimedTerminal) return
            if (!visible) { console.log("PaneTreeNode._attemptClaim: skip !visible paneId=" + _paneId); return }
            if (_paneId < 0) { console.log("PaneTreeNode._attemptClaim: skip paneId<0"); return }
            if (!node.splitManager) { console.log("PaneTreeNode._attemptClaim: skip !splitManager paneId=" + _paneId); return }
            if (terminalSlot.width <= 0 || terminalSlot.height <= 0) {
                _claimPending = true
                return
            }
            _claim()
        }

        function _claim() {
            if (_paneId < 0 || !node.splitManager) return
            var t = node.splitManager.getTerminal(_paneId)
            if (!t) { console.warn("PaneTreeNode: getTerminal returned null for paneId", _paneId); return }
            console.log("PaneTreeNode._claim(): paneId=" + _paneId,
                        "slotSize=" + terminalSlot.width + "x" + terminalSlot.height)
            _claimPending = false
            _claimedTerminal = t
            t.parent = terminalSlot
            t.x = 0
            t.y = 0
            t.width = Qt.binding(function() { return terminalSlot.width })
            t.height = Qt.binding(function() { return terminalSlot.height })
            t.visible = true
            _setupBindings(t)
            Qt.callLater(function() {
                if (!_claimedTerminal) return
                _claimedTerminal.refresh()
                if (node.splitManager.isCurrentTab &&
                    node.treeData &&
                    node.treeData.paneId === node.splitManager.focusedPaneId) {
                    _claimedTerminal.activate()
                }
            })
        }

        function _release() {
            if (!_claimedTerminal) return
            var t = _claimedTerminal
            _claimedTerminal = null
            _claimPending = false
            // 他の slot が既に claim していた場合はプールに戻さない
            if (t.parent !== terminalSlot) return
            t.visible = false
            t.parent = node.splitManager.terminalPool
        }

        function _setupBindings(t) {
            t.isActive = Qt.binding(function() {
                return node.splitManager !== null &&
                       node.splitManager.isCurrentTab &&
                       node.treeData !== null &&
                       node.treeData.paneId === node.splitManager.focusedPaneId
            })
            t.splitActive = Qt.binding(function() {
                return node.splitManager ? node.splitManager.needsUnifiedCRT : false
            })
            t.isSplitLayout = Qt.binding(function() {
                return node.splitManager ? node.splitManager.isSplitMode : false
            })
            if (node.splitManager)
                node.splitManager.refreshTerminalRenderMode()
            t.showDividerRight = Qt.binding(function() {
                return node.treeData ? (node.treeData._showDividerRight || false) : false
            })
            t.showDividerBottom = Qt.binding(function() {
                return node.treeData ? (node.treeData._showDividerBottom || false) : false
            })
        }

        // Signal connections via dynamic target
        Connections {
            target: terminalSlot._claimedTerminal
            function onSessionFinished() {
                if (node.splitManager && node.treeData)
                    node.splitManager.closePane(node.treeData.paneId)
            }
            function onPaneClicked() {
                if (node.splitManager && node.treeData)
                    node.splitManager.focusedPaneId = node.treeData.paneId
            }
            function onTitleChanged() {
                var t = terminalSlot._claimedTerminal
                if (!t || !node.splitManager) return
                node.splitManager.tabsModel.setProperty(
                    node.splitManager.currentIndex, "title",
                    node.splitManager.normalizeTitle(t.title))
                node.splitManager.titleRevision++
            }
        }

        // Use property change handlers instead of Connections to avoid Qt 6
        // var-target signal resolution issues
        property var _splitMgr: node.splitManager
        on_SplitMgrChanged: _attemptClaim()

        property int _focusedPaneId: node.splitManager ? node.splitManager.focusedPaneId : -1
        on_FocusedPaneIdChanged: {
            if (_claimedTerminal && node.treeData &&
                node.treeData.paneId === _focusedPaneId)
                _claimedTerminal.activate()
        }
    }

    // Split container — loaded lazily via source to avoid recursive type instantiation at parse time
    Loader {
        id: splitLoader
        anchors.fill: parent
        active: node.isSplit
        source: node.isSplit ? "PaneSplitContainer.qml" : ""
        onLoaded: {
            item.treeNode = node
        }
    }

    Shortcut {
        sequence: appSettings.isMacOS ? "Meta+Shift+D" : "Ctrl+Shift+F12"
        onActivated: splitModel.dumpSplitDebug()
    }
}
