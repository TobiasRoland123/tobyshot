import AppKit

enum AnnotationArrowStyle: String, CaseIterable, Identifiable {
    case clean, sketch, handDrawn
    var id: String { rawValue }
    var title: String {
        switch self {
        case .clean: "Clean"
        case .sketch: "Sketch"
        case .handDrawn: "Hand-drawn"
        }
    }
}

enum AnnotationArrowStroke: String, CaseIterable, Identifiable {
    case solid, dashed, dotted
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func lengths(width: CGFloat) -> [CGFloat] {
        switch self {
        case .solid: []
        case .dashed: [width * 4, width * 3]
        case .dotted: [0, width * 2.5]
        }
    }
}

/// Stable, local-coordinate strokes keep the sketch unchanged when moved or exported.
enum AnnotationArrowPath {
    static func make(_ annotation: EditorAnnotation) -> CGPath {
        let from = annotation.reversed ? annotation.end : annotation.start
        let to = annotation.reversed ? annotation.start : annotation.end
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        let angle = atan2(dy, dx)
        let cosine = cos(angle), sine = sin(angle)
        // Bending is stored as the curve midpoint's displacement. A quadratic
        // Bezier reaches that midpoint when its control point is displaced by 2x.
        let bend = annotation.arrowBend
        let localBend = CGPoint(x: bend.x * cosine + bend.y * sine,
                                y: -bend.x * sine + bend.y * cosine)
        let control = CGPoint(x: length / 2 + 2 * localBend.x, y: 2 * localBend.y)
        let head = max(10, annotation.width * 3)
        let path = CGMutablePath()
        let shaft = CGMutablePath()
        let tip = CGPoint(x: length, y: 0)
        // The derivative at t=1 points from the control point toward the tip.
        // A coincident control and tip has no tangent, so use the chord direction.
        let tangentX = tip.x - control.x, tangentY = tip.y - control.y
        let tangentAngle = hypot(tangentX, tangentY) > .ulpOfOne ? atan2(tangentY, tangentX) : 0
        let wings = [-CGFloat.pi / 6, .pi / 6].map {
            CGPoint(x: length - head * cos(tangentAngle + $0),
                    y: -head * sin(tangentAngle + $0))
        }
        if annotation.arrowStyle == .clean {
            shaft.move(to: .zero)
            if bend == .zero {
                shaft.addLine(to: tip)
            } else {
                shaft.addQuadCurve(to: tip, control: control)
            }
            for wing in wings {
                path.move(to: tip)
                path.addLine(to: wing)
            }
        } else {
            var random = AnnotationSketchPath.Random(state: annotation.arrowSeed)
            let roughness: CGFloat = annotation.arrowStyle == .sketch ? 1 : 2
            let amplitude = min(6, max(1.5, annotation.width)) * roughness * min(1, length / 40)
            let passes = annotation.arrowStyle == .sketch ? 1 : 2
            for _ in 0..<passes {
                AnnotationSketchPath.addStroke(to: shaft, from: .zero, control: control, to: tip,
                                               amplitude: amplitude, random: &random)
                for wing in wings {
                    AnnotationSketchPath.addStroke(to: path, from: tip, to: wing,
                                                   amplitude: amplitude * 0.55, random: &random)
                }
            }
        }
        let dashes = annotation.arrowStroke.lengths(width: annotation.width)
        // Keep arrowheads solid and recognizable even on a short dashed arrow.
        path.addPath(dashes.isEmpty ? shaft : shaft.copy(dashingWithPhase: 0, lengths: dashes))
        var transform = CGAffineTransform(translationX: from.x, y: from.y).rotated(by: angle)
        return path.copy(using: &transform)!
    }

}
