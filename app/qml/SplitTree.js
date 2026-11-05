.pragma library

// Immutable tree operations and normalized pane geometry. No UI or session ownership.
function updateRatio(node, boundary, newRatio, x, y, w, h) {
    if (!node || node.type === "terminal") return node
    // Identify the target split node by its bounding rect + orientation.
    // paneId alone is ambiguous when nested splits share the same first leaf.
    var eps = 1e-6
    var matches = node.orientation === boundary.orientation
               && Math.abs(x - boundary.nodeX) < eps
               && Math.abs(y - boundary.nodeY) < eps
               && Math.abs(w - boundary.nodeW) < eps
               && Math.abs(h - boundary.nodeH) < eps
    if (matches)
        return { type: "split", orientation: node.orientation,
                 ratio: newRatio, first: node.first, second: node.second }
    var r = node.ratio
    if (node.orientation === Qt.Horizontal)
        return { type: "split", orientation: node.orientation, ratio: r,
                 first:  updateRatio(node.first,  boundary, newRatio, x,       y, w * r,     h),
                 second: updateRatio(node.second, boundary, newRatio, x + w*r, y, w * (1-r), h) }
    return { type: "split", orientation: node.orientation, ratio: r,
             first:  updateRatio(node.first,  boundary, newRatio, x, y,       w, h * r),
             second: updateRatio(node.second, boundary, newRatio, x, y + h*r, w, h * (1-r)) }
}

function computeSplitBoundaries(node, x, y, w, h) {
    if (!node || node.type === "terminal") return []
    var r = node.ratio
    var result = []
    if (node.orientation === Qt.Horizontal) {
        result.push({ orientation: Qt.Horizontal,
                      pos: x + w * r, start: y, end: y + h,
                      firstLeafPaneId: findFirstTerminal(node.first),
                      nodeX: x, nodeY: y, nodeW: w, nodeH: h })
        result = result
            .concat(computeSplitBoundaries(node.first,  x,       y, w * r,     h))
            .concat(computeSplitBoundaries(node.second, x + w*r, y, w * (1-r), h))
    } else {
        result.push({ orientation: Qt.Vertical,
                      pos: y + h * r, start: x, end: x + w,
                      firstLeafPaneId: findFirstTerminal(node.first),
                      nodeX: x, nodeY: y, nodeW: w, nodeH: h })
        result = result
            .concat(computeSplitBoundaries(node.first,  x, y,       w, h * r))
            .concat(computeSplitBoundaries(node.second, x, y + h*r, w, h * (1-r)))
    }
    return result
}

function computePaneBounds(node, x, y, w, h) {
    if (!node) return []
    if (node.type === "terminal")
        return [{ paneId: node.paneId, cx: x + w/2, cy: y + h/2, w: w, h: h }]
    var r = node.ratio
    if (node.orientation === Qt.Horizontal)
        return computePaneBounds(node.first,  x,       y, w * r,     h)
              .concat(computePaneBounds(node.second, x + w*r, y, w * (1-r), h))
    return computePaneBounds(node.first,  x, y,       w, h * r)
          .concat(computePaneBounds(node.second, x, y + h*r, w, h * (1-r)))
}

function computePaneRects(node, x, y, w, h) {
    return computePaneBounds(node, x, y, w, h).map(function(b) {
        return { paneId: b.paneId, x: b.cx - b.w / 2, y: b.cy - b.h / 2,
                 w: b.w, h: b.h }
    })
}

function countTerminals(node) {
    if (!node) return 0
    if (node.type === "terminal") return 1
    return countTerminals(node.first) + countTerminals(node.second)
}

function collectTerminals(node) {
    if (!node) return []
    if (node.type === "terminal") return [node.paneId]
    return collectTerminals(node.first).concat(collectTerminals(node.second))
}

function findFirstTerminal(node) {
    if (!node) return -1
    if (node.type === "terminal") return node.paneId
    return findFirstTerminal(node.first)
}

function replaceNode(node, paneId, newNode) {
    if (!node) return node
    if (node.type === "terminal") return node.paneId === paneId ? newNode : node
    return { type: "split", orientation: node.orientation, ratio: node.ratio,
             first:  replaceNode(node.first,  paneId, newNode),
             second: replaceNode(node.second, paneId, newNode) }
}

function removeNode(node, paneId) {
    if (!node) return node
    if (node.type === "terminal") return node.paneId === paneId ? null : node
    if (node.first  && node.first.type  === "terminal" && node.first.paneId  === paneId) return node.second
    if (node.second && node.second.type === "terminal" && node.second.paneId === paneId) return node.first
    return { type: "split", orientation: node.orientation, ratio: node.ratio,
             first:  removeNode(node.first,  paneId),
             second: removeNode(node.second, paneId) }
}
