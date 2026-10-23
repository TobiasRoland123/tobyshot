import AppKit
import Carbon
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationCanvasImageTests {
    @Test func pasteRequiresCanvasFocusAndLeavesNativeTextPasteAlone() {
        withClipboard {
            let (editor, canvas, window) = makeEditor()
            defer { window.close() }
            let model = editor.editorModel
            let board = NSPasteboard.general
            board.clearContents()
            board.writeObjects([image(width: 80, height: 40)])
            let paste = key("v", code: kVK_ANSI_V)
            #expect(editor.handleKeyEvent(paste))
            #expect(model.annotations.count == 1)
            #expect(model.annotations.first?.kind == .image)
            #expect(model.selectedID == model.annotations.first?.id)

            let text = NSTextView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
            canvas.addSubview(text)
            window.makeFirstResponder(text)
            #expect(!editor.handleKeyEvent(paste))
            board.clearContents()
            board.setString("Native text paste", forType: .string)
            text.paste(nil)
            #expect(text.string == "Native text paste")
            #expect(model.annotations.count == 1)

            window.makeFirstResponder(canvas)
            #expect(!editor.handleKeyEvent(paste))
            board.clearContents()
            board.writeObjects([image(width: 80, height: 40)])
            window.makeFirstResponder(nil)
            #expect(!editor.handleKeyEvent(paste))
            #expect(model.annotations.count == 1)
        }
    }

    @Test func pastedObjectCopyDuplicateAndAllExportActionsKeepPixels() throws {
        try withClipboard {
            var exports: [NSImage] = []
            let (editor, canvas, window) = makeEditor(onExport: { exports.append($0) })
            defer { window.close() }
            let model = editor.editorModel
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image(width: 80, height: 40)])
            #expect(editor.handleKeyEvent(key("v", code: kVK_ANSI_V)))
            let original = try #require(model.annotations.first)
            #expect(editor.handleKeyEvent(key("c", code: kVK_ANSI_C)))
            let copied = try #require(AnnotationClipboard.image())
            #expect(copied.width == 80 && copied.height == 40)
            #expect(editor.handleKeyEvent(key("d", code: kVK_ANSI_D)))
            #expect(model.annotations.count == 2)
            #expect(model.annotations[0] == original)
            #expect(model.annotations[1].id != original.id)
            #expect(model.annotations[1].image === original.image)

            // Place the duplicate beside the original screenshot and export through each action.
            model.annotations[1].start = CGPoint(x: 200, y: 0)
            model.annotations[1].end = CGPoint(x: 280, y: 40)
            window.makeFirstResponder(canvas)
            #expect(editor.handleKeyEvent(key("c", code: kVK_ANSI_C, modifiers: [.command, .shift])))
            #expect(editor.handleKeyEvent(key("s", code: kVK_ANSI_S, modifiers: [.command, .shift])))
            #expect(editor.handleKeyEvent(key("p", code: kVK_ANSI_P, modifiers: [.command, .shift])))
            #expect(exports.count == 3)
            for output in exports {
                let pixels = try #require(output.cgImage(forProposedRect: nil, context: nil, hints: nil))
                #expect(pixels.width == 280 && pixels.height == 120)
                let color = try #require(NSBitmapImageRep(cgImage: pixels).colorAt(x: 240, y: 20)?.usingColorSpace(.deviceRGB))
                #expect(color.blueComponent > 0.9 && color.alphaComponent == 1)
            }
        }
    }

    @Test func canvasRoutesImageHandlesMovementAndDrawingAtDifferentZooms() throws {
        for zoom in [CGFloat(0), 0.5, 2] {
            let (editor, canvas, window) = makeEditor()
            defer { window.close() }
            let model = editor.editorModel
            model.zoom = zoom
            let pixels = try #require(image(width: 80, height: 40).cgImage(forProposedRect: nil, context: nil, hints: nil))
            let pasted = EditorAnnotation(kind: .image, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 120, y: 80), image: pixels)
            model.annotations = [pasted]
            model.selectedID = pasted.id
            drag(from: pasted.end, to: CGPoint(x: 160, y: 100), canvas: canvas, window: window)
            #expect(model.annotations[0].start == pasted.start)
            #expect(abs(model.annotations[0].end.x - 160) < 0.001)
            #expect(abs(model.annotations[0].end.y - 100) < 0.001)
            drag(from: CGPoint(x: 80, y: 60), to: CGPoint(x: 260, y: -20), canvas: canvas, window: window)
            #expect(abs(model.annotations[0].start.x - 220) < 0.001)
            #expect(abs(model.annotations[0].start.y + 40) < 0.001)
            #expect(model.canvasBounds.maxX > model.pixelSize.width)
            #expect(model.canvasBounds.minY < 0)

            model.tool = .arrow
            #expect(canvas.pointerTarget(at: canvas.viewPoint(CGPoint(x: 240, y: -20))) == .canvas)
            drag(from: CGPoint(x: 240, y: -20), to: CGPoint(x: 100, y: 80), canvas: canvas, window: window)
            #expect(model.annotations.map(\.kind) == [.image, .arrow])
            #expect(abs(model.annotations[1].start.x - 240) < 0.001)
            #expect(abs(model.annotations[1].start.y + 20) < 0.001)
            model.tool = .pixelate
            model.clearSelection()
            drag(from: CGPoint(x: 280, y: -10), to: CGPoint(x: 320, y: 10), canvas: canvas, window: window)
            #expect(model.annotations.map(\.kind) == [.image, .arrow, .pixelation])
            #expect(abs(model.annotations[2].end.x - 320) < 0.001)
            #expect(abs(model.annotations[2].end.y - 10) < 0.001)
        }
    }

    private func makeEditor(onExport: @escaping (NSImage) -> Void = { _ in }) -> (AnnotationEditorWindow, AnnotationCanvasView, NSWindow) {
        _ = NSApplication.shared
        let name = "TobyShot.ImageShortcuts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let shortcuts = HotKeyManager(defaults: defaults)
        let pin = ShortcutBinding(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | shiftKey))
        #expect(shortcuts.setShortcut(pin, for: .editorPin) == nil)
        let editor = AnnotationEditorWindow(image: image(width: 200, height: 120), sourceURL: nil, shortcuts: shortcuts,
            onSave: { image, _ in onExport(image); return true }, onCopy: onExport, onPin: onExport)
        // Avoid automatic clipboard publication while testing explicit keyboard commands.
        editor.editorModel.onImageChange = nil
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let canvas = AnnotationCanvasView(frame: CGRect(x: 0, y: 0, width: 700, height: 500))
        canvas.model = editor.editorModel
        window.contentView = canvas
        editor.window = window
        window.makeFirstResponder(canvas)
        return (editor, canvas, window)
    }

    private func image(width: Int, height: Int) -> NSImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSImage(cgImage: context.makeImage()!, size: CGSize(width: width, height: height))
    }

    private func key(_ characters: String, code: Int, modifiers: NSEvent.ModifierFlags = .command) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code))!
    }

    private func drag(from start: CGPoint, to end: CGPoint, canvas: AnnotationCanvasView, window: NSWindow) {
        canvas.synchronizeTextEditor()
        for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
            let event = NSEvent.mouseEvent(with: type, location: canvas.convert(canvas.viewPoint(point), to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
    }

    private func withClipboard(_ body: () throws -> Void) rethrows {
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer { board.clearContents(); board.writeObjects(saved) }
        try body()
    }
}
