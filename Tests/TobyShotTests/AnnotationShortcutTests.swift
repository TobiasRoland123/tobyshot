import AppKit
import Carbon
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationShortcutTests {
    private func image() -> NSImage {
        let image = NSImage(size: CGSize(width: 240, height: 180))
        image.lockFocus(); NSColor.white.setFill(); CGRect(x: 0, y: 0, width: 240, height: 180).fill(); image.unlockFocus()
        return image
    }

    @Test func duplicatingAnObjectPreservesOriginalAndSupportsUndo() throws {
        let model = AnnotationEditorModel(image: image(), sourceURL: nil)
        let original = EditorAnnotation(kind: .rectangle, start: CGPoint(x: 20, y: 30), end: CGPoint(x: 70, y: 90), color: .red)
        model.annotations = [original]; model.selectedID = original.id
        #expect(model.duplicateSelection())
        let copy = try #require(model.annotations.last)
        #expect(model.annotations.count == 2)
        #expect(model.annotations.first == original)
        #expect(copy.id != original.id)
        #expect(copy.start == CGPoint(x: 32, y: 42))
        #expect(model.selectedID == copy.id)
        model.undo()
        #expect(model.annotations == [original])
        model.redo()
        #expect(model.annotations.count == 2)
    }

    @Test func copiedObjectDoesNotIncludeTheUnderlyingScreenshot() throws {
        let model = AnnotationEditorModel(image: image(), sourceURL: nil)
        let rectangle = EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 30, y: 30), end: CGPoint(x: 80, y: 70), color: .red, shadow: false)
        model.annotations = [rectangle]; model.selectedID = rectangle.id
        let rendered = try #require(model.renderedSelection())
        let bitmap = NSBitmapImageRep(cgImage: try #require(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        #expect(bitmap.pixelsWide < 240)
        #expect(bitmap.pixelsHigh < 180)
        #expect(try #require(bitmap.colorAt(x: 0, y: 0)).alphaComponent == 0)
        let middle = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        #expect(middle.redComponent > 0.9)
        #expect(middle.greenComponent < 0.1)
        #expect(middle.alphaComponent == 1)
    }

    @Test func sizeShortcutsStayWithinSupportedBounds() {
        let model = AnnotationEditorModel(image: image(), sourceURL: nil)
        model.adjustToolSize(by: 1)
        #expect(model.strokeWidth == 6)
        model.adjustToolSize(by: 100)
        #expect(model.strokeWidth == 40)
        model.adjustToolSize(by: -100)
        #expect(model.strokeWidth == 1)
    }

    @Test func saveAndSaveAsStayOpenAndDoneClosesOnlyAfterSuccessfulSave() {
        _ = NSApplication.shared
        let name = "TobyShot.EditorShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let manager = HotKeyManager(defaults: defaults)
        var requestedSaveAs: [Bool] = []
        var succeeds = true
        let editor = AnnotationEditorWindow(image: image(), sourceURL: nil, shortcuts: manager,
            onSave: { _, ask in requestedSaveAs.append(ask); return succeeds }, onCopy: { _ in }, onPin: { _ in })
        let tracking = CloseTrackingWindow()
        editor.window = tracking
        #expect(editor.handleKeyEvent(event(kVK_ANSI_S, modifiers: .command)))
        #expect(editor.handleKeyEvent(event(kVK_ANSI_S, modifiers: [.command, .shift])))
        #expect(requestedSaveAs == [false, true])
        #expect(tracking.closeCount == 0)
        succeeds = false
        #expect(editor.handleKeyEvent(event(kVK_Return, modifiers: .command)))
        #expect(tracking.closeCount == 0)
        succeeds = true
        #expect(editor.handleKeyEvent(event(kVK_Return, modifiers: .command)))
        #expect(tracking.closeCount == 1)
        #expect(!editor.handleKeyEvent(event(kVK_ANSI_Z, modifiers: [.command, .option])))
    }

    private func event(_ code: Int, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: code == kVK_ANSI_Z ? "z" : "s",
            charactersIgnoringModifiers: code == kVK_ANSI_Z ? "z" : "s", isARepeat: false, keyCode: UInt16(code))!
    }
}

@MainActor
private final class CloseTrackingWindow: NSWindow {
    var closeCount = 0
    override func close() { closeCount += 1 }
}
