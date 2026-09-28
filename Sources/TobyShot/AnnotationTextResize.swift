import AppKit

enum AnnotationResizeCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var opposite: Self {
        switch self {
        case .topLeft: .bottomRight
        case .topRight: .bottomLeft
        case .bottomLeft: .topRight
        case .bottomRight: .topLeft
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

struct AnnotationTextResize {
    let original: EditorAnnotation
    let corner: AnnotationResizeCorner
    let start: CGPoint
    let bounds: CGRect

    func annotation(at point: CGPoint) -> EditorAnnotation {
        guard point != start else { return original }
        let anchor = corner.opposite.point(in: bounds)
        let handle = corner.point(in: bounds)
        let vector = CGPoint(x: handle.x - anchor.x, y: handle.y - anchor.y)
        let lengthSquared = vector.x * vector.x + vector.y * vector.y
        guard lengthSquared > 0 else { return original }
        // Project the drag onto the diagonal to scale uniformly without stretching letters.
        let scale = 1 + ((point.x - start.x) * vector.x + (point.y - start.y) * vector.y) / lengthSquared
        let fontSize = AnnotationTextLayout.fontSize(for: original)
        let resizedFontSize = min(400, max(8, fontSize * scale))
        guard abs(resizedFontSize - fontSize) > 0.0001 else { return original }
        var resized = original
        resized.textSize = resizedFontSize
        let size = AnnotationTextLayout(resized).selectionSize
        let opposite = corner.opposite.point(in: CGRect(origin: .zero, size: size))
        resized.start = CGPoint(x: anchor.x - opposite.x, y: anchor.y - opposite.y)
        resized.end.x += resized.start.x - original.start.x
        resized.end.y += resized.start.y - original.start.y
        return resized
    }
}
