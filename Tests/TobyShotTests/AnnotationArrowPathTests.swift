import AppKit
import Testing
@testable import TobyShot

@Suite
struct AnnotationArrowPathTests {
    @Test func cleanCurvePassesThroughRequestedMidpointAndReversalKeepsItsLocus() throws {
        let start = CGPoint(x: 24, y: 36)
        let end = CGPoint(x: 144, y: 76)
        let bend = CGPoint(x: -8, y: 22)
        let forward = arrow(start: start, end: end, bend: bend)
        let reversed = arrow(start: start, end: end, bend: bend, reversed: true)
        let forwardShaft = try #require(quadraticShaft(AnnotationArrowPath.make(forward)))
        let reverseShaft = try #require(quadraticShaft(AnnotationArrowPath.make(reversed)))

        let midpoint = quadraticPoint(forwardShaft.start, forwardShaft.control, forwardShaft.end, t: 0.5)
        #expect(close(midpoint.x, (start.x + end.x) / 2 + bend.x))
        #expect(close(midpoint.y, (start.y + end.y) / 2 + bend.y))
        #expect(close(forwardShaft.control.x, reverseShaft.control.x))
        #expect(close(forwardShaft.control.y, reverseShaft.control.y))
    }

    @Test func arrowheadFollowsEndpointTangentInBothDirections() throws {
        let start = CGPoint(x: 15, y: 20)
        let end = CGPoint(x: 115, y: 20)
        let bend = CGPoint(x: 0, y: 18)
        for reversed in [false, true] {
            let elements = pathElements(AnnotationArrowPath.make(arrow(start: start, end: end,
                                                                         bend: bend, reversed: reversed)))
            let wingLines = elements.prefix(4)
            #expect(wingLines.count == 4)
            let tip = wingLines[0].points[0]
            let wingA = wingLines[1].points[0]
            let wingB = wingLines[3].points[0]
            let headCenter = CGPoint(x: (wingA.x + wingB.x) / 2, y: (wingA.y + wingB.y) / 2)
            let direction = CGPoint(x: headCenter.x - tip.x, y: headCenter.y - tip.y)
            let control = CGPoint(x: 65, y: 20 + 2 * bend.y)
            let targetTip = reversed ? start : end
            let expected = CGPoint(x: control.x - targetTip.x, y: control.y - targetTip.y)
            let dot = direction.x * expected.x + direction.y * expected.y
            let cross = direction.x * expected.y - direction.y * expected.x
            #expect(dot > 0)
            #expect(abs(cross) < abs(dot) * 0.05)
        }
    }

    @Test func degenerateTangentsAndCoincidentEndpointsStayFinite() {
        let cases = [
            arrow(start: CGPoint(x: 40, y: 40), end: CGPoint(x: 40, y: 40)),
            // This bend places the quadratic control exactly at the forward tip.
            arrow(start: .zero, end: CGPoint(x: 100, y: 0), bend: CGPoint(x: 25, y: 0)),
            arrow(start: .zero, end: CGPoint(x: 100, y: 0), bend: CGPoint(x: -25, y: 0), reversed: true)
        ]
        for annotation in cases {
            #expect(pathElements(AnnotationArrowPath.make(annotation)).allSatisfy { element in
                element.points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            })
        }
    }

    @Test(arguments: AnnotationArrowStyle.allCases, AnnotationArrowStroke.allCases)
    func everyRenderingStylePreservesSeededGeometryUnderTranslation(
        style: AnnotationArrowStyle, stroke: AnnotationArrowStroke
    ) {
        let original = arrow(start: CGPoint(x: 16, y: 28), end: CGPoint(x: 136, y: 68),
                             bend: CGPoint(x: -10, y: 21), style: style, stroke: stroke)
        var moved = original
        moved.start.x += 43
        moved.start.y -= 17
        moved.end.x += 43
        moved.end.y -= 17
        let first = pathElements(AnnotationArrowPath.make(original))
        let second = pathElements(AnnotationArrowPath.make(moved))
        #expect(first.count == second.count)
        for (a, b) in zip(first, second) {
            #expect(a.type == b.type)
            #expect(a.points.count == b.points.count)
            for (pointA, pointB) in zip(a.points, b.points) {
                #expect(close(pointB.x - pointA.x, 43))
                #expect(close(pointB.y - pointA.y, -17))
            }
        }
    }

    private func arrow(start: CGPoint, end: CGPoint, bend: CGPoint = .zero,
                       reversed: Bool = false, style: AnnotationArrowStyle = .clean,
                       stroke: AnnotationArrowStroke = .solid) -> EditorAnnotation {
        EditorAnnotation(kind: .arrow, start: start, end: end, width: 6, shadow: false,
                         reversed: reversed, arrowStyle: style, arrowStroke: stroke,
                         arrowSeed: 1234, arrowBend: bend)
    }

    private func pathElements(_ path: CGPath) -> [(type: CGPathElementType, points: [CGPoint])] {
        var result: [(CGPathElementType, [CGPoint])] = []
        path.applyWithBlock { element in
            let count: Int
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            result.append((element.pointee.type, (0..<count).map { element.pointee.points[$0] }))
        }
        return result
    }

    private func quadraticShaft(_ path: CGPath) -> (start: CGPoint, control: CGPoint, end: CGPoint)? {
        let elements = pathElements(path)
        guard let index = elements.firstIndex(where: { $0.type == .addQuadCurveToPoint }), index > 0,
              elements[index - 1].type == .moveToPoint else { return nil }
        return (elements[index - 1].points[0], elements[index].points[0], elements[index].points[1])
    }

    private func quadraticPoint(_ start: CGPoint, _ control: CGPoint, _ end: CGPoint, t: CGFloat) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
                      y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y)
    }

    private func close(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool { abs(lhs - rhs) < 0.001 }
}
