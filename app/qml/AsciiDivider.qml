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

import QtQuick 2.2

Item {
    id: root

    // Qt.Horizontal means vertical divider line (|), Qt.Vertical means horizontal line (-)
    property int orientation: Qt.Horizontal
    property color fontColor: "#33ff00"
    property color backgroundColor: "#000000"
    property size charMetrics: Qt.size(8, 16)
    property font termFont

    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor
    }

    // Vertical divider: column of "|" characters
    Column {
        visible: root.orientation === Qt.Horizontal
        anchors.left: parent.left
        anchors.top: parent.top

        Repeater {
            model: root.charMetrics.height > 0 ? Math.ceil(root.height / root.charMetrics.height) : 0
            Text {
                text: "|"
                font: root.termFont
                color: root.fontColor
                width: root.charMetrics.width
                height: root.charMetrics.height
                smooth: false
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // Horizontal divider: row of "-" characters
    Text {
        visible: root.orientation === Qt.Vertical
        anchors.left: parent.left
        anchors.top: parent.top
        text: {
            var s = ""
            var count = root.charMetrics.width > 0 ? Math.ceil(root.width / root.charMetrics.width) : 0
            for (var i = 0; i < count; i++) s += "-"
            return s
        }
        font: root.termFont
        color: root.fontColor
        smooth: false
    }
}
