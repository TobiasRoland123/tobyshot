import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationArrowBendTests {
    @Test func bendingKeepsEndpointsAndAppearanceAndUndoesAsOneGesture() throws {
        let original = arrow()
        let model = model(with: original)
        model.markSaved()
        let handle = original.arrowBendPoint
        #expect(model.beginArrowEdit(handle: .bend, at: handle))
        model.continueDrag(to: CGPoint(x: handle.x + 12, y: handle.y - 25))
        model.continueDrag(to: CGPoint(x: handle.x + 20, y: handle.y - 60))
        model.endDrag()
        var expected = original
        expected.arrowBend = CGPoint(x: 20, y: -60)
        #expect(model.annotations == [expected])
        #expect(model.selectedID == original.id)
        #expect(model.hasUnsavedChanges)
        #expect(model.annotation(at: expected.arrowBendPoint)?.id == original.id)
        #expect(model.renderedSelection() != nil)
        model.undo()
        #expect(model.annotations == [original])
        #expect(!model.hasUnsavedChanges)
        #expect(!model.canUndo)
        model.redo()
        #expect(model.annotations == [expected])
    }

    @Test func clickingHandlePreservesRedoAndNewBendClearsIt() {
        let original = arrow()
        let model = model(with: original)
        #expect(model.beginArrowEdit(handle: .bend, at: original.arrowBendPoint))
        model.continueDrag(to: CGPoint(x: 150, y: 20))
        model.endDrag()
        model.undo()
        model.selectedID = original.id
        #expect(model.beginArrowEdit(handle: .bend, at: original.arrowBendPoint))
        model.continueDrag(to: original.arrowBendPoint)
        model.endDrag()
        #expect(model.canRedo)
        #expect(!model.canUndo)
        #expect(model.annotations == [original])
        #expect(model.beginArrowEdit(handle: .bend, at: original.arrowBendPoint))
        model.continueDrag(to: CGPoint(x: 150, y: 180))
        model.endDrag()
        #expect(!model.canRedo)
    }

    @Test func draggingFromEdgeOfHandleDoesNotJumpAndSupportsRepeatedBends() {
        var original = arrow()
        original.arrowBend = CGPoint(x: 10, y: -30)
        let model = model(with: original)
        let click = CGPoint(x: original.arrowBendPoint.x + 3, y: original.arrowBendPoint.y - 2)
        #expect(model.beginArrowEdit(handle: .bend, at: click))
        model.continueDrag(to: CGPoint(x: click.x + 15, y: click.y + 20))
        model.endDrag()
        let first = model.annotations[0]
        #expect(first.arrowBend == CGPoint(x: 25, y: -10))
        #expect(model.beginArrowEdit(handle: .bend, at: first.arrowBendPoint))
        model.continueDrag(to: original.arrowBendPoint)
        model.endDrag()
        #expect(model.annotations == [original])
        model.undo()
        #expect(model.annotations == [first])
    }

    @Test func straightenIsUndoableAndAlreadyStraightIsANoOp() {
        var original = arrow()
        original.arrowBend = CGPoint(x: 0, y: 50)
        let model = model(with: original)
        model.straightenSelectedArrow()
        #expect(model.annotations[0].arrowBend == .zero)
        #expect(model.selectedID == original.id)
        model.straightenSelectedArrow()
        model.undo()
        #expect(model.annotations == [original])
        #expect(!model.canUndo)
        model.redo()
        #expect(model.annotations[0].arrowBend == .zero)
    }

    @Test func movingDuplicatingAndCroppingPreserveCurve() throws {
        var original = arrow()
        original.arrowBend = CGPoint(x: 10, y: -40)
        let model = model(with: original)
        let before = try ImageOutput.data(#require(model.renderedSelection()), format: "PNG")
        model.begin(at: original.start)
        model.continueDrag(to: CGPoint(x: original.start.x + 20, y: original.start.y + 30))
        model.endDrag()
        let moved = model.annotations[0]
        #expect(moved.start == CGPoint(x: original.start.x + 20, y: original.start.y + 30))
        #expect(moved.arrowBend == original.arrowBend)
        #expect(try ImageOutput.data(#require(model.renderedSelection()), format: "PNG") == before)
        #expect(model.duplicateSelection())
        let copy = model.annotations[1]
        #expect(copy.id != moved.id)
        #expect(copy.arrowBend == moved.arrowBend)
        #expect(try ImageOutput.data(#require(model.renderedSelection()), format: "PNG") == before)
        model.tool = .crop
        model.begin(at: CGPoint(x: 10, y: 10))
        model.continueDrag(to: CGPoint(x: 320, y: 240))
        model.endDrag()
        #expect(model.annotations.count == 2)
        #expect(model.annotations[0].start == CGPoint(x: moved.start.x - 10, y: moved.start.y - 10))
        #expect(model.annotations[0].arrowBend == moved.arrowBend)
        model.selectedID = moved.id
        #expect(try ImageOutput.data(#require(model.renderedSelection()), format: "PNG") == before)
        model.undo()
        #expect(model.annotations == [moved, copy])
    }

    @Test func cropRetainsCurveEvenWhenBothEndpointsAreOutside() {
        var original = arrow()
        original.arrowBend = CGPoint(x: 0, y: -60)
        let model = model(with: original)
        model.tool = .crop
        model.begin(at: CGPoint(x: 130, y: 20))
        model.continueDrag(to: CGPoint(x: 170, y: 60))
        model.endDrag()
        #expect(model.annotations.count == 1)
        #expect(model.annotations.first?.arrowBend == original.arrowBend)
        #expect(model.annotations.first?.arrowBendPoint == CGPoint(x: 20, y: 20))
    }

    @Test func otherToolsAndNonArrowSelectionsCannotEditArrowHandles() {
        let original = arrow()
        let model = model(with: original)
        for tool in [AnnotationTool.text, .rectangle, .freehand, .crop] {
            model.tool = tool
            for handle in AnnotationArrowHandle.allCases {
                #expect(!model.beginArrowEdit(handle: handle, at: handle.point(in: original)))
            }
        }
        model.tool = .arrow
        #expect(model.beginArrowEdit(handle: .bend, at: original.arrowBendPoint))
        model.endDrag()
        var line = original
        line.kind = .line
        model.annotations = [line]
        for tool in [AnnotationTool.select, .arrow] {
            model.tool = tool
            for handle in AnnotationArrowHandle.allCases {
                #expect(!model.beginArrowEdit(handle: handle, at: handle.point(in: line)))
            }
        }
        #expect(!model.canUndo)
    }

    private func arrow() -> EditorAnnotation {
        EditorAnnotation(kind: .arrow, start: CGPoint(x: 50, y: 100), end: CGPoint(x: 250, y: 100),
            width: 6, reversed: true, arrowStyle: .handDrawn, arrowStroke: .dashed, arrowSeed: 42)
    }

    private func model(with annotation: EditorAnnotation) -> AnnotationEditorModel {
        let context = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = NSImage(cgImage: context.makeImage()!, size: CGSize(width: 400, height: 300))
        let model = AnnotationEditorModel(image: image, sourceURL: nil)
        model.annotations = [annotation]
        model.selectedID = annotation.id
        return model
    }
}
