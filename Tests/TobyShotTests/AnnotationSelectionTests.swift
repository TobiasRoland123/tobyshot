import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationSelectionTests {
    @Test
    func reverseMarqueeSelectsEveryIntersectingAnnotation() {
        let model = makeModel()
        let first = rectangle(x: 20, y: 20, width: 20, height: 20)
        let partial = rectangle(x: 55, y: 25, width: 30, height: 20)
        let outside = rectangle(x: 100, y: 20, width: 18, height: 18)
        model.annotations = [first, partial, outside]
        model.tool = .select

        model.begin(at: CGPoint(x: 70, y: 60))
        model.continueDrag(to: CGPoint(x: 30, y: 15))

        #expect(model.selectionRect == CGRect(x: 30, y: 15, width: 40, height: 45))
        #expect(model.selectedIDs == [first.id, partial.id])
        model.endDrag()
        #expect(model.selectionRect == nil)
        #expect(model.selectedIDs == [first.id, partial.id])
    }

    @Test
    func marqueeUsesTextSelectionBoundsAndCanSelectDisjointItems() {
        let model = makeModel()
        let left = rectangle(x: 12, y: 18, width: 14, height: 14)
        let text = EditorAnnotation(kind: .text, start: CGPoint(x: 65, y: 24), end: CGPoint(x: 65, y: 24), text: "A longer label")
        let right = rectangle(x: 112, y: 18, width: 14, height: 14)
        model.annotations = [left, text, right]
        model.tool = .select

        model.begin(at: .zero)
        model.continueDrag(to: CGPoint(x: 140, y: 50))
        model.endDrag()

        #expect(model.selectedIDs == [left.id, text.id, right.id])
    }

    @Test
    func selectionChangesDoNotDirtyCreateHistoryOrDiscardRedo() {
        let model = makeModel()
        let item = rectangle(x: 30, y: 30, width: 20, height: 20)
        model.annotations = [item]
        model.markSaved()
        model.updateBackground(style: .peach)
        model.undo()
        #expect(model.canRedo)

        model.begin(at: CGPoint(x: 5, y: 5))
        model.continueDrag(to: CGPoint(x: 55, y: 55))
        model.endDrag()

        #expect(!model.hasUnsavedChanges)
        #expect(!model.canUndo)
        #expect(model.canRedo)
        model.redo()
        #expect(model.background == .peach)
        #expect(model.annotations == [item])
    }

    @Test
    func draggingSelectedGroupMovesAllItemsAndFreehandPointsAsOneUndoStep() {
        let model = makeModel()
        let first = rectangle(x: 20, y: 20, width: 20, height: 20)
        var ink = EditorAnnotation(kind: .freehand, start: CGPoint(x: 70, y: 30), end: CGPoint(x: 82, y: 42))
        ink.points = [CGPoint(x: 70, y: 30), CGPoint(x: 76, y: 36), CGPoint(x: 82, y: 42)]
        model.annotations = [first, ink]
        model.selectedIDs = [first.id, ink.id]
        model.tool = .select

        model.begin(at: CGPoint(x: 24, y: 24))
        model.continueDrag(to: CGPoint(x: 34, y: 39))
        model.endDrag()
        #expect(model.annotations[0].start == CGPoint(x: 30, y: 35))
        #expect(model.annotations[1].points == [CGPoint(x: 80, y: 45), CGPoint(x: 86, y: 51), CGPoint(x: 92, y: 57)])

        model.undo()
        #expect(model.annotations == [first, ink])
        model.redo()
        #expect(model.annotations[0].start == CGPoint(x: 30, y: 35))
        #expect(model.annotations[1].points.last == CGPoint(x: 92, y: 57))
    }

    @Test
    func deleteAndDuplicateOperateOnTheWholeSelection() {
        let model = makeModel()
        let first = rectangle(x: 20, y: 20, width: 20, height: 20)
        let middle = rectangle(x: 60, y: 20, width: 20, height: 20)
        let last = rectangle(x: 100, y: 20, width: 20, height: 20)
        model.annotations = [first, middle, last]
        model.selectedIDs = [first.id, last.id]

        #expect(model.duplicateSelection())
        #expect(model.annotations.count == 5)
        let copies = Array(model.annotations.suffix(2))
        #expect(copies.map(\.start) == [CGPoint(x: 32, y: 32), CGPoint(x: 112, y: 32)])
        #expect(Set(copies.map(\.id)).count == 2)
        #expect(model.selectedIDs == Set(copies.map(\.id)))
        model.undo()
        #expect(model.annotations == [first, middle, last])

        model.selectedIDs = [first.id, last.id]
        model.deleteSelection()
        #expect(model.annotations == [middle])
        model.undo()
        #expect(model.annotations == [first, middle, last])
    }

    @Test
    func selectedIDGetterSetterPreserveSingleSelectionCompatibility() {
        let model = makeModel()
        let first = rectangle(x: 20, y: 20, width: 20, height: 20)
        let second = rectangle(x: 60, y: 20, width: 20, height: 20)

        model.selectedID = first.id
        #expect(model.selectedIDs == [first.id])
        #expect(model.selectedID == first.id)
        model.selectedIDs = [first.id, second.id]
        #expect(model.selectedID == nil)
        model.selectedID = second.id
        #expect(model.selectedIDs == [second.id])
        model.selectedID = nil
        #expect(model.selectedIDs.isEmpty)
    }

    @Test
    func shiftClickTogglesAndShiftBlankMarqueeAddsToSelection() {
        let model = makeModel()
        let first = rectangle(x: 20, y: 20, width: 20, height: 20)
        let second = rectangle(x: 70, y: 20, width: 20, height: 20)
        let third = rectangle(x: 120, y: 20, width: 20, height: 20)
        model.annotations = [first, second, third]
        model.selectedIDs = [first.id]
        model.tool = .select

        model.begin(at: CGPoint(x: 75, y: 25), extendingSelection: true)
        model.endDrag()
        #expect(model.selectedIDs == [first.id, second.id])
        model.begin(at: CGPoint(x: 75, y: 25), extendingSelection: true)
        model.endDrag()
        #expect(model.selectedIDs == [first.id])

        model.begin(at: CGPoint(x: 105, y: 5), extendingSelection: true)
        model.continueDrag(to: CGPoint(x: 145, y: 55))
        model.endDrag()
        #expect(model.selectedIDs == [first.id, third.id])
    }

    @Test
    func renderedSelectionIncludesOnlySelectedItemsOnTransparentBackground() throws {
        let model = makeModel()
        let first = EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 40, y: 40), color: .red, shadow: false)
        let middle = EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 45, y: 20), end: CGPoint(x: 65, y: 40), color: .green, shadow: false)
        let second = EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 70, y: 20), end: CGPoint(x: 90, y: 40), color: .blue, shadow: false)
        model.annotations = [first, middle, second]

        #expect(model.renderedSelection() == nil)
        model.selectedIDs = [first.id, second.id]
        let groupImage = try #require(model.renderedSelection())
        let bitmap = NSBitmapImageRep(cgImage: try #require(groupImage.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        #expect(bitmap.pixelsWide == 72)
        #expect(bitmap.pixelsHigh == 22)
        let left = try #require(bitmap.colorAt(x: 11, y: 11)?.usingColorSpace(.deviceRGB))
        let right = try #require(bitmap.colorAt(x: 61, y: 11)?.usingColorSpace(.deviceRGB))
        #expect(left.redComponent > 0.9 && left.blueComponent < 0.1 && left.alphaComponent == 1)
        #expect(right.blueComponent > 0.9 && right.redComponent < 0.1 && right.alphaComponent == 1)
        #expect(try #require(bitmap.colorAt(x: 36, y: 11)).alphaComponent == 0)
        #expect(try #require(bitmap.colorAt(x: 0, y: 0)).alphaComponent == 0)
        model.selectedIDs = []
        #expect(model.renderedSelection() == nil)
    }

    private func rectangle(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> EditorAnnotation {
        EditorAnnotation(kind: .rectangle, start: CGPoint(x: x, y: y), end: CGPoint(x: x + width, y: y + height), shadow: false)
    }

    private func makeModel() -> AnnotationEditorModel {
        let image = NSImage(size: CGSize(width: 180, height: 120))
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 180, height: 120).fill()
        image.unlockFocus()
        return AnnotationEditorModel(image: image, sourceURL: nil)
    }
}
