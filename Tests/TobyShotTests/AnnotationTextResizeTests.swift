import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationTextResizeTests {
    @Test(arguments: AnnotationResizeCorner.allCases)
    func everyCornerKeepsItsOppositeCornerFixedWhileGrowingAndShrinking(corner: AnnotationResizeCorner) {
        let original = textAnnotation()
        let originalBounds = bounds(of: original)
        let anchor = corner.opposite.point(in: originalBounds)
        let handle = corner.point(in: originalBounds)

        let growModel = model(with: original)
        #expect(growModel.beginTextResize(corner: corner, at: handle))
        growModel.continueDrag(to: point(handle, extendedFrom: anchor, by: 0.6))
        growModel.endDrag()
        let grown = growModel.annotations[0]
        #expect(AnnotationTextLayout.fontSize(for: grown) > AnnotationTextLayout.fontSize(for: original))
        #expect(corner.opposite.point(in: growModel.textSelectionBounds(grown)) == anchor)

        let shrinkModel = model(with: original)
        #expect(shrinkModel.beginTextResize(corner: corner, at: handle))
        shrinkModel.continueDrag(to: point(handle, extendedFrom: anchor, by: -0.5))
        shrinkModel.endDrag()
        let shrunk = shrinkModel.annotations[0]
        #expect(AnnotationTextLayout.fontSize(for: shrunk) < AnnotationTextLayout.fontSize(for: original))
        #expect(corner.opposite.point(in: shrinkModel.textSelectionBounds(shrunk)) == anchor)
        #expect(shrunk.text == original.text)
        #expect(shrunk.color == original.color)
        #expect(shrunk.id == original.id)
    }

    @Test(arguments: AnnotationResizeCorner.allCases)
    func fontSizeClampsAtBothBoundsWithoutFlipping(corner: AnnotationResizeCorner) {
        let original = textAnnotation(size: 32)
        let originalBounds = bounds(of: original)
        let anchor = corner.opposite.point(in: originalBounds)
        let handle = corner.point(in: originalBounds)

        let largeModel = model(with: original)
        #expect(largeModel.beginTextResize(corner: corner, at: handle))
        largeModel.continueDrag(to: point(handle, extendedFrom: anchor, by: 20))
        largeModel.endDrag()
        #expect(AnnotationTextLayout.fontSize(for: largeModel.annotations[0]) == 400)
        #expect(corner.opposite.point(in: largeModel.textSelectionBounds(largeModel.annotations[0])) == anchor)

        let smallModel = model(with: original)
        #expect(smallModel.beginTextResize(corner: corner, at: handle))
        smallModel.continueDrag(to: point(handle, extendedFrom: anchor, by: -2))
        smallModel.endDrag()
        #expect(AnnotationTextLayout.fontSize(for: smallModel.annotations[0]) == 8)
        #expect(corner.opposite.point(in: smallModel.textSelectionBounds(smallModel.annotations[0])) == anchor)
    }

    @Test
    func multipleDragUpdatesAreOneUndoableResize() {
        let original = textAnnotation()
        let model = model(with: original)
        let bounds = model.textSelectionBounds(original)
        let corner = AnnotationResizeCorner.bottomRight
        let anchor = corner.opposite.point(in: bounds)
        let handle = corner.point(in: bounds)

        #expect(model.beginTextResize(corner: corner, at: handle))
        model.continueDrag(to: point(handle, extendedFrom: anchor, by: 0.2))
        model.continueDrag(to: point(handle, extendedFrom: anchor, by: 0.8))
        model.endDrag()
        let finalAnnotation = model.annotations[0]
        #expect(AnnotationTextLayout.fontSize(for: finalAnnotation) > AnnotationTextLayout.fontSize(for: original))

        model.undo()
        #expect(model.annotations == [original])
        model.redo()
        #expect(model.annotations == [finalAnnotation])
    }

    @Test
    func liveTextEditFinishesBeforeResizeAndHasItsOwnUndoStep() {
        var original = textAnnotation()
        original.text = "Before edit"
        let model = model(with: original)
        #expect(model.beginTextEditing(original.id))
        model.updateText("Edited label")
        let edited = model.annotations[0]
        let bounds = model.textSelectionBounds(edited)
        let corner = AnnotationResizeCorner.bottomRight
        let anchor = corner.opposite.point(in: bounds)
        let handle = corner.point(in: bounds)

        #expect(model.beginTextResize(corner: corner, at: handle))
        #expect(model.editingTextID == nil)
        model.continueDrag(to: point(handle, extendedFrom: anchor, by: 0.5))
        model.endDrag()
        let resized = model.annotations[0]
        #expect(resized.text == "Edited label")
        #expect(AnnotationTextLayout.fontSize(for: resized) > AnnotationTextLayout.fontSize(for: edited))

        model.undo()
        #expect(model.annotations == [edited])
        model.undo()
        #expect(model.annotations == [original])
    }

    @Test
    func clickOnlyResizePreservesRedoHistory() {
        let original = textAnnotation()
        let model = model(with: original)
        model.beginTextEditing(original.id)
        model.updateText("Redo this edit")
        model.finishTextEditing()
        model.undo()
        #expect(model.canRedo)

        model.selectedID = original.id
        let bounds = model.textSelectionBounds(original)
        let corner = AnnotationResizeCorner.topLeft
        let handle = corner.point(in: bounds)
        #expect(model.beginTextResize(corner: corner, at: handle))
        model.continueDrag(to: handle)
        model.endDrag()

        #expect(model.annotations == [original])
        #expect(model.canRedo)
        model.redo()
        #expect(model.annotations.first?.text == "Redo this edit")
    }

    @Test
    func nonTextSelectionAndDrawingToolRejectResize() {
        let shape = EditorAnnotation(kind: .rectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 70))
        let shapeModel = model(with: shape)
        #expect(!shapeModel.beginTextResize(corner: .bottomRight, at: CGPoint(x: 80, y: 70)))

        let text = textAnnotation()
        let drawingModel = model(with: text)
        drawingModel.tool = .freehand
        let bottomRight = AnnotationResizeCorner.bottomRight.point(in: drawingModel.textSelectionBounds(text))
        #expect(!drawingModel.beginTextResize(corner: .bottomRight, at: bottomRight))
        #expect(drawingModel.annotations == [text])
        #expect(!drawingModel.canUndo)
    }

    private func textAnnotation(size: CGFloat = 28) -> EditorAnnotation {
        var annotation = EditorAnnotation(
            kind: .text,
            start: CGPoint(x: 70, y: 55),
            end: CGPoint(x: 70, y: 55),
            color: .systemBlue,
            text: "Resize this label"
        )
        annotation.textSize = size
        return annotation
    }

    private func bounds(of annotation: EditorAnnotation) -> CGRect {
        let image = NSImage(size: CGSize(width: 400, height: 300))
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        return AnnotationEditorModel(image: image, sourceURL: nil).textSelectionBounds(annotation)
    }

    private func model(with annotation: EditorAnnotation) -> AnnotationEditorModel {
        let image = NSImage(size: CGSize(width: 400, height: 300))
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        let model = AnnotationEditorModel(image: image, sourceURL: nil)
        model.annotations = [annotation]
        model.selectedID = annotation.id
        return model
    }

    private func point(_ handle: CGPoint, extendedFrom anchor: CGPoint, by fraction: CGFloat) -> CGPoint {
        CGPoint(
            x: handle.x + (handle.x - anchor.x) * fraction,
            y: handle.y + (handle.y - anchor.y) * fraction
        )
    }
}
