import AppKit

enum AnnotationArrowHandle: CaseIterable {
    case start, bend, end

    func point(in annotation: EditorAnnotation) -> CGPoint {
        switch self {
        case .start: annotation.start
        case .bend: annotation.arrowBendPoint
        case .end: annotation.end
        }
    }
}

struct AnnotationArrowEdit {
    let original: EditorAnnotation
    let handle: AnnotationArrowHandle
    let start: CGPoint

    func annotation(at point: CGPoint) -> EditorAnnotation {
        let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
        var edited = original
        switch handle {
        case .start:
            edited.start.x += delta.x
            edited.start.y += delta.y
        case .end:
            edited.end.x += delta.x
            edited.end.y += delta.y
        case .bend:
            edited.arrowBend.x += delta.x
            edited.arrowBend.y += delta.y
        }
        // A placed bend stays anchored while either endpoint moves. Straight
        // arrows stay straight and their middle handle follows the new midpoint.
        if handle != .bend, original.arrowBend != .zero {
            edited.arrowBend.x -= delta.x / 2
            edited.arrowBend.y -= delta.y / 2
        }
        return edited
    }
}
