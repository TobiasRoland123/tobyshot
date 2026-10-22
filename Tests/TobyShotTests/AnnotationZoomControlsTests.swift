import AppKit
import Carbon
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationZoomControlsTests {
    @Test func zoomModelClampsStepsAndKeepsFitSeparate() {
        let model = makeModel()

        #expect(model.zoom == 0)
        #expect(model.actualZoom == 1)
        model.zoomIn()
        #expect(model.zoom == 1.25)
        model.zoomOut()
        #expect(model.zoom == 1)

        model.setZoom(.infinity)
        #expect(model.zoom == 1)
        model.setZoom(0.01)
        #expect(model.zoom == AnnotationEditorModel.minimumZoom)
        model.setZoom(100)
        #expect(model.zoom == AnnotationEditorModel.maximumZoom)

        model.fitToWindow()
        model.updateFitZoom(0.05)
        #expect(model.zoom == 0)
        #expect(model.actualZoom == 0.05)
        model.zoomOut()
        #expect(model.zoom == 0)
        model.zoomIn()
        #expect(model.zoom == AnnotationEditorModel.minimumZoom)
        model.fitToWindow()
        #expect(model.zoom == 0)
        #expect(model.actualZoom == 0.05)
    }

    @Test func zoomDoesNotChangeAnnotationHistoryDirtyStateOrRenderedPixels() throws {
        let model = makeModel()
        model.tool = .rectangle
        model.begin(at: CGPoint(x: 12, y: 10))
        model.continueDrag(to: CGPoint(x: 58, y: 42))
        model.endDrag()
        #expect(model.annotations.count == 1)
        model.markSaved()
        model.updateBackground(style: .lavender)
        model.undo()
        #expect(model.canRedo)
        var imageChangeCount = 0
        model.onImageChange = { _ in imageChangeCount += 1 }
        let originalExport = try bitmapSnapshot(model.renderedImage())

        model.setZoom(2)
        model.zoomIn()
        model.zoomOut()
        model.updateFitZoom(0.75)
        model.fitToWindow()

        let zoomedExport = try bitmapSnapshot(model.renderedImage())
        #expect(!model.hasUnsavedChanges)
        #expect(model.canRedo)
        #expect(imageChangeCount == 0)
        #expect(zoomedExport.width == originalExport.width)
        #expect(zoomedExport.height == originalExport.height)
        #expect(zoomedExport.pixels == originalExport.pixels)
        #expect(model.annotations.count == 1)
        model.redo()
        #expect(model.background == .lavender)
        #expect(model.hasUnsavedChanges)
    }

    @Test func zoomCommandsWorkDuringTextEditingAndLeaveTypingAndCopyAlone() {
        _ = NSApplication.shared
        let suiteName = "TobyShot.ZoomShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = HotKeyManager(defaults: defaults)
        let editor = AnnotationEditorWindow(image: image(), sourceURL: nil, shortcuts: manager,
            onSave: { _, _ in true }, onCopy: { _ in }, onPin: { _ in })
        let window = CloseTrackingWindow()
        let textView = NSTextView(frame: .zero)
        window.contentView = NSView(frame: .zero)
        window.contentView?.addSubview(textView)
        editor.window = window
        window.makeFirstResponder(textView)

        #expect(!editor.handleKeyEvent(event(kVK_ANSI_T, characters: "t", modifiers: [])))
        #expect(!editor.handleKeyEvent(event(kVK_ANSI_C, characters: "c", modifiers: .command)))
        // Danish layouts can produce '+' from a different physical key than ANSI Equal.
        #expect(editor.handleKeyEvent(event(kVK_ANSI_Minus, characters: "+", modifiers: [.command, .shift])))
        #expect(editor.editorModel.zoom == 1.25)
        #expect(editor.handleKeyEvent(event(kVK_ANSI_1, characters: "1", modifiers: .command)))
        #expect(editor.editorModel.zoom == 1)
        #expect(editor.handleKeyEvent(event(kVK_ANSI_0, characters: "0", modifiers: .command)))
        #expect(editor.editorModel.zoom == 0)
        #expect(editor.handleKeyEvent(event(kVK_ANSI_Minus, characters: "-", modifiers: .command)))
        #expect(editor.editorModel.zoom == 0.8)
        #expect(!editor.handleKeyEvent(event(kVK_ANSI_C, characters: "c", modifiers: .command)))

        manager.beginRecording()
        #expect(!editor.handleKeyEvent(event(kVK_ANSI_1, characters: "1", modifiers: .command)))
        #expect(editor.editorModel.zoom == 0.8)
        manager.endRecording()
    }

    @Test func configuredEditorShortcutKeepsPrecedenceOverZoomCommand() {
        _ = NSApplication.shared
        let suiteName = "TobyShot.ZoomShortcutPrecedenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = HotKeyManager(defaults: defaults)
        let custom = ShortcutBinding(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey))
        #expect(manager.setShortcut(custom, for: .editorPin) == nil)
        var pinCount = 0
        let editor = AnnotationEditorWindow(image: image(), sourceURL: nil, shortcuts: manager,
            onSave: { _, _ in true }, onCopy: { _ in }, onPin: { _ in pinCount += 1 })

        #expect(editor.handleKeyEvent(event(kVK_ANSI_1, characters: "1", modifiers: .command)))
        #expect(pinCount == 1)
        #expect(editor.editorModel.zoom == 0)
    }

    private func makeModel() -> AnnotationEditorModel {
        AnnotationEditorModel(image: image(), sourceURL: nil)
    }

    private func image() -> NSImage {
        let image = NSImage(size: CGSize(width: 80, height: 60))
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 80, height: 60).fill()
        image.unlockFocus()
        return image
    }

    private func bitmapSnapshot(_ image: NSImage) throws -> (width: Int, height: Int, pixels: Data) {
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let bytes = try #require(bitmap.bitmapData)
        let pixels = Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        return (bitmap.pixelsWide, bitmap.pixelsHigh, pixels)
    }

    private func event(_ code: Int, characters: String, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code))!
    }
}

@MainActor
private final class CloseTrackingWindow: NSWindow {}
