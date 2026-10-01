import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationCanvasArrowTests {
    @Test func placedArrowImmediatelySupportsEndpointBendAndMoveGestures() throws {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.annotations = []
        model.selectedID = nil
        model.tool = .arrow
        func drag(from: CGPoint, to: CGPoint) {
            let start = viewPoint(from, model: model, canvas: canvas)
            let end = viewPoint(to, model: model, canvas: canvas)
            canvas.mouseDown(with: mouse(.leftMouseDown, at: start, canvas: canvas, window: window))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end, canvas: canvas, window: window))
            canvas.mouseUp(with: mouse(.leftMouseUp, at: end, canvas: canvas, window: window))
        }
        drag(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 200, y: 100))
        let placed = try #require(model.annotations.first)
        #expect(model.tool == .select)
        #expect(model.selectedID == placed.id)
        drag(from: placed.end, to: CGPoint(x: 250, y: 100))
        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].start == placed.start)
        #expect(model.annotations[0].end == CGPoint(x: 250, y: 100))
        drag(from: CGPoint(x: 150, y: 100), to: CGPoint(x: 150, y: 60))
        let bent = model.annotations[0]
        #expect(bent.arrowBend == CGPoint(x: 0, y: -40))
        // A point on the shaft away from its handles moves the whole arrow.
        drag(from: CGPoint(x: 100, y: 70), to: CGPoint(x: 110, y: 90))
        let moved = model.annotations[0]
        #expect(moved.start == CGPoint(x: 60, y: 120))
        #expect(moved.end == CGPoint(x: 260, y: 120))
        #expect(moved.arrowBend == bent.arrowBend)
        #expect(model.annotations.count == 1)
        #expect(model.selectedID == placed.id)
        model.undo()
        #expect(model.annotations == [bent])
    }

    @Test(arguments: [CGFloat(0), 0.5, 1, 2], [AnnotationArrowHandle.start, .end])
    func endpointHandlesWorkWithZoomPaddingAndReversedCurves(zoom: CGFloat, handle: AnnotationArrowHandle) {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.zoom = zoom
        model.updateBackground(style: .lavender)
        model.updateBackground(padding: 24)
        model.annotations[0].arrowBend = CGPoint(x: 10, y: -30)
        model.annotations[0].reversed = true
        let original = model.annotations[0]
        model.selectedID = original.id
        let endpoint = handle.point(in: original)
        let destination = CGPoint(x: endpoint.x + 20, y: endpoint.y - 45)
        let start = viewPoint(endpoint, model: model, canvas: canvas)
        let end = viewPoint(destination, model: model, canvas: canvas)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: end, canvas: canvas, window: window))
        let edited = model.annotations[0]
        #expect(abs(handle.point(in: edited).x - destination.x) < 0.001)
        #expect(abs(handle.point(in: edited).y - destination.y) < 0.001)
        #expect(handle == .start ? edited.end == original.end : edited.start == original.start)
        #expect(abs(edited.arrowBendPoint.x - original.arrowBendPoint.x) < 0.001)
        #expect(abs(edited.arrowBendPoint.y - original.arrowBendPoint.y) < 0.001)
        #expect(edited.reversed)
        #expect(model.annotations.count == 1)
        model.undo()
        #expect(model.annotations == [original])
        model.redo()
        #expect(model.annotations == [edited])
    }

    @Test(arguments: [CGFloat(0), 4])
    func overlappingHandlesLetShortArrowsExtendFromTheirEnd(length: CGFloat) {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.annotations[0].end = CGPoint(x: model.annotations[0].start.x + length, y: model.annotations[0].start.y)
        let original = model.annotations[0]
        let start = viewPoint(original.end, model: model, canvas: canvas)
        let end = viewPoint(CGPoint(x: 240, y: 140), model: model, canvas: canvas)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: end, canvas: canvas, window: window))
        #expect(model.annotations[0].start == original.start)
        #expect(model.annotations[0].end == CGPoint(x: 240, y: 140))
        #expect(model.annotations[0].arrowBend == .zero)
    }

    @Test(arguments: [CGFloat(0), 0.5, 1, 2], [AnnotationTool.select, .arrow])
    func middleHandleBendsAtEveryZoomWithBackgroundPadding(zoom: CGFloat, tool: AnnotationTool) throws {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.zoom = zoom
        model.updateBackground(style: .lavender)
        model.updateBackground(padding: 24)
        model.tool = tool
        let original = try #require(model.annotations.first)
        model.selectedID = original.id
        let handle = viewPoint(original.arrowBendPoint, model: model, canvas: canvas)
        let destination = viewPoint(CGPoint(x: 150, y: 35), model: model, canvas: canvas)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: handle, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: destination, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: destination, canvas: canvas, window: window))
        let bent = try #require(model.annotations.first)
        #expect(model.annotations.count == 1)
        #expect(bent.start == original.start)
        #expect(bent.end == original.end)
        #expect(abs(bent.arrowBend.x) < 0.001)
        #expect(abs(bent.arrowBend.y + 65) < 0.001)
        model.undo()
        #expect(model.annotations == [original])
        model.redo()
        #expect(model.annotations == [bent])
    }

    @Test func bendHandleCanLeaveAndReenterImageWithoutClamping() throws {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        let original = try #require(model.annotations.first)
        let handle = viewPoint(original.arrowBendPoint, model: model, canvas: canvas)
        let outside = viewPoint(CGPoint(x: 150, y: -20), model: model, canvas: canvas)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: handle, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: outside, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: outside, canvas: canvas, window: window))
        #expect(model.annotations[0].arrowBendPoint == CGPoint(x: 150, y: -20))
        // The completed gesture fits the view to the expanded canvas.
        let returnStart = viewPoint(model.annotations[0].arrowBendPoint, model: model, canvas: canvas)
        let returnEnd = viewPoint(original.arrowBendPoint, model: model, canvas: canvas)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: returnStart, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: returnEnd, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: returnEnd, canvas: canvas, window: window))
        #expect(model.annotations == [original])
    }

    @Test func doubleClickingMiddleHandleStraightensWithoutDrawingAnotherArrow() {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.tool = .arrow
        model.annotations[0].arrowBend = CGPoint(x: 20, y: 60)
        let bent = model.annotations[0]
        let handle = viewPoint(bent.arrowBendPoint, model: model, canvas: canvas)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: handle, canvas: canvas, window: window, clicks: 2))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: handle, canvas: canvas, window: window, clicks: 2))
        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].arrowBend == .zero)
        model.undo()
        #expect(model.annotations == [bent])
    }

    private func viewPoint(_ point: CGPoint, model: AnnotationEditorModel, canvas: AnnotationCanvasView) -> CGPoint {
        let bounds = canvas.layoutCanvasBounds
        let width = bounds.width
        let height = bounds.height
        let scale = model.zoom == 0 ? min((canvas.bounds.width - 48) / width, (canvas.bounds.height - 48) / height) : model.zoom
        return CGPoint(x: (canvas.bounds.width - width * scale) / 2 + (point.x - bounds.minX) * scale,
                       y: (canvas.bounds.height - height * scale) / 2 + (point.y - bounds.minY) * scale)
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, canvas: NSView, window: NSWindow, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    private func makeCanvas() -> (AnnotationEditorModel, AnnotationCanvasView, NSWindow) {
        _ = NSApplication.shared
        let context = CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = NSImage(cgImage: context.makeImage()!, size: CGSize(width: 300, height: 200))
        let model = AnnotationEditorModel(image: image, sourceURL: nil)
        model.zoom = 1
        let arrow = EditorAnnotation(kind: .arrow, start: CGPoint(x: 70, y: 100), end: CGPoint(x: 230, y: 100))
        model.annotations = [arrow]
        model.selectedID = arrow.id
        let canvas = AnnotationCanvasView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        canvas.model = model
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        return (model, canvas, window)
    }
}
