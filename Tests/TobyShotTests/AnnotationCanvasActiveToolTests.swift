import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationCanvasActiveToolTests {
    @Test func drawsConsecutiveArrowsWithoutReselectingTheTool() {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.tool = .arrow
        drag(from: CGPoint(x: 40, y: 40), to: CGPoint(x: 200, y: 60), canvas: canvas, window: window)
        drag(from: CGPoint(x: 40, y: 140), to: CGPoint(x: 200, y: 160), canvas: canvas, window: window)

        #expect(model.tool == .arrow)
        #expect(model.annotations.map(\.kind) == [.arrow, .arrow])
        #expect(model.annotations[1].end == CGPoint(x: 200, y: 160))
        #expect(model.selectedID == model.annotations[1].id)
    }

    @Test func olderArrowEditsFromHoverWhileArrowIsActive() throws {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        let older = EditorAnnotation(kind: .arrow, start: CGPoint(x: 40, y: 60), end: CGPoint(x: 240, y: 60), shadow: false)
        let newer = EditorAnnotation(kind: .arrow, start: CGPoint(x: 40, y: 160), end: CGPoint(x: 240, y: 160), shadow: false)
        model.annotations = [older, newer]
        model.selectedID = newer.id
        model.tool = .arrow

        // Hovering the shaft reveals the older arrow's handles without a selection click.
        hover(CGPoint(x: 100, y: 61), canvas: canvas, window: window)
        #expect(canvas.hoveredAnnotationID == older.id)
        #expect(target(at: CGPoint(x: 100, y: 61), canvas: canvas) == .move(older.id))
        guard case let .handle(endHandle) = target(at: older.end, canvas: canvas) else {
            Issue.record("Expected the older arrow's end handle")
            return
        }
        #expect(endHandle.annotationID == older.id)
        #expect(endHandle.kind == .arrow(.end))

        drag(from: older.end, to: CGPoint(x: 260, y: 90), canvas: canvas, window: window)
        #expect(model.annotations[0].end == CGPoint(x: 260, y: 90))
        #expect(model.annotations[0].start == older.start)
        let repositioned = model.annotations[0]

        hover(repositioned.arrowBendPoint, canvas: canvas, window: window)
        drag(from: repositioned.arrowBendPoint, to: CGPoint(x: repositioned.arrowBendPoint.x, y: repositioned.arrowBendPoint.y - 30),
             canvas: canvas, window: window)
        #expect(model.annotations[0].arrowBend == CGPoint(x: 0, y: -30))
        let bent = model.annotations[0]

        // A point on the curve away from the handles moves the whole arrow.
        let shaft = CGPoint(x: 95, y: 45)
        hover(shaft, canvas: canvas, window: window)
        #expect(target(at: shaft, canvas: canvas) == .move(older.id))
        drag(from: shaft, to: CGPoint(x: shaft.x + 10, y: shaft.y + 20), canvas: canvas, window: window)
        #expect(model.annotations[0].start == CGPoint(x: 50, y: 80))
        #expect(model.annotations[0].end == CGPoint(x: 270, y: 110))
        #expect(model.annotations[0].arrowBend == bent.arrowBend)

        #expect(model.tool == .arrow)
        #expect(model.annotations.count == 2)
        #expect(model.annotations[1] == newer)
        model.undo()
        #expect(model.annotations[0] == bent)
        model.undo()
        #expect(model.annotations[0] == repositioned)
        model.undo()
        #expect(model.annotations == [older, newer])
    }

    @Test(arguments: [EditorAnnotation.Kind.rectangle, .ellipse])
    func resizesOutlinedShapeWhileArrowIsActive(kind: EditorAnnotation.Kind) {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        let shape = EditorAnnotation(kind: kind, start: CGPoint(x: 60, y: 40), end: CGPoint(x: 220, y: 140), shadow: false)
        model.annotations = [shape]
        model.tool = .arrow
        let corner = CGPoint(x: 220, y: 140)

        // Without hover there are no handles; an ellipse's corner is empty canvas.
        if kind == .ellipse { #expect(target(at: corner, canvas: canvas) == .canvas) }
        // Hover the outline, then move onto the corner handle.
        hover(CGPoint(x: 140, y: 140), canvas: canvas, window: window)
        hover(corner, canvas: canvas, window: window)
        #expect(canvas.hoveredAnnotationID == shape.id)
        #expect(target(at: corner, canvas: canvas) == .handle(AnnotationEditHandle(
            annotationID: shape.id, kind: .shape(.corner(.bottomRight)),
            rect: CGRect(x: viewPoint(corner, canvas: canvas).x - 4, y: viewPoint(corner, canvas: canvas).y - 4, width: 8, height: 8))))

        drag(from: corner, to: CGPoint(x: 260, y: 170), canvas: canvas, window: window)
        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].start == shape.start)
        #expect(model.annotations[0].end == CGPoint(x: 260, y: 170))
        #expect(model.tool == .arrow)
        model.undo()
        #expect(model.annotations == [shape])
    }

    @Test(arguments: [EditorAnnotation.Kind.rectangle, .ellipse])
    func emptyInteriorDrawsWhileOutlineMoves(kind: EditorAnnotation.Kind) {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        let shape = EditorAnnotation(kind: kind, start: CGPoint(x: 60, y: 40), end: CGPoint(x: 220, y: 160), shadow: false)
        model.annotations = [shape]
        model.tool = .arrow
        let interior = CGPoint(x: 140, y: 100)

        hover(interior, canvas: canvas, window: window)
        #expect(canvas.hoveredAnnotationID == nil)
        #expect(target(at: interior, canvas: canvas) == .canvas)
        drag(from: interior, to: CGPoint(x: 190, y: 130), canvas: canvas, window: window)
        #expect(model.annotations.count == 2)
        #expect(model.annotations[0] == shape)
        #expect(model.annotations[1].kind == .arrow)

        let outline = CGPoint(x: 60, y: 100)
        model.selectedID = nil
        hover(outline, canvas: canvas, window: window)
        #expect(target(at: outline, canvas: canvas) == .move(shape.id))
        drag(from: outline, to: CGPoint(x: 70, y: 110), canvas: canvas, window: window)
        #expect(model.annotations.count == 2)
        #expect(model.annotations[0].start == CGPoint(x: 70, y: 50))
        #expect(model.tool == .arrow)
    }

    @Test func textToolTargetsLabelsForEditingAndOtherAnnotationsForMoving() {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        let label = EditorAnnotation(kind: .text, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 40, y: 40), text: "Label")
        let filled = EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 150, y: 120), end: CGPoint(x: 250, y: 180))
        model.annotations = [label, filled]
        model.tool = .text

        #expect(target(at: CGPoint(x: 50, y: 50), canvas: canvas) == .editText(label.id))
        #expect(target(at: CGPoint(x: 200, y: 150), canvas: canvas) == .move(filled.id))
        drag(from: CGPoint(x: 200, y: 150), to: CGPoint(x: 210, y: 160), canvas: canvas, window: window)
        #expect(model.annotations[1].start == CGPoint(x: 160, y: 130))
        #expect(model.annotations.count == 2)
        #expect(model.editingTextID == nil)
        #expect(model.tool == .text)
    }

    private func target(at point: CGPoint, canvas: AnnotationCanvasView) -> AnnotationPointerTarget {
        canvas.pointerTarget(at: viewPoint(point, canvas: canvas))
    }

    private func hover(_ point: CGPoint, canvas: AnnotationCanvasView, window: NSWindow) {
        canvas.mouseMoved(with: mouse(.mouseMoved, at: point, canvas: canvas, window: window))
    }

    private func drag(from start: CGPoint, to end: CGPoint, canvas: AnnotationCanvasView, window: NSWindow) {
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: end, canvas: canvas, window: window))
    }

    private func viewPoint(_ point: CGPoint, canvas: AnnotationCanvasView) -> CGPoint {
        let bounds = canvas.layoutCanvasBounds
        return CGPoint(x: (canvas.bounds.width - bounds.width) / 2 + point.x - bounds.minX,
                       y: (canvas.bounds.height - bounds.height) / 2 + point.y - bounds.minY)
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, canvas: AnnotationCanvasView, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(viewPoint(point, canvas: canvas), to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func makeCanvas() -> (AnnotationEditorModel, AnnotationCanvasView, NSWindow) {
        _ = NSApplication.shared
        let context = CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = NSImage(cgImage: context.makeImage()!, size: CGSize(width: 300, height: 200))
        let model = AnnotationEditorModel(image: image, sourceURL: nil)
        model.zoom = 1
        let canvas = AnnotationCanvasView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        canvas.model = model
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        return (model, canvas, window)
    }
}
