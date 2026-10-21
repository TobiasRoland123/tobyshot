import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationToolCompletionTests {
    static let dragTools: [(AnnotationTool, EditorAnnotation.Kind)] = [
        (.arrow, .arrow), (.rectangle, .rectangle), (.filledRectangle, .filledRectangle), (.ellipse, .ellipse),
        (.line, .line), (.freehand, .freehand), (.redact, .redaction), (.pixelate, .pixelation)
    ]

    @Test(arguments: dragTools)
    func repeatedCreationKeepsDrawingToolActive(tool: AnnotationTool, kind: EditorAnnotation.Kind) {
        let model = makeModel()
        model.tool = tool
        model.begin(at: CGPoint(x: 40, y: 70))
        model.continueDrag(to: CGPoint(x: 140, y: 130))
        let firstID = model.selectedID
        model.endDrag()

        #expect(model.tool == tool)
        #expect(model.selectedID == firstID)

        model.begin(at: CGPoint(x: 200, y: 180))
        model.continueDrag(to: CGPoint(x: 320, y: 260))
        let secondID = model.selectedID
        model.endDrag()

        #expect(model.tool == tool)
        #expect(secondID != firstID)
        #expect(model.selectedID == secondID)
        #expect(model.annotations.map(\.kind) == [kind, kind])
        #expect(model.annotations[1].end == CGPoint(x: 320, y: 260))

        model.undo()
        #expect(model.annotations.map(\.id) == [firstID])
        model.undo()
        #expect(model.annotations.isEmpty)
        #expect(!model.canUndo)
    }

    @Test(arguments: dragTools)
    func gestureOnVisibleAnnotationMovesItWithoutChangingTool(tool: AnnotationTool, kind: EditorAnnotation.Kind) throws {
        let model = makeModel()
        model.tool = tool
        model.begin(at: CGPoint(x: 40, y: 70))
        model.continueDrag(to: CGPoint(x: 140, y: 130))
        model.endDrag()
        let created = try #require(model.annotations.first)
        model.selectedID = nil

        // The outline of an outlined shape is its left edge here; other kinds pass through the center.
        let grab = kind == .rectangle || kind == .ellipse ? CGPoint(x: 40, y: 100) : CGPoint(x: 90, y: 100)
        model.begin(at: grab)
        model.continueDrag(to: CGPoint(x: grab.x + 10, y: grab.y + 5))
        model.endDrag()

        #expect(model.tool == tool)
        #expect(model.annotations.count == 1)
        #expect(model.selectedID == created.id)
        #expect(model.annotations[0].start == CGPoint(x: 50, y: 75))
        #expect(model.annotations[0].end == CGPoint(x: 150, y: 135))
        model.undo()
        #expect(model.annotations == [created])
    }

    @Test(arguments: [EditorAnnotation.Kind.rectangle, .ellipse])
    func emptyInteriorOfOutlinedShapeStartsNewAnnotation(kind: EditorAnnotation.Kind) {
        let model = makeModel()
        let outlined = EditorAnnotation(kind: kind, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 240, y: 200))
        model.annotations = [outlined]
        model.tool = .arrow
        model.begin(at: CGPoint(x: 140, y: 120))
        model.continueDrag(to: CGPoint(x: 200, y: 160))
        model.endDrag()

        #expect(model.annotations.count == 2)
        #expect(model.annotations[0] == outlined)
        #expect(model.annotations[1].kind == .arrow)
        #expect(model.annotations[1].start == CGPoint(x: 140, y: 120))
        #expect(model.tool == .arrow)
    }

    @Test func emptySpaceBesideDiagonalArrowStartsNewArrow() {
        let model = makeModel()
        let diagonal = EditorAnnotation(kind: .arrow, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 240, y: 240))
        model.annotations = [diagonal]
        model.tool = .arrow
        // Inside the arrow's bounds, but far from its shaft.
        model.begin(at: CGPoint(x: 200, y: 60))
        model.continueDrag(to: CGPoint(x: 260, y: 100))
        model.endDrag()

        #expect(model.annotations.count == 2)
        #expect(model.annotations[0] == diagonal)
        #expect(model.annotations[1].start == CGPoint(x: 200, y: 60))
    }

    @Test func drawingAcrossAnnotationsNeverMovesThem() {
        let model = makeModel()
        let filled = EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 200, y: 200))
        let arrow = EditorAnnotation(kind: .arrow, start: CGPoint(x: 250, y: 40), end: CGPoint(x: 250, y: 260))
        model.annotations = [filled, arrow]
        model.tool = .arrow
        model.begin(at: CGPoint(x: 20, y: 150))
        model.continueDrag(to: CGPoint(x: 150, y: 150))
        model.continueDrag(to: CGPoint(x: 330, y: 150))
        model.endDrag()

        #expect(model.annotations.count == 3)
        #expect(Array(model.annotations.prefix(2)) == [filled, arrow])
        #expect(model.annotations[2].end == CGPoint(x: 330, y: 150))
    }

    @Test func handleEditsOfUnselectedAnnotationsKeepToolAndStaySeparatelyUndoable() {
        let model = makeModel()
        let rectangle = EditorAnnotation(kind: .rectangle, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 140, y: 100))
        let arrow = EditorAnnotation(kind: .arrow, start: CGPoint(x: 60, y: 200), end: CGPoint(x: 260, y: 200))
        model.annotations = [rectangle, arrow]
        model.tool = .arrow

        #expect(model.beginShapeEdit(rectangle.id, handle: .corner(.bottomRight), at: rectangle.end))
        model.continueDrag(to: CGPoint(x: 180, y: 130))
        model.endDrag()
        #expect(model.annotations[0].end == CGPoint(x: 180, y: 130))
        #expect(model.selectedID == rectangle.id)

        #expect(model.beginArrowEdit(arrow.id, handle: .bend, at: arrow.arrowBendPoint))
        model.continueDrag(to: CGPoint(x: 160, y: 170))
        model.endDrag()
        #expect(model.annotations[1].arrowBend == CGPoint(x: 0, y: -30))
        #expect(model.selectedID == arrow.id)

        model.begin(at: CGPoint(x: 300, y: 40))
        model.continueDrag(to: CGPoint(x: 360, y: 80))
        model.endDrag()
        #expect(model.annotations.count == 3)
        #expect(model.tool == .arrow)

        model.undo()
        #expect(model.annotations.count == 2)
        model.undo()
        #expect(model.annotations[1] == arrow)
        model.undo()
        #expect(model.annotations == [rectangle, arrow])
        #expect(!model.canUndo)
    }

    @Test
    func stepPlacementKeepsToolAndNumbersEachNewStep() {
        let model = makeModel()
        model.tool = .step
        model.begin(at: CGPoint(x: 50, y: 60))
        let firstID = model.annotations.last?.id
        model.endDrag()

        #expect(model.tool == .step)
        #expect(model.selectedID == firstID)
        #expect(model.annotations.map(\.step) == [1])

        // Clicking an existing step targets it instead of placing another.
        model.begin(at: CGPoint(x: 50, y: 60))
        model.endDrag()
        #expect(model.selectedID == firstID)
        #expect(model.annotations.count == 1)

        model.begin(at: CGPoint(x: 100, y: 120))
        let secondID = model.annotations.last?.id
        model.endDrag()
        model.begin(at: CGPoint(x: 160, y: 180))
        model.endDrag()

        #expect(model.tool == .step)
        #expect(model.selectedID != secondID)
        #expect(model.annotations.map(\.step) == [1, 2, 3])

        model.undo()
        #expect(model.annotations.map(\.step) == [1, 2])
        model.undo()
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
    func textCommitsOnFinishAndKeepsTextToolForTheNextLabel() {
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

        #expect(model.tool == .text)
        #expect(model.editingTextID == nil)
        #expect(model.selectedID == textID)
        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].text == "Committed label")

        model.begin(at: CGPoint(x: 40, y: 220))
        model.updateText("Second label")
        model.finishTextEditing()
        #expect(model.annotations.map(\.text) == ["Committed label", "Second label"])
        #expect(model.tool == .text)

        // Clicking an existing label edits it.
        model.begin(at: CGPoint(x: 30, y: 40))
        #expect(model.editingTextID == textID)
        model.finishTextEditing()
        #expect(model.annotations.count == 2)

        model.undo()
        #expect(model.annotations.count == 1)
        model.undo()
        #expect(model.annotations.isEmpty)
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
    func finishingBlankTextKeepsTextToolWithoutHistory() {
        let model = makeModel()
        model.tool = .text
        model.begin(at: CGPoint(x: 24, y: 32))
        model.endDrag()
        model.finishTextEditing()

        #expect(model.tool == .text)
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
