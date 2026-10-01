import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationArrowEditingTests {
    @Test func placingArrowSelectsItAndAllowsImmediateEndpointEditing() {
        let model = makeModel()
        model.tool = .arrow
        model.begin(at: CGPoint(x: 40, y: 70))
        model.continueDrag(to: CGPoint(x: 240, y: 150))
        let createdID = model.selectedID
        model.endDrag()

        #expect(model.tool == .select)
        #expect(model.selectedID == createdID)
        let created = model.annotations[0]
        #expect(created.kind == .arrow)

        let grab = created.start
        #expect(model.beginArrowEdit(handle: .start, at: grab))
        model.continueDrag(to: CGPoint(x: grab.x - 18, y: grab.y + 12))
        model.endDrag()

        #expect(model.annotations[0].start == CGPoint(x: grab.x - 18, y: grab.y + 12))
        #expect(model.annotations[0].end == created.end)
        #expect(model.selectedID == created.id)
    }

    @Test(arguments: [AnnotationArrowHandle.start, .end])
    func endpointHandleRepositionsOnlyThatEndpoint(handle: AnnotationArrowHandle) {
        var original = arrow()
        original.arrowBend = CGPoint(x: 16, y: -34)
        let model = makeModel(with: original)
        let opposite = handle == .start ? original.end : original.start
        let grab = handle.point(in: original)
        let delta = CGPoint(x: 24, y: -14)
        #expect(model.beginArrowEdit(handle: handle, at: grab))
        model.continueDrag(to: CGPoint(x: grab.x + delta.x, y: grab.y + delta.y))
        model.endDrag()

        var expected = original
        if handle == .start {
            expected.start = CGPoint(x: original.start.x + delta.x, y: original.start.y + delta.y)
        } else {
            expected.end = CGPoint(x: original.end.x + delta.x, y: original.end.y + delta.y)
        }
        expected.arrowBend = CGPoint(x: original.arrowBend.x - delta.x / 2,
                                      y: original.arrowBend.y - delta.y / 2)
        #expect(model.annotations == [expected])
        #expect(handle == .start ? model.annotations[0].end == opposite : model.annotations[0].start == opposite)
    }

    @Test(arguments: [AnnotationArrowHandle.start, .end])
    func endpointDragUsesGrabDeltaAndIsOneUndoableGesture(handle: AnnotationArrowHandle) {
        var original = arrow()
        original.reversed = true
        let model = makeModel(with: original)
        model.markSaved()
        let handlePoint = handle.point(in: original)
        let grabOffset = CGPoint(x: 3, y: -2)
        let grab = CGPoint(x: handlePoint.x + grabOffset.x, y: handlePoint.y + grabOffset.y)
        #expect(model.beginArrowEdit(handle: handle, at: grab))
        model.continueDrag(to: CGPoint(x: grab.x + 8, y: grab.y + 5))
        model.continueDrag(to: CGPoint(x: grab.x + 21, y: grab.y - 11))
        model.endDrag()

        var expected = original
        let delta = CGPoint(x: 21, y: -11)
        if handle == .start {
            expected.start = CGPoint(x: original.start.x + delta.x, y: original.start.y + delta.y)
        } else {
            expected.end = CGPoint(x: original.end.x + delta.x, y: original.end.y + delta.y)
        }
        #expect(model.annotations == [expected])
        #expect(model.hasUnsavedChanges)
        model.undo()
        #expect(model.annotations == [original])
        #expect(!model.hasUnsavedChanges)
        #expect(!model.canUndo)
        #expect(model.canRedo)
        model.redo()
        #expect(model.annotations == [expected])
    }

    @Test(arguments: [AnnotationArrowHandle.start, .end])
    func straightEndpointEditKeepsArrowStraightAndClickPreservesRedo(handle: AnnotationArrowHandle) {
        let original = arrow()
        let model = makeModel(with: original)
        let handlePoint = handle.point(in: original)
        #expect(model.beginArrowEdit(handle: handle, at: handlePoint))
        model.continueDrag(to: CGPoint(x: handlePoint.x + 20, y: handlePoint.y + 10))
        model.endDrag()
        #expect(model.annotations[0].arrowBend == .zero)
        var moved = original
        if handle == .start {
            moved.start = CGPoint(x: original.start.x + 20, y: original.start.y + 10)
        } else {
            moved.end = CGPoint(x: original.end.x + 20, y: original.end.y + 10)
        }
        #expect(model.annotations == [moved])
        model.undo()
        #expect(model.canRedo)

        let restored = model.annotations[0]
        model.selectedID = restored.id
        let clickHandle = handle == .start ? AnnotationArrowHandle.end : .start
        let clickPoint = clickHandle.point(in: restored)
        #expect(model.beginArrowEdit(handle: clickHandle, at: clickPoint))
        model.continueDrag(to: clickPoint)
        model.endDrag()
        #expect(model.annotations == [restored])
        #expect(model.canRedo)
        model.redo()
        #expect(model.annotations == [moved])
    }

    @Test func editingExistingArrowKeepsActiveToolWhileNewArrowCreationSelects() {
        let original = arrow()
        let model = makeModel(with: original)
        model.tool = .arrow
        #expect(model.beginArrowEdit(handle: .end, at: original.end))
        model.continueDrag(to: CGPoint(x: original.end.x + 10, y: original.end.y))
        model.endDrag()
        #expect(model.tool == .arrow)
        #expect(model.selectedID == original.id)

        model.begin(at: CGPoint(x: 60, y: 60))
        model.continueDrag(to: CGPoint(x: 140, y: 90))
        let createdID = model.selectedID
        model.endDrag()
        #expect(model.tool == .select)
        #expect(model.selectedID == createdID)
        #expect(model.annotations.count == 2)
    }

    private func arrow() -> EditorAnnotation {
        EditorAnnotation(kind: .arrow, start: CGPoint(x: 50, y: 100), end: CGPoint(x: 250, y: 100),
            width: 6, reversed: true, arrowStyle: .handDrawn, arrowStroke: .dashed, arrowSeed: 42)
    }

    private func makeModel(with annotation: EditorAnnotation? = nil) -> AnnotationEditorModel {
        let context = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = NSImage(cgImage: context.makeImage()!, size: CGSize(width: 400, height: 300))
        let model = AnnotationEditorModel(image: image, sourceURL: nil)
        if let annotation {
            model.annotations = [annotation]
            model.selectedID = annotation.id
        }
        return model
    }
}
