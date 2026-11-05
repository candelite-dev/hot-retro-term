import QtQuick
import QtTest
import "../../app/qml" as App
import "../../app/qml/SplitTree.js" as Tree

TestCase {
    name: "PaneRegressions"
    Item { id: pool }
    ListModel { id: tabs }
    Component {
        id: fakeTerminal
        Item {
            property int paneId: -1
            property string title: ""
            signal sessionFinished()
            signal paneClicked()
        }
    }
    App.TerminalSessionPool {
        id: sessions
        container: pool
        terminalComponent: fakeTerminal
    }
    SignalSpy { id: lastTab; target: model; signalName: "lastTabClosed" }
    App.SplitTreeModel {
        id: model
        tabsModel: tabs
        sessionPool: sessions
    }
    function init() {
        lastTab.clear()
        sessions.terminalComponent = fakeTerminal
        model.splitTrees = []
        tabs.clear()
        model.currentIndex = 0
        model.focusedPaneId = -1
        model.nextPaneId = 0
    }
    function cleanup() {
        sessions.clear()
        wait(0)
    }
    function test_closeEarlierTabPreservesActiveTerminal() {
        model.addTab(); model.addTab(); model.addTab()
        model.currentIndex = 1
        model.focusedPaneId = 1
        model.closeTab(0)
        compare(model.currentIndex, 0)
        compare(model.focusedPaneId, 1)
    }
    function test_closeBackgroundPaneUsesOwningTab() {
        model.addTab()
        model.splitPane(Qt.Horizontal)
        model.addTab()
        model.closePane(0)
        compare(tabs.count, 2)
        compare(Tree.collectTerminals(model.splitTrees[0]), [1])
        compare(Tree.collectTerminals(model.splitTrees[1]), [2])
        compare(model.focusedPaneId, 2)
    }
    function test_backgroundSessionFinished() {
        model.addTab(); model.addTab()
        model.getTerminal(0).sessionFinished()
        compare(tabs.count, 1)
        compare(Tree.collectTerminals(model.splitTrees[0]), [1])
    }
    function test_emptyTreeGeometry() {
        compare(Tree.computePaneRects(null, 0, 0, 1, 1), [])
    }

    function test_backgroundTitleUpdatesOwningTab() {
        model.addTab(); model.addTab()
        model.getTerminal(0).title = "background job"
        compare(tabs.get(0).title, "background job")
        compare(tabs.get(1).title, "")
    }
    function test_failedCreationDoesNotCreateTabOrPane() {
        sessions.terminalComponent = null
        model.addTab()
        compare(tabs.count, 0)
        compare(model.splitTrees.length, 0)
        sessions.terminalComponent = fakeTerminal
        model.addTab()
        sessions.terminalComponent = null
        model.splitPane(Qt.Horizontal)
        compare(Tree.countTerminals(model.splitTrees[0]), 1)
        compare(model.focusedPaneId, 0)
    }
    function test_invalidCloseIsNoOp() {
        model.addTab()
        model.closePane(99)
        model.closeTab(-1)
        model.closeTab(99)
        compare(tabs.count, 1)
        verify(model.getTerminal(0) !== null)
        compare(lastTab.count, 0)
    }
    function test_lastTabRequestsWindowCloseOnce() {
        model.addTab()
        model.getTerminal(0).sessionFinished()
        compare(tabs.count, 0)
        compare(lastTab.count, 1)
        compare(model.getTerminal(0), null)
        compare(model.focusedPaneId, -1)
        model.closeTab(0)
        compare(lastTab.count, 1)
    }
    function test_closeNonfocusedPanePreservesFocus() {
        model.addTab()
        model.splitPane(Qt.Horizontal)
        model.splitPane(Qt.Vertical)
        compare(model.focusedPaneId, 2)
        model.closePane(0)
        compare(model.focusedPaneId, 2)
        compare(Tree.collectTerminals(model.splitTrees[0]), [1, 2])
    }
    function test_paneLimitDoesNotCreateOrphans() {
        model.addTab()
        for (var i = 0; i < 20; ++i) model.splitPane(Qt.Horizontal)
        compare(Tree.countTerminals(model.splitTrees[0]), 16)
        compare(Object.keys(sessions._terminals).length, 16)
    }
}
