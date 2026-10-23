import AppKit

/// Tracks detected area suggestions and turns a press into either a click or a
/// manual rectangle drag. All points and rectangles use global AppKit space.
final class AreaSuggestionSelection {
    var didChange: (() -> Void)?

    private(set) var rect: CGRect = .zero
    private(set) var anchor: CGPoint?
    private(set) var isDragging = false

    private struct Candidate {
        let id: Int
        let rect: CGRect
    }

    private var candidates: [Candidate] = []
    private var selectionPath: [Candidate] = []
    private var pathIndex: Int?
    private var lockedPath = false

    private var gestureActive = false
    private var gestureBounds: CGRect = .zero
    private var frozenSuggestion: CGRect?
    private var manualGesture = false

    func replaceCandidates(_ rects: [CGRect], pointer: CGPoint) {
        candidates = rects.enumerated().map { Candidate(id: $0.offset, rect: $0.element) }
        guard !gestureActive else { return }
        hover(at: pointer)
    }

    func hover(at point: CGPoint) {
        guard !gestureActive else { return }
        if lockedPath, let selected = currentCandidate, selected.rect.contains(point) {
            return
        }
        lockedPath = false
        updateHover(at: point)
    }

    /// Moves one level between the selected suggestion and its containing
    /// ancestors. Returns the new center only when the visible selection moves.
    func step(outward: Bool) -> CGPoint? {
        guard !gestureActive, !selectionPath.isEmpty, let currentIndex = pathIndex else { return nil }
        let nextIndex = outward ? currentIndex + 1 : currentIndex - 1
        guard selectionPath.indices.contains(nextIndex) else { return nil }

        let previous = rect
        pathIndex = nextIndex
        lockedPath = true
        rect = selectionPath[nextIndex].rect
        guard rect != previous else { return nil }
        didChange?()
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    func begin(at point: CGPoint, bounds: CGRect) {
        guard !gestureActive else { return }
        hover(at: point)
        gestureActive = true
        gestureBounds = bounds
        anchor = point
        isDragging = false
        manualGesture = false
        frozenSuggestion = currentCandidate?.rect
        rect = frozenSuggestion ?? .zero
        didChange?()
    }

    func drag(to point: CGPoint) {
        guard gestureActive, let anchor else { return }
        var startedManualDrag = false
        if !manualGesture {
            let dx = point.x - anchor.x
            let dy = point.y - anchor.y
            guard hypot(dx, dy) > 4 else { return }
            manualGesture = true
            isDragging = true
            frozenSuggestion = nil
            startedManualDrag = true
        }
        let dragRect = CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                              width: abs(point.x - anchor.x), height: abs(point.y - anchor.y))
        let updated = dragRect.intersection(gestureBounds)
        guard updated != rect else {
            if startedManualDrag { didChange?() }
            return
        }
        rect = updated
        didChange?()
    }

    func end(at point: CGPoint) -> CGRect? {
        guard gestureActive, anchor != nil else { return nil }
        drag(to: point)
        gestureActive = false
        self.anchor = nil

        let result: CGRect?
        if manualGesture {
            result = rect.width >= 2 && rect.height >= 2 ? rect : nil
        } else {
            result = frozenSuggestion
        }

        let completedManually = manualGesture && result != nil
        isDragging = false
        manualGesture = false
        frozenSuggestion = nil
        lockedPath = false

        if result == nil {
            updateHover(at: point)
        } else if completedManually {
            selectionPath = []
            pathIndex = nil
        }
        didChange?()
        return result
    }

    private var currentCandidate: Candidate? {
        guard let pathIndex, selectionPath.indices.contains(pathIndex) else { return nil }
        return selectionPath[pathIndex]
    }

    private func updateHover(at point: CGPoint) {
        let selected = candidates
            .filter { $0.rect.contains(point) }
            .min { lhs, rhs in
                let lhsArea = lhs.rect.width * lhs.rect.height
                let rhsArea = rhs.rect.width * rhs.rect.height
                return lhsArea == rhsArea ? lhs.id < rhs.id : lhsArea < rhsArea
            }

        guard let selected else {
            let changed = rect != .zero
            rect = .zero
            selectionPath = []
            pathIndex = nil
            if changed { didChange?() }
            return
        }

        let ancestors = candidates
            .filter { $0.id != selected.id && $0.rect.contains(selected.rect) }
            .sorted { lhs, rhs in
                let lhsArea = lhs.rect.width * lhs.rect.height
                let rhsArea = rhs.rect.width * rhs.rect.height
                return lhsArea == rhsArea ? lhs.id < rhs.id : lhsArea < rhsArea
            }
        // Overlapping ancestors of the same child need not enclose each other.
        // Only a strictly enclosing chain is a nesting path.
        var newPath = [selected]
        for ancestor in ancestors where ancestor.rect != newPath.last!.rect && ancestor.rect.contains(newPath.last!.rect) {
            newPath.append(ancestor)
        }
        let changed = rect != selected.rect || selectionPath.map(\.id) != newPath.map(\.id) || pathIndex != 0
        selectionPath = newPath
        pathIndex = 0
        rect = selected.rect
        if changed { didChange?() }
    }
}
