import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationHistoryTests {
    @Test
    func backgroundOnlyEditTracksUndoRedoAndSavedState() {
        let model = makeModel()
        model.updateBackground(style: .lavender)
        #expect(model.background == .lavender)
        #expect(model.hasUnsavedChanges)

        model.undo()
        #expect(model.background == .none)
        #expect(!model.hasUnsavedChanges)
        #expect(model.canRedo)

        model.redo()
        #expect(model.background == .lavender)
        #expect(model.hasUnsavedChanges)
        model.markSaved()
        #expect(!model.hasUnsavedChanges)
    }

    @Test
    func newBackgroundEditAfterUndoClearsStaleRedo() {
        let model = makeModel()
        model.updateBackground(style: .lavender)
        model.tool = .rectangle
        model.begin(at: CGPoint(x: 10, y: 20))
        model.continueDrag(to: CGPoint(x: 60, y: 80))
        model.endDrag()

        model.undo()
        #expect(model.annotations.isEmpty)
        #expect(model.background == .lavender)

        model.updateBackground(style: .peach)
        #expect(!model.canRedo)
        model.redo()
        #expect(model.background == .peach)
        #expect(model.annotations.isEmpty)
    }

    @Test
    func removingBackgroundUndoAndRedoRestoresBothValues() {
        let model = makeModel()
        model.updateBackground(style: .lavender)
        model.updateBackground(style: .none)
        #expect(model.background == AnnotationBackground.none)

        model.undo()
        #expect(model.background == .lavender)
        model.redo()
        #expect(model.background == AnnotationBackground.none)
    }

    @Test(arguments: [
        ("padding", CGFloat(36), CGFloat(52)),
        ("cornerRadius", CGFloat(18), CGFloat(30))
    ])
    func paddingAndRadiusChangesUndoAndRedo(property: String, initial: CGFloat, changed: CGFloat) {
        let model = makeModel()
        if property == "padding" {
            model.updateBackground(padding: changed)
        } else {
            model.updateBackground(cornerRadius: changed)
        }
        #expect(property == "padding" ? model.padding == changed : model.cornerRadius == changed)
        model.undo()
        #expect(property == "padding" ? model.padding == initial : model.cornerRadius == initial)
        model.redo()
        #expect(property == "padding" ? model.padding == changed : model.cornerRadius == changed)
    }

    @Test
    func sliderValuesInOneGestureUndoTogetherAndSeparateGesturesRemainSeparate() {
        let model = makeModel()
        model.setBackgroundEditing(true)
        model.updateBackground(padding: 40)
        model.updateBackground(padding: 48)
        model.updateBackground(cornerRadius: 24)
        model.setBackgroundEditing(false)

        model.undo()
        #expect(model.padding == 36)
        #expect(model.cornerRadius == 18)
        model.redo()
        #expect(model.padding == 48)
        #expect(model.cornerRadius == 24)

        model.setBackgroundEditing(true)
        model.updateBackground(padding: 50)
        model.setBackgroundEditing(false)
        model.setBackgroundEditing(true)
        model.updateBackground(padding: 54)
        model.setBackgroundEditing(false)
        model.undo()
        #expect(model.padding == 50)
        model.undo()
        #expect(model.padding == 48)
    }

    @Test(arguments: [
        ("padding", CGFloat(36), CGFloat(40), CGFloat(48)),
        ("cornerRadius", CGFloat(18), CGFloat(22), CGFloat(28))
    ])
    func repeatedSliderValuesInOneGestureUndoAsOneStep(property: String, initial: CGFloat, first: CGFloat, final: CGFloat) {
        let model = makeModel()
        model.setBackgroundEditing(true)
        if property == "padding" {
            model.updateBackground(padding: first)
            model.updateBackground(padding: final)
        } else {
            model.updateBackground(cornerRadius: first)
            model.updateBackground(cornerRadius: final)
        }
        model.setBackgroundEditing(false)

        model.undo()
        #expect(property == "padding" ? model.padding == initial : model.cornerRadius == initial)
        model.redo()
        #expect(property == "padding" ? model.padding == final : model.cornerRadius == final)
    }

    @Test
    func noOpUpdatesAndGesturesPreserveRedo() {
        let model = makeModel()
        model.updateBackground(style: .lavender)
        model.undo()
        model.updateBackground(style: .none)
        model.setBackgroundEditing(true)
        model.updateBackground(padding: 36)
        model.setBackgroundEditing(false)
        #expect(model.canRedo)
        model.redo()
        #expect(model.background == .lavender)
    }

    @Test
    func zoomIsOutsideUndoHistory() {
        let model = makeModel()
        model.updateBackground(style: .lavender)
        model.zoom = 2
        model.undo()
        #expect(model.background == .none)
        #expect(model.zoom == 2)
        model.redo()
        #expect(model.background == .lavender)
        #expect(model.zoom == 2)
    }

    @Test
    func historyActionDuringSliderEditEndsGroupingBeforeLaterEdit() {
        let model = makeModel()
        model.updateBackground(style: .lavender)
        model.setBackgroundEditing(true)
        model.updateBackground(padding: 44)
        model.undo()
        model.updateBackground(padding: 52)

        #expect(model.background == .lavender)
        #expect(model.padding == 52)
        #expect(!model.canRedo)
        model.redo()
        #expect(model.background == .lavender)
        #expect(model.padding == 52)
        model.undo()
        #expect(model.padding == 36)
    }

    private func makeModel() -> AnnotationEditorModel {
        let image = NSImage(size: CGSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        return AnnotationEditorModel(image: image, sourceURL: nil)
    }
}
