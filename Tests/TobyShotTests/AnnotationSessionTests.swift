import AppKit
import Carbon
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationSessionTests {
    @Test func savedSessionReopensWithEditableObjectsCanvasSettingsAndHistory() throws {
        try withCoordinator { app, directory in
            let source = image()
            let editor = app.openEditor(source)
            let model = editor.editorModel
            model.tool = .text
            model.begin(at: CGPoint(x: 20, y: 30))
            model.updateText("Editable label")
            model.finishTextEditing()
            model.updateBackground(style: .lavender)
            model.updateBackground(padding: 48, cornerRadius: 24)
            model.zoom = 2
            model.tool = .rectangle
            model.begin(at: CGPoint(x: 80, y: 70))
            model.continueDrag(to: CGPoint(x: 140, y: 120))
            model.endDrag()
            model.undo()
            let annotations = model.annotations
            #expect(model.canRedo)

            #expect(editor.handleKeyEvent(saveEvent()))
            #expect(editor.window?.isVisible == false)
            #expect(!model.hasUnsavedChanges)
            let item = try #require(app.store.items.first)
            let export = URL(fileURLWithPath: try #require(item.exportedPath))
            #expect(export.deletingLastPathComponent() == directory.appendingPathComponent("Exports"))
            #expect(FileManager.default.fileExists(atPath: export.path))

            app.pasteImage()
            #expect(editor.window?.isVisible == true)
            #expect(model.image === source)
            #expect(model.annotations == annotations)
            #expect(model.background == .lavender)
            #expect(model.padding == 48)
            #expect(model.cornerRadius == 24)
            #expect(model.zoom == 2)
            #expect(model.canUndo)
            #expect(model.canRedo)
            #expect(app.store.items.count == 1)
            model.redo()
            #expect(model.annotations.count == 2)
            model.undo()
            #expect(model.annotations == annotations)
            let text = try #require(model.annotations.first)
            #expect(model.beginTextEditing(text.id))
            model.updateText("Continued label")
            #expect(editor.handleKeyEvent(saveEvent()))
            app.pasteImage()
            #expect(editor.window?.isVisible == true)
            #expect(model.annotations.first?.text == "Continued label")
            #expect(!model.hasUnsavedChanges)
        }
    }

    @Test func savedSessionSurvivesOpeningAnotherEditor() throws {
        try withCoordinator { app, _ in
            let editor = app.openEditor(image())
            #expect(editor.handleKeyEvent(saveEvent()))
            let other = app.openEditor(image())
            other.close()

            app.pasteImage()
            #expect(editor.window?.isVisible == true)
            #expect(other.window?.isVisible == false)
        }
    }

    @Test func copyingANewImageStartsAFreshEditorInsteadOfResumingSavedSession() throws {
        try withCoordinator { app, _ in
            let board = NSPasteboard.general
            let originalItems: [NSPasteboardItem] = board.pasteboardItems?.map { item in
                let copy = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) { copy.setData(data, forType: type) }
                }
                return copy
            } ?? []
            defer { board.clearContents(); board.writeObjects(originalItems) }

            let editor = app.openEditor(image())
            #expect(editor.handleKeyEvent(saveEvent()))
            let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
            board.clearContents()
            #expect(board.writeObjects([image()]))

            app.pasteImage()
            #expect(editor.window?.isVisible == false)
            let newEditors = NSApp.windows.filter {
                !previousWindows.contains(ObjectIdentifier($0)) && $0.title == "Annotate — TobyShot" && $0.isVisible
            }
            #expect(newEditors.count == 1)
        }
    }

    private func withCoordinator(_ body: (AppCoordinator, URL) throws -> Void) throws {
        _ = NSApplication.shared
        Preferences.register()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TobyShot.SessionTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keys = ["exportPath", "askFilename", "imageFormat"]
        let priorValues = keys.map { UserDefaults.standard.object(forKey: $0) }
        let priorWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let name = "TobyShot.SessionShortcuts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let app = AppCoordinator(shortcuts: HotKeyManager(defaults: defaults), store: CaptureStore(directory: directory.appendingPathComponent("Captures")))
        defer {
            app.closeOverlays()
            for window in NSApp.windows where !priorWindows.contains(ObjectIdentifier(window)) { window.close() }
            for (key, value) in zip(keys, priorValues) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        UserDefaults.standard.set(directory.appendingPathComponent("Exports").path, forKey: "exportPath")
        UserDefaults.standard.set(false, forKey: "askFilename")
        UserDefaults.standard.set("PNG", forKey: "imageFormat")
        try body(app, directory)
    }

    private func image() -> NSImage {
        let image = NSImage(size: CGSize(width: 240, height: 180))
        image.lockFocus(); NSColor.white.setFill(); CGRect(x: 0, y: 0, width: 240, height: 180).fill(); image.unlockFocus()
        return image
    }

    private func saveEvent() -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: UInt16(kVK_ANSI_S))!
    }
}
