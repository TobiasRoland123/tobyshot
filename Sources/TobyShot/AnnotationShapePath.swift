import AppKit

enum AnnotationShapePath {
    /// `rect` is the normalized shape bounds, or the circle bounds for a step.
    static func make(_ annotation: EditorAnnotation, in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let style = annotation.arrowStyle
        let rough = style != .clean
        let passes = style == .handDrawn ? 2 : 1

        switch annotation.kind {
        case .line:
            let dx = annotation.end.x - annotation.start.x
            let dy = annotation.end.y - annotation.start.y
            if rough {
                var random = AnnotationSketchPath.Random(state: annotation.arrowSeed)
                let amplitude = roughness(annotation.width, narrowDimension: hypot(dx, dy), style: style)
                for _ in 0..<passes {
                    AnnotationSketchPath.addStroke(to: path, from: .zero, to: CGPoint(x: dx, y: dy),
                                                   amplitude: amplitude, random: &random)
                }
            } else {
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: dx, y: dy))
            }
            let dashed = dashedPath(path, annotation: annotation)
            var transform = CGAffineTransform(translationX: annotation.start.x, y: annotation.start.y)
            return dashed.copy(using: &transform)!

        case .rectangle, .filledRectangle:
            let bounds = rect.standardized
            if !rough {
                path.addRect(CGRect(origin: .zero, size: bounds.size))
            } else {
                var random = AnnotationSketchPath.Random(state: annotation.arrowSeed)
                let amplitude = roughness(annotation.width,
                                          narrowDimension: min(bounds.width, bounds.height), style: style)
                let contour = rectangleContour(bounds.size)
                // A filled annotation needs one closed contour, so its silhouette is drawn once.
                let contourPasses = annotation.kind == .filledRectangle ? 1 : passes
                for _ in 0..<contourPasses {
                    AnnotationSketchPath.addClosedContour(to: path, points: contour,
                                                          amplitude: amplitude, random: &random)
                }
            }
            let outlined = annotation.kind == .filledRectangle ? path : dashedPath(path, annotation: annotation)
            var transform = CGAffineTransform(translationX: rect.standardized.minX,
                                              y: rect.standardized.minY)
            return outlined.copy(using: &transform)!

        case .ellipse, .step:
            let bounds = rect.standardized
            if !rough {
                path.addEllipse(in: CGRect(origin: .zero, size: bounds.size))
            } else {
                var random = AnnotationSketchPath.Random(state: annotation.arrowSeed)
                let amplitude = roughness(annotation.width,
                                          narrowDimension: min(bounds.width, bounds.height), style: style)
                let contourPasses = annotation.kind == .step ? 1 : passes
                for _ in 0..<contourPasses {
                    AnnotationSketchPath.addClosedEllipse(to: path, size: bounds.size,
                                                          amplitude: amplitude, random: &random)
                }
            }
            let outlined = annotation.kind == .step ? path : dashedPath(path, annotation: annotation)
            var transform = CGAffineTransform(translationX: bounds.minX, y: bounds.minY)
            return outlined.copy(using: &transform)!

        default:
            return path
        }
    }

    private static func dashedPath(_ path: CGPath, annotation: EditorAnnotation) -> CGPath {
        let lengths = annotation.arrowStroke.lengths(width: annotation.width)
        return lengths.isEmpty ? path : path.copy(dashingWithPhase: 0, lengths: lengths)
    }

    private static func roughness(_ width: CGFloat, narrowDimension: CGFloat,
                                  style: AnnotationArrowStyle) -> CGFloat {
        let strength: CGFloat = style == .sketch ? 1 : 2
        let base = min(6, max(1.5, width)) * strength * min(1, narrowDimension / 40)
        return min(base, max(0, narrowDimension) * 0.08)
    }

    private static func rectangleContour(_ size: CGSize) -> [CGPoint] {
        [CGPoint.zero, CGPoint(x: size.width, y: 0),
         CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)]
    }
}
