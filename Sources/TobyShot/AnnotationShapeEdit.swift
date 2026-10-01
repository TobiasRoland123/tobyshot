import AppKit

enum AnnotationShapeHandle: Equatable {
    case start, end, corner(AnnotationResizeCorner)

    static func handles(for annotation: EditorAnnotation) -> [Self] {
        switch annotation.kind {
        case .line:
            [.start, .end]
        case .rectangle, .filledRectangle, .ellipse, .freehand, .step, .redaction, .pixelation:
            AnnotationResizeCorner.allCases.map(Self.corner)
        case .arrow, .text:
            []
        }
    }

    func point(in annotation: EditorAnnotation) -> CGPoint {
        switch self {
        case .start: annotation.start
        case .end: annotation.end
        case let .corner(corner): corner.point(in: AnnotationShapeEdit.bounds(for: annotation))
        }
    }
}

struct AnnotationShapeEdit {
    let original: EditorAnnotation
    let handle: AnnotationShapeHandle
    let start: CGPoint

    static func bounds(for annotation: EditorAnnotation) -> CGRect {
        switch annotation.kind {
        case .step:
            let radius = max(15, annotation.width * 3.5)
            return CGRect(x: annotation.start.x - radius, y: annotation.start.y - radius,
                          width: radius * 2, height: radius * 2)
        case .freehand:
            let points = annotation.points.isEmpty ? [annotation.start, annotation.end] : annotation.points
            let minX = points.map(\.x).min() ?? annotation.start.x
            let maxX = points.map(\.x).max() ?? annotation.start.x
            let minY = points.map(\.y).min() ?? annotation.start.y
            let maxY = points.map(\.y).max() ?? annotation.start.y
            return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
        case .rectangle, .filledRectangle, .ellipse, .line, .redaction, .pixelation:
            return CGRect(x: min(annotation.start.x, annotation.end.x),
                          y: min(annotation.start.y, annotation.end.y),
                          width: abs(annotation.end.x - annotation.start.x),
                          height: abs(annotation.end.y - annotation.start.y))
        case .arrow, .text:
            return .zero
        }
    }

    func annotation(at point: CGPoint) -> EditorAnnotation {
        guard point != start else { return original }
        let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
        var edited = original

        switch handle {
        case .start:
            edited.start.x += delta.x
            edited.start.y += delta.y
        case .end:
            edited.end.x += delta.x
            edited.end.y += delta.y
        case let .corner(corner):
            let bounds = Self.bounds(for: original)
            let anchor = corner.opposite.point(in: bounds)
            let dragged = corner.point(in: bounds)
            var resized = CGPoint(x: dragged.x + delta.x, y: dragged.y + delta.y)
            let growsRight: Bool
            let growsDown: Bool
            switch corner {
            case .topLeft:
                growsRight = false
                growsDown = false
            case .topRight:
                growsRight = true
                growsDown = false
            case .bottomLeft:
                growsRight = false
                growsDown = true
            case .bottomRight:
                growsRight = true
                growsDown = true
            }
            resized.x = clamped(resized.x, from: anchor.x, towardPositive: growsRight)
            resized.y = clamped(resized.y, from: anchor.y, towardPositive: growsDown)

            switch original.kind {
            case .freehand:
                let resizedBounds = rect(from: anchor, to: resized)
                func map(_ value: CGPoint) -> CGPoint {
                    CGPoint(x: resizedBounds.minX + (value.x - bounds.minX) * resizedBounds.width / bounds.width,
                            y: resizedBounds.minY + (value.y - bounds.minY) * resizedBounds.height / bounds.height)
                }
                edited.points = original.points.map(map)
                edited.start = map(original.start)
                edited.end = map(original.end)
            case .step:
                let vector = CGPoint(x: dragged.x - anchor.x, y: dragged.y - anchor.y)
                let lengthSquared = vector.x * vector.x + vector.y * vector.y
                let scale = 1 + (delta.x * vector.x + delta.y * vector.y) / lengthSquared
                let originalRadius = max(15, original.width * 3.5)
                let radius = max(15, originalRadius * scale)
                guard radius != originalRadius else { return original }
                let center = CGPoint(x: anchor.x + (vector.x < 0 ? -radius : radius),
                                     y: anchor.y + (vector.y < 0 ? -radius : radius))
                let shift = CGPoint(x: center.x - original.start.x, y: center.y - original.start.y)
                edited.start = center
                edited.end.x += shift.x
                edited.end.y += shift.y
                edited.width = radius / 3.5
            default:
                let resizedBounds = rect(from: anchor, to: resized)
                let startIsMinX = original.start.x <= original.end.x
                let startIsMinY = original.start.y <= original.end.y
                edited.start = CGPoint(x: startIsMinX ? resizedBounds.minX : resizedBounds.maxX,
                                       y: startIsMinY ? resizedBounds.minY : resizedBounds.maxY)
                edited.end = CGPoint(x: startIsMinX ? resizedBounds.maxX : resizedBounds.minX,
                                     y: startIsMinY ? resizedBounds.maxY : resizedBounds.minY)
            }
        }
        return edited
    }

    private func clamped(_ value: CGFloat, from anchor: CGFloat, towardPositive: Bool) -> CGFloat {
        towardPositive ? max(anchor + 1, value) : min(anchor - 1, value)
    }

    private func rect(from first: CGPoint, to second: CGPoint) -> CGRect {
        CGRect(x: min(first.x, second.x), y: min(first.y, second.y),
               width: abs(second.x - first.x), height: abs(second.y - first.y))
    }
}
