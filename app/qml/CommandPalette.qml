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

    property color fontColor: "#33ff00"
    property color backgroundColor: "#000000"
    property size charMetrics: Qt.size(8, 16)
    property font termFont

    property bool isOpen: false
    property string filterText: ""
    property int selectedIndex: 0
    property var allCommands: []
    property var filteredCommands: []
    property int scrollOffset: 0
    property bool blinkCursor: true

    readonly property int maxVisible: 10
    readonly property int paletteWidthChars: 56
    readonly property int visibleCount: filteredCommands ? Math.min(filteredCommands.length, maxVisible) : 0
    readonly property real totalHeight: (4 + visibleCount) * charMetrics.height

    signal commandTriggered(string actionId)
    signal profileRequested(int index)
    signal toggleRequested(string prop)
    signal closed()

    visible: isOpen
    width: paletteWidthChars * charMetrics.width
    height: totalHeight
    z: 20

    // -- Public API --

    function open() {
        allCommands = buildCommandList()
        searchInput.text = ""
        filterText = ""
        selectedIndex = 0
        scrollOffset = 0
        updateFilter()
        isOpen = true
        searchInput.forceActiveFocus()
    }

    function close() {
        isOpen = false
        filterText = ""
        root.closed()
    }

    function toggle() {
        if (isOpen) close()
        else open()
    }

    // -- Internal --

    function updateFilter() {
        var q = filterText.toLowerCase()
        var result = []
        for (var i = 0; i < allCommands.length; i++) {
            if (q === "" || allCommands[i].name.toLowerCase().indexOf(q) >= 0) {
                result.push(allCommands[i])
            }
        }
        filteredCommands = result
        if (result.length > 0 && selectedIndex >= result.length)
            selectedIndex = result.length - 1
        adjustScroll()
    }

    function adjustScroll() {
        if (scrollOffset < 0) scrollOffset = 0
        if (selectedIndex < scrollOffset) scrollOffset = selectedIndex
        if (selectedIndex >= scrollOffset + maxVisible)
            scrollOffset = selectedIndex - maxVisible + 1
        if (scrollOffset < 0) scrollOffset = 0
    }

    function moveSelection(delta) {
        if (!filteredCommands || filteredCommands.length === 0) return
        var newIdx = selectedIndex + delta
        if (newIdx < 0) newIdx = 0
        if (newIdx >= filteredCommands.length) newIdx = filteredCommands.length - 1
        selectedIndex = newIdx
        adjustScroll()
    }

    function executeSelected() {
        if (!filteredCommands || selectedIndex < 0 || selectedIndex >= filteredCommands.length) return
        var cmd = filteredCommands[selectedIndex]
        if (cmd.actionId !== undefined) {
            root.commandTriggered(cmd.actionId)
        } else if (cmd.profileIndex !== undefined) {
            root.profileRequested(cmd.profileIndex)
        } else if (cmd.toggleProp !== undefined) {
            root.toggleRequested(cmd.toggleProp)
        }
        close()
    }

    function buildCommandList() {
        var cmds = []
        cmds.push({name: "New Tab",    shortcut: "Ctrl+Shift+T", actionId: "newTab"})
        cmds.push({name: "Close Tab",  shortcut: "Ctrl+Shift+W", actionId: "closeTab"})
        cmds.push({name: "New Window", shortcut: "Ctrl+Shift+N", actionId: "newWindow"})
        cmds.push({name: "Split Right", shortcut: "Ctrl+Shift+D", actionId: "splitRight"})
        cmds.push({name: "Split Down",  shortcut: "Ctrl+Shift+H", actionId: "splitDown"})
        cmds.push({name: "Copy",       shortcut: "Ctrl+Shift+C", actionId: "copy"})
        cmds.push({name: "Paste",      shortcut: "Ctrl+Shift+V", actionId: "paste"})
        cmds.push({name: "Fullscreen", shortcut: "F11",          actionId: "fullscreen"})
        cmds.push({name: "Settings",   shortcut: "",             actionId: "settings"})
        cmds.push({name: "Zoom In",    shortcut: "Ctrl++",       actionId: "zoomIn"})
        cmds.push({name: "Zoom Out",   shortcut: "Ctrl+-",       actionId: "zoomOut"})
        cmds.push({name: "Quit",       shortcut: "Ctrl+Shift+Q", actionId: "quit"})

        for (var i = 0; i < appSettings.profilesList.count; i++) {
            var p = appSettings.profilesList.get(i)
            cmds.push({name: "Profile: " + p.text, shortcut: "", profileIndex: i})
        }

        var toggles = [
            {prop: "bloom",           label: "Bloom"},
            {prop: "burnIn",          label: "Burn-in"},
            {prop: "staticNoise",     label: "Static Noise"},
            {prop: "jitter",          label: "Jitter"},
            {prop: "glowingLine",     label: "Glow Line"},
            {prop: "screenCurvature", label: "Screen Curvature"},
            {prop: "flickering",      label: "Flickering"},
            {prop: "horizontalSync",  label: "Horizontal Sync"},
            {prop: "rgbShift",        label: "RGB Shift"},
            {prop: "chromaColor",     label: "Chroma Color"},
            {prop: "ambientLight",    label: "Ambient Light"}
        ]
        for (var j = 0; j < toggles.length; j++) {
            cmds.push({name: "Toggle: " + toggles[j].label, shortcut: "", toggleProp: toggles[j].prop})
        }
        return cmds
    }

    function padRight(s, len) {
        while (s.length < len) s += " "
        return s.substring(0, len)
    }

    function buildHeaderLine() {
        var title = "-- Command Palette "
        var inner = paletteWidthChars - 2
        var line = "+" + title
        var remaining = inner - title.length
        for (var i = 0; i < remaining; i++) line += "-"
        return line + "+"
    }

    function buildDividerLine() {
        var inner = paletteWidthChars - 2
        var line = "+"
        for (var i = 0; i < inner; i++) line += "-"
        return line + "+"
    }

    function buildFilterLine() {
        var inner = paletteWidthChars - 2
        var cursor = blinkCursor ? "_" : " "
        var content = " > " + filterText + cursor
        return "|" + padRight(content, inner) + "|"
    }

    function buildItemLine(cmdIndex) {
        if (!filteredCommands || cmdIndex < 0 || cmdIndex >= filteredCommands.length)
            return buildEmptyLine()
        var cmd = filteredCommands[cmdIndex]
        var inner = paletteWidthChars - 2
        var shortcut = cmd.shortcut || ""
        if (cmd.toggleProp !== undefined) {
            shortcut = appSettings[cmd.toggleProp] > 0 ? "[ON ]" : "[OFF]"
        }
        var prefix = "  "
        var suffix = shortcut.length > 0 ? "  " + shortcut : ""
        var nameLen = inner - prefix.length - suffix.length
        return "|" + prefix + padRight(cmd.name, nameLen) + suffix + "|"
    }

    function buildEmptyLine() {
        var inner = paletteWidthChars - 2
        var line = "|"
        for (var i = 0; i < inner; i++) line += " "
        return line + "|"
    }

    Timer {
        running: root.isOpen
        repeat: true
        interval: 530
        onTriggered: root.blinkCursor = !root.blinkCursor
    }

    // Invisible input capture — opacity:0 keeps events active (unlike visible:false)
    TextInput {
        id: searchInput
        x: 0; y: 0; width: 1; height: 1
        opacity: 0
        color: "transparent"
        cursorVisible: false
        Keys.onUpPressed:     { root.moveSelection(-1); event.accepted = true }
        Keys.onDownPressed:   { root.moveSelection(1);  event.accepted = true }
        Keys.onReturnPressed: { root.executeSelected(); event.accepted = true }
        Keys.onEscapePressed: { root.close();           event.accepted = true }
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Tab) event.accepted = true
        }
        onTextChanged: {
            root.filterText = text
            root.updateFilter()
        }
    }

    Column {
        width: root.width
        spacing: 0

        // Header row
        Item {
            width: root.width
            height: root.charMetrics.height
            Rectangle { anchors.fill: parent; color: root.backgroundColor }
            Text {
                anchors.fill: parent
                text: root.buildHeaderLine()
                font: root.termFont
                color: root.fontColor
                smooth: false
            }
        }

        // Filter input row
        Item {
            width: root.width
            height: root.charMetrics.height
            Rectangle { anchors.fill: parent; color: root.backgroundColor }
            Text {
                anchors.fill: parent
                text: {
                    root.filterText
                    root.blinkCursor
                    return root.buildFilterLine()
                }
                font: root.termFont
                color: root.fontColor
                smooth: false
            }
        }

        // Divider row
        Item {
            width: root.width
            height: root.charMetrics.height
            Rectangle { anchors.fill: parent; color: root.backgroundColor }
            Text {
                anchors.fill: parent
                text: root.buildDividerLine()
                font: root.termFont
                color: root.fontColor
                smooth: false
            }
        }

        // Command list rows
        Repeater {
            model: root.visibleCount
            delegate: Item {
                width: root.width
                height: root.charMetrics.height
                property int cmdIndex: root.scrollOffset + index
                property bool isSelected: cmdIndex === root.selectedIndex

                Rectangle {
                    anchors.fill: parent
                    color: isSelected ? root.fontColor : root.backgroundColor
                }
                Text {
                    anchors.fill: parent
                    text: {
                        root.filteredCommands
                        root.scrollOffset
                        return root.buildItemLine(root.scrollOffset + index)
                    }
                    font: root.termFont
                    color: isSelected ? root.backgroundColor : root.fontColor
                    smooth: false
                }
            }
        }

        // Footer divider row
        Item {
            width: root.width
            height: root.charMetrics.height
            Rectangle { anchors.fill: parent; color: root.backgroundColor }
            Text {
                anchors.fill: parent
                text: root.buildDividerLine()
                font: root.termFont
                color: root.fontColor
                smooth: false
            }
        }
    }
}
