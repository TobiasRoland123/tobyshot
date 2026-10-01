import AppKit
import Testing
@testable import TobyShot

@Suite
struct AnnotationShapePathTests {
    @Test(arguments: [EditorAnnotation.Kind.rectangle, .ellipse, .line])
    func cleanPathsKeepTheirOriginalCenterlines(kind: EditorAnnotation.Kind) {
        let annotation = shape(kind, style: .clean)
        let path = AnnotationShapePath.make(annotation, in: CGRect(x: 20, y: 30, width: 80, height: 50))
        let expected: CGPath
        switch kind {
        case .rectangle: expected = CGPath(rect: CGRect(x: 20, y: 30, width: 80, height: 50), transform: nil)
        case .ellipse: expected = CGPath(ellipseIn: CGRect(x: 20, y: 30, width: 80, height: 50), transform: nil)
        case .line:
            let line = CGMutablePath()
            line.move(to: annotation.start)
            line.addLine(to: annotation.end)
            expected = line
        default: return
        }
        #expect(samePath(path, expected))
    }

    @Test(arguments: [AnnotationArrowStyle.sketch, .handDrawn])
    func roughPathsDifferFromCleanAndHandDrawnUsesTwoPasses(style: AnnotationArrowStyle) {
        for kind in [EditorAnnotation.Kind.rectangle, .ellipse, .line] {
            let rough = AnnotationShapePath.make(shape(kind, style: style),
                                                 in: CGRect(x: 20, y: 30, width: 80, height: 50))
            let clean = AnnotationShapePath.make(shape(kind, style: .clean),
                                                 in: CGRect(x: 20, y: 30, width: 80, height: 50))
            #expect(!samePath(rough, clean))
            let roughElements = elements(rough)
            let closedPasses = roughElements.filter { $0.type == .closeSubpath }.count
            if kind != .line {
                #expect(closedPasses == (style == .sketch ? 1 : 2))
                if kind == .ellipse {
                    #expect(roughElements.filter { $0.type == .addCurveToPoint }.count == (style == .sketch ? 4 : 8))
                }
                if kind == .rectangle {
                    #expect(roughElements.filter { $0.type == .addCurveToPoint }.count == (style == .sketch ? 4 : 8))
                }
            }
        }
    }

    @Test(arguments: [EditorAnnotation.Kind.rectangle, .filledRectangle, .ellipse, .line, .step])
    func seededPathsRepeatAndMoveWithTheirAnnotation(kind: EditorAnnotation.Kind) {
        let rect = CGRect(x: 20, y: 30, width: 80, height: 50)
        let original = shape(kind, style: .handDrawn)
        var moved = original
        moved.start.x += 17; moved.start.y -= 9
        moved.end.x += 17; moved.end.y -= 9
        let first = AnnotationShapePath.make(original, in: rect)
        let repeatPath = AnnotationShapePath.make(original, in: rect)
        let translated = AnnotationShapePath.make(moved, in: rect.offsetBy(dx: 17, dy: -9))
        #expect(samePath(first, repeatPath))
        let firstElements = elements(first), translatedElements = elements(translated)
        #expect(firstElements.count == translatedElements.count)
        for (a, b) in zip(firstElements, translatedElements) {
            #expect(a.type == b.type)
            #expect(a.points.count == b.points.count)
            for (p, q) in zip(a.points, b.points) {
                #expect(abs(q.x - p.x - 17) < 0.001)
                #expect(abs(q.y - p.y + 9) < 0.001)
            }
        }
    }

    @Test func zeroAndShortDimensionsStayFinite() {
        let cases: [(EditorAnnotation.Kind, CGRect, CGPoint, CGPoint)] = [
            (.rectangle, CGRect(x: 10, y: 12, width: 0, height: 0), .zero, .zero),
            (.ellipse, CGRect(x: 10, y: 12, width: 0.01, height: 0), .zero, .zero),
            (.filledRectangle, CGRect(x: 10, y: 12, width: 0, height: 0.01), .zero, .zero),
            (.line, .zero, CGPoint(x: 4, y: 5), CGPoint(x: 4.01, y: 5)),
            (.step, CGRect(x: 10, y: 12, width: 0, height: 0), .zero, .zero)
        ]
        for (kind, rect, start, end) in cases {
            let annotation = EditorAnnotation(kind: kind, start: start, end: end, width: 5,
                                              arrowStyle: .handDrawn, arrowSeed: 1234)
            #expect(elements(AnnotationShapePath.make(annotation, in: rect))
                .allSatisfy { $0.points.allSatisfy { $0.x.isFinite && $0.y.isFinite } })
        }
    }

    @Test(arguments: [EditorAnnotation.Kind.filledRectangle, .step])
    func roughFilledShapesHaveOneClosedContour(kind: EditorAnnotation.Kind) {
        let path = AnnotationShapePath.make(shape(kind, style: .handDrawn),
                                            in: CGRect(x: 20, y: 30, width: 80, height: 50))
        #expect(elements(path).filter { $0.type == .closeSubpath }.count == 1)
    }

    @Test(arguments: AnnotationArrowStroke.allCases)
    func outlinesRespectStrokeStyle(stroke: AnnotationArrowStroke) {
        let annotation = shape(.rectangle, style: .clean, stroke: stroke)
        let path = AnnotationShapePath.make(annotation, in: CGRect(x: 20, y: 30, width: 80, height: 50))
        let solid = CGPath(rect: CGRect(x: 20, y: 30, width: 80, height: 50), transform: nil)
        if stroke == .solid {
            #expect(samePath(path, solid))
        } else {
            #expect(!samePath(path, solid))
        }
    }

    @Test func filledShapesIgnoreStrokeStyle() {
        let rect = CGRect(x: 20, y: 30, width: 80, height: 50)
        let solid = AnnotationShapePath.make(shape(.filledRectangle, style: .sketch, stroke: .solid), in: rect)
        let dotted = AnnotationShapePath.make(shape(.filledRectangle, style: .sketch, stroke: .dotted), in: rect)
        #expect(samePath(solid, dotted))
    }

    private func shape(_ kind: EditorAnnotation.Kind, style: AnnotationArrowStyle,
                       stroke: AnnotationArrowStroke = .solid) -> EditorAnnotation {
        EditorAnnotation(kind: kind, start: CGPoint(x: 20, y: 30), end: CGPoint(x: 100, y: 80),
                         width: 5, arrowStyle: style, arrowStroke: stroke, arrowSeed: 2468)
    }

    private func elements(_ path: CGPath) -> [(type: CGPathElementType, points: [CGPoint])] {
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

    private func samePath(_ lhs: CGPath, _ rhs: CGPath) -> Bool {
        let left = elements(lhs), right = elements(rhs)
        guard left.count == right.count else { return false }
        for (a, b) in zip(left, right) {
            guard a.type == b.type, a.points.count == b.points.count else { return false }
            for (p, q) in zip(a.points, b.points) {
                guard abs(p.x - q.x) < 0.001, abs(p.y - q.y) < 0.001 else { return false }
            }
        }
        return true
    }
}
