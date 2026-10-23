import AppKit
import Testing
@testable import TobyShot

struct AreaSelectionTests {
    @Test(arguments: [false, true])
    func dragCrossesDisplayBoundariesInBothDirections(reversed: Bool) throws {
        let left = CGRect(x: -1200, y: -200, width: 1200, height: 900)
        let right = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let first = CGPoint(x: -300, y: 100)
        let last = CGPoint(x: 500, y: 600)
        let area = AreaSelection()
        var redraws = 0
        area.didChange = { redraws += 1 }

        area.begin(at: reversed ? last : first, bounds: left.union(right))
        area.drag(to: CGPoint(x: 20, y: 200))
        let result = try #require(area.end(at: reversed ? first : last))

        #expect(result == CGRect(x: -300, y: 100, width: 800, height: 500))
        #expect(CaptureGeometry.localRect(result, in: left).intersection(CGRect(origin: .zero, size: left.size))
                == CGRect(x: 900, y: 100, width: 300, height: 500))
        #expect(CaptureGeometry.localRect(result, in: right).intersection(CGRect(origin: .zero, size: right.size))
                == CGRect(x: 0, y: 400, width: 500, height: 500))
        #expect(redraws == 3)
        #expect(area.anchor == nil)
        #expect(area.end(at: first) == nil)
    }

    @Test func verticallyArrangedDisplaysUseTopLeftLocalCoordinates() throws {
        let lower = CGRect(x: 0, y: -900, width: 1200, height: 900)
        let upper = CGRect(x: -100, y: 0, width: 1400, height: 1000)
        let area = AreaSelection()
        area.begin(at: CGPoint(x: 100, y: -200), bounds: lower.union(upper))
        let rect = try #require(area.end(at: CGPoint(x: 600, y: 300)))
        #expect(rect == CGRect(x: 100, y: -200, width: 500, height: 500))
        #expect(CaptureGeometry.localRect(rect, in: lower) == CGRect(x: 100, y: -300, width: 500, height: 500))
        #expect(CaptureGeometry.localRect(rect, in: upper) == CGRect(x: 200, y: 700, width: 500, height: 500))
    }

    @Test func recordingSelectionStaysWithinItsStartingDisplay() throws {
        let screen = CGRect(x: -1200, y: -200, width: 1200, height: 900)
        let area = AreaSelection()
        area.begin(at: CGPoint(x: -300, y: 100), bounds: screen)
        area.drag(to: CGPoint(x: 500, y: 600))
        let rect = try #require(area.end(at: CGPoint(x: 500, y: 600)))
        #expect(rect == CGRect(x: -300, y: 100, width: 300, height: 500))
        #expect(CaptureGeometry.localRect(rect, in: screen) == CGRect(x: 900, y: 100, width: 300, height: 500))
    }

    @Test func clickOrTinyDragCanBeRetriedOnAnotherDisplay() throws {
        let area = AreaSelection()
        let desktop = CGRect(x: -100, y: -100, width: 200, height: 200)
        area.begin(at: .zero, bounds: desktop)
        #expect(area.end(at: CGPoint(x: 1, y: 1)) == nil)
        area.begin(at: CGPoint(x: -50, y: -50), bounds: desktop)
        #expect(area.rect == .zero)
        #expect(try #require(area.end(at: CGPoint(x: 50, y: 50))) == CGRect(x: -50, y: -50, width: 100, height: 100))
        area.drag(to: .zero)
        #expect(area.rect == CGRect(x: -50, y: -50, width: 100, height: 100))
    }
}

@Suite(.serialized)
@MainActor
struct SelectionViewTests {
    @Test(arguments: [false, true])
    func dragDeliveredOutsideStartingWindowUpdatesBothOverlays(reversed: Bool) throws {
        _ = NSApplication.shared
        let frames = [CGRect(x: -400, y: 100, width: 400, height: 400),
                      CGRect(x: 0, y: 0, width: 500, height: 500)]
        let context = try #require(CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let displays = frames.map { CaptureDisplayImage(frame: $0, image: image) }
        let area = AreaSelection()
        var results: [CGRect?] = []
        let views = displays.map { display in
            SelectionView(snapshot: display, displayFrame: display.frame, windows: [], instruction: "Capture",
                          area: area, displays: displays, selectionBounds: frames[0].union(frames[1])) { result in
                results.append(result?.rect)
            }
        }
        area.didChange = { for view in views { view.needsDisplay = true } }
        let panels = zip(frames, views).map { frame, view in
            let panel = CapturePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.contentView = view
            return panel
        }
        defer { for panel in panels { panel.close() } }
        let index = reversed ? 1 : 0
        let view = views[index], panel = panels[index]
        let first = CGPoint(x: -200, y: 200), last = CGPoint(x: 300, y: 400)
        let start = reversed ? last : first, end = reversed ? first : last

        #expect(view.acceptsFirstMouse(for: nil))
        view.mouseDown(with: mouse(.leftMouseDown, at: start, window: panel))
        for view in views { view.needsDisplay = false }
        view.mouseDragged(with: mouse(.leftMouseDragged, at: end, window: panel))

        #expect(views.allSatisfy { $0.needsDisplay })
        #expect(views[0].selection == CGRect(x: 200, y: 100, width: 500, height: 200))
        #expect(views[1].selection == CGRect(x: -200, y: 100, width: 500, height: 200))
        let released = CGPoint(x: end.x, y: end.y + 10)
        view.mouseUp(with: mouse(.leftMouseUp, at: released, window: panel))
        #expect(results.count == 1)
        let rect = try #require(results.first.flatMap { $0 })
        #expect(rect.minX == -200)
        #expect(rect.width == 500)
        #expect(rect.height == (reversed ? 190 : 210))

        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                 windowNumber: panels[1 - index].windowNumber, context: nil,
                                                 characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        views[1 - index].keyDown(with: escape)
        #expect(results.count == 2)
        #expect(results[1] == nil)
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: point), modifierFlags: [],
                          timestamp: 0, windowNumber: window.windowNumber, context: nil,
                          eventNumber: 0, clickCount: 1, pressure: 1)!
    }
}

struct PreviousCaptureAreaTests {
    let left = CGRect(x: -1200, y: 0, width: 1200, height: 900)
    let right = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    let rect = CGRect(x: -300, y: 100, width: 800, height: 500)

    @Test func repeatAreaRemembersEveryParticipatingDisplay() throws {
        let previous = PreviousCaptureArea(rect: rect, displays: [1: left, 2: right])
        #expect(previous.rect == rect)
        #expect(previous.displays == [1: left, 2: right])
        try previous.validate(displays: [1: left, 2: right])
    }

    @Test func disconnectedOrRearrangedDisplaysRequireANewSelection() {
        let previous = PreviousCaptureArea(rect: rect, displays: [1: left, 2: right])
        #expect(throws: (any Error).self) { try previous.validate(displays: [2: right]) }
        #expect(throws: (any Error).self) { try previous.validate(displays: [1: left, 2: right.offsetBy(dx: 50, dy: 0)]) }
        #expect(throws: (any Error).self) { try previous.validate(displays: [1: left, 3: right]) }
    }

    @Test func unrelatedDisplayChangesDoNotBlockRepeatingAnArea() throws {
        let third = CGRect(x: 1600, y: 0, width: 1000, height: 900)
        let previous = PreviousCaptureArea(rect: rect, displays: [1: left, 2: right, 3: third])
        #expect(previous.displays.count == 2)
        try previous.validate(displays: [1: left, 2: right])
        try previous.validate(displays: [1: left, 2: right, 3: third.offsetBy(dx: 200, dy: 200)])
        #expect(throws: (any Error).self) { try previous.validate(displays: [1: left, 2: right, 3: third.offsetBy(dx: -1600, dy: 0)]) }
    }
}
