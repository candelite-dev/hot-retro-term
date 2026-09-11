import QtQuick 2.2

// Draws a box-drawing character border around the focused pane.
// Uses the terminal font so it blends naturally with terminal content.
Item {
    id: root

    property color fontColor: "#33ff00"
    property size charMetrics: Qt.size(8, 16)
    property font termFont

    readonly property int cw: charMetrics.width  > 0 ? charMetrics.width  : 8
    readonly property int ch: charMetrics.height > 0 ? charMetrics.height : 16

    // Top edge: ┌─────┐
    Row {
        anchors.top: parent.top
        anchors.left: parent.left
        spacing: 0
        Text { text: "\u250C"; font: root.termFont; color: root.fontColor; width: root.cw; height: root.ch; smooth: false }
        Repeater {
            model: root.cw > 0 ? Math.max(0, Math.floor((root.width - 2 * root.cw) / root.cw)) : 0
            Text { text: "\u2500"; font: root.termFont; color: root.fontColor; width: root.cw; height: root.ch; smooth: false }
        }
        Text { text: "\u2510"; font: root.termFont; color: root.fontColor; width: root.cw; height: root.ch; smooth: false }
    }

    // Bottom edge: └─────┘
    Row {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        spacing: 0
        Text { text: "\u2514"; font: root.termFont; color: root.fontColor; width: root.cw; height: root.ch; smooth: false }
        Repeater {
            model: root.cw > 0 ? Math.max(0, Math.floor((root.width - 2 * root.cw) / root.cw)) : 0
            Text { text: "\u2500"; font: root.termFont; color: root.fontColor; width: root.cw; height: root.ch; smooth: false }
        }
        Text { text: "\u2518"; font: root.termFont; color: root.fontColor; width: root.cw; height: root.ch; smooth: false }
    }

    // Left edge: column of │
    Column {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: root.ch
        spacing: 0
        Repeater {
            model: root.ch > 0 ? Math.max(0, Math.floor((root.height - 2 * root.ch) / root.ch)) : 0
            Text { text: "\u2502"; font: root.termFont; color: root.fontColor; width: root.cw; height: root.ch; smooth: false }
        }
    }

    // Right edge: column of │
    Column {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: root.ch
        spacing: 0
        Repeater {
            model: root.ch > 0 ? Math.max(0, Math.floor((root.height - 2 * root.ch) / root.ch)) : 0
            Text { text: "\u2502"; font: root.termFont; color: root.fontColor; width: root.cw; height: root.ch; smooth: false }
        }
    }
}
