import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationCanvasZoomTests {
    @Test func pinchKeepsImagePointUnderPointerIncludingExpandedCanvas() throws {
        let (model, canvas, scroll, window) = makeCanvas()
        defer { window.close() }
        model.annotations = [EditorAnnotation(kind: .rectangle, start: CGPoint(x: -80, y: -40), end: CGPoint(x: 100, y: 90))]
        model.updateBackground(style: .lavender)
        model.markSaved()
        layout(scroll)
        scroll.contentView.scroll(to: CGPoint(x: 140, y: 110))
        scroll.reflectScrolledClipView(scroll.contentView)
        let viewportPoint = CGPoint(x: 175, y: 130)
        let location = CGPoint(x: scroll.contentView.bounds.minX + viewportPoint.x, y: scroll.contentView.bounds.minY + viewportPoint.y)
        let imagePoint = try #require(canvas.imagePoint(location, requireInside: false, clampToImage: false))
        let event = MagnificationEvent(amount: 0.25, location: canvas.convert(location, to: nil))
        let annotations = model.annotations
        let exportSize = model.renderedImage().size
        let undo = model.canUndo
        var imageChanges = 0
        model.onImageChange = { _ in imageChanges += 1 }

        canvas.magnify(with: event)

        #expect(abs(model.zoom - 1.25) < 0.0001)
        let after = canvas.viewPoint(imagePoint)
        #expect(abs(after.x - scroll.contentView.bounds.minX - viewportPoint.x) <= 1)
        #expect(abs(after.y - scroll.contentView.bounds.minY - viewportPoint.y) <= 1)
        #expect(model.annotations == annotations)
        #expect(model.renderedImage().size == exportSize)
        #expect(!model.hasUnsavedChanges)
        #expect(model.canUndo == undo)
        #expect(imageChanges == 0)
    }

    @Test func controlsZoomAroundVisibleCenterAndFitRespondsToResize() async throws {
        let (model, canvas, scroll, window) = makeCanvas()
        defer { window.close() }
        scroll.contentView.scroll(to: CGPoint(x: 210, y: 150))
        let center = CGPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY)
        let imagePoint = try #require(canvas.imagePoint(center, requireInside: false, clampToImage: false))
        model.setZoom(4)
        layout(scroll)
        let after = canvas.viewPoint(imagePoint)
        #expect(abs(after.x - scroll.contentView.bounds.midX) <= 1)
        #expect(abs(after.y - scroll.contentView.bounds.midY) <= 1)

        model.fitToWindow()
        layout(scroll)
        await Task.yield()
        let firstScale = canvas.currentScale
        #expect(model.zoom == 0)
        #expect(abs(model.actualZoom - firstScale) < 0.0001)
        #expect(canvas.frame.size == scroll.contentView.bounds.size)
        #expect(scroll.contentView.bounds.origin == .zero)
        #expect(canvas.visibleRect.contains(canvas.viewPoint(.zero)))
        #expect(canvas.visibleRect.contains(canvas.viewPoint(CGPoint(x: 1000, y: 800))))

        window.setContentSize(CGSize(width: 700, height: 520))
        layout(scroll)
        await Task.yield()
        #expect(model.zoom == 0)
        #expect(canvas.currentScale > firstScale)
        #expect(abs(model.actualZoom - canvas.currentScale) < 0.0001)
        #expect(canvas.visibleRect.contains(canvas.viewPoint(CGPoint(x: 1000, y: 800))))

        model.setZoom(1)
        layout(scroll)
        #expect(canvas.currentScale == 1)
    }

    @Test func scrollingReachesEveryCornerWithoutDrawingWithAnActiveTool() throws {
        let (model, canvas, scroll, window) = makeCanvas()
        defer { window.close() }
        model.tool = .freehand
        model.setZoom(8)
        layout(scroll)
        for corner in [CGPoint.zero, CGPoint(x: 1000, y: 0), CGPoint(x: 0, y: 800), CGPoint(x: 1000, y: 800)] {
            let point = canvas.viewPoint(corner)
            let proposed = CGRect(x: point.x - 100, y: point.y - 100, width: scroll.contentView.bounds.width, height: scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(proposed).origin)
            scroll.reflectScrolledClipView(scroll.contentView)
            #expect(canvas.visibleRect.contains(point))
        }
        let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 60, wheel2: 80, wheel3: 0))
        scroll.scrollWheel(with: try #require(NSEvent(cgEvent: wheel)))
        #expect(model.annotations.isEmpty)
        #expect(!model.hasUnsavedChanges)
        #expect(!model.canUndo)
    }

    @Test(arguments: [CGFloat(0.1), 0.625, 1, 3.125, 8])
    func drawingSelectionMovingAndResizingUseImageCoordinatesAfterScrolling(zoom: CGFloat) throws {
        let (model, canvas, scroll, window) = makeCanvas()
        defer { window.close() }
        model.setZoom(zoom)
        model.tool = .rectangle
        layout(scroll)
        scroll.contentView.scroll(to: CGPoint(x: max(0, canvas.frame.width - 600), y: max(0, canvas.frame.height - 500)))
        let start = CGPoint(x: 650, y: 450), end = CGPoint(x: 900, y: 700)
        drag(start, end, canvas: canvas, window: window)
        let drawn = try #require(model.annotations.first)
        expectPoint(drawn.start, start)
        expectPoint(drawn.end, end)
        #expect(model.selectedID == drawn.id)

        drag(end, CGPoint(x: 950, y: 750), canvas: canvas, window: window)
        expectPoint(model.annotations[0].end, CGPoint(x: 950, y: 750))
        model.tool = .select
        model.clearSelection()
        drag(CGPoint(x: 800, y: 600), CGPoint(x: 820, y: 620), canvas: canvas, window: window)
        #expect(model.annotations.count == 1)
        #expect(model.selectedID == drawn.id)
        expectPoint(model.annotations[0].start, CGPoint(x: 670, y: 470))
        expectPoint(model.annotations[0].end, CGPoint(x: 970, y: 770))
    }

    @Test func pinchOverLiveTextPreservesEditingAndScalesItsFrame() throws {
        let (model, canvas, scroll, window) = makeCanvas()
        defer { window.close() }
        model.tool = .text
        model.begin(at: CGPoint(x: 200, y: 180))
        model.updateText("Still editing")
        layout(scroll)
        let editor = try #require(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        let originalSize = editor.frame.size
        let selection = editor.selectedRange()
        let annotations = model.annotations
        let location = editor.convert(CGPoint(x: 20, y: 10), to: nil)
        editor.magnify(with: MagnificationEvent(amount: 0.5, location: location))
        #expect(window.firstResponder === editor)
        #expect(editor.selectedRange() == selection)
        #expect(model.editingTextID != nil)
        #expect(model.annotations == annotations)
        #expect(abs(editor.frame.width - originalSize.width * 1.5) < 0.0001)
        #expect(abs(editor.frame.height - originalSize.height * 1.5) < 0.0001)
        expectPoint(editor.frame.origin, canvas.viewPoint(model.annotations[0].start))
        editor.insertText("!", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
        #expect(model.annotations.first?.text == "Still editing!")
    }

    @Test func pinchLimitsAndZeroDeltaDoNotDisturbFitOrAnActiveDrawing() {
        let (model, canvas, scroll, window) = makeCanvas()
        defer { window.close() }
        model.fitToWindow()
        layout(scroll)
        let location = canvas.convert(CGPoint(x: 200, y: 150), to: nil)
        scroll.magnify(with: MagnificationEvent(amount: 0, location: location))
        #expect(model.zoom == 0)
        scroll.magnify(with: MagnificationEvent(amount: 100, location: location))
        #expect(model.zoom == AnnotationEditorModel.maximumZoom)
        scroll.magnify(with: MagnificationEvent(amount: -1, location: location))
        #expect(model.zoom == AnnotationEditorModel.minimumZoom)
        model.tool = .line
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 100, y: 100), canvas: canvas, window: window))
        scroll.magnify(with: MagnificationEvent(amount: 0.5, location: location))
        #expect(model.zoom == AnnotationEditorModel.minimumZoom)
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 100, y: 100), canvas: canvas, window: window))
    }

    private func layout(_ scroll: AnnotationScrollView) {
        scroll.needsLayout = true
        scroll.layoutSubtreeIfNeeded()
    }

    private func makeCanvas() -> (AnnotationEditorModel, AnnotationCanvasView, AnnotationScrollView, NSWindow) {
        _ = NSApplication.shared
        let context = CGContext(data: nil, width: 1000, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let model = AnnotationEditorModel(image: NSImage(cgImage: context.makeImage()!, size: CGSize(width: 1000, height: 800)), sourceURL: nil)
        model.zoom = 1
        let canvas = AnnotationCanvasView()
        canvas.model = model
        let scroll = AnnotationScrollView(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = canvas
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        layout(scroll)
        return (model, canvas, scroll, window)
    }

    private func expectPoint(_ actual: CGPoint, _ expected: CGPoint) {
        #expect(abs(actual.x - expected.x) < 0.0001)
        #expect(abs(actual.y - expected.y) < 0.0001)
    }

    private func drag(_ start: CGPoint, _ end: CGPoint, canvas: AnnotationCanvasView, window: NSWindow) {
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: end, canvas: canvas, window: window))
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, canvas: AnnotationCanvasView, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(canvas.viewPoint(point), to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
}

private final class MagnificationEvent: NSEvent {
    private let amount: CGFloat
    private let location: CGPoint
    override var magnification: CGFloat { amount }
    override var locationInWindow: NSPoint { location }

    init(amount: CGFloat, location: CGPoint) {
        self.amount = amount
        self.location = location
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
