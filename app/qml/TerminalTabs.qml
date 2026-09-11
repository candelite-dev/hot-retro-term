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

Item {
    id: tabsRoot

    // ── Public API ────────────────────────────────────────────────────────────

    readonly property string currentTitle: {
        var idx = currentIndex
        if (idx === undefined || idx === null ||
            tabsModel.count === 0 || idx < 0 || idx >= tabsModel.count)
            return "cool-retro-term"
        var tab = tabsModel.get(idx)
        return tab && tab.title ? tab.title : "cool-retro-term"
    }
    property alias  currentIndex: splitModel.currentIndex
    property alias  focusedPaneId: splitModel.focusedPaneId
    readonly property int count: tabsModel.count
    property size terminalSize: Qt.size(0, 0)

    readonly property bool isSplitMode:     splitModel.isSplitMode
    readonly property bool needsUnifiedCRT: splitModel.needsUnifiedCRT

    property alias terminalPool: terminalPool

    // Delegate tab/pane operations to SplitTreeModel
    function addTab()               { splitModel.addTab() }
    function closeTab(index)        { splitModel.closeTab(index) }
    function splitPane(orientation) { splitModel.splitPane(orientation) }
    function closePane(paneId)      { splitModel.closePane(paneId) }
    function closeFocusedPane()     { splitModel.closePane(splitModel.focusedPaneId) }
    function moveFocus(direction)   { splitModel.moveFocus(direction) }

    // ── Internal state ────────────────────────────────────────────────────────

    readonly property int innerPadding: 6
    readonly property int tabWidth:     160
    readonly property int tabBarHeight: 28
    property real scrollTargetX: 0

    // ── Core objects ──────────────────────────────────────────────────────────

    Item { id: terminalPool; visible: false }

    ListModel { id: tabsModel }

    SplitTreeModel {
        id: splitModel
        tabsModel:    tabsModel
        terminalPool: terminalPool
    }

    onCurrentIndexChanged: {
        ensureTabVisible(currentIndex)
        splitModel.isCurrentTab = true
        if (splitModel.splitTrees[currentIndex])
            splitModel.focusedPaneId = splitModel.findFirstTerminal(splitModel.splitTrees[currentIndex])
    }

    Component.onCompleted: splitModel.addTab()

    function ensureTabVisible(idx) {
        var x = idx * tabWidth
        if (x < scrollTargetX) {
            scrollTargetX = x
        } else if (x + tabWidth > scrollTargetX + tabsFlickable.width) {
            scrollTargetX = x + tabWidth - tabsFlickable.width
        }
        tabsFlickable.contentX = scrollTargetX
    }

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

        // ── Legacy tab row (currently unused — height:0 / visible:false) ─────
        // AsciiTabBar inside PaneLayout is the active tab bar implementation.
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

                        property int  draggingIndex: -1
                        property real draggingX: 0

                        Repeater {
                            model: tabsModel

                            Item {
                                id: tabDelegate
                                width: tabWidth
                                height: tabBarHeight

                                property bool isCurrentTab: index === tabsRoot.currentIndex
                                property bool isDragging:   tabsContainer.draggingIndex === index

                                property real baseX: {
                                    if (tabsContainer.draggingIndex < 0 || index === tabsContainer.draggingIndex)
                                        return index * tabWidth
                                    var di = tabsContainer.draggingIndex
                                    var targetIdx = Math.max(0, Math.min(tabsModel.count - 1,
                                                             Math.round(tabsContainer.draggingX / tabWidth)))
                                    if (di < targetIdx && index > di && index <= targetIdx)
                                        return (index - 1) * tabWidth
                                    if (di > targetIdx && index >= targetIdx && index < di)
                                        return (index + 1) * tabWidth
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
                                        radius: 6; samples: 13
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
                                    text: "×"
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
        // ── End legacy tab row ────────────────────────────────────────────────

        // ── Content area ──────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            PaneLayout {
                id: paneLayout
                anchors.fill: parent
                splitManager: splitModel
                onTabClicked:   function(idx) { tabsRoot.currentIndex = idx }
                onAddTabClicked: tabsRoot.addTab()
            }

            InputRouter {
                id: inputRouter
                anchors.fill: parent
                splitManager: splitModel
                tabBarRef:    paneLayout.sharedTabBar
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
        curvature: isSplitMode
            ? appSettings.screenCurvature * appSettings.screenCurvatureSize * terminalWindow.normalizedWindowScale
            : 0
    }
}
