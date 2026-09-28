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

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, canvas: NSView, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func makeCanvas() -> (AnnotationEditorModel, AnnotationCanvasView, NSWindow) {
        _ = NSApplication.shared
        let image = NSImage(size: CGSize(width: 500, height: 300))
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 500, height: 300).fill()
        image.unlockFocus()
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
