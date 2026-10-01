import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationCanvasTextTests {
    @Test func typingOnCanvasUpdatesModelAndReturnFinishesEditing() throws {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.tool = .text
        model.begin(at: CGPoint(x: 40, y: 50))
        canvas.synchronizeTextEditor()
        let editor = try #require(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        #expect(window.firstResponder === editor)
        #expect(!editor.drawsBackground)
        #expect(editor.frame.width < 200)
        editor.insertText("Inline label", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(model.annotations.first?.text == "Inline label")
        #expect(editor.frame.width > 40)
        #expect(canvas.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(model.editingTextID == nil)
        #expect(model.tool == .select)
        #expect(canvas.subviews.isEmpty)
        model.undo()
        #expect(model.annotations.isEmpty)
    }

    @Test func nativeSelectionReplacementAndMultilinePasteStayInSync() throws {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        let annotation = EditorAnnotation(kind: .text, start: CGPoint(x: 50, y: 40), end: .zero, text: "Before")
        model.annotations = [annotation]
        model.beginTextEditing(annotation.id)
        canvas.synchronizeTextEditor()
        let editor = try #require(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        let singleLineHeight = editor.bounds.height
        editor.selectAll(nil)
        editor.insertText("Édited\nSecond line 😀", replacementRange: editor.selectedRange())
        #expect(model.annotations.first?.text == "Édited\nSecond line 😀")
        #expect(editor.bounds.height > singleLineHeight * 1.5)
        #expect(editor.frame.width < 500)
        #expect(canvas.textView(editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        model.undo()
        #expect(model.annotations == [annotation])
    }

    @Test func activeTextFollowsZoomAndStyleWithoutChangingItsPosition() throws {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.tool = .text
        model.begin(at: CGPoint(x: 40, y: 50))
        canvas.synchronizeTextEditor()
        let editor = try #require(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        editor.insertText("Zoom", replacementRange: NSRange(location: NSNotFound, length: 0))
        let initialSize = editor.frame.size
        model.zoom = 2
        canvas.synchronizeTextEditor()
        #expect(editor.frame.width == initialSize.width * 2)
        #expect(editor.frame.height == initialSize.height * 2)
        #expect(editor.bounds.size == initialSize)
        #expect(window.firstResponder === editor)
        model.color = .systemBlue
        model.strokeWidth = 10
        canvas.synchronizeTextEditor()
        #expect(editor.font?.pointSize == 50)
        #expect(editor.textColor == NSColor.systemBlue)
        #expect(model.annotations.first?.start == CGPoint(x: 40, y: 50))
        model.tool = .select
        canvas.synchronizeTextEditor()
        #expect(canvas.subviews.isEmpty)
        #expect(model.annotations.first?.text == "Zoom")
    }

    @Test(arguments: [CGFloat(0.5), 1, 2])
    func draggingTextCornerWhileEditingResizesAtEveryZoom(zoom: CGFloat) throws {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.zoom = zoom
        let original = EditorAnnotation(kind: .text, start: CGPoint(x: 80, y: 60), end: CGPoint(x: 80, y: 60), text: "Resize")
        model.annotations = [original]
        model.beginTextEditing(original.id)
        canvas.synchronizeTextEditor()
        let editor = try #require(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        editor.insertText(" me", replacementRange: NSRange(location: NSNotFound, length: 0))
        let selection = model.textSelectionBounds(try #require(model.annotations.first))
        let handle = CGPoint(x: (canvas.bounds.width - model.pixelSize.width * zoom) / 2 + selection.maxX * zoom + 4,
                             y: (canvas.bounds.height - model.pixelSize.height * zoom) / 2 + selection.maxY * zoom + 4)
        #expect(canvas.hitTest(canvas.convert(handle, to: canvas.superview)) === canvas)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: handle, canvas: canvas, window: window))
        #expect(model.editingTextID == nil)
        #expect(canvas.subviews.isEmpty)
        let destination = CGPoint(x: handle.x + selection.width * zoom / 2, y: handle.y + selection.height * zoom / 2)
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: destination, canvas: canvas, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: destination, canvas: canvas, window: window))
        let resized = try #require(model.annotations.first)
        #expect(abs(AnnotationTextLayout.fontSize(for: resized) - 37.5) < 0.001)
        #expect(resized.start == original.start)
        #expect(resized.text == "Resize me")
        #expect(model.annotations.count == 1)
        model.undo()
        #expect(model.annotations.first?.text == "Resize me")
        #expect(model.annotations.first?.textSize == nil)
        model.undo()
        #expect(model.annotations == [original])
    }

    @Test(arguments: [CGFloat(0), 0.5, 1, 2])
    func drawingOutsideCanvasKeepsDragCoordinatesStableUntilRelease(zoom: CGFloat) throws {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.zoom = zoom
        model.tool = .line
        let originalBounds = canvas.layoutCanvasBounds
        let start = CGPoint(x: -10, y: 40)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: viewPoint(start, model: model, canvas: canvas), canvas: canvas, window: window))
        for end in [CGPoint(x: -20, y: -15), CGPoint(x: -30, y: -25)] {
            canvas.mouseDragged(with: mouse(.leftMouseDragged, at: viewPoint(end, model: model, canvas: canvas), canvas: canvas, window: window))
            canvas.synchronizeTextEditor()
            #expect(canvas.layoutCanvasBounds == originalBounds)
            let annotation = try #require(model.annotations.first)
            #expect(abs(annotation.start.x - start.x) < 0.001)
            #expect(abs(annotation.end.x - end.x) < 0.001)
            #expect(abs(annotation.end.y - end.y) < 0.001)
        }
        canvas.mouseUp(with: mouse(.leftMouseUp, at: .zero, canvas: canvas, window: window))
        #expect(canvas.layoutCanvasBounds == model.canvasBounds)
        #expect(canvas.layoutCanvasBounds.minX < -30)
        #expect(canvas.layoutCanvasBounds.minY < -25)

        // Hit testing uses the expanded canvas's translated origin on the next gesture.
        model.tool = .select
        canvas.synchronizeTextEditor()
        let hit = viewPoint(start, model: model, canvas: canvas)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: hit, canvas: canvas, window: window))
        #expect(model.selectedID == model.annotations.first?.id)
        canvas.mouseUp(with: mouse(.leftMouseUp, at: hit, canvas: canvas, window: window))
    }

    @Test func textCanStartOutsideCanvasAndKeepsItsInsertionPointSteady() throws {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.tool = .text
        let originalBounds = canvas.layoutCanvasBounds
        let start = CGPoint(x: -20, y: -20)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: viewPoint(start, model: model, canvas: canvas), canvas: canvas, window: window))
        let editor = try #require(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        let origin = editor.frame.origin
        editor.insertText("Outside\ncanvas", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.frame.origin == origin)
        #expect(canvas.layoutCanvasBounds == originalBounds)
        #expect(model.annotations.first?.start == start)
        #expect(model.renderedImage().size.width > model.pixelSize.width)
        #expect(canvas.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(canvas.layoutCanvasBounds == model.canvasBounds)
    }

    @Test(arguments: [AnnotationTool.crop, .pixelate])
    func sourceOnlyToolsStillRequireAStartInsideTheImage(tool: AnnotationTool) {
        let (model, canvas, window) = makeCanvas()
        defer { window.close() }
        model.tool = tool
        let start = viewPoint(CGPoint(x: -10, y: -10), model: model, canvas: canvas)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, canvas: canvas, window: window))
        #expect(model.annotations.isEmpty)
        #expect(model.cropRect == nil)
    }

    private func viewPoint(_ point: CGPoint, model: AnnotationEditorModel, canvas: AnnotationCanvasView) -> CGPoint {
        let bounds = canvas.layoutCanvasBounds
        let scale = model.zoom == 0 ? min((canvas.bounds.width - 48) / bounds.width, (canvas.bounds.height - 48) / bounds.height) : model.zoom
        return CGPoint(x: (canvas.bounds.width - bounds.width * scale) / 2 + (point.x - bounds.minX) * scale,
                       y: (canvas.bounds.height - bounds.height * scale) / 2 + (point.y - bounds.minY) * scale)
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, canvas: NSView, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func makeCanvas() -> (AnnotationEditorModel, AnnotationCanvasView, NSWindow) {
        _ = NSApplication.shared
        let context = CGContext(data: nil, width: 500, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 500, height: 300))
        let image = NSImage(cgImage: context.makeImage()!, size: CGSize(width: 500, height: 300))
        let model = AnnotationEditorModel(image: image, sourceURL: nil)
        model.zoom = 1
        let canvas = AnnotationCanvasView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        canvas.model = model
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        return (model, canvas, window)
    }
}
