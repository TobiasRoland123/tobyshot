import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationTextEditingTests {
    @Test
    func newTextDraftTypingCommitsAsOneUndoableChange() {
        let model = makeModel()
        model.tool = .text

        model.begin(at: CGPoint(x: 24, y: 32))
        let draftID = model.editingTextID
        #expect(draftID != nil)
        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].text.isEmpty)

        model.updateText("First line")
        model.updateText("Finished label")
        #expect(model.annotations[0].text == "Finished label")
        model.finishTextEditing()

        #expect(model.editingTextID == nil)
        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].id == draftID)
        #expect(model.annotations[0].text == "Finished label")
        #expect(model.canUndo)

        model.undo()
        #expect(model.annotations.isEmpty)
        model.redo()
        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].text == "Finished label")
    }

    @Test
    func clickingExistingTextWithTextToolOpensItInsteadOfCreatingAnother() {
        let model = makeModel()
        let existing = textAnnotation("Existing label", at: CGPoint(x: 24, y: 32))
        model.annotations = [existing]
        model.tool = .text

        model.begin(at: existing.start)

        #expect(model.editingTextID == existing.id)
        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].id == existing.id)
    }

    @Test
    func beginTextEditingUpdatesExistingTextAndUndoRestoresOriginal() throws {
        let model = makeModel()
        let existing = textAnnotation("Original", at: CGPoint(x: 24, y: 32))
        model.annotations = [existing]

        #expect(model.beginTextEditing(existing.id))
        model.updateText("Revised")
        #expect(model.annotations[0].text == "Revised")
        model.finishTextEditing()

        model.undo()
        #expect(model.annotations == [existing])
        model.redo()
        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].text == "Revised")
        #expect(!model.beginTextEditing(UUID()))
    }

    @Test
    func whitespaceOnlyEditRemovesExistingTextAndUndoRestoresIt() {
        let model = makeModel()
        let existing = textAnnotation("Keep me", at: CGPoint(x: 24, y: 32))
        model.annotations = [existing]

        #expect(model.beginTextEditing(existing.id))
        model.updateText(" \n\t ")
        model.finishTextEditing()

        #expect(model.annotations.isEmpty)
        model.undo()
        #expect(model.annotations == [existing])
        model.redo()
        #expect(model.annotations.isEmpty)
    }

    @Test
    func whitespaceOnlyNewDraftIsRemovedWithoutAddingHistory() {
        let model = makeModel()
        model.tool = .text

        model.begin(at: CGPoint(x: 24, y: 32))
        model.updateText("  \n\t")
        model.finishTextEditing()

        #expect(model.annotations.isEmpty)
        #expect(model.editingTextID == nil)
        #expect(!model.canUndo)
    }

    @Test
    func finishingUntouchedDraftPreservesRedo() {
        let model = makeModel()
        model.tool = .text
        model.begin(at: CGPoint(x: 24, y: 32))
        model.updateText("Redo target")
        model.finishTextEditing()
        model.undo()
        #expect(model.canRedo)

        model.tool = .text
        model.begin(at: CGPoint(x: 48, y: 56))
        model.finishTextEditing()

        #expect(model.annotations.isEmpty)
        #expect(model.canRedo)
        model.redo()
        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].text == "Redo target")
    }

    @Test
    func reopeningAndFinishingUnchangedTextPreservesRedo() {
        let model = makeModel()
        let existing = textAnnotation("Unchanged", at: CGPoint(x: 24, y: 32))
        model.annotations = [existing]
        model.tool = .text
        model.begin(at: existing.start)
        model.updateText("Newer")
        model.finishTextEditing()
        model.undo()
        #expect(model.canRedo)

        #expect(model.beginTextEditing(existing.id))
        model.finishTextEditing()

        #expect(model.canRedo)
        #expect(model.annotations == [existing])
        model.redo()
        #expect(model.annotations[0].text == "Newer")
    }

    @Test
    func changingToolFinishesEditingAndUndoRevertsTheTextChange() {
        let model = makeModel()
        let existing = textAnnotation("Before", at: CGPoint(x: 24, y: 32))
        model.annotations = [existing]
        #expect(model.beginTextEditing(existing.id))
        model.updateText("After")

        model.tool = .select

        #expect(model.editingTextID == nil)
        #expect(model.annotations[0].text == "After")
        model.undo()
        #expect(model.annotations == [existing])
    }

    @Test
    func renderedImageIncludesLiveTextBeforeEditingFinishes() throws {
        let model = makeModel()
        let unannotated = try ImageOutput.data(model.renderedImage(), format: "PNG")
        model.tool = .text
        model.begin(at: CGPoint(x: 24, y: 32))
        model.updateText("Visible while editing")

        let liveExport = try ImageOutput.data(model.renderedImage(), format: "PNG")

        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].text == "Visible while editing")
        #expect(liveExport != unannotated)
    }

    private func makeModel() -> AnnotationEditorModel {
        let image = NSImage(size: CGSize(width: 120, height: 100))
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 120, height: 100).fill()
        image.unlockFocus()
        return AnnotationEditorModel(image: image, sourceURL: nil)
    }

    private func textAnnotation(_ text: String, at point: CGPoint) -> EditorAnnotation {
        EditorAnnotation(kind: .text, start: point, end: point, text: text)
    }
}
