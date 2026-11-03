import QtQuick
import QtTest
import "../../app/qml" as App

TestCase {
    name: "InputRouter"
    visible: true
    width: 800
    height: 600
    when: windowShown

    Item {
        id: layout
        anchors.fill: parent
        Item {
            id: tabBar
            width: parent.width
            height: 60
            function hitTest(x) { return x < 300 ? 0 : -1 }
            function hitTestAddButton(x) { return x >= 300 && x < 400 }
        }
        Item {
            id: area
            x: 40; y: 100; width: 720; height: 460
            Item {
                id: terminal
                property alias mainTerminal: target
                function activate() {}
                Item {
                    id: target
                    // Deliberately different pixel coordinates from the overlay.
                    x: 10; y: 5; scale: 0.5
                    width: 1400; height: 900
                    transformOrigin: Item.TopLeft
                    property var lastPress: null
                    property var lastMove: null
                    property int releases: 0
                    function simulateMousePress(x, y, button, buttons, modifiers) { lastPress = Qt.point(x, y) }
                    function simulateMouseRelease(x, y, button, buttons, modifiers) { releases++ }
                    function simulateMouseMove(x, y, button, buttons, modifiers) { lastMove = Qt.point(x, y) }
                    function simulateMouseDoubleClick(x, y, button, buttons, modifiers) {}
                    function simulateWheel(x, y, buttons, modifiers, delta) {}
                }
            }
        }
        QtObject {
            id: model
            property int currentIndex: 0
            property int focusedPaneId: 0
            property var splitTrees: [{type: "terminal", paneId: 0}]
            property real ratio: -1
            function getTerminal(id) { return id === 0 ? terminal : null }
            function focusPane(id) { focusedPaneId = id }
            function updateSplitRatio(boundary, value) { ratio = value }
        }
        App.InputRouter {
            id: router
            anchors.fill: parent
            splitManager: model
            paneArea: area
            tabBarRef: tabBar
        }
    }
    SignalSpy { id: tabClicks; target: router; signalName: "tabClicked" }

    function init() {
        target.lastPress = null
        target.lastMove = null
        target.releases = 0
        tabClicks.clear()
        model.ratio = -1
        model.splitTrees = [{type: "terminal", paneId: 0}]
    }
    function test_marginsAreNotTerminalInput() {
        compare(router._getPaneAt(20, 120), null)
        compare(router._getPaneAt(60, 80), null)
        compare(router._getPaneAt(780, 120), null)
        compare(router._getPaneAt(60, 580), null)
        compare(router._getPaneAt(60, 120).paneId, 0)
    }
    function test_terminalCoordinatesRespectScaleAndPosition() {
        mouseClick(router, 150, 205)
        compare(target.lastPress, Qt.point(200, 200))
        compare(target.releases, 1)
    }
    function test_tabClickDoesNotReleaseTerminalMouse() {
        mouseClick(router, 100, 30)
        compare(tabClicks.count, 1)
        compare(target.lastPress, null)
        compare(target.releases, 0)
    }
    function test_verticalResizeUsesPaneArea() {
        model.splitTrees = [{type: "split", orientation: Qt.Vertical, ratio: 0.5,
                             first: {type: "terminal", paneId: 0}, second: {type: "terminal", paneId: 1}}]
        mousePress(router, 200, area.y + area.height / 2)
        mouseMove(router, 200, area.y + area.height * 0.75)
        fuzzyCompare(model.ratio, 0.75, 0.01)
        mouseRelease(router, 200, area.y + area.height * 0.75)
        compare(target.releases, 0)
    }
    function test_pointerCaptureSurvivesFocusChange() {
        mousePress(router, 150, 205)
        model.focusedPaneId = 9
        mouseRelease(router, 150, 205)
        compare(target.releases, 1)
    }
}
