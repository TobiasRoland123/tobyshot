import AppKit
import Carbon
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationMouseNavigationTests {
    @Test(arguments: [CGFloat(0.5), 1, 3])
    func commandWheelZoomKeepsPointerAnchoredAndDocumentUnchanged(scale: CGFloat) throws {
        let fixture = Fixture(scale: scale)
        defer { fixture.close() }
        let (model, canvas, scroll) = (fixture.model, fixture.canvas, fixture.scroll)
        model.annotations = [EditorAnnotation(kind: .rectangle, start: CGPoint(x: -80, y: -40), end: CGPoint(x: 120, y: 90))]
        model.markSaved()
        fixture.layout()
        scroll.contentView.scroll(to: CGPoint(x: 70, y: 60))
        let location = CGPoint(x: scroll.contentView.bounds.minX + 160, y: scroll.contentView.bounds.minY + 120)
        let point = try #require(canvas.imagePoint(location, requireInside: false, clampToImage: false))
        let annotations = model.annotations
        let exportSize = model.renderedImage().size
        scroll.scrollWheel(with: WheelEvent(delta: 1, location: canvas.convert(location, to: nil)))
        #expect(abs(model.zoom - scale * 1.1) < 0.0001)
        let after = canvas.viewPoint(point)
        #expect(abs(after.x - scroll.contentView.bounds.minX - 160) <= 1)
        #expect(abs(after.y - scroll.contentView.bounds.minY - 120) <= 1)
        #expect(model.annotations == annotations)
        #expect(model.renderedImage().size == exportSize)
        #expect(!model.hasUnsavedChanges)
        #expect(!model.canUndo)
    }

    @Test func wheelLimitsZeroAndInvalidDeltasPreserveFitAndActiveGestures() {
        let fixture = Fixture()
        defer { fixture.close() }
        let (model, canvas, scroll) = (fixture.model, fixture.canvas, fixture.scroll)
        let point = fixture.windowPoint(CGPoint(x: 100, y: 100))
        model.fitToWindow()
        fixture.layout()
        for delta in [CGFloat.zero, .nan, .infinity] {
            scroll.scrollWheel(with: WheelEvent(delta: delta, location: point))
            #expect(model.zoom == 0)
        }
        model.setZoom(8)
        fixture.layout()
        scroll.scrollWheel(with: WheelEvent(delta: 100, location: point))
        #expect(model.zoom == 8)
        model.setZoom(0.1)
        fixture.layout()
        scroll.scrollWheel(with: WheelEvent(delta: -100, location: point))
        #expect(model.zoom == 0.1)
        model.setZoom(1)
        fixture.layout()
        model.tool = .line
        canvas.mouseDown(with: fixture.mouse(.leftMouseDown, at: point))
        scroll.scrollWheel(with: WheelEvent(delta: 1, location: point))
        #expect(model.zoom == 1)
        canvas.mouseUp(with: fixture.mouse(.leftMouseUp, at: point))
        model.isPanKeyDown = true
        canvas.mouseDown(with: fixture.mouse(.leftMouseDown, at: point))
        scroll.scrollWheel(with: WheelEvent(delta: 1, location: point))
        #expect(model.zoom == 1)
        canvas.mouseUp(with: fixture.mouse(.leftMouseUp, at: point))
    }

    @Test(arguments: [false, true])
    func dragPanningMovesBothAxesWithoutEditingAndClampsAtEdges(middleButton: Bool) {
        let fixture = Fixture()
        defer { fixture.close() }
        let (model, canvas, scroll) = (fixture.model, fixture.canvas, fixture.scroll)
        model.tool = .rectangle
        model.annotations = [EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 200, y: 150), end: CGPoint(x: 350, y: 250))]
        model.selectedID = model.annotations[0].id
        model.markSaved()
        let originals = model.annotations
        let selection = model.selectedIDs
        scroll.contentView.scroll(to: CGPoint(x: 200, y: 150))
        let start = fixture.windowPoint(CGPoint(x: 300, y: 250))
        let end = CGPoint(x: start.x + 60, y: start.y - 40)
        model.isPanKeyDown = !middleButton
        if middleButton {
            canvas.otherMouseDown(with: MiddleMouseEvent(type: .otherMouseDown, location: start))
            canvas.otherMouseDragged(with: MiddleMouseEvent(type: .otherMouseDragged, location: end))
        } else {
            canvas.mouseDown(with: fixture.mouse(.leftMouseDown, at: start, modifiers: .option))
            model.isPanKeyDown = false // Releasing Space does not turn an active pan into drawing.
            canvas.mouseDragged(with: fixture.mouse(.leftMouseDragged, at: end))
        }
        #expect(canvas.isPanning)
        #expect(abs(scroll.contentView.bounds.minX - 140) <= 1)
        #expect(abs(scroll.contentView.bounds.minY - 110) <= 1)
        let beyondEdge = CGPoint(x: end.x + 10000, y: end.y - 10000)
        if middleButton {
            canvas.otherMouseUp(with: MiddleMouseEvent(type: .otherMouseUp, location: beyondEdge))
        } else {
            canvas.mouseUp(with: fixture.mouse(.leftMouseUp, at: beyondEdge))
        }
        #expect(scroll.contentView.bounds.origin == .zero)
        #expect(!canvas.isPanning)
        #expect(model.tool == .rectangle)
        #expect(model.selectedIDs == selection)
        #expect(model.annotations == originals)
        #expect(!model.canUndo)
        #expect(!model.hasUnsavedChanges)
        // The next ordinary gesture still uses the drawing tool.
        let blank = fixture.windowPoint(CGPoint(x: 80, y: 80))
        canvas.mouseDown(with: fixture.mouse(.leftMouseDown, at: blank))
        canvas.mouseDragged(with: fixture.mouse(.leftMouseDragged, at: CGPoint(x: blank.x + 20, y: blank.y - 20)))
        canvas.mouseUp(with: fixture.mouse(.leftMouseUp, at: CGPoint(x: blank.x + 20, y: blank.y - 20)))
        #expect(model.annotations.count == 2)
    }

    @Test(arguments: [CGFloat(0.5), 1, 3])
    func duplicateDragCopiesGroupOnceAndUsesReleasePositionInOneUndoStep(scale: CGFloat) throws {
        let fixture = Fixture(scale: scale)
        defer { fixture.close() }
        let (model, canvas) = (fixture.model, fixture.canvas)
        let originals = [
            EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 180, y: 170), color: .blue, width: 7),
            EditorAnnotation(kind: .arrow, start: CGPoint(x: 200, y: 100), end: CGPoint(x: 280, y: 160), arrowBend: CGPoint(x: 10, y: 20))
        ]
        model.annotations = originals
        model.selectedIDs = Set(originals.map(\.id))
        model.tool = .arrow
        model.markSaved()
        fixture.layout()
        let start = fixture.windowPoint(CGPoint(x: 140, y: 130))
        canvas.mouseDown(with: fixture.mouse(.leftMouseDown, at: start, modifiers: .option))
        #expect(model.annotations == originals)
        #expect(!model.canUndo)
        canvas.mouseDragged(with: fixture.mouse(.leftMouseDragged, at: CGPoint(x: start.x + 10 * scale, y: start.y - 15 * scale)))
        canvas.mouseDragged(with: fixture.mouse(.leftMouseDragged, at: CGPoint(x: start.x + 20 * scale, y: start.y - 25 * scale)))
        canvas.mouseUp(with: fixture.mouse(.leftMouseUp, at: CGPoint(x: start.x + 30 * scale, y: start.y - 35 * scale)))
        #expect(model.annotations.count == 4)
        #expect(Array(model.annotations.prefix(2)) == originals)
        let copies = Array(model.annotations.suffix(2))
        #expect(model.selectedIDs == Set(copies.map(\.id)))
        for (copy, original) in zip(copies, originals) {
            var expected = original
            expected.id = copy.id
            expected.start.x += 30; expected.start.y += 35
            expected.end.x += 30; expected.end.y += 35
            #expect(copy == expected)
            #expect(copy.id != original.id)
        }
        let final = model.annotations
        model.undo()
        #expect(model.annotations == originals)
        #expect(!model.canUndo)
        #expect(!model.hasUnsavedChanges)
        model.redo()
        #expect(model.annotations == final)
    }

    @Test func duplicateDragOverridesResizeHandlesAndClickDoesNotDuplicate() {
        let fixture = Fixture()
        defer { fixture.close() }
        let (model, canvas) = (fixture.model, fixture.canvas)
        let original = EditorAnnotation(kind: .rectangle, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 180, y: 170))
        model.annotations = [original]
        model.selectedID = original.id
        model.markSaved()
        fixture.layout()
        let start = fixture.windowPoint(original.end)
        canvas.mouseDown(with: fixture.mouse(.leftMouseDown, at: start, modifiers: .option))
        let slight = CGPoint(x: start.x + 1, y: start.y - 1)
        canvas.mouseDragged(with: fixture.mouse(.leftMouseDragged, at: slight, modifiers: .option))
        canvas.mouseUp(with: fixture.mouse(.leftMouseUp, at: slight, modifiers: .option))
        #expect(model.annotations == [original])
        #expect(!model.canUndo)
        #expect(!model.hasUnsavedChanges)
        canvas.mouseDown(with: fixture.mouse(.leftMouseDown, at: start, modifiers: .option))
        let end = CGPoint(x: start.x + 25, y: start.y - 30)
        canvas.mouseDragged(with: fixture.mouse(.leftMouseDragged, at: end, modifiers: .option))
        canvas.mouseUp(with: fixture.mouse(.leftMouseUp, at: end, modifiers: .option))
        #expect(model.annotations.count == 2)
        #expect(model.annotations[0] == original)
        #expect(model.annotations[1].start == CGPoint(x: 125, y: 130))
        #expect(model.annotations[1].end == CGPoint(x: 205, y: 200))
    }

    @Test func customizedAndDisabledDuplicateBindingsTakeEffectInExistingEditor() {
        let fixture = Fixture()
        defer { fixture.close() }
        let (model, canvas) = (fixture.model, fixture.canvas)
        let original = EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 180, y: 170))
        model.annotations = [original]
        fixture.layout()
        fixture.defaults.set(AnnotationDuplicateDragBinding.commandShift.rawValue, forKey: AnnotationDuplicateDragBinding.preferenceKey)
        let start = fixture.windowPoint(CGPoint(x: 140, y: 135))
        let end = CGPoint(x: start.x + 30, y: start.y - 20)
        canvas.mouseDown(with: fixture.mouse(.leftMouseDown, at: start, modifiers: [.command, .shift]))
        canvas.mouseDragged(with: fixture.mouse(.leftMouseDragged, at: end, modifiers: [.command, .shift]))
        canvas.mouseUp(with: fixture.mouse(.leftMouseUp, at: end, modifiers: [.command, .shift]))
        #expect(model.annotations.count == 2)
        #expect(model.annotations[0] == original)
        model.undo()
        fixture.defaults.set(AnnotationDuplicateDragBinding.disabled.rawValue, forKey: AnnotationDuplicateDragBinding.preferenceKey)
        canvas.mouseDown(with: fixture.mouse(.leftMouseDown, at: start, modifiers: .option))
        canvas.mouseDragged(with: fixture.mouse(.leftMouseDragged, at: end, modifiers: .option))
        canvas.mouseUp(with: fixture.mouse(.leftMouseUp, at: end, modifiers: .option))
        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].start == CGPoint(x: 130, y: 120))
    }

    @Test func losingWindowFocusClearsTemporaryPan() {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.model.isPanKeyDown = true
        fixture.canvas.mouseDown(with: fixture.mouse(.leftMouseDown, at: fixture.windowPoint(CGPoint(x: 100, y: 100))))
        #expect(fixture.canvas.isPanning)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        #expect(!fixture.model.isPanKeyDown)
        #expect(!fixture.canvas.isPanning)
    }

    @Test func duplicateTextWithTextToolPreservesContentWithoutStartingTextEditing() {
        let fixture = Fixture()
        defer { fixture.close() }
        let original = EditorAnnotation(kind: .text, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 100, y: 100), text: "Copy this", textSize: 32)
        fixture.model.annotations = [original]
        fixture.model.tool = .text
        fixture.layout()
        let start = fixture.windowPoint(CGPoint(x: 125, y: 115))
        let end = CGPoint(x: start.x + 30, y: start.y - 20)
        fixture.canvas.mouseDown(with: fixture.mouse(.leftMouseDown, at: start, modifiers: .option))
        fixture.canvas.mouseDragged(with: fixture.mouse(.leftMouseDragged, at: end, modifiers: .option))
        fixture.canvas.mouseUp(with: fixture.mouse(.leftMouseUp, at: end, modifiers: .option))
        #expect(fixture.model.annotations.count == 2)
        #expect(fixture.model.annotations[0] == original)
        #expect(fixture.model.annotations.last?.text == "Copy this")
        #expect(fixture.model.annotations.last?.textSize == 32)
        #expect(fixture.model.annotations.last?.start == CGPoint(x: 130, y: 120))
        #expect(fixture.model.editingTextID == nil)
        #expect(fixture.model.tool == .text)
    }

    @Test func duplicatePastedImageStaysBelowAnnotationsAndSharesPixels() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let pixels = try #require(fixture.model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let original = EditorAnnotation(kind: .image, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 300, y: 260), image: pixels)
        let mark = EditorAnnotation(kind: .line, start: CGPoint(x: 400, y: 400), end: CGPoint(x: 500, y: 500))
        fixture.model.annotations = [original, mark]
        fixture.layout()
        let start = fixture.windowPoint(CGPoint(x: 150, y: 140))
        let end = CGPoint(x: start.x + 30, y: start.y - 20)
        fixture.canvas.mouseDown(with: fixture.mouse(.leftMouseDown, at: start, modifiers: .option))
        fixture.canvas.mouseDragged(with: fixture.mouse(.leftMouseDragged, at: end, modifiers: .option))
        fixture.canvas.mouseUp(with: fixture.mouse(.leftMouseUp, at: end, modifiers: .option))
        #expect(fixture.model.annotations.count == 3)
        #expect(fixture.model.annotations.first == original)
        #expect(fixture.model.annotations.last == mark)
        #expect(fixture.model.annotations[1].image === pixels)
        #expect(fixture.model.annotations[1].start == CGPoint(x: 130, y: 120))
        fixture.model.undo()
        #expect(fixture.model.annotations == [original, mark])
    }

    @Test func regularWheelAndShiftWheelPanWithoutZooming() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        for horizontal in [false, true] {
            fixture.scroll.contentView.scroll(to: CGPoint(x: 200, y: 200))
            let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
            wheel.flags = horizontal ? .maskShift : []
            fixture.scroll.scrollWheel(with: try #require(NSEvent(cgEvent: wheel)))
            for _ in 0..<50 where fixture.scroll.contentView.bounds.origin == CGPoint(x: 200, y: 200) {
                try await Task.sleep(for: .milliseconds(10))
            }
            let origin = fixture.scroll.contentView.bounds.origin
            if horizontal {
                #expect(origin.x < 200)
                #expect(origin.y == 200)
            } else {
                #expect(origin.x == 200)
                #expect(origin.y < 200)
            }
            #expect(fixture.model.zoom == 1)
        }
    }

    @MainActor
    private final class Fixture {
        let defaultsName = "TobyShot.MouseNavigationTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let model: AnnotationEditorModel
        let canvas = AnnotationCanvasView()
        let scroll = AnnotationScrollView(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
        let window: NSWindow

        init(scale: CGFloat = 1) {
            _ = NSApplication.shared
            defaults = UserDefaults(suiteName: defaultsName)!
            let context = CGContext(data: nil, width: 1000, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            model = AnnotationEditorModel(image: NSImage(cgImage: context.makeImage()!, size: CGSize(width: 1000, height: 800)), sourceURL: nil, defaults: defaults)
            model.zoom = scale
            canvas.model = model
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers = true
            scroll.scrollerStyle = .overlay
            scroll.documentView = canvas
            window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = scroll
            layout()
        }

        func close() {
            window.close()
            defaults.removePersistentDomain(forName: defaultsName)
        }

        func layout() { scroll.needsLayout = true; scroll.layoutSubtreeIfNeeded() }
        func windowPoint(_ point: CGPoint) -> CGPoint { canvas.convert(canvas.viewPoint(point), to: nil) }
        func mouse(_ type: NSEvent.EventType, at location: CGPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
    }
}

private final class WheelEvent: NSEvent {
    private let delta: CGFloat
    private let location: CGPoint
    override var scrollingDeltaY: CGFloat { delta }
    override var hasPreciseScrollingDeltas: Bool { false }
    override var modifierFlags: NSEvent.ModifierFlags { .command }
    override var locationInWindow: NSPoint { location }
    init(delta: CGFloat, location: CGPoint) { self.delta = delta; self.location = location; super.init() }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

private final class MiddleMouseEvent: NSEvent {
    private let eventType: NSEvent.EventType
    private let location: CGPoint
    override var type: NSEvent.EventType { eventType }
    override var buttonNumber: Int { 2 }
    override var locationInWindow: NSPoint { location }
    init(type: NSEvent.EventType, location: CGPoint) { eventType = type; self.location = location; super.init() }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
