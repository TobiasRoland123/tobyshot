import AppKit
import Testing
@testable import TobyShot

struct AnnotationShapeEditingTests {
    @Test
    func handlesMatchEditableShapeKinds() {
        let line = annotation(.line)
        #expect(AnnotationShapeHandle.handles(for: line) == [.start, .end])
        for kind: EditorAnnotation.Kind in [.rectangle, .filledRectangle, .ellipse, .freehand, .step, .redaction, .pixelation] {
            #expect(AnnotationShapeHandle.handles(for: annotation(kind)).count == 4)
        }
        #expect(AnnotationShapeHandle.handles(for: annotation(.arrow)).isEmpty)
        #expect(AnnotationShapeHandle.handles(for: annotation(.text)).isEmpty)
    }

    @Test(arguments: AnnotationResizeCorner.allCases)
    func shapeCornerResizeKeepsOppositeCornerFixed(corner: AnnotationResizeCorner) {
        for kind: EditorAnnotation.Kind in [.rectangle, .filledRectangle, .ellipse, .redaction, .pixelation] {
            let original = annotation(kind)
            let bounds = AnnotationShapeEdit.bounds(for: original)
            let anchor = corner.opposite.point(in: bounds)
            let handlePoint = corner.point(in: bounds)
            let edit = AnnotationShapeEdit(original: original, handle: .corner(corner), start: handlePoint)
            let resized = edit.annotation(at: CGPoint(x: handlePoint.x + 18, y: handlePoint.y + 12))
            #expect(corner.opposite.point(in: AnnotationShapeEdit.bounds(for: resized)) == anchor)
            #expect(resized.id == original.id)
            #expect(resized.color == original.color)
            #expect(resized.width == original.width)
        }
    }

    @Test
    func reversedRectangleKeepsEndpointOrientationAndClampsWithoutCrossing() {
        var original = annotation(.rectangle)
        original.start = CGPoint(x: 140, y: 110)
        original.end = CGPoint(x: 40, y: 30)
        let corner = AnnotationResizeCorner.topLeft
        let initialHandle = corner.point(in: AnnotationShapeEdit.bounds(for: original))
        let edit = AnnotationShapeEdit(original: original, handle: .corner(corner), start: initialHandle)
        let resized = edit.annotation(at: CGPoint(x: 500, y: 500))

        #expect(resized.start.x > resized.end.x)
        #expect(resized.start.y > resized.end.y)
        #expect(AnnotationShapeEdit.bounds(for: resized).width == 1)
        #expect(AnnotationShapeEdit.bounds(for: resized).height == 1)
        #expect(AnnotationResizeCorner.bottomRight.point(in: AnnotationShapeEdit.bounds(for: resized)) == CGPoint(x: 140, y: 110))
    }

    @Test
    func lineEndpointsMoveIndependentlyByDragDelta() {
        let original = annotation(.line)
        let startEdit = AnnotationShapeEdit(original: original, handle: .start, start: original.start)
        let movedStart = startEdit.annotation(at: CGPoint(x: 22, y: 15))
        #expect(movedStart.start == CGPoint(x: 22, y: 15))
        #expect(movedStart.end == original.end)

        let endEdit = AnnotationShapeEdit(original: original, handle: .end, start: original.end)
        let movedEnd = endEdit.annotation(at: CGPoint(x: 110, y: 82))
        #expect(movedEnd.end == CGPoint(x: 110, y: 82))
        #expect(movedEnd.start == original.start)
    }

    @Test
    func freehandBoundsAndResizeScaleEveryStoredPointAndEndpoints() {
        var original = annotation(.freehand)
        original.points = [CGPoint(x: 20, y: 30), CGPoint(x: 60, y: 50), CGPoint(x: 100, y: 70)]
        original.start = CGPoint(x: 22, y: 31)
        original.end = CGPoint(x: 98, y: 68)
        let bounds = AnnotationShapeEdit.bounds(for: original)
        #expect(bounds == CGRect(x: 20, y: 30, width: 80, height: 40))
        let corner = AnnotationResizeCorner.bottomRight
        let handlePoint = corner.point(in: bounds)
        let resized = AnnotationShapeEdit(original: original, handle: .corner(corner), start: handlePoint)
            .annotation(at: CGPoint(x: handlePoint.x + 80, y: handlePoint.y + 40))

        #expect(corner.opposite.point(in: AnnotationShapeEdit.bounds(for: resized)) == CGPoint(x: 20, y: 30))
        #expect(resized.points == [CGPoint(x: 20, y: 30), CGPoint(x: 100, y: 70), CGPoint(x: 180, y: 110)])
        #expect(resized.start == CGPoint(x: 24, y: 32))
        #expect(resized.end == CGPoint(x: 176, y: 106))
        #expect(resized.width == original.width)
    }

    @Test
    func freehandDegenerateAxesHaveOnePointLogicalExtent() {
        var original = annotation(.freehand)
        original.points = [CGPoint(x: 40, y: 50), CGPoint(x: 40, y: 80)]
        let bounds = AnnotationShapeEdit.bounds(for: original)
        #expect(bounds.width == 1)
        #expect(bounds.height == 30)
    }

    @Test
    func verticalFreehandResizesWithFiniteCoordinatesAndFixedOppositeCorner() {
        var original = annotation(.freehand)
        original.points = [CGPoint(x: 40, y: 50), CGPoint(x: 40, y: 80)]
        original.start = original.points[0]
        original.end = original.points[1]
        let bounds = AnnotationShapeEdit.bounds(for: original)
        let corner = AnnotationResizeCorner.bottomRight
        let handlePoint = corner.point(in: bounds)
        let anchor = corner.opposite.point(in: bounds)
        let resized = AnnotationShapeEdit(original: original, handle: .corner(corner), start: handlePoint)
            .annotation(at: CGPoint(x: handlePoint.x + 20, y: handlePoint.y + 30))
        let resizedBounds = AnnotationShapeEdit.bounds(for: resized)

        #expect(corner.opposite.point(in: resizedBounds) == anchor)
        #expect(resized.points == [CGPoint(x: 40, y: 50), CGPoint(x: 40, y: 110)])
        #expect((resized.points + [resized.start, resized.end]).allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @Test
    func horizontalFreehandResizesWithFiniteCoordinatesAndFixedOppositeCorner() {
        var original = annotation(.freehand)
        original.points = [CGPoint(x: 50, y: 40), CGPoint(x: 80, y: 40)]
        original.start = original.points[0]
        original.end = original.points[1]
        let bounds = AnnotationShapeEdit.bounds(for: original)
        let corner = AnnotationResizeCorner.bottomRight
        let handlePoint = corner.point(in: bounds)
        let anchor = corner.opposite.point(in: bounds)
        let resized = AnnotationShapeEdit(original: original, handle: .corner(corner), start: handlePoint)
            .annotation(at: CGPoint(x: handlePoint.x + 30, y: handlePoint.y + 20))
        let resizedBounds = AnnotationShapeEdit.bounds(for: resized)

        #expect(corner.opposite.point(in: resizedBounds) == anchor)
        #expect(resized.points == [CGPoint(x: 50, y: 40), CGPoint(x: 110, y: 40)])
        #expect((resized.points + [resized.start, resized.end]).allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @Test
    func clickOffsetIsNoOpAndUpdatesRemainRelativeToOriginal() {
        let original = annotation(.ellipse)
        let corner = AnnotationResizeCorner.bottomRight
        let handlePoint = corner.point(in: AnnotationShapeEdit.bounds(for: original))
        let dragStart = CGPoint(x: handlePoint.x + 4, y: handlePoint.y - 3)
        let edit = AnnotationShapeEdit(original: original, handle: .corner(corner), start: dragStart)
        #expect(edit.annotation(at: dragStart) == original)

        let first = edit.annotation(at: CGPoint(x: dragStart.x + 10, y: dragStart.y + 8))
        let later = edit.annotation(at: CGPoint(x: dragStart.x + 20, y: dragStart.y + 16))
        #expect(first.end == CGPoint(x: original.end.x + 10, y: original.end.y + 8))
        #expect(later.end == CGPoint(x: original.end.x + 20, y: original.end.y + 16))
    }

    @Test(arguments: AnnotationResizeCorner.allCases)
    func stepResizesUniformlyAndKeepsOppositeCornerFixed(corner: AnnotationResizeCorner) {
        var original = annotation(.step)
        original.width = 10
        original.step = 7
        let bounds = AnnotationShapeEdit.bounds(for: original)
        #expect(bounds.width == 70)
        #expect(bounds.height == 70)
        let anchor = corner.opposite.point(in: bounds)
        let handlePoint = corner.point(in: bounds)
        let dragged = CGPoint(x: handlePoint.x + (handlePoint.x - anchor.x) * 0.5,
                              y: handlePoint.y + (handlePoint.y - anchor.y) * 0.5)
        let resized = AnnotationShapeEdit(original: original, handle: .corner(corner), start: handlePoint)
            .annotation(at: dragged)
        let resizedBounds = AnnotationShapeEdit.bounds(for: resized)

        #expect(abs(resizedBounds.width - 105) < 0.0001)
        #expect(abs(resizedBounds.height - 105) < 0.0001)
        #expect(corner.opposite.point(in: resizedBounds) == anchor)
        #expect(resized.step == original.step)
        #expect(resized.width == 15)
        #expect(resized.id == original.id)
    }

    @Test
    func stepMinimumRadiusMatchesRendererAndClickPreservesExactOriginal() {
        var original = annotation(.step)
        original.width = 1
        let bounds = AnnotationShapeEdit.bounds(for: original)
        #expect(bounds.width == 30)
        let corner = AnnotationResizeCorner.bottomRight
        let handlePoint = corner.point(in: bounds)
        let edit = AnnotationShapeEdit(original: original, handle: .corner(corner), start: handlePoint)
        #expect(edit.annotation(at: handlePoint) == original)

        #expect(edit.annotation(at: CGPoint(x: handlePoint.x - 100, y: handlePoint.y - 100)) == original)
        #expect(edit.annotation(at: CGPoint(x: handlePoint.x + 10, y: handlePoint.y - 10)) == original)

        let shrunk = edit.annotation(at: CGPoint(x: handlePoint.x - 100, y: handlePoint.y - 100))
        #expect(AnnotationShapeEdit.bounds(for: shrunk).width == 30)
        #expect(AnnotationShapeEdit.bounds(for: shrunk).height == 30)
    }

    private func annotation(_ kind: EditorAnnotation.Kind) -> EditorAnnotation {
        EditorAnnotation(kind: kind, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 90, y: 70),
                         color: .systemBlue, width: 6, step: 3)
    }
}
