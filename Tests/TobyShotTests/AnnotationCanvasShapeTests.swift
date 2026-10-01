import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationCanvasShapeTests {
    @Test(arguments: [
        (AnnotationTool.rectangle, EditorAnnotation.Kind.rectangle),
        (.filledRectangle, .filledRectangle), (.ellipse, .ellipse), (.line, .line),
        (.freehand, .freehand), (.redact, .redaction), (.pixelate, .pixelation)
    ])
    func placedShapeCanImmediatelyResizeThenMove(tool: AnnotationTool, kind: EditorAnnotation.Kind) throws {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.tool = tool
        drag(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 150, y: 110), model: model, canvas: canvas, window: window)
        let placed = try #require(model.annotations.first)
        #expect(model.tool == .select)
        #expect(model.selectedID == placed.id)
        #expect(placed.kind == kind)

        drag(from: CGPoint(x: 150, y: 110), to: CGPoint(x: 190, y: 130), model: model, canvas: canvas, window: window)
        let resized = model.annotations[0]
        #expect(model.annotations.count == 1)
        #expect(resized.start == placed.start)
        #expect(resized.end == CGPoint(x: 190, y: 130))
        #expect(resized.id == placed.id)
        #expect(resized.width == placed.width)
        if kind == .freehand {
            #expect(resized.points.first == placed.points.first)
            #expect(resized.points.last == resized.end)
        }

        drag(from: CGPoint(x: 120, y: 90), to: CGPoint(x: 130, y: 105), model: model, canvas: canvas, window: window)
        #expect(model.annotations[0].start == CGPoint(x: 60, y: 65))
        #expect(model.annotations[0].end == CGPoint(x: 200, y: 145))
        model.undo()
        #expect(model.annotations == [resized])
        model.undo()
        #expect(model.annotations == [placed])
        model.undo()
        #expect(model.annotations.isEmpty)
    }

    @Test(arguments: [CGFloat(0), 0.5, 1, 2], [EditorAnnotation.Kind.rectangle, .filledRectangle, .ellipse, .line, .freehand, .redaction, .pixelation])
    func handlesRespectZoomPaddingAndFinalMouseUp(zoom: CGFloat, kind: EditorAnnotation.Kind) {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.zoom = zoom
        model.updateBackground(style: .lavender)
        model.updateBackground(padding: 24)
        let original = EditorAnnotation(kind: kind, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 150, y: 110),
            points: kind == .freehand ? [CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 80), CGPoint(x: 150, y: 110)] : [],
            shadow: false)
        model.annotations = [original]
        model.selectedID = original.id
        canvas.mouseDown(with: mouse(.leftMouseDown, at: original.end, model: model, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 170, y: 120), model: model, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 200, y: 140), model: model, canvas: canvas, window: window))
        let edited = model.annotations[0]
        #expect(abs(edited.end.x - 200) < 0.001)
        #expect(abs(edited.end.y - 140) < 0.001)
        #expect(edited.start == original.start)
        #expect(model.selectedID == original.id)
        model.undo()
        #expect(model.annotations == [original])
        model.redo()
        #expect(model.annotations == [edited])
    }

    @Test func numberedStepHasCornerHandlesImmediatelyAfterPlacement() throws {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.tool = .step
        drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 100, y: 100), model: model, canvas: canvas, window: window)
        let placed = try #require(model.annotations.first)
        #expect(model.tool == .select)
        // Default width 5 gives a 17.5 px radius. Grow the diameter by 35 px.
        drag(from: CGPoint(x: 117.5, y: 117.5), to: CGPoint(x: 152.5, y: 152.5), model: model, canvas: canvas, window: window)
        #expect(model.annotations[0].width == 10)
        #expect(model.annotations[0].start == CGPoint(x: 117.5, y: 117.5))
        #expect(model.annotations[0].step == placed.step)
        #expect(model.annotations.count == 1)
        model.undo()
        #expect(model.annotations == [placed])
    }

    @Test func groupDragFromCornerMovesBothShapesWithoutResizing() {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        let first = EditorAnnotation(kind: .rectangle, start: CGPoint(x: 30, y: 30), end: CGPoint(x: 80, y: 70), shadow: false)
        let second = EditorAnnotation(kind: .ellipse, start: CGPoint(x: 120, y: 90), end: CGPoint(x: 180, y: 130), shadow: false)
        model.annotations = [first, second]
        model.selectedIDs = [first.id, second.id]
        drag(from: first.end, to: CGPoint(x: 90, y: 90), model: model, canvas: canvas, window: window)
        #expect(model.annotations[0].start == CGPoint(x: 40, y: 50))
        #expect(model.annotations[0].end == CGPoint(x: 90, y: 90))
        #expect(model.annotations[1].start == CGPoint(x: 130, y: 110))
        #expect(model.annotations[1].end == CGPoint(x: 190, y: 150))
        model.undo()
        #expect(model.annotations == [first, second])
        #expect(!model.canUndo)
    }

    @Test func shiftClickOnCornerDeselectsWithoutResizing() {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        let original = EditorAnnotation(kind: .rectangle, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 120, y: 100))
        model.annotations = [original]
        model.selectedID = original.id
        canvas.mouseDown(with: mouse(.leftMouseDown, at: original.end, modifiers: .shift, model: model, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: original.end, modifiers: .shift, model: model, canvas: canvas, window: window))
        #expect(model.selectedIDs.isEmpty)
        #expect(model.annotations == [original])
        #expect(!model.canUndo)
    }

    @Test func reselectingShapeRestoresHandlesAndAllowsResizeOutsideImage() {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        let original = EditorAnnotation(kind: .ellipse, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 120, y: 100))
        model.annotations = [original]
        drag(from: CGPoint(x: 80, y: 70), to: CGPoint(x: 80, y: 70), model: model, canvas: canvas, window: window)
        #expect(model.selectedID == original.id)
        #expect(!model.canUndo)
        drag(from: original.start, to: CGPoint(x: -20, y: -10), model: model, canvas: canvas, window: window)
        #expect(model.annotations[0].start == CGPoint(x: -20, y: -10))
        #expect(model.annotations[0].end == original.end)
        drag(from: CGPoint(x: -20, y: -10), to: original.start, model: model, canvas: canvas, window: window)
        #expect(model.annotations == [original])
    }

    @Test(arguments: [AnnotationTool.rectangle, .freehand, .arrow, .step, .crop, .text])
    func changingToolsDuringResizeStopsFurtherEdits(tool: AnnotationTool) {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        let original = EditorAnnotation(kind: .rectangle, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 120, y: 100))
        model.annotations = [original]
        model.selectedID = original.id
        canvas.mouseDown(with: mouse(.leftMouseDown, at: original.end, model: model, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 160, y: 120), model: model, canvas: canvas, window: window))
        let resized = model.annotations[0]
        model.tool = tool
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 190, y: 150), model: model, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 200, y: 160), model: model, canvas: canvas, window: window))
        #expect(model.annotations == [resized])
        #expect(model.tool == tool)
        #expect(model.cropRect == nil)
        model.undo()
        #expect(model.annotations == [original])
    }

    private func drag(from start: CGPoint, to end: CGPoint, model: AnnotationEditorModel, canvas: AnnotationCanvasView, window: NSWindow) {
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, model: model, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end, model: model, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: end, model: model, canvas: canvas, window: window))
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, modifiers: NSEvent.ModifierFlags = [], model: AnnotationEditorModel, canvas: AnnotationCanvasView, window: NSWindow) -> NSEvent {
        let bounds = canvas.layoutCanvasBounds
        let size = bounds.size
        let scale = model.zoom == 0 ? min((canvas.bounds.width - 48) / size.width, (canvas.bounds.height - 48) / size.height) : model.zoom
        let location = CGPoint(x: (canvas.bounds.width - size.width * scale) / 2 + (point.x - bounds.minX) * scale,
                               y: (canvas.bounds.height - size.height * scale) / 2 + (point.y - bounds.minY) * scale)
        return NSEvent.mouseEvent(with: type, location: canvas.convert(location, to: nil), modifierFlags: modifiers,
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
