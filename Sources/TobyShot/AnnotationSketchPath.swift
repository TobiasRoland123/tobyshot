import AppKit

/// Seeded local-coordinate path primitives shared by hand-drawn annotations.
enum AnnotationSketchPath {
    struct Random {
        var state: UInt64

        mutating func offset(_ amplitude: CGFloat) -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (CGFloat(state >> 32) / CGFloat(UInt32.max) * 2 - 1) * amplitude
        }
    }

    static func addStroke(to path: CGMutablePath, from: CGPoint, control: CGPoint, to: CGPoint,
                          amplitude: CGFloat, random: inout Random) {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = max(1, hypot(dx, dy))
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let first = random.offset(amplitude)
        let second = random.offset(amplitude)
        let startOffset = random.offset(amplitude * 0.35)
        path.move(to: CGPoint(x: from.x + normal.x * startOffset, y: from.y + normal.y * startOffset))
        let cubic1 = CGPoint(x: from.x + 2 * (control.x - from.x) / 3,
                             y: from.y + 2 * (control.y - from.y) / 3)
        let cubic2 = CGPoint(x: to.x + 2 * (control.x - to.x) / 3,
                             y: to.y + 2 * (control.y - to.y) / 3)
        let firstNormal = Self.normal(at: 1 / 3, from: from, control: control, to: to)
        let secondNormal = Self.normal(at: 2 / 3, from: from, control: control, to: to)
        path.addCurve(to: to,
                      control1: CGPoint(x: cubic1.x + firstNormal.x * first,
                                        y: cubic1.y + firstNormal.y * first),
                      control2: CGPoint(x: cubic2.x + secondNormal.x * second,
                                        y: cubic2.y + secondNormal.y * second))
    }

    static func addStroke(to path: CGMutablePath, from: CGPoint, to: CGPoint,
                          amplitude: CGFloat, random: inout Random) {
        addStroke(to: path, from: from,
                  control: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2),
                  to: to, amplitude: amplitude, random: &random)
    }

    /// Builds one closed, continuous rough contour from an ordered local polygon.
    static func addClosedContour(to path: CGMutablePath, points: [CGPoint], amplitude: CGFloat,
                                 random: inout Random) {
        guard points.count >= 3 else { return }
        let normals = points.indices.map { index -> CGPoint in
            let previous = points[(index + points.count - 1) % points.count]
            let next = points[(index + 1) % points.count]
            let dx = next.x - previous.x, dy = next.y - previous.y
            let length = hypot(dx, dy)
            return length > .ulpOfOne ? CGPoint(x: -dy / length, y: dx / length) : CGPoint(x: 0, y: 1)
        }
        let vertices = points.indices.map { index in
            let offset = random.offset(amplitude)
            return CGPoint(x: points[index].x + normals[index].x * offset,
                           y: points[index].y + normals[index].y * offset)
        }
        path.move(to: vertices[0])
        for index in points.indices {
            let next = (index + 1) % points.count
            let from = vertices[index], to = vertices[next]
            let dx = to.x - from.x, dy = to.y - from.y
            let firstOffset = random.offset(amplitude)
            let secondOffset = random.offset(amplitude)
            path.addCurve(to: to,
                          control1: CGPoint(x: from.x + dx / 3 + normals[index].x * firstOffset,
                                            y: from.y + dy / 3 + normals[index].y * firstOffset),
                          control2: CGPoint(x: from.x + 2 * dx / 3 + normals[next].x * secondOffset,
                                            y: from.y + 2 * dy / 3 + normals[next].y * secondOffset))
        }
        path.closeSubpath()
    }

    /// Four tangent-aligned cubic arcs retain an ellipse's smooth outline while varying its contour.
    static func addClosedEllipse(to path: CGMutablePath, size: CGSize, amplitude: CGFloat,
                                 random: inout Random) {
        let radiusX = size.width / 2, radiusY = size.height / 2
        let angles = (0..<4).map { CGFloat($0) * CGFloat.pi / 2 }
        let points = angles.map { angle in
            let normal = CGPoint(x: cos(angle), y: sin(angle))
            let offset = random.offset(amplitude)
            return CGPoint(x: radiusX + radiusX * normal.x + normal.x * offset,
                           y: radiusY + radiusY * normal.y + normal.y * offset)
        }
        // One scale per node is shared by the incoming and outgoing handles, preserving tangent continuity.
        let handleScales = (0..<4).map { _ in 1 + random.offset(0.12) }
        let handleFactor = 4 / 3 * tan(CGFloat.pi / 8)
        path.move(to: points[0])
        for index in 0..<4 {
            let next = (index + 1) % 4
            let angle = angles[index], nextAngle = angles[next]
            let tangent = CGPoint(x: -radiusX * sin(angle), y: radiusY * cos(angle))
            let nextTangent = CGPoint(x: -radiusX * sin(nextAngle), y: radiusY * cos(nextAngle))
            let startLength = handleFactor * handleScales[index]
            let endLength = handleFactor * handleScales[next]
            path.addCurve(to: points[next],
                          control1: CGPoint(x: points[index].x + tangent.x * startLength,
                                            y: points[index].y + tangent.y * startLength),
                          control2: CGPoint(x: points[next].x - nextTangent.x * endLength,
                                            y: points[next].y - nextTangent.y * endLength))
        }
        path.closeSubpath()
    }

    private static func normal(at t: CGFloat, from: CGPoint, control: CGPoint, to: CGPoint) -> CGPoint {
        // Derivative of the quadratic centerline, which supplies the local normal.
        let dx = 2 * ((1 - t) * (control.x - from.x) + t * (to.x - control.x))
        let dy = 2 * ((1 - t) * (control.y - from.y) + t * (to.y - control.y))
        let length = hypot(dx, dy)
        if length > .ulpOfOne { return CGPoint(x: -dy / length, y: dx / length) }
        return CGPoint(x: 0, y: 1)
    }
}
