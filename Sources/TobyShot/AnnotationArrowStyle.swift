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
        let length = hypot(to.x - from.x, to.y - from.y)
        let angle = atan2(to.y - from.y, to.x - from.x)
        let head = max(10, annotation.width * 3)
        let path = CGMutablePath()
        let shaft = CGMutablePath()
        let tip = CGPoint(x: length, y: 0)
        let wings = [-CGFloat.pi / 6, .pi / 6].map {
            CGPoint(x: length - head * cos($0), y: -head * sin($0))
        }
        if annotation.arrowStyle == .clean {
            shaft.move(to: .zero)
            shaft.addLine(to: tip)
            for wing in wings {
                path.move(to: tip)
                path.addLine(to: wing)
            }
        } else {
            var random = SketchRandom(state: annotation.arrowSeed)
            let roughness: CGFloat = annotation.arrowStyle == .sketch ? 1 : 2
            let amplitude = min(6, max(1.5, annotation.width)) * roughness * min(1, length / 40)
            let passes = annotation.arrowStyle == .sketch ? 1 : 2
            for _ in 0..<passes {
                addStroke(to: shaft, from: .zero, to: tip, amplitude: amplitude, random: &random)
                for wing in wings {
                    addStroke(to: path, from: tip, to: wing, amplitude: amplitude * 0.55, random: &random)
                }
            }
        }
        let dashes = annotation.arrowStroke.lengths(width: annotation.width)
        // Keep arrowheads solid and recognizable even on a short dashed arrow.
        path.addPath(dashes.isEmpty ? shaft : shaft.copy(dashingWithPhase: 0, lengths: dashes))
        var transform = CGAffineTransform(translationX: from.x, y: from.y).rotated(by: angle)
        return path.copy(using: &transform)!
    }

    private static func addStroke(to path: CGMutablePath, from: CGPoint, to: CGPoint,
                                  amplitude: CGFloat, random: inout SketchRandom) {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = max(1, hypot(dx, dy))
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let first = random.offset(amplitude)
        let second = random.offset(amplitude)
        let startOffset = random.offset(amplitude * 0.35)
        path.move(to: CGPoint(x: from.x + normal.x * startOffset, y: from.y + normal.y * startOffset))
        path.addCurve(to: to,
                      control1: CGPoint(x: from.x + dx / 3 + normal.x * first,
                                        y: from.y + dy / 3 + normal.y * first),
                      control2: CGPoint(x: from.x + dx * 2 / 3 + normal.x * second,
                                        y: from.y + dy * 2 / 3 + normal.y * second))
    }

    private struct SketchRandom {
        var state: UInt64

        mutating func offset(_ amplitude: CGFloat) -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (CGFloat(state >> 32) / CGFloat(UInt32.max) * 2 - 1) * amplitude
        }
    }
}
