import QtQuick
import QtTest
import "../../app/qml/SplitTree.js" as Tree

TestCase {
    name: "SplitTree"
    function leaf(id) { return { type: "terminal", paneId: id } }
    function split(first, second, orientation, ratio) {
        return { type: "split", first: first, second: second, orientation: orientation, ratio: ratio }
    }
    function test_nestedGeometryAndImmutableResize() {
        var tree = split(split(leaf(0), leaf(1), Qt.Horizontal, 0.5), leaf(2), Qt.Vertical, 0.6)
        var original = JSON.stringify(tree)
        var bounds = Tree.computePaneRects(tree, 0, 0, 1, 1)
        compare(bounds.length, 3)
        compare(bounds[0], {paneId: 0, x: 0, y: 0, w: 0.5, h: 0.6})
        fuzzyCompare(bounds[2].y, 0.6, 0.0001)
        var boundaries = Tree.computeSplitBoundaries(tree, 0, 0, 1, 1)
        var resized = Tree.updateRatio(tree, boundaries[1], 0.7, 0, 0, 1, 1)
        compare(resized.ratio, 0.6)
        compare(resized.first.ratio, 0.7)
        compare(JSON.stringify(tree), original)
    }
    function test_nestedRemovalKeepsOtherPaneIds() {
        var tree = split(leaf(0), split(leaf(1), leaf(2), Qt.Vertical, 0.5), Qt.Horizontal, 0.5)
        compare(Tree.collectTerminals(Tree.removeNode(tree, 1)), [0, 2])
        compare(Tree.collectTerminals(tree), [0, 1, 2])
        compare(Tree.removeNode(leaf(0), 0), null)
    }
}
