import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationToolCompletionTests {
    @Test(arguments: [
        (AnnotationTool.arrow, EditorAnnotation.Kind.arrow),
        (.rectangle, .rectangle),
        (.filledRectangle, .filledRectangle),
        (.ellipse, .ellipse),
        (.line, .line),
        (.freehand, .freehand),
        (.redact, .redaction),
        (.pixelate, .pixelation)
    ])
    func dragCreationReturnsToPointerAndSelectionRemainsStable(
        tool: AnnotationTool,
        kind: EditorAnnotation.Kind
    ) {
        let model = makeModel()
        model.tool = tool
        model.begin(at: CGPoint(x: 40, y: 70))
        model.continueDrag(to: CGPoint(x: 140, y: 130))
        let createdID = model.selectedID
        model.endDrag()

        #expect(model.tool == .select)
        #expect(model.selectedID == createdID)
        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].kind == kind)

        let created = model.annotations[0]
        let midpoint = CGPoint(x: (created.start.x + created.end.x) / 2,
                               y: (created.start.y + created.end.y) / 2)
        model.begin(at: midpoint)
        model.endDrag()
        #expect(model.tool == .select)
        #expect(model.selectedID == createdID)
        #expect(model.annotations == [created])

        model.undo()
        #expect(model.annotations.isEmpty)
        #expect(!model.canUndo)
    }

    @Test
    func stepPlacementReturnsToPointerAndNumbersEachNewStep() {
        let model = makeModel()
        model.tool = .step
        model.begin(at: CGPoint(x: 50, y: 60))
        let firstID = model.annotations.last?.id
        model.endDrag()

        #expect(model.tool == .select)
        #expect(model.selectedID == firstID)
        #expect(model.annotations.map(\.step) == [1])

        model.begin(at: CGPoint(x: 50, y: 60))
        model.endDrag()
        #expect(model.selectedID == firstID)
        #expect(model.annotations.count == 1)

        model.tool = .step
        model.begin(at: CGPoint(x: 100, y: 120))
        let secondID = model.annotations.last?.id
        model.endDrag()

        #expect(model.tool == .select)
        #expect(model.selectedID == secondID)
        #expect(model.annotations.map(\.step) == [1, 2])

        model.undo()
        #expect(model.annotations.map(\.step) == [1])
        model.undo()
        #expect(model.annotations.isEmpty)
        #expect(!model.canUndo)
    }

    @Test
    func cropAppliesOnMouseupAndReturnsToPointer() {
        let model = makeModel()
        model.tool = .crop
        model.begin(at: CGPoint(x: 40, y: 30))
        model.continueDrag(to: CGPoint(x: 160, y: 110))
        model.endDrag()

        #expect(model.tool == .select)
        #expect(model.cropRect == nil)
        #expect(model.pixelSize == NSSize(width: 120, height: 80))
        #expect(model.canUndo)

        model.undo()
        #expect(model.pixelSize == NSSize(width: 400, height: 300))
        #expect(!model.canUndo)
    }

    @Test
    func textDraftSurvivesInitialMouseupAndCommitsOnFinish() {
        let model = makeModel()
        model.tool = .text
        model.begin(at: CGPoint(x: 24, y: 32))
        let textID = model.editingTextID
        model.endDrag()

        #expect(model.tool == .text)
        #expect(model.editingTextID == textID)
        #expect(model.selectedID == textID)

        model.updateText("Committed label")
        model.finishTextEditing()

        #expect(model.tool == .select)
        #expect(model.editingTextID == nil)
        #expect(model.selectedID == textID)
        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].text == "Committed label")
        #expect(model.canUndo)
    }

    @Test
    func choosingAnotherToolFinishesTextWithoutOverridingChoice() {
        let model = makeModel()
        model.tool = .text
        model.begin(at: CGPoint(x: 24, y: 32))
        let textID = model.editingTextID
        model.updateText("Committed label")

        model.tool = .rectangle

        #expect(model.tool == .rectangle)
        #expect(model.editingTextID == nil)
        #expect(model.selectedID == textID)
        #expect(model.annotations.first?.text == "Committed label")
    }

    @Test
    func finishingBlankTextReturnsToPointerWithoutHistory() {
        let model = makeModel()
        model.tool = .text
        model.begin(at: CGPoint(x: 24, y: 32))
        model.endDrag()
        model.finishTextEditing()

        #expect(model.tool == .select)
        #expect(model.editingTextID == nil)
        #expect(model.selectedID == nil)
        #expect(model.annotations.isEmpty)
        #expect(!model.canUndo)
    }

    private func makeModel() -> AnnotationEditorModel {
        let context = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = NSImage(cgImage: context.makeImage()!, size: CGSize(width: 400, height: 300))
        return AnnotationEditorModel(image: image, sourceURL: nil)
    }
}
