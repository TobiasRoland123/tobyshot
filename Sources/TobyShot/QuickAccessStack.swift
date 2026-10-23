import CoreGraphics
import Foundation

/// Recent captures shown in Quick Access, newest first.
struct QuickAccessStack {
    struct Entry: Identifiable, Equatable {
        let item: CaptureItem
        /// Seconds left before the preview closes on its own.
        var remaining: TimeInterval
        var id: UUID { item.id }
    }

    private(set) var entries: [Entry] = []
    private(set) var draggedIDs: Set<UUID> = []

    var items: [CaptureItem] { entries.map(\.item) }
    var isEmpty: Bool { entries.isEmpty }
    var isDragging: Bool { !draggedIDs.isEmpty }

    /// Shows a capture above older ones, moving it to the top if it is already stacked.
    /// Each preview keeps its own countdown, so previews close in the order they were captured.
    mutating func push(_ item: CaptureItem, duration: TimeInterval) {
        entries.removeAll { $0.id == item.id }
        entries.insert(Entry(item: item, remaining: duration), at: 0)
    }

    /// Removes the oldest previews that no longer fit on screen. The newest preview and previews being dragged stay.
    mutating func trim(to capacity: Int) {
        var excess = entries.count - max(1, capacity)
        var index = entries.count - 1
        while excess > 0, index > 0 {
            if !draggedIDs.contains(entries[index].id) { entries.remove(at: index); excess -= 1 }
            index -= 1
        }
    }

    mutating func dismiss(_ id: UUID) {
        entries.removeAll { $0.id == id }
        draggedIDs.remove(id)
    }

    mutating func removeAll() {
        entries.removeAll()
        draggedIDs.removeAll()
    }

    /// Keeps only previews whose captures are still in history.
    mutating func retain(_ ids: Set<UUID>) {
        entries.removeAll { !ids.contains($0.id) }
        draggedIDs.formIntersection(ids)
    }

    mutating func beginDrag(_ id: UUID) {
        if entries.contains(where: { $0.id == id }) { draggedIDs.insert(id) }
    }

    /// Ends a drag. A completed drop dismisses the capture when `dismissOnDrop` is set; a cancelled drag keeps it.
    /// Returns whether the capture was dismissed.
    @discardableResult
    mutating func endDrag(_ id: UUID, dropped: Bool, dismissOnDrop: Bool) -> Bool {
        draggedIDs.remove(id)
        guard dropped, dismissOnDrop, entries.contains(where: { $0.id == id }) else { return false }
        dismiss(id)
        return true
    }

    /// Counts down while the stack is idle and removes expired previews. Returns the expired captures.
    @discardableResult
    mutating func advance(by elapsed: TimeInterval, paused: Bool) -> [CaptureItem] {
        guard elapsed > 0, !paused, !isDragging else { return [] }
        for index in entries.indices { entries[index].remaining -= elapsed }
        let expired = entries.filter { $0.remaining <= 0 }.map(\.item)
        entries.removeAll { $0.remaining <= 0 }
        return expired
    }
}

/// Quick Access sizes: the newest capture gets a full card, and older captures get compact thumbnails.
enum QuickAccessStackLayout {
    static let spacing: CGFloat = 8
    /// Distance from the edges of the screen's visible area.
    static let margin: CGFloat = 22

    // Whole points keep the card sizes in step with the panel frame, which AppKit rounds.
    static func cardHeight(width: CGFloat) -> CGFloat { (width * 0.64).rounded() + 80 }
    static func compactHeight(width: CGFloat) -> CGFloat { (width * 0.36).rounded() }

    /// Window height for a stack of `count` previews, including a 1 pt border inset.
    static func height(count: Int, width: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return cardHeight(width: width) + CGFloat(count - 1) * (compactHeight(width: width) + spacing) + 2
    }

    /// How many previews fit in `availableHeight`. At least the newest preview is always shown.
    static func capacity(width: CGFloat, availableHeight: CGFloat) -> Int {
        let room = availableHeight - height(count: 1, width: width)
        guard room > 0 else { return 1 }
        return 1 + Int(room / (compactHeight(width: width) + spacing))
    }
}
