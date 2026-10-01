import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationGeometryTests {
    @Test func stepCircleExportsAllPaintAtWidth20AndSupportedWidths() throws {
        for width in 1...40 {
            for shadow in [false, true] {
                let annotation = EditorAnnotation(
                    kind: .step,
                    start: CGPoint(x: 116, y: 92),
                    end: CGPoint(x: 116, y: 92),
                    color: .systemOrange,
                    width: CGFloat(width),
                    step: 8,
                    shadow: shadow
                )
                try assertObjectExportMatchesCanvas(annotation)
            }
        }
    }

    @Test func width20StepCircleHas140PixelPaintAnd142PixelExport() throws {
        let center = CGPoint(x: 120, y: 90)
        let annotation = EditorAnnotation(kind: .step, start: center, end: center, width: 20, step: 8, shadow: false)
        let source = transparentImage(width: 260, height: 220)
        let object = try #require(AnnotationRenderer.render(annotation: annotation, sourceImage: source))
        let bitmap = try bitmap(object)
        #expect(bitmap.pixelsWide == 142)
        #expect(bitmap.pixelsHigh == 142)

        var paintedXs: [Int] = []
        var paintedYs: [Int] = []
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if try #require(bitmap.colorAt(x: x, y: y)).alphaComponent > 0.05 {
                    paintedXs.append(x)
                    paintedYs.append(y)
                }
            }
        }
        #expect(!paintedXs.isEmpty)
        #expect((paintedXs.max() ?? 0) - (paintedXs.min() ?? 0) + 1 == 140)
        #expect((paintedYs.max() ?? 0) - (paintedYs.min() ?? 0) + 1 == 140)

        let model = AnnotationEditorModel(image: source, sourceURL: nil)
        model.annotations = [annotation]
        model.tool = .select
        model.begin(at: CGPoint(x: center.x + 65, y: center.y))
        #expect(model.selectedID == annotation.id)
    }

    @Test func arrowsIncludeReversedAndShortDiagonalArrowheads() throws {
        let arrows = [
            EditorAnnotation(kind: .arrow, start: CGPoint(x: 42, y: 130), end: CGPoint(x: 164, y: 45), color: .systemBlue, width: 14, shadow: true),
            EditorAnnotation(kind: .arrow, start: CGPoint(x: 170, y: 132), end: CGPoint(x: 78, y: 54), color: .systemPink, width: 9, shadow: true, reversed: true),
            EditorAnnotation(kind: .arrow, start: CGPoint(x: 90, y: 90), end: CGPoint(x: 97, y: 94), color: .systemGreen, width: 8, shadow: true),
            EditorAnnotation(kind: .arrow, start: CGPoint(x: 150, y: 140), end: CGPoint(x: 149, y: 139), color: .systemPurple, width: 3, shadow: false, reversed: true)
        ]
        for arrow in arrows { try assertObjectExportMatchesCanvas(arrow) }
    }

    @Test func thickStrokesAndFreehandRoundCapsAreNotClipped() throws {
        let annotations = [
            EditorAnnotation(kind: .line, start: CGPoint(x: 54, y: 82), end: CGPoint(x: 154, y: 82), color: .systemRed, width: 40, shadow: true),
            EditorAnnotation(kind: .freehand, start: CGPoint(x: 84, y: 106), end: CGPoint(x: 84, y: 106), points: [CGPoint(x: 84, y: 106)], color: .systemBlue, width: 40, shadow: true),
            EditorAnnotation(kind: .freehand, start: CGPoint(x: 42, y: 36), end: CGPoint(x: 172, y: 148), points: [CGPoint(x: 42, y: 36), CGPoint(x: 91, y: 120), CGPoint(x: 172, y: 148)], color: .systemTeal, width: 27, shadow: true)
        ]
        for annotation in annotations { try assertObjectExportMatchesCanvas(annotation) }
    }

    @Test(arguments: AnnotationArrowStyle.allCases, AnnotationArrowStroke.allCases)
    func arrowStylesKeepTheirFullPaintInObjectExports(style: AnnotationArrowStyle, stroke: AnnotationArrowStroke) throws {
        for reversed in [false, true] {
            for end in [CGPoint(x: 210, y: 48), CGPoint(x: 94, y: 91), CGPoint(x: 90, y: 90)] {
                let arrow = EditorAnnotation(kind: .arrow, start: CGPoint(x: 90, y: 90), end: end,
                    color: .systemBlue, width: 8, shadow: true, reversed: reversed,
                    arrowStyle: style, arrowStroke: stroke, arrowSeed: 42)
                #expect(AnnotationGeometry(arrow).path == AnnotationGeometry(arrow).path)
                try assertObjectExportMatchesCanvas(arrow)
            }
        }
    }

    @Test(arguments: AnnotationFont.allCases)
    func annotationFontsExportMultilineAccentsWithoutClipping(font: AnnotationFont) throws {
        let annotation = EditorAnnotation(kind: .text, start: CGPoint(x: 40, y: 60), end: .zero,
            width: 8, text: "Æblegrød, Øresund\nÅngström — Égjyp 😀", shadow: true, font: font)
        try assertObjectExportMatchesCanvas(annotation)
    }

    @Test(arguments: AnnotationArrowStyle.allCases, AnnotationArrowStroke.allCases)
    func bentArrowExportsIncludeCurveHeadsAndShadow(style: AnnotationArrowStyle, stroke: AnnotationArrowStroke) throws {
        for reversed in [false, true] {
            let arrow = EditorAnnotation(kind: .arrow, start: CGPoint(x: 40, y: 120), end: CGPoint(x: 210, y: 95),
                color: .systemBlue, width: 8, shadow: true, reversed: reversed,
                arrowStyle: style, arrowStroke: stroke, arrowSeed: 42, arrowBend: CGPoint(x: 25, y: -70))
            try assertObjectExportMatchesCanvas(arrow)
        }
    }

    @Test func textMetricsIncludeAccentsDescendersAndShadow() throws {
        let annotation = EditorAnnotation(
            kind: .text,
            start: CGPoint(x: 68, y: 74),
            end: CGPoint(x: 68, y: 74),
            color: .systemIndigo,
            width: 40,
            text: "Égjyp qÅ",
            shadow: true
        )
        try assertObjectExportMatchesCanvas(annotation)
        let fallbackText = EditorAnnotation(
            kind: .text,
            start: CGPoint(x: 46, y: 58),
            end: CGPoint(x: 46, y: 58),
            color: .systemPurple,
            width: 40,
            text: "A😀 gyp Å",
            shadow: true
        )
        try assertObjectExportMatchesCanvas(fallbackText)
    }

    @Test(arguments: AnnotationArrowStyle.allCases, AnnotationArrowStroke.allCases)
    func shapeStylesExportTheirFullContoursAndShadows(style: AnnotationArrowStyle, stroke: AnnotationArrowStroke) throws {
        for kind in [EditorAnnotation.Kind.rectangle, .filledRectangle, .ellipse, .line, .step] {
            let shape = EditorAnnotation(kind: kind, start: CGPoint(x: 60, y: 60), end: CGPoint(x: 180, y: 130),
                color: .systemBlue, width: 6, step: 2, shadow: true,
                arrowStyle: style, arrowStroke: stroke, arrowSeed: 42)
            try assertObjectExportMatchesCanvas(shape)
        }
    }

    @Test func shapeStylesPreserveFreehandAndPrivacyToolGeometry() {
        for kind in [EditorAnnotation.Kind.freehand, .redaction, .pixelation] {
            let original = EditorAnnotation(kind: kind, start: CGPoint(x: 40, y: 50), end: CGPoint(x: 150, y: 100),
                points: [CGPoint(x: 40, y: 50), CGPoint(x: 90, y: 110), CGPoint(x: 150, y: 100)])
            var styled = original
            styled.arrowStyle = .handDrawn
            styled.arrowStroke = .dotted
            #expect(AnnotationGeometry(styled).path == AnnotationGeometry(original).path)
            #expect(AnnotationGeometry(styled).renderedBounds == AnnotationGeometry(original).renderedBounds)
        }
    }

    @Test func multilineTextExportsEveryLineWithoutContainerSizedBounds() throws {
        let annotation = EditorAnnotation(kind: .text, start: CGPoint(x: 40, y: 60), end: .zero,
            width: 5, text: "Édited label\n\nSecond line 😀\n", shadow: true)
        let bounds = AnnotationGeometry(annotation).exportBounds
        #expect(bounds.width < 400)
        #expect(bounds.height > 75)
        try assertObjectExportMatchesCanvas(annotation)
    }

    @Test func selectedObjectExportUsesTheSameCompleteGeometry() throws {
        let source = transparentImage(width: 240, height: 180)
        let annotation = EditorAnnotation(kind: .step, start: CGPoint(x: 108, y: 86), end: CGPoint(x: 108, y: 86), width: 20, step: 3)
        let model = AnnotationEditorModel(image: source, sourceURL: nil)
        model.annotations = [annotation]
        model.selectedID = annotation.id
        let selected = try #require(model.renderedSelection())
        try assertSameRaster(selected, try #require(AnnotationRenderer.render(annotation: annotation, sourceImage: source)))
    }

    @Test func cropKeepsVisibleEdgePaintAndDropsToleranceOnlyObjects() {
        let model = AnnotationEditorModel(image: transparentImage(width: 160, height: 100), sourceURL: nil)
        let edge = EditorAnnotation(kind: .rectangle, start: CGPoint(x: 96, y: 30), end: CGPoint(x: 108, y: 54), width: 6, shadow: false)
        let outside = EditorAnnotation(kind: .rectangle, start: CGPoint(x: 112, y: 32), end: CGPoint(x: 132, y: 52), width: 2, shadow: false)
        model.annotations = [edge, outside]

        model.tool = .crop
        model.begin(at: CGPoint(x: 50, y: 10))
        model.continueDrag(to: CGPoint(x: 100, y: 90))
        model.endDrag()

        #expect(model.pixelSize == CGSize(width: 50, height: 80))
        #expect(model.annotations.map(\.id) == [edge.id])
        #expect(model.annotations[0].start == CGPoint(x: 46, y: 20))
        #expect(model.annotations[0].end == CGPoint(x: 58, y: 44))
    }

    @Test func cropKeepsStepCirclePaintOutsideItsOldBounds() {
        let model = AnnotationEditorModel(image: transparentImage(width: 240, height: 180), sourceURL: nil)
        let center = CGPoint(x: 145, y: 100)
        let step = EditorAnnotation(kind: .step, start: center, end: center, width: 20, step: 4, shadow: false)
        model.annotations = [step]

        model.tool = .crop
        model.begin(at: CGPoint(x: 80, y: 50))
        model.continueDrag(to: CGPoint(x: 95, y: 150))
        model.endDrag()

        #expect(model.pixelSize == CGSize(width: 15, height: 100))
        #expect(model.annotations.map(\.id) == [step.id])
        #expect(model.annotations[0].start == CGPoint(x: 65, y: 50))
    }

    @Test func multiDigitStepLabelExtendsBeyondItsCircleBounds() throws {
        let annotation = EditorAnnotation(kind: .step, start: CGPoint(x: 118, y: 88), end: CGPoint(x: 118, y: 88), width: 40, step: 1_000, shadow: true)
        try assertObjectExportMatchesCanvas(annotation)
    }

    @Test func representativeShapeBoundsContainRasterPaint() throws {
        let annotations = [
            EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 42, y: 44), end: CGPoint(x: 132, y: 104), color: .systemRed, width: 20, shadow: true),
            EditorAnnotation(kind: .rectangle, start: CGPoint(x: 50, y: 48), end: CGPoint(x: 156, y: 124), color: .systemBlue, width: 32, shadow: true),
            EditorAnnotation(kind: .ellipse, start: CGPoint(x: 54, y: 50), end: CGPoint(x: 158, y: 122), color: .systemGreen, width: 24, shadow: true),
            EditorAnnotation(kind: .redaction, start: CGPoint(x: 44, y: 42), end: CGPoint(x: 148, y: 116), shadow: false)
        ]
        for annotation in annotations { try assertObjectExportMatchesCanvas(annotation) }
    }

    /// Compare the object-only export with the same annotation rendered at a known offset
    /// on a much larger transparent canvas. This catches clipping even when the reported
    /// bounds would otherwise define both the crop and the assertion window.
    private func assertObjectExportMatchesCanvas(_ annotation: EditorAnnotation) throws {
        let source = transparentImage(width: 240, height: 180)
        let bounds = AnnotationEditorModel.bounds(for: annotation)
        let exportRect = bounds.insetBy(dx: -1, dy: -1).integral
        let margin: CGFloat = 96
        let placement = CGPoint(x: margin - exportRect.minX, y: margin - exportRect.minY)
        let shifted = translated(annotation, by: placement)

        let object = try #require(AnnotationRenderer.render(annotation: annotation, sourceImage: source))
        let expectedWidth = Int(exportRect.width)
        let expectedHeight = Int(exportRect.height)
        let canvas = AnnotationRenderer.render(
            image: transparentImage(width: Int(margin) * 2 + expectedWidth, height: Int(margin) * 2 + expectedHeight),
            annotations: [shifted]
        )
        let objectBitmap = try bitmap(object)
        let canvasBitmap = try bitmap(canvas)

        #expect(objectBitmap.pixelsWide == expectedWidth)
        #expect(objectBitmap.pixelsHigh == expectedHeight)
        #expect(canvasBitmap.pixelsWide >= Int(margin) + expectedWidth)
        #expect(canvasBitmap.pixelsHigh >= Int(margin) + expectedHeight)
        try assertSameRaster(objectBitmap, canvasBitmap, at: CGPoint(x: margin, y: margin), width: expectedWidth, height: expectedHeight)
        try assertNoPaintOutsideExport(objectBitmap, canvasBitmap, at: CGPoint(x: margin, y: margin))

        // The reference canvas is transparent, so the comparison also ensures the export
        // retains transparent pixels around shapes such as filled rectangles and step marks.
        #expect(try #require(objectBitmap.colorAt(x: 0, y: 0)).alphaComponent < 0.02)
    }

    private func assertSameRaster(_ lhsImage: NSImage, _ rhsImage: NSImage) throws {
        let lhs = try bitmap(lhsImage)
        let rhs = try bitmap(rhsImage)
        try assertSameRaster(lhs, rhs, at: .zero, width: lhs.pixelsWide, height: lhs.pixelsHigh)
    }

    private func assertSameRaster(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, at origin: CGPoint, width: Int, height: Int) throws {
        var mismatches = 0
        for y in 0..<height {
            for x in 0..<width {
                let a = try #require(lhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try #require(rhs.colorAt(x: Int(origin.x) + x, y: Int(origin.y) + y)?.usingColorSpace(.deviceRGB))
                let alphaDelta = abs(a.alphaComponent - b.alphaComponent)
                let premultipliedDeltas = [
                    abs(a.redComponent * a.alphaComponent - b.redComponent * b.alphaComponent),
                    abs(a.greenComponent * a.alphaComponent - b.greenComponent * b.alphaComponent),
                    abs(a.blueComponent * a.alphaComponent - b.blueComponent * b.alphaComponent)
                ]
                if alphaDelta > 0.03 || (premultipliedDeltas.max() ?? 0) > 0.03 { mismatches += 1 }
            }
        }
        #expect(mismatches == 0, "Object export differs from its larger-canvas reference at \(mismatches) pixels")
    }

    private func assertNoPaintOutsideExport(_ object: NSBitmapImageRep, _ canvas: NSBitmapImageRep, at origin: CGPoint) throws {
        let left = Int(origin.x)
        let top = Int(origin.y)
        var outsidePaint = 0
        for y in 0..<canvas.pixelsHigh {
            for x in 0..<canvas.pixelsWide {
                let isInside = x >= left && x < left + object.pixelsWide && y >= top && y < top + object.pixelsHigh
                guard !isInside else { continue }
                if try #require(canvas.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)).alphaComponent > 0 {
                    outsidePaint += 1
                }
            }
        }
        #expect(outsidePaint == 0, "Larger-canvas render has \(outsidePaint) visible pixels beyond the object export")
    }

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        NSBitmapImageRep(cgImage: try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
    }

    private func transparentImage(width: Int, height: Int) -> NSImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return NSImage(cgImage: context.makeImage()!, size: CGSize(width: width, height: height))
    }

    private func translated(_ annotation: EditorAnnotation, by offset: CGPoint) -> EditorAnnotation {
        var moved = annotation
        moved.start = CGPoint(x: moved.start.x + offset.x, y: moved.start.y + offset.y)
        moved.end = CGPoint(x: moved.end.x + offset.x, y: moved.end.y + offset.y)
        moved.points = moved.points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
        return moved
    }
}
