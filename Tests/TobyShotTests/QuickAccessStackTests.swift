import AppKit
import Foundation
import Testing
@testable import TobyShot

struct QuickAccessStackTests {
    @Test func newestCaptureIsOnTopAndShowingAStackedCaptureMovesItUp() {
        let (a, b, c) = (item("A"), item("B"), item("C"))
        var stack = QuickAccessStack()
        stack.push(a, duration: 8); stack.push(b, duration: 8); stack.push(c, duration: 8)
        #expect(stack.items == [c, b, a])

        stack.push(a, duration: 8)
        #expect(stack.items == [a, c, b])
    }

    @Test func previewsExpireInTheOrderTheyWereCaptured() {
        let (a, b, c) = (item("A"), item("B"), item("C"))
        var stack = QuickAccessStack()
        stack.push(a, duration: 8)
        stack.advance(by: 3, paused: false)
        stack.push(b, duration: 8)
        stack.advance(by: 3, paused: false)
        stack.push(c, duration: 8)

        let first = stack.advance(by: 2, paused: false)
        #expect(first == [a])
        #expect(stack.items == [c, b])
        let second = stack.advance(by: 3, paused: false)
        #expect(second == [b])
        #expect(stack.items == [c])
        let third = stack.advance(by: 3, paused: false)
        #expect(third == [c])
        #expect(stack.isEmpty)
    }

    @Test func hoverAndActiveDragsPauseExpiry() {
        let (a, b) = (item("A"), item("B"))
        var stack = QuickAccessStack()
        stack.push(a, duration: 8); stack.push(b, duration: 8)

        let hovered = stack.advance(by: 30, paused: true)
        #expect(hovered.isEmpty)
        stack.beginDrag(a.id)
        let dragging = stack.advance(by: 30, paused: false)
        #expect(dragging.isEmpty)
        stack.endDrag(a.id, dropped: false, dismissOnDrop: true)
        #expect(stack.items == [b, a])

        stack.advance(by: 7.9, paused: false)
        #expect(stack.items == [b, a])
        let expired = stack.advance(by: 0.1, paused: false)
        #expect(expired == [b, a])
        #expect(stack.isEmpty)
    }

    @Test func expiringOnePreviewKeepsTheOthers() {
        let (a, b) = (item("A"), item("B"))
        var stack = QuickAccessStack()
        stack.push(a, duration: 15)
        stack.push(b, duration: 5)
        let expired = stack.advance(by: 5, paused: false)
        #expect(expired == [b])
        #expect(stack.items == [a])
    }

    @Test func dropsDismissOnlyTheDraggedCaptureWhenConfigured() {
        let (a, b, c) = (item("A"), item("B"), item("C"))
        var stack = QuickAccessStack()
        [a, b, c].forEach { stack.push($0, duration: 8) }

        stack.beginDrag(b.id)
        let cancelled = stack.endDrag(b.id, dropped: false, dismissOnDrop: true)
        #expect(!cancelled)
        #expect(stack.items == [c, b, a])

        // Close after dragging is off, or Option is held.
        stack.beginDrag(b.id)
        let kept = stack.endDrag(b.id, dropped: true, dismissOnDrop: false)
        #expect(!kept)
        #expect(stack.items == [c, b, a])

        stack.beginDrag(b.id)
        let dismissed = stack.endDrag(b.id, dropped: true, dismissOnDrop: true)
        #expect(dismissed)
        #expect(stack.items == [c, a])
        #expect(!stack.isDragging)

        stack.dismiss(c.id)
        #expect(stack.items == [a])
    }

    @Test func trimmingRemovesTheOldestPreviewsButKeepsTheNewestAndDraggedOnes() {
        let captures = (0..<5).map { item("\($0)") }
        var stack = QuickAccessStack()
        captures.forEach { stack.push($0, duration: 8) }
        stack.beginDrag(captures[0].id)

        stack.trim(to: 3)
        #expect(stack.items == [captures[4], captures[3], captures[0]])

        stack.trim(to: 0)
        #expect(stack.items == [captures[4], captures[0]])
    }

    @Test func retainingHistoryRemovesDeletedCapturesOnly() {
        let (a, b) = (item("A"), item("B"))
        var stack = QuickAccessStack()
        stack.push(a, duration: 8); stack.push(b, duration: 8)
        stack.beginDrag(a.id)
        stack.retain([b.id])
        #expect(stack.items == [b])
        #expect(!stack.isDragging)
    }

    @Test(arguments: [220.0, 280.0, 400.0], [300.0, 700.0, 806.0, 1400.0])
    func capacityFitsTheAvailableHeight(width: Double, available: Double) {
        let width = CGFloat(width), available = CGFloat(available)
        let capacity = QuickAccessStackLayout.capacity(width: width, availableHeight: available)
        #expect(capacity >= 1)
        if capacity > 1 { #expect(QuickAccessStackLayout.height(count: capacity, width: width) <= available) }
        #expect(QuickAccessStackLayout.height(count: capacity + 1, width: width) > available)
    }

    @Test func threeCapturesFitOnASmallLaptopScreenAtTheLargestSize() {
        // A 13-inch MacBook Air has about 830 pt of visible height with the Dock shown.
        #expect(QuickAccessStackLayout.capacity(width: 400, availableHeight: 830 - 44) >= 3)
    }

    private func item(_ title: String) -> CaptureItem {
        CaptureItem(id: UUID(), filename: "\(title).png", title: title, date: Date(), kind: .image, width: 4, height: 3)
    }
}

@Suite(.serialized)
@MainActor
struct QuickAccessWindowTests {
    @Test func showsCapturesAsAnOrderedStackInsideTheScreen() throws {
        try withCoordinator(position: "Right") { app in
            let captures = try (0..<3).map { _ in try app.store.add(image: image()) }
            captures.forEach(app.showPreview)
            let quickAccess = app.quickAccess
            let window = try #require(quickAccess.window)

            #expect(quickAccess.items == captures.reversed())
            #expect(quickAccess.isVisible)
            let screen = try #require(NSScreen.screens.first { $0.frame.intersects(window.frame) })
            #expect(screen.visibleFrame.contains(window.frame))
            #expect(window.frame.maxX == screen.visibleFrame.maxX - QuickAccessStackLayout.margin)
            #expect(window.frame.minY == screen.visibleFrame.minY + QuickAccessStackLayout.margin)
            #expect(window.frame.height == QuickAccessStackLayout.height(count: 3, width: 280))
        }
        try withCoordinator(position: "Left") { app in
            app.showPreview(try app.store.add(image: image()))
            let window = try #require(app.quickAccess.window)
            let screen = try #require(NSScreen.screens.first { $0.frame.intersects(window.frame) })
            #expect(window.frame.minX == screen.visibleFrame.minX + QuickAccessStackLayout.margin)
        }
    }

    @Test func dismissalAndExpiryKeepOtherPreviewsAndHistory() throws {
        try withCoordinator { app in
            let captures = try (0..<3).map { _ in try app.store.add(image: image()) }
            captures.forEach(app.showPreview)
            let quickAccess = app.quickAccess

            quickAccess.dismiss(captures[1].id)
            #expect(quickAccess.items == [captures[2], captures[0]])
            #expect(quickAccess.window?.frame.height == QuickAccessStackLayout.height(count: 2, width: 280))

            quickAccess.advance(by: 30, hovered: true)
            #expect(quickAccess.items.count == 2)
            quickAccess.beginDrag(captures[0].id)
            quickAccess.advance(by: 30, hovered: false)
            #expect(quickAccess.items.count == 2)
            quickAccess.endDrag(captures[0].id, dropped: false)
            #expect(quickAccess.items == [captures[2], captures[0]])

            quickAccess.advance(by: 8, hovered: false)
            #expect(quickAccess.items.isEmpty)
            #expect(!quickAccess.isVisible)
            #expect(app.store.items.map(\.id) == captures.reversed().map(\.id))
        }
    }

    @Test func autoCloseOffKeepsPreviewsUntilClosed() throws {
        try withCoordinator(autoClose: false) { app in
            let capture = try app.store.add(image: image())
            app.showPreview(capture)
            app.quickAccess.advance(by: 60, hovered: false)
            #expect(app.quickAccess.items == [capture])

            app.closeOverlays()
            #expect(app.quickAccess.items.isEmpty)
            #expect(!app.quickAccess.isVisible)
            #expect(app.store.items == [capture])
        }
    }

    @Test func successfulDropFollowsCloseAfterDragging() throws {
        for closeAfterDrag in [true, false] {
            try withCoordinator(closeAfterDrag: closeAfterDrag) { app in
                let older = try app.store.add(image: image())
                let newer = try app.store.add(image: image())
                app.showPreview(older); app.showPreview(newer)

                app.quickAccess.beginDrag(newer.id)
                app.quickAccess.endDrag(newer.id, dropped: true)
                #expect(app.quickAccess.items == (closeAfterDrag ? [older] : [newer, older]))
                #expect(app.quickAccess.isVisible)
            }
        }
    }

    @Test func deletingACaptureFromHistoryRemovesItsPreview() throws {
        try withCoordinator { app in
            let older = try app.store.add(image: image())
            let newer = try app.store.add(image: image())
            app.showPreview(older); app.showPreview(newer)
            app.remove(newer)
            #expect(app.quickAccess.items == [older])
        }
    }

    @Test func captureHidesTheStackAndRestoresItsVisibility() throws {
        try withCoordinator { app in
            let quickAccess = app.quickAccess
            app.showPreview(try app.store.add(image: image()))

            quickAccess.hideForCapture()
            #expect(!quickAccess.isVisible)
            quickAccess.advance(by: 30, hovered: false)
            #expect(quickAccess.items.count == 1)
            quickAccess.restoreAfterCapture()
            #expect(quickAccess.isVisible)

            // A new capture appears after the capture finishes, together with older previews.
            quickAccess.hideForCapture()
            app.showPreview(try app.store.add(image: image()))
            #expect(!quickAccess.isVisible)
            quickAccess.restoreAfterCapture()
            #expect(quickAccess.isVisible)
            #expect(quickAccess.items.count == 2)

            // Previews hidden with the overlay shortcut stay hidden after a capture without a new preview.
            app.toggleOverlays()
            quickAccess.hideForCapture()
            quickAccess.restoreAfterCapture()
            #expect(!quickAccess.isVisible)
            app.toggleOverlays()
            #expect(quickAccess.isVisible)
        }
    }

    @Test func closingPreviewsAnimateOutBeforeThePanelShrinks() async throws {
        try await withCoordinator { app in
            let quickAccess = app.quickAccess
            quickAccess.outroDuration = 0.2
            let older = try app.store.add(image: image())
            let newer = try app.store.add(image: image())
            app.showPreview(older); app.showPreview(newer)
            let twoHigh = QuickAccessStackLayout.height(count: 2, width: 280)

            quickAccess.dismiss(newer.id)
            #expect(quickAccess.items == [older])
            #expect(quickAccess.window?.frame.height == twoHigh)
            try await Task.sleep(for: .milliseconds(500))
            #expect(quickAccess.window?.frame.height == QuickAccessStackLayout.height(count: 1, width: 280))

            quickAccess.dismiss(older.id)
            #expect(quickAccess.isVisible)
            try await Task.sleep(for: .milliseconds(500))
            #expect(!quickAccess.isVisible)
        }
    }

    private func withCoordinator(position: String = "Right", autoClose: Bool = true, closeAfterDrag: Bool = true,
                                 _ body: (AppCoordinator) throws -> Void) throws {
        try withCoordinatorSetup(position: position, autoClose: autoClose, closeAfterDrag: closeAfterDrag) { app, finish in
            defer { finish() }
            app.quickAccess.outroDuration = 0
            try body(app)
        }
    }

    private func withCoordinator(_ body: (AppCoordinator) async throws -> Void) async throws {
        var coordinator: AppCoordinator?
        var cleanup: (() -> Void)?
        try withCoordinatorSetup(position: "Right", autoClose: true, closeAfterDrag: true) { app, finish in
            coordinator = app; cleanup = finish
        }
        defer { cleanup?() }
        try await body(try #require(coordinator))
    }

    /// Creates a coordinator with Quick Access preferences set. `finish` restores them and removes test files.
    private func withCoordinatorSetup(position: String, autoClose: Bool, closeAfterDrag: Bool,
                                      _ body: (AppCoordinator, @escaping () -> Void) throws -> Void) throws {
        _ = NSApplication.shared
        Preferences.register()
        let values: [String: Any] = ["overlayPosition": position, "overlayActiveScreen": false, "overlaySize": 280.0,
                                     "overlayAutoClose": autoClose, "overlayInterval": 8.0, "overlayCloseAfterDrag": closeAfterDrag]
        let prior = values.keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TobyShot.QuickAccessTests.\(UUID().uuidString)")
        let app = AppCoordinator(shortcuts: HotKeyManager(), store: CaptureStore(directory: directory))
        let finish = {
            app.quickAccess.outroDuration = 0
            app.closeOverlays()
            app.quickAccess.close()
            for (key, value) in prior {
                if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
            try? FileManager.default.removeItem(at: directory)
        }
        values.forEach { UserDefaults.standard.set($0.value, forKey: $0.key) }
        try body(app, finish)
    }

    private func image() -> NSImage {
        let image = NSImage(size: CGSize(width: 240, height: 180))
        image.lockFocus(); NSColor.white.setFill(); CGRect(x: 0, y: 0, width: 240, height: 180).fill(); image.unlockFocus()
        return image
    }
}
