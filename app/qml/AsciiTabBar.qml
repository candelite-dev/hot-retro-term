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

Item {
    id: root

    property int tabCount: 0
    property int activeTabIndex: 0
    property var tabTitles: []
    property color fontColor: "#33ff00"
    property color backgroundColor: "#000000"
    property size charMetrics: Qt.size(8, 16)
    property font termFont
    property real screenScaling: 1
    property int lineSpacing: 0
    property bool textAntialiasing: true

    // charMetrics and hit tests use displayed pixels. Text is laid out at the
    // terminal's native font size, then scaled just like the terminal item.
    readonly property real textBaseline: lineSpacing + Math.round(labelMetrics.ascent)

    FontMetrics {
        id: labelMetrics
        font: root.termFont
    }

    visible: tabCount > 1
    height: visible ? charMetrics.height : 0
    z: 10

    // Number of chars for the [+] button
    readonly property int addBtnChars: 5
    // Total chars available for all tabs
    readonly property int totalTabChars: Math.max(0, Math.floor(width / charMetrics.width) - addBtnChars)
    // Chars allocated per tab
    readonly property int charsPerTab: tabCount > 0 ? Math.max(5, Math.floor(totalTabChars / tabCount)) : 5
    // Pixel width per tab
    readonly property real tabPixelWidth: charsPerTab * charMetrics.width
    // Pixel width for add button
    readonly property real addBtnPixelWidth: addBtnChars * charMetrics.width

    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor
    }

    Row {
        id: tabsRow
        height: root.charMetrics.height / root.screenScaling
        transformOrigin: Item.TopLeft
        scale: root.screenScaling

        Repeater {
            model: root.tabCount

            Item {
                id: tabItem
                width: root.tabPixelWidth / root.screenScaling
                height: tabsRow.height
                clip: true

                readonly property bool isActive: index === root.activeTabIndex

                Rectangle {
                    anchors.fill: parent
                    color: root.fontColor
                    visible: tabItem.isActive
                }

                Text {
                    objectName: "tabLabel"
                    width: parent.width
                    y: root.textBaseline - baselineOffset
                    text: root.buildTabLabel(index)
                    textFormat: Text.PlainText
                    font: root.termFont
                    color: tabItem.isActive ? root.backgroundColor : root.fontColor
                    renderType: Text.NativeRendering
                    antialiasing: root.textAntialiasing
                    smooth: false
                }
            }
        }

        Text {
            id: addBtn
            objectName: "addTabLabel"
            width: root.addBtnPixelWidth / root.screenScaling
            y: root.textBaseline - baselineOffset
            text: " [+] "
            textFormat: Text.PlainText
            font: root.termFont
            color: root.fontColor
            renderType: Text.NativeRendering
            antialiasing: root.textAntialiasing
            smooth: false
        }
    }

    function buildTabLabel(i) {
        var title = (tabTitles && i < tabTitles.length) ? tabTitles[i] : ""
        if (!title || title === "") title = "cool-retro-term"

        var prefix = " " + (i + 1) + ":"
        var maxContent = Math.max(1, charsPerTab - prefix.length - 1)

        if (title.length > maxContent)
            title = title.substring(0, maxContent - 1) + "\u2026"

        var label = prefix + title
        // Pad with spaces to fill the full tab width
        while (label.length < charsPerTab)
            label += " "

        return label.substring(0, charsPerTab)
    }

    // Returns tab index (0-based) for a given x pixel coordinate, or -1
    function hitTest(x) {
        if (tabPixelWidth <= 0 || tabCount <= 0) return -1
        var idx = Math.floor(x / tabPixelWidth)
        if (idx >= 0 && idx < tabCount) return idx
        return -1
    }

    // Returns true if x is within the [+] add button area
    function hitTestAddButton(x) {
        var addBtnStart = tabCount * tabPixelWidth
        return x >= addBtnStart && x < addBtnStart + addBtnPixelWidth
    }
}
