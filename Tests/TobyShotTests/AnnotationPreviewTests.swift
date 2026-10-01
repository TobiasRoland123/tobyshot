import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationPreviewTests {
    @Test func scaleOnePreviewMatchesExportForBackgroundAndAnnotationKinds() throws {
        let source = orientationFixture(width: 240, height: 180)
        let annotations = [
            EditorAnnotation(kind: .arrow, start: CGPoint(x: 25, y: 45), end: CGPoint(x: 112, y: 54), color: .systemBlue, width: 8, shadow: true, reversed: true, arrowBend: CGPoint(x: 8, y: 24)),
            EditorAnnotation(kind: .rectangle, start: CGPoint(x: 125, y: 20), end: CGPoint(x: 205, y: 75), color: .systemRed, width: 6, shadow: true),
            EditorAnnotation(kind: .freehand, start: CGPoint(x: 30, y: 100), end: CGPoint(x: 100, y: 145), points: [CGPoint(x: 30, y: 100), CGPoint(x: 65, y: 145), CGPoint(x: 100, y: 112)], color: .systemTeal, width: 9, shadow: true),
            EditorAnnotation(kind: .text, start: CGPoint(x: 120, y: 112), end: .zero, color: .systemPurple, width: 12, text: "Æble Ångström", shadow: true, font: .system),
            EditorAnnotation(kind: .step, start: CGPoint(x: 190, y: 125), end: .zero, color: .systemOrange, width: 12, step: 7, shadow: true),
            EditorAnnotation(kind: .pixelation, start: CGPoint(x: 15, y: 20), end: CGPoint(x: 90, y: 70), width: 4, shadow: false),
            EditorAnnotation(kind: .redaction, start: CGPoint(x: 45, y: 35), end: CGPoint(x: 82, y: 62), shadow: false),
            EditorAnnotation(kind: .pixelation, start: CGPoint(x: 42, y: 32), end: CGPoint(x: 74, y: 60), width: 2, shadow: false),
            EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 165, y: 30), end: CGPoint(x: 214, y: 60), color: .systemGreen, width: 5, shadow: true)
        ]

        let preview = try preview(source: source, annotations: annotations, background: .lavender, padding: 12, cornerRadius: 14)
        let exported = AnnotationRenderer.render(image: source, annotations: annotations, background: .lavender, padding: 12, cornerRadius: 14)
        try assertRaster(preview, matches: bitmap(exported))
        let raster = try bitmap(exported)
        let sourceRaster = try bitmap(source)
        #expect(raster.pixelsWide > sourceRaster.pixelsWide)
        #expect(raster.pixelsHigh > sourceRaster.pixelsHigh)
    }

    @Test func reusedPreviewRefreshesMovedPixelationAndSameSizeReplacementSource() throws {
        let firstSource = orientationFixture(width: 160, height: 120)
        let renderer = AnnotationPreviewRenderer()
        var annotations = [EditorAnnotation(kind: .pixelation, start: CGPoint(x: 12, y: 12), end: CGPoint(x: 62, y: 58), width: 2, shadow: false)]

        let first = try preview(source: firstSource, annotations: annotations, renderer: renderer)
        try assertRaster(first, matches: bitmap(AnnotationRenderer.render(image: firstSource, annotations: annotations)))

        annotations[0].start = CGPoint(x: 83, y: 50)
        annotations[0].end = CGPoint(x: 145, y: 104)
        annotations[0].width = 7
        let moved = try preview(source: firstSource, annotations: annotations, renderer: renderer)
        try assertRaster(moved, matches: bitmap(AnnotationRenderer.render(image: firstSource, annotations: annotations)))
        #expect(try rasterDifferenceCount(first, moved) > 0)

        let replacement = solidImage(width: 160, height: 120, color: .systemYellow)
        let replaced = try preview(source: replacement, annotations: annotations, renderer: renderer)
        try assertRaster(replaced, matches: bitmap(AnnotationRenderer.render(image: replacement, annotations: annotations)))
        #expect(colorDistance(try pixel(replaced, at: (20, 20)), try pixel(first, at: (20, 20))) > 0.03)

        let model = AnnotationEditorModel(image: firstSource, sourceURL: nil)
        model.tool = .crop
        model.begin(at: CGPoint(x: 20, y: 15))
        model.continueDrag(to: CGPoint(x: 120, y: 90))
        model.endDrag()
        let cropped = try preview(source: model.image, annotations: model.annotations, renderer: renderer)
        model.undo()
        let restored = try preview(source: model.image, annotations: model.annotations, renderer: renderer)
        try assertRaster(restored, matches: bitmap(model.renderedImage()))
        #expect(restored.pixelsWide > cropped.pixelsWide)
    }

    @Test func previewSupportsZoomAndTwoTimesBackingScale() throws {
        let source = orientationFixture(width: 120, height: 90)
        let renderer = AnnotationPreviewRenderer()
        let annotations = [EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 22, y: 18), end: CGPoint(x: 52, y: 38), color: .systemRed, shadow: false)]
        let normal = try preview(source: source, annotations: annotations, renderer: renderer)
        let zoomed = try preview(source: source, annotations: annotations, scale: 1.5, backingScale: 2, renderer: renderer)
        #expect(zoomed.pixelsWide == normal.pixelsWide * 3)
        #expect(zoomed.pixelsHigh == normal.pixelsHigh * 3)
        let expected = try pixel(normal, at: (35, 25))
        let actual = try pixel(zoomed, at: (105, 75))
        #expect(colorDistance(expected, actual) < 0.03)
        let smaller = try preview(source: source, annotations: annotations, scale: 0.5, renderer: renderer)
        #expect(colorDistance(expected, try pixel(smaller, at: (17, 12))) < 0.03)
        try assertRaster(preview(source: source, annotations: annotations, renderer: renderer), matches: normal)
    }

    @Test func equivalentZoomAndBackingScaleKeepShadowsAligned() throws {
        let source = orientationFixture(width: 120, height: 90)
        let annotation = EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 22, y: 18),
                                          end: CGPoint(x: 52, y: 38), color: .systemRed, shadow: true)
        let zoomed = try preview(source: source, annotations: [annotation], scale: 2)
        let retina = try preview(source: source, annotations: [annotation], backingScale: 2)
        try assertRaster(retina, matches: zoomed)
    }

    @Test(arguments: AnnotationFont.allCases)
    func textFontsRenderTheSameAsExport(font: AnnotationFont) throws {
        let source = orientationFixture(width: 180, height: 120)
        let annotation = EditorAnnotation(kind: .text, start: CGPoint(x: 24, y: 55), end: .zero,
            color: .systemPurple, width: 14, text: "Æblegrød Ångström", shadow: true, font: font)
        let previewImage = try preview(source: source, annotations: [annotation])
        try assertRaster(previewImage, matches: bitmap(AnnotationRenderer.render(image: source, annotations: [annotation])))
    }

    private func preview(
        source: NSImage,
        annotations: [EditorAnnotation],
        background: AnnotationBackground = .none,
        padding: CGFloat = 0,
        cornerRadius: CGFloat = 0,
        scale: CGFloat = 1,
        backingScale: CGFloat = 1,
        renderer: AnnotationPreviewRenderer? = nil
    ) throws -> NSBitmapImageRep {
        let sourceCGImage = try #require(source.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let sourceSize = CGSize(width: sourceCGImage.width, height: sourceCGImage.height)
        let bounds = AnnotationRenderer.canvasBounds(imageSize: sourceSize, annotations: annotations, background: background, padding: padding)
        let width = max(1, Int(ceil(bounds.width * scale * backingScale)))
        let height = max(1, Int(ceil(bounds.height * scale * backingScale)))
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: backingScale, y: backingScale)
        (renderer ?? AnnotationPreviewRenderer()).draw(image: source, annotations: annotations, canvasBounds: bounds, background: background,
            cornerRadius: cornerRadius,
            imageOrigin: CGPoint(x: -bounds.minX * scale, y: -bounds.minY * scale),
            scale: scale, backingScale: backingScale,
            shadowScale: CGSize(width: scale * backingScale, height: scale * backingScale), in: context)
        return NSBitmapImageRep(cgImage: try #require(context.makeImage()))
    }

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        NSBitmapImageRep(cgImage: try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
    }

    private func orientationFixture(width: Int, height: Int) -> NSImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)); context.fill(CGRect(x: width / 2, y: height / 2, width: width / 2, height: height / 2))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height / 2))
        return NSImage(cgImage: context.makeImage()!, size: CGSize(width: width, height: height))
    }

    private func solidImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSImage(cgImage: context.makeImage()!, size: CGSize(width: width, height: height))
    }

    private func pixel(_ bitmap: NSBitmapImageRep, at point: (Int, Int)) throws -> NSColor {
        try #require(bitmap.colorAt(x: point.0, y: point.1)?.usingColorSpace(.deviceRGB))
    }

    private func assertRaster(_ actual: NSBitmapImageRep, matches expected: NSBitmapImageRep) throws {
        #expect(actual.pixelsWide == expected.pixelsWide)
        #expect(actual.pixelsHigh == expected.pixelsHigh)
        var mismatches = 0
        for y in 0..<min(actual.pixelsHigh, expected.pixelsHigh) {
            for x in 0..<min(actual.pixelsWide, expected.pixelsWide) {
                let a = try pixel(actual, at: (x, y)), b = try pixel(expected, at: (x, y))
                if colorDistance(a, b) > 0.03 { mismatches += 1 }
            }
        }
        #expect(mismatches == 0, "Preview differs from export at \(mismatches) pixels")
    }

    private func rasterDifferenceCount(_ first: NSBitmapImageRep, _ second: NSBitmapImageRep) throws -> Int {
        guard first.pixelsWide == second.pixelsWide, first.pixelsHigh == second.pixelsHigh else { return .max }
        var differences = 0
        for y in 0..<first.pixelsHigh {
            for x in 0..<first.pixelsWide {
                if colorDistance(try pixel(first, at: (x, y)), try pixel(second, at: (x, y))) > 0.03 {
                    differences += 1
                }
            }
        }
        return differences
    }

    private func colorDistance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent),
            abs(a.blueComponent - b.blueComponent), abs(a.alphaComponent - b.alphaComponent))
    }
}
