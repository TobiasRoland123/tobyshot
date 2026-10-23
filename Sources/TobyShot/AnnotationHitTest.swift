import AppKit

/// Finds the visible parts of an annotation that can start an edit. Strokes and outlines
/// count within a tolerance; an outlined shape's empty interior does not.
enum AnnotationHitTest {
    static func contains(_ annotation: EditorAnnotation, point: CGPoint, tolerance: CGFloat,
                         imageSize: CGSize? = nil, imageBounds: CGRect? = nil) -> Bool {
        if annotation.kind == .text {
            return CGRect(origin: annotation.start, size: AnnotationTextLayout(annotation).selectionSize)
                .insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
        // Dash gaps are part of the visible stroke, so test the continuous path.
        var solid = annotation
        solid.arrowStroke = .solid
        let geometry = AnnotationGeometry(solid, imageSize: imageSize, imageBounds: imageBounds)
        guard !geometry.path.isEmpty,
              geometry.renderedBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return false }
        if !geometry.stroked, geometry.path.contains(point) { return true }
        let width = (geometry.stroked ? geometry.lineWidth : 0) + tolerance * 2
        return geometry.path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
            .contains(point)
    }
}
