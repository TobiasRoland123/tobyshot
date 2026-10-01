import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationCanvasSelectionTests {
    @Test(arguments: [CGFloat(0), 0.5, 1, 2], [false, true])
    func marqueeSelectsAtEveryZoomFromOutsideImage(zoom: CGFloat, reversed: Bool) throws {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.zoom = zoom
        model.updateBackground(style: .lavender)
        model.updateBackground(padding: 24)
        model.markSaved()
        let originals = model.annotations
        let first = CGPoint(x: -15, y: -10)
        let last = CGPoint(x: 180, y: 150)
        let start = reversed ? last : first
        let end = reversed ? first : last

        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, model: model, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end, model: model, canvas: canvas, window: window))
        let rect = try #require(model.selectionRect)
        #expect(abs(rect.minX + 15) < 0.001)
        #expect(abs(rect.minY + 10) < 0.001)
        #expect(abs(rect.width - 195) < 0.001)
        #expect(abs(rect.height - 160) < 0.001)
        #expect(model.selectedIDs == Set(originals.prefix(2).map(\.id)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: end, model: model, canvas: canvas, window: window))

        #expect(model.selectionRect == nil)
        #expect(model.selectedIDs == Set(originals.prefix(2).map(\.id)))
        #expect(model.annotations == originals)
        #expect(!model.hasUnsavedChanges)
    }

    @Test func mouseUpUsesFinalSelectionPositionAndBlankClickClearsIt() {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        let start = CGPoint(x: 5, y: 5)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, model: model, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 80, y: 80), model: model, canvas: canvas, window: window))
        #expect(model.selectedIDs == [model.annotations[0].id])
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 180, y: 150), model: model, canvas: canvas, window: window))
        #expect(model.selectedIDs == Set(model.annotations.prefix(2).map(\.id)))
        #expect(!model.canUndo)

        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, model: model, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: start, model: model, canvas: canvas, window: window))
        #expect(model.selectedIDs.isEmpty)
        #expect(model.selectionRect == nil)
        #expect(!model.canUndo)
    }

    @Test func draggingGroupFromArrowEndpointMovesBothWithoutEditingArrow() {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        let arrow = EditorAnnotation(kind: .arrow, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 100, y: 40), shadow: false)
        model.annotations[0] = arrow
        let originals = model.annotations
        drag(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 180, y: 150), model: model, canvas: canvas, window: window)
        #expect(model.selectedIDs == Set(originals.prefix(2).map(\.id)))
        drag(from: arrow.end, to: CGPoint(x: 120, y: 60), model: model, canvas: canvas, window: window)
        #expect(model.annotations[0].start == CGPoint(x: 60, y: 60))
        #expect(model.annotations[0].end == CGPoint(x: 120, y: 60))
        #expect(model.annotations[0].arrowBend == .zero)
        #expect(model.annotations[1].start == CGPoint(x: originals[1].start.x + 20, y: originals[1].start.y + 20))
        #expect(model.annotations[2] == originals[2])
        model.undo()
        #expect(model.annotations == originals)
        #expect(!model.canUndo)
    }

    @Test func shiftDragAddsAndShiftClickOnArrowHandleDeselects() {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        let arrow = EditorAnnotation(kind: .arrow, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 100, y: 40), shadow: false)
        model.annotations[0] = arrow
        model.selectedID = arrow.id
        canvas.mouseDown(with: mouse(.leftMouseDown, at: arrow.end, modifiers: .shift, model: model, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: arrow.end, modifiers: .shift, model: model, canvas: canvas, window: window))
        #expect(model.selectedIDs.isEmpty)
        model.selectedID = arrow.id
        drag(from: CGPoint(x: 105, y: 75), to: CGPoint(x: 180, y: 150), modifiers: .shift, model: model, canvas: canvas, window: window)
        #expect(model.selectedIDs == Set(model.annotations.prefix(2).map(\.id)))
        #expect(model.annotations[0] == arrow)
        #expect(!model.canUndo)
    }

    @Test func clearingSelectionDuringMarqueeStopsLaterDragEvents() {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        let originals = model.annotations
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 5, y: 5), model: model, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 180, y: 150), model: model, canvas: canvas, window: window))
        model.clearSelection()
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 280, y: 190), model: model, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 280, y: 190), model: model, canvas: canvas, window: window))
        #expect(model.selectedIDs.isEmpty)
        #expect(model.selectionRect == nil)
        #expect(model.annotations == originals)
        #expect(!model.canUndo)
    }

    @Test(arguments: [AnnotationTool.rectangle, .freehand, .arrow, .step, .crop, .text])
    func switchingToolsDuringMarqueeDoesNotEditSelectedAnnotation(tool: AnnotationTool) {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        let originals = model.annotations
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 5, y: 5), model: model, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 80, y: 80), model: model, canvas: canvas, window: window))
        #expect(model.selectedID == originals[0].id)
        model.tool = tool
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 180, y: 150), model: model, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 180, y: 150), model: model, canvas: canvas, window: window))
        #expect(model.selectionRect == nil)
        #expect(model.cropRect == nil)
        #expect(model.annotations == originals)
        #expect(model.tool == tool)
        #expect(!model.canUndo)
    }

    private func drag(from start: CGPoint, to end: CGPoint, modifiers: NSEvent.ModifierFlags = [], model: AnnotationEditorModel, canvas: AnnotationCanvasView, window: NSWindow) {
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, modifiers: modifiers, model: model, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end, modifiers: modifiers, model: model, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: end, modifiers: modifiers, model: model, canvas: canvas, window: window))
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, modifiers: NSEvent.ModifierFlags = [], model: AnnotationEditorModel, canvas: NSView, window: NSWindow) -> NSEvent {
        let padding = model.background == .none ? 0 : model.padding.rounded()
        let size = CGSize(width: model.pixelSize.width + padding * 2, height: model.pixelSize.height + padding * 2)
        let scale = model.zoom == 0 ? min((canvas.bounds.width - 48) / size.width, (canvas.bounds.height - 48) / size.height) : model.zoom
        let location = CGPoint(x: (canvas.bounds.width - size.width * scale) / 2 + (point.x + padding) * scale,
                               y: (canvas.bounds.height - size.height * scale) / 2 + (point.y + padding) * scale)
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
        model.annotations = [
            EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 30, y: 30), end: CGPoint(x: 70, y: 65), shadow: false),
            EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 120, y: 95), end: CGPoint(x: 165, y: 135), shadow: false),
            EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 235, y: 155), end: CGPoint(x: 270, y: 180), shadow: false)
        ]
        let canvas = AnnotationCanvasView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        canvas.model = model
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        return (model, canvas, window)
    }
}
