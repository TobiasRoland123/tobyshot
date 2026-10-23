import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AreaSuggestionViewTests {
    @Test func clickCapturesHighlightedPixelsAndLateResultsCannotChangeGesture() throws {
        try withViews { views, panels, model, results in
            let suggestion = CGRect(x: -300, y: 180, width: 200, height: 160)
            model.replaceCandidates([suggestion], pointer: CGPoint(x: -250, y: 220))
            #expect(views[0].selection == CGRect(x: 100, y: 160, width: 200, height: 160))
            views[0].mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: -250, y: 220), window: panels[0]))
            model.replaceCandidates([], pointer: CGPoint(x: -249, y: 221))
            views[0].mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: -249, y: 221), window: panels[0]))
            #expect(results.rectangles == [suggestion])
        }
    }

    @Test func absentSuggestionStaysAbsentForClickAndManualDragCrossesDisplays() throws {
        try withViews { views, panels, model, results in
            let first = CGPoint(x: -250, y: 220)
            views[0].mouseDown(with: mouse(.leftMouseDown, at: first, window: panels[0]))
            model.replaceCandidates([CGRect(x: -300, y: 180, width: 200, height: 160)], pointer: first)
            views[0].mouseUp(with: mouse(.leftMouseUp, at: first, window: panels[0]))
            #expect(results.rectangles.isEmpty)

            views[0].mouseDown(with: mouse(.leftMouseDown, at: first, window: panels[0]))
            views[0].mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 250, y: 400), window: panels[0]))
            #expect(model.isDragging)
            #expect(views[0].selection == CGRect(x: 150, y: 100, width: 500, height: 180))
            #expect(views[1].selection == CGRect(x: -250, y: 100, width: 500, height: 180))
            views[0].mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 250, y: 400), window: panels[0]))
            #expect(results.rectangles == [CGRect(x: -250, y: 220, width: 500, height: 180)])
        }
    }

    @Test func pointerConversionHandlesDisplaysAboveBelowAndLeftWithoutPixelScaling() {
        let frames = [CGRect(x: -1200, y: -200, width: 1200, height: 900),
                      CGRect(x: 0, y: 1000, width: 1600, height: 900),
                      CGRect(x: 0, y: -900, width: 1600, height: 900)]
        let quartzFrames = [CGRect(x: -1200, y: 300, width: 1200, height: 900),
                            CGRect(x: 0, y: -900, width: 1600, height: 900),
                            CGRect(x: 0, y: 1000, width: 1600, height: 900)]
        for (frame, quartz) in zip(frames, quartzFrames) {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            #expect(SelectionView.quartzPoint(center, screenFrame: frame, displayFrame: quartz)
                    == CGPoint(x: quartz.midX, y: quartz.midY))
        }
    }

    @Test func scrollRecentersWithoutCapturingAndIgnoresMomentumAndPathEndpoints() throws {
        try withViews { views, _, model, results in
            let view = views[1] // Origin zero also accepts windowless CGEvent coordinates.
            let child = CGRect(x: 20, y: 30, width: 30, height: 50)
            let parent = CGRect(x: 10, y: 10, width: 300, height: 300)
            let sibling = CGRect(x: 130, y: 130, width: 80, height: 80)
            let start = CGPoint(x: 30, y: 40)
            model.replaceCandidates([child, parent, sibling], pointer: start)
            var warps: [CGPoint] = []
            view.recenterPointer = { warps.append($0) }
            view.scrollWheel(with: scroll(delta: 1, at: start))
            #expect(model.rect == parent)
            #expect(warps == [CGPoint(x: 160, y: 340)])
            let center = CGPoint(x: 160, y: 160)
            view.scrollWheel(with: scroll(delta: -1, at: center, momentum: true))
            #expect(model.rect == parent)
            view.scrollWheel(with: scroll(delta: 1, at: center))
            #expect(warps.count == 1)
            view.scrollWheel(with: scroll(delta: -1, at: center))
            #expect(model.rect == child)
            #expect(warps.last == CGPoint(x: 35, y: 445))
            #expect(results.rectangles.isEmpty)
        }
    }

    private final class Results { var rectangles: [CGRect] = [] }

    private func withViews(_ body: ([SelectionView], [NSPanel], AreaSuggestionSelection, Results) throws -> Void) throws {
        _ = NSApplication.shared
        let context = try #require(CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let frames = [CGRect(x: -400, y: 100, width: 400, height: 400), CGRect(x: 0, y: 0, width: 500, height: 500)]
        let displays = frames.map { CaptureDisplayImage(frame: $0, image: image) }
        let model = AreaSuggestionSelection()
        let results = Results()
        let views = displays.map { display in
            SelectionView(snapshot: display, displayFrame: display.frame, windows: [], instruction: "Capture",
                          area: AreaSelection(), displays: displays, selectionBounds: frames[0].union(frames[1]),
                          suggestions: model) { result in
                if let result { results.rectangles.append(result.rect) }
            }
        }
        model.didChange = { for view in views { view.needsDisplay = true } }
        let panels = zip(frames, views).map { frame, view in
            let panel = CapturePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.contentView = view
            return panel
        }
        defer {
            model.didChange = nil
            for panel in panels { panel.close() }
        }
        try body(views, panels, model, results)
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: point), modifierFlags: [],
                          timestamp: 0, windowNumber: window.windowNumber, context: nil,
                          eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func scroll(delta: Int32, at point: CGPoint, momentum: Bool = false) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                            wheel1: delta, wheel2: 0, wheel3: 0)!
        event.location = CGPoint(x: point.x, y: NSScreen.screens[0].frame.maxY - point.y)
        if momentum { event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1) }
        return NSEvent(cgEvent: event)!
    }
}
