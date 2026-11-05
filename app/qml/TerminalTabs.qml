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
import CoolRetroTerm 1.0

Item {
    id: tabsRoot

    // ── Public API ────────────────────────────────────────────────────────────

    readonly property string currentTitle: {
        var idx = currentIndex
        if (idx === undefined || idx === null ||
            tabData.count === 0 || idx < 0 || idx >= tabData.count)
            return "cool-retro-term"
        var tab = tabData.get(idx)
        return tab && tab.title ? tab.title : "cool-retro-term"
    }
    property alias  currentIndex: splitModel.currentIndex
    property alias  focusedPaneId: splitModel.focusedPaneId
    readonly property int count: tabData.count
    readonly property var focusedTerminal: splitModel.getTerminal(focusedPaneId)
    readonly property size terminalSize: focusedTerminal ? focusedTerminal.terminalSize : Qt.size(0, 0)

    readonly property bool isSplitMode:     splitModel.isSplitMode
    readonly property bool needsUnifiedCRT: splitModel.needsUnifiedCRT

    property alias terminalPool: terminalStash

    // Delegate tab/pane operations to SplitTreeModel
    function addTab()               { splitModel.addTab() }
    function closeTab(index)        { splitModel.closeTab(index) }
    function splitPane(orientation) { splitModel.splitPane(orientation) }
    function closePane(paneId)      { splitModel.closePane(paneId) }
    function closeFocusedPane()     { splitModel.closePane(splitModel.focusedPaneId) }
    function moveFocus(direction)   { splitModel.moveFocus(direction) }

    Item { id: terminalStash; visible: false }
    ListModel { id: tabData }

    TerminalSessionPool {
        id: sessions
        container: terminalStash
        terminalComponent: Component { TerminalContainer {} }
    }

    SplitTreeModel {
        id: splitModel
        tabsModel: tabData
        sessionPool: sessions
        onLastTabClosed: terminalWindow.close()
    }

    Component.onCompleted: splitModel.addTab()

    // ── Window curvature (outer) ──────────────────────────────────────────────

    CurvatureInputFilter {
        targetItem: contentColumn
        curvature: appSettings.windowCurvature > 0
            ? appSettings.windowCurvature * appSettings.screenCurvatureSize
              * (1024 / (0.5 * contentColumn.width + 0.5 * contentColumn.height))
            : 0
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: 0

        layer.enabled: appSettings.windowCurvature > 0
        layer.effect: ShaderEffect {
            property real screenCurvature: appSettings.windowCurvature * appSettings.screenCurvatureSize
                * (1024 / (0.5 * width + 0.5 * height))
            vertexShader:   "qrc:/shaders/window_curvature.vert.qsb"
            fragmentShader: "qrc:/shaders/window_curvature.frag.qsb"
        }

        // ── Content area ──────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            PaneLayout {
                id: paneLayout
                anchors.fill: parent
                splitManager: splitModel
                terminalPool: tabsRoot.terminalPool
                onTabClicked:   function(idx) { tabsRoot.currentIndex = idx }
                onAddTabClicked: tabsRoot.addTab()
            }

            InputRouter {
                id: inputRouter
                anchors.fill: parent
                splitManager: splitModel
                tabBarRef:    paneLayout.sharedTabBar
                paneArea:     paneLayout.paneArea
                visible: splitModel.needsUnifiedCRT
                z: 3
                onZoomRequested: function(delta) { delta > 0 ? zoomIn.trigger() : zoomOut.trigger() }
                onTabClicked:    function(idx) { tabsRoot.currentIndex = idx }
                onAddTabClicked: tabsRoot.addTab()
            }
        }
    }

    // ── Screen curvature input correction for split mode ──────────────────────
    CurvatureInputFilter {
        targetItem: tabsRoot
        curvature: needsUnifiedCRT
            ? appSettings.screenCurvature * appSettings.screenCurvatureSize * terminalWindow.normalizedWindowScale
            : 0
    }
}
