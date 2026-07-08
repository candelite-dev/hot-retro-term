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
import Qt5Compat.GraphicalEffects

import "utils.js" as Utils

// Visual composition layer: shared tab bar + pane stack + unified CRT pipeline.
// splitManager (SplitTreeModel) drives all content.
Item {
    id: paneLayout

    property var splitManager: null  // SplitTreeModel

    signal tabClicked(int index)
    signal addTabClicked()

    // Exposed for InputRouter so it can measure the tab bar and call hitTest()
    property alias sharedTabBar: sharedTabBar
    // Exposed for any parent that needs direct access to the unified source FBO
    property alias paneSource: unifiedPaneSource

    // ── Font metrics from focused terminal ────────────────────────────────────

    property var  _ft: splitManager ? splitManager.getTerminal(splitManager.focusedPaneId) : null
    property size _charMetrics: _ft && _ft.mainTerminal ? _ft.mainTerminal.fontMetrics : Qt.size(8, 16)
    property font _termFont:    _ft && _ft.mainTerminal ? _ft.mainTerminal.font
                                                        : Qt.font({family: "monospace", pixelSize: 16})
    property var _currentTree: splitManager ? splitManager.splitTrees[splitManager.currentIndex] : null
    property var _paneRects: (splitManager && _currentTree)
                             ? splitManager.computePaneRects(_currentTree, 0, 0, 1, 1)
                             : []
    property var _splitBoundaries: (splitManager && _currentTree)
                                   ? splitManager.computeSplitBoundaries(_currentTree, 0, 0, 1, 1)
                                   : []

    // ── crtContent: captured as unified CRT source ────────────────────────────

    Item {
        id: crtContent
        anchors.fill: parent

        AsciiTabBar {
            id: sharedTabBar
            anchors.top: parent.top
            anchors.left: parent.left
            width: parent.width
            visible: splitManager ? splitManager.tabsModel.count > 1 : false
            tabCount: splitManager ? splitManager.tabsModel.count : 0
            activeTabIndex: splitManager ? splitManager.currentIndex : 0
            tabTitles: splitManager ? splitManager.collectTitles() : []
            fontColor: appSettings.fontColor
            backgroundColor: appSettings.backgroundColor
            height: visible ? paneLayout._charMetrics.height * appSettings.tabBarScale : 0
            charMetrics: Qt.size(
                paneLayout._charMetrics.width  * appSettings.tabBarScale,
                paneLayout._charMetrics.height * appSettings.tabBarScale
            )
            termFont: Qt.font({
                family: paneLayout._termFont.family,
                pixelSize: (paneLayout._termFont.pixelSize > 0
                            ? paneLayout._termFont.pixelSize : 16) * appSettings.tabBarScale
            })
            z: 5

            // Non-unified-CRT path: tab bar handles its own clicks
            MouseArea {
                anchors.fill: parent
                visible: !(splitManager ? splitManager.needsUnifiedCRT : false)
                onClicked: function(mouse) {
                    var idx = sharedTabBar.hitTest(mouse.x)
                    if (idx >= 0) { paneLayout.tabClicked(idx); return }
                    if (sharedTabBar.hitTestAddButton(mouse.x)) paneLayout.addTabClicked()
                }
            }
        }

        Item {
            id: paneStack
            anchors.top: sharedTabBar.visible ? sharedTabBar.bottom : parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: (splitManager && splitManager.needsUnifiedCRT) ? appSettings.margin : 0

            Repeater {
                model: paneLayout._paneRects

                Item {
                    id: paneSlot

                    property var rectData: modelData

                    x: Math.round(rectData.x * paneStack.width)
                    y: Math.round(rectData.y * paneStack.height)
                    width: Math.round(rectData.w * paneStack.width)
                    height: Math.round(rectData.h * paneStack.height)

                    PaneTreeNode {
                        anchors.fill: parent
                        treeData: ({
                            type: "terminal",
                            paneId: paneSlot.rectData.paneId,
                            _showDividerRight: false,
                            _showDividerBottom: false
                        })
                        splitManager: paneLayout.splitManager
                    }
                }
            }

            Repeater {
                model: paneLayout._splitBoundaries

                AsciiDivider {
                    property var boundary: modelData

                    orientation: boundary.orientation
                    x: boundary.orientation === Qt.Horizontal
                       ? Math.round(boundary.pos * paneStack.width)
                       : Math.round(boundary.start * paneStack.width)
                    y: boundary.orientation === Qt.Horizontal
                       ? Math.round(boundary.start * paneStack.height)
                       : Math.round(boundary.pos * paneStack.height)
                    width: boundary.orientation === Qt.Horizontal
                           ? paneLayout._charMetrics.width
                           : Math.round((boundary.end - boundary.start) * paneStack.width)
                    height: boundary.orientation === Qt.Horizontal
                            ? Math.round((boundary.end - boundary.start) * paneStack.height)
                            : paneLayout._charMetrics.height
                    fontColor: appSettings.fontColor
                    backgroundColor: appSettings.backgroundColor
                    charMetrics: paneLayout._charMetrics
                    termFont: paneLayout._termFont
                    z: 20
                }
            }
        }
    }

    // ── Unified CRT source ────────────────────────────────────────────────────

    ShaderEffectSource {
        id: unifiedPaneSource
        sourceItem: crtContent
        hideSource: splitManager ? splitManager.needsUnifiedCRT : false
        visible: false
        live: splitManager ? splitManager.needsUnifiedCRT : false
        format: ShaderEffectSource.RGBA
        smooth: true
    }

    // ── Unified CRT overlay (enabled:false so input falls through to terminals)

    ShaderTerminal {
        id: unifiedCRT
        anchors.fill: parent
        visible: splitManager ? splitManager.needsUnifiedCRT : false
        enabled: false
        z: 2
        splitActive: false

        source: unifiedPaneSource
        burnInEffect: unifiedBurnIn
        bloomSource: unifiedBloomSourceLoader.item
        virtualResolution: Qt.size(paneStack.width, paneStack.height)
        screenResolution: Qt.size(
            terminalWindow.width  * Screen.devicePixelRatio * appSettings.windowScaling,
            terminalWindow.height * Screen.devicePixelRatio * appSettings.windowScaling
        )
    }

    // ── Unified burn-in (event-driven — aggregates every pane's imagePainted
    //    so decay runs at content rate, same semantics as the single-pane path) ─

    BurnInEffect {
        id: unifiedBurnIn
        anchors.fill: parent
        textSource: unifiedPaneSource
        triggerTarget: unifiedBurnInTrigger
        active: appSettings.burnIn !== 0 && (splitManager ? splitManager.needsUnifiedCRT : false)
    }

    Item {
        id: unifiedBurnInTrigger
        signal imagePainted()
    }

    Instantiator {
        model: (splitManager && splitManager.needsUnifiedCRT && appSettings.burnIn !== 0)
               ? paneLayout._paneRects : []
        delegate: Connections {
            target: {
                var t = paneLayout.splitManager.getTerminal(modelData.paneId)
                return (t && t.mainTerminal) ? t.mainTerminal : null
            }
            function onImagePainted() { unifiedBurnInTrigger.imagePainted() }
        }
    }

    // ── Unified bloom ─────────────────────────────────────────────────────────

    Loader {
        id: unifiedBloomLoader
        active: (splitManager ? splitManager.needsUnifiedCRT : false) &&
                (appSettings.bloom > 0 || appSettings._frameShininess > 0)
        width:  paneStack.width  * appSettings.bloomQuality
        height: paneStack.height * appSettings.bloomQuality
        sourceComponent: FastBlur {
            radius: Utils.lint(16, 64, appSettings.bloomQuality)
            source: unifiedPaneSource
            transparentBorder: true
        }
    }

    Loader {
        id: unifiedBloomSourceLoader
        active: (splitManager ? splitManager.needsUnifiedCRT : false) &&
                (appSettings.bloom > 0 || appSettings._frameShininess > 0)
        sourceComponent: ShaderEffectSource {
            sourceItem: unifiedBloomLoader.item
            wrapMode: ShaderEffectSource.Repeat
            hideSource: true
            smooth: true
            visible: false
        }
    }
}
