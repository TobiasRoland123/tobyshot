import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationDrawingConstraintTests {
    @Test(arguments: [AnnotationTool.line, .arrow])
    func constrainedLinesSnapTo45DegreeAngles(tool: AnnotationTool) throws {
        let start = CGPoint(x: 100, y: 100)
        for (delta, expectedAngle) in [
            (CGPoint(x: 80, y: 30), CGFloat(0)), (CGPoint(x: 80, y: 70), CGFloat(45)),
            (CGPoint(x: -30, y: 80), CGFloat(90)), (CGPoint(x: -80, y: 70), CGFloat(135)),
            (CGPoint(x: -80, y: -30), CGFloat(-180)), (CGPoint(x: -80, y: -70), CGFloat(-135)),
            (CGPoint(x: 30, y: -80), CGFloat(-90)), (CGPoint(x: 80, y: -70), CGFloat(-45))
        ] {
            let model = makeModel()
            model.tool = tool
            model.begin(at: start)
            model.continueDrag(to: CGPoint(x: start.x + delta.x, y: start.y + delta.y), constrained: true)
            let annotation = try #require(model.annotations.first)
            let angle = atan2(annotation.end.y - start.y, annotation.end.x - start.x) * 180 / .pi
            #expect(abs(angle - expectedAngle) < 0.001 || abs(angle - expectedAngle) > 359.999)
            #expect(abs(hypot(annotation.end.x - start.x, annotation.end.y - start.y) - hypot(delta.x, delta.y)) < 0.001)
            #expect((annotation.end.x - start.x) * delta.x >= 0)
            #expect((annotation.end.y - start.y) * delta.y >= 0)
        }
        let zero = makeModel()
        zero.tool = tool
        zero.begin(at: start)
        zero.continueDrag(to: start, constrained: true)
        #expect(try #require(zero.annotations.first).end == start)
    }

    @Test(arguments: [AnnotationTool.rectangle, .filledRectangle, .ellipse])
    func constrainedShapesPreserveQuadrantAndUseSquareDeltas(tool: AnnotationTool) throws {
        let start = CGPoint(x: 100, y: 100)
        for delta in [CGPoint(x: 80, y: 30), CGPoint(x: -30, y: 80), CGPoint(x: -80, y: -30), CGPoint(x: 30, y: -80)] {
            let model = makeModel()
            model.tool = tool
            model.begin(at: start)
            model.continueDrag(to: CGPoint(x: start.x + delta.x, y: start.y + delta.y), constrained: true)
            let end = try #require(model.annotations.first).end
            #expect(abs(abs(end.x - start.x) - max(abs(delta.x), abs(delta.y))) < 0.001)
            #expect(abs(abs(end.y - start.y) - max(abs(delta.x), abs(delta.y))) < 0.001)
            #expect((end.x - start.x) * delta.x >= 0)
            #expect((end.y - start.y) * delta.y >= 0)
        }
        let zero = makeModel()
        zero.tool = tool
        zero.begin(at: start)
        zero.continueDrag(to: start, constrained: true)
        #expect(try #require(zero.annotations.first).end == start)
    }

    @Test func unconstrainedDrawingRemainsFreeAndTogglingUsesSameRawPoint() throws {
        let start = CGPoint(x: 40, y: 50), raw = CGPoint(x: 121, y: 83)
        let model = makeModel()
        model.tool = .rectangle
        model.begin(at: start)
        model.continueDrag(to: raw)
        #expect(try #require(model.annotations.first).end == raw)
        model.continueDrag(to: raw, constrained: true)
        let constrainedEnd = try #require(model.annotations.first).end
        #expect(abs(abs(constrainedEnd.x - start.x) - abs(constrainedEnd.y - start.y)) < 0.001)
        model.continueDrag(to: raw, constrained: false)
        #expect(try #require(model.annotations.first).end == raw)
        model.endDrag()
        #expect(model.annotations.count == 1)
        model.undo()
        #expect(model.annotations.isEmpty)
        #expect(!model.canUndo)
        model.redo()
        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].end == raw)
    }

    @Test(arguments: [CGFloat(0), 0.5, 1, 2], [AnnotationTool.line, .arrow, .rectangle, .filledRectangle, .ellipse])
    func canvasTracksShiftChangesAtStationaryPointer(zoom: CGFloat, tool: AnnotationTool) throws {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.zoom = zoom
        model.tool = tool
        let start = CGPoint(x: 50, y: 50), raw = CGPoint(x: 131, y: 89)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, model: model, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: raw, model: model, canvas: canvas, window: window))
        let initial = try #require(model.annotations.first)
        expectPoint(initial.end, equals: raw)
        let expected = tool == .line || tool == .arrow
            ? CGPoint(x: start.x + hypot(raw.x - start.x, raw.y - start.y) / sqrt(2),
                      y: start.y + hypot(raw.x - start.x, raw.y - start.y) / sqrt(2))
            : CGPoint(x: 131, y: 131)
        canvas.flagsChanged(with: flags(.shift, window: window))
        expectPoint(try #require(model.annotations.first).end, equals: expected)
        canvas.flagsChanged(with: flags([], window: window))
        expectPoint(try #require(model.annotations.first).end, equals: raw)
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: raw, modifiers: .shift, model: model, canvas: canvas, window: window))
        expectPoint(try #require(model.annotations.first).end, equals: expected)
        canvas.mouseUp(with: mouse(.leftMouseUp, at: raw, modifiers: .shift, model: model, canvas: canvas, window: window))
        let finished = try #require(model.annotations.first)
        expectPoint(finished.end, equals: expected)
        #expect(finished.id == initial.id)
        #expect(model.tool == .select)
        canvas.flagsChanged(with: flags([], window: window))
        #expect(model.annotations == [finished])
        #expect(model.annotations.count == 1)
        model.undo()
        #expect(model.annotations.isEmpty)
        #expect(!model.canUndo)
        model.redo()
        #expect(model.annotations == [finished])
    }

    @Test(arguments: [false, true])
    func mouseUpUsesFinalShiftStateAndLastDrawingPoint(shiftOnRelease: Bool) throws {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.tool = .rectangle
        let start = CGPoint(x: 50, y: 50), raw = CGPoint(x: 131, y: 89)
        let initialModifiers: NSEvent.ModifierFlags = shiftOnRelease ? [] : .shift
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, modifiers: initialModifiers, model: model, canvas: canvas, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: raw, modifiers: initialModifiers, model: model, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 220, y: 170), modifiers: shiftOnRelease ? .shift : [], model: model, canvas: canvas, window: window))
        expectPoint(try #require(model.annotations.first).end, equals: shiftOnRelease ? CGPoint(x: 131, y: 131) : raw)
    }

    private func expectPoint(_ actual: CGPoint, equals expected: CGPoint) {
        #expect(abs(actual.x - expected.x) < 0.001)
        #expect(abs(actual.y - expected.y) < 0.001)
    }

    private func makeModel() -> AnnotationEditorModel {
        let context = CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return AnnotationEditorModel(image: NSImage(cgImage: context.makeImage()!, size: CGSize(width: 300, height: 200)), sourceURL: nil)
    }

    private func makeCanvas() -> (AnnotationEditorModel, AnnotationCanvasView, NSWindow) {
        _ = NSApplication.shared
        let model = makeModel()
        model.zoom = 1
        let canvas = AnnotationCanvasView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        canvas.model = model
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        return (model, canvas, window)
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

    private func flags(_ modifiers: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 56)!
    }
}
