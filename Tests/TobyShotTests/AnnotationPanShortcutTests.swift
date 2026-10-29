import AppKit
import Carbon
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationPanShortcutTests {
    @Test func spacePressReleaseAndFocusLossDoNotSwitchTools() {
        withEditor { editor in
            editor.editorModel.tool = .arrow
            #expect(editor.handleKeyEvent(space(.keyDown)))
            #expect(editor.editorModel.isPanKeyDown)
            #expect(editor.editorModel.tool == .arrow)
            #expect(editor.handleKeyEvent(space(.keyDown, repeating: true)))
            #expect(editor.handleKeyEvent(space(.keyUp)))
            #expect(!editor.editorModel.isPanKeyDown)
            #expect(editor.editorModel.tool == .arrow)
            #expect(!editor.handleKeyEvent(space(.keyUp)))
            #expect(!editor.handleKeyEvent(space(.keyDown, modifiers: .option)))
            #expect(!editor.editorModel.isPanKeyDown)
            #expect(editor.handleKeyEvent(space(.keyDown)))
            editor.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: editor.window))
            #expect(!editor.editorModel.isPanKeyDown)
            #expect(!editor.editorModel.hasUnsavedChanges)
            #expect(!editor.editorModel.canUndo)
        }
    }

    @Test func spaceTypingAndShortcutRecordingDoNotStartPanning() {
        withEditor { editor in
            let window = editor.window!
            let text = NSTextView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
            window.contentView?.addSubview(text)
            window.makeFirstResponder(text)
            #expect(window.firstResponder === text)
            #expect(!editor.handleKeyEvent(space(.keyDown)))
            #expect(!editor.editorModel.isPanKeyDown)
            #expect(!editor.handleKeyEvent(space(.keyUp)))
            window.makeFirstResponder(nil)
            editor.editorModel.tool = .text
            editor.editorModel.begin(at: CGPoint(x: 30, y: 30))
            #expect(!editor.handleKeyEvent(space(.keyDown)))
            #expect(!editor.editorModel.isPanKeyDown)
        }
    }

    private func withEditor(_ body: (AnnotationEditorWindow) -> Void) {
        _ = NSApplication.shared
        let name = "TobyShot.PanShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let manager = HotKeyManager(defaults: defaults)
        let editor = AnnotationEditorWindow(image: NSImage(size: CGSize(width: 300, height: 200)), sourceURL: nil,
            shortcuts: manager, onSave: { _, _ in true }, onCopy: { _ in }, onPin: { _ in })
        defer { editor.window?.close() }
        body(editor)
        manager.beginRecording()
        #expect(!editor.handleKeyEvent(space(.keyDown)))
        #expect(!editor.editorModel.isPanKeyDown)
        manager.endRecording()
    }

    private func space(_ type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags = [], repeating: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
            context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: repeating, keyCode: UInt16(kVK_Space))!
    }
}
