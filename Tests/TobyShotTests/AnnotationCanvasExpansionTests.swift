import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationCanvasExpansionTests {
    @Test func canvasBoundsIncludePaintPastAllFourSourceEdgesAndPreserveTopLeftCoordinates() throws {
        let sourceSize = CGSize(width: 100, height: 80)
        let annotation = EditorAnnotation(kind: .rectangle,
            start: CGPoint(x: -18, y: -14), end: CGPoint(x: 118, y: 94),
            color: .systemRed, width: 12, shadow: true)
        let bounds = AnnotationRenderer.canvasBounds(imageSize: sourceSize, annotations: [annotation])
        let paintBounds = AnnotationGeometry(annotation, imageSize: sourceSize).exportBounds

        #expect(bounds == CGRect(origin: .zero, size: sourceSize).union(paintBounds))
        #expect(bounds.minX < 0 && bounds.minY < 0)
        #expect(bounds.maxX > sourceSize.width && bounds.maxY > sourceSize.height)

        let source = orientationFixture(width: 100, height: 80)
        let original = try bitmap(source)
        let pixelation = EditorAnnotation(kind: .pixelation, start: CGPoint(x: 5, y: 5), end: CGPoint(x: 40, y: 35), width: 2)
        let rendered = AnnotationRenderer.render(image: source, annotations: [annotation, pixelation])
        let bitmap = try bitmap(rendered)
        #expect(bitmap.pixelsWide == Int(bounds.width))
        #expect(bitmap.pixelsHigh == Int(bounds.height))
        let offsetX = Int(-bounds.minX), offsetY = Int(-bounds.minY)
        for point in [(20, 20), (20, 60), (80, 20), (80, 60)] {
            try expectSamePixel(bitmap, at: (offsetX + point.0, offsetY + point.1), matching: original, at: point)
        }
    }

    @Test func outsideShapesStrokesStepsTextAndShadowsMatchAnUnclippedReference() throws {
        let annotations = [
            EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: -20, y: 18), end: CGPoint(x: 20, y: 52), color: .systemOrange, width: 8, shadow: true),
            EditorAnnotation(kind: .freehand, start: CGPoint(x: 34, y: -7), end: CGPoint(x: 55, y: 8), points: [CGPoint(x: 34, y: -7), CGPoint(x: 44, y: 3), CGPoint(x: 55, y: 8)], color: .systemBlue, width: 26, shadow: true),
            EditorAnnotation(kind: .line, start: CGPoint(x: 68, y: 28), end: CGPoint(x: 114, y: 28), color: .systemRed, width: 32, shadow: true),
            EditorAnnotation(kind: .arrow, start: CGPoint(x: -12, y: 62), end: CGPoint(x: 38, y: 96), color: .systemTeal, width: 17, shadow: true, reversed: true, arrowSeed: 7),
            EditorAnnotation(kind: .step, start: CGPoint(x: 104, y: 66), end: CGPoint(x: 104, y: 66), color: .systemGreen, width: 12, step: 42, shadow: true),
            EditorAnnotation(kind: .text, start: CGPoint(x: 24, y: 91), end: .zero, color: .systemPurple, width: 9, text: "Multiline Æble\nÅngström qyp", shadow: true, font: .system)
        ]
        let source = transparentImage(width: 100, height: 80)
        for annotation in annotations {
            let actual = try bitmap(AnnotationRenderer.render(image: source, annotations: [annotation]))
            let margin = 160
            let exportBounds = AnnotationGeometry(annotation).exportBounds
            let shift = CGPoint(x: CGFloat(margin) - min(0, exportBounds.minX),
                                y: CGFloat(margin) - min(0, exportBounds.minY))
            let referenceWidth = Int(ceil(shift.x + max(100, exportBounds.maxX) + CGFloat(margin)))
            let referenceHeight = Int(ceil(shift.y + max(80, exportBounds.maxY) + CGFloat(margin)))
            let reference = try bitmap(AnnotationRenderer.render(
                image: transparentImage(width: referenceWidth, height: referenceHeight),
                annotations: [translated(annotation, by: shift)]
            ))
            let actualOrigin = CGPoint(x: margin, y: margin)
            try assertRaster(actual, equals: reference, at: actualOrigin)
            try assertNoPaintOutside(actual, in: reference, at: actualOrigin)
        }
    }

    @Test func emptyInsideAndOutsidePixelationAnnotationsDoNotGrowCanvas() {
        let sourceSize = CGSize(width: 100, height: 80)
        let inside = EditorAnnotation(kind: .ellipse, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 60, y: 50), shadow: false)
        let outsidePixelation = EditorAnnotation(kind: .pixelation, start: CGPoint(x: 120, y: 15), end: CGPoint(x: 145, y: 38), shadow: true)
        let emptyText = EditorAnnotation(kind: .text, start: CGPoint(x: -900, y: -700), end: .zero, text: "", shadow: true)
        let whitespaceText = EditorAnnotation(kind: .text, start: CGPoint(x: 800, y: 700), end: .zero, text: " \n  ", shadow: true)
        let original = CGRect(origin: .zero, size: sourceSize)

        #expect(AnnotationRenderer.canvasBounds(imageSize: sourceSize, annotations: []) == original)
        #expect(AnnotationRenderer.canvasBounds(imageSize: sourceSize, annotations: [inside]) == original)
        #expect(AnnotationRenderer.canvasBounds(imageSize: sourceSize, annotations: [outsidePixelation]) == original)
        #expect(AnnotationRenderer.canvasBounds(imageSize: sourceSize, annotations: [emptyText, whitespaceText]) == original)
    }

    @Test func backgroundPaddingOutsetsExpandedCanvasAndKeepsSourceCorners() throws {
        let source = orientationFixture(width: 100, height: 80)
        let original = try bitmap(source)
        let annotation = EditorAnnotation(kind: .line, start: CGPoint(x: 44, y: 32), end: CGPoint(x: 124, y: 54), width: 8, shadow: false)
        let padding: CGFloat = 9.5
        let bounds = AnnotationRenderer.canvasBounds(imageSize: source.size, annotations: [annotation], background: .lavender, padding: padding)
        let unpadded = CGRect(origin: .zero, size: source.size).union(AnnotationGeometry(annotation).exportBounds)
        #expect(bounds == unpadded.insetBy(dx: -10, dy: -10))
        let rendered = try bitmap(AnnotationRenderer.render(image: source, annotations: [annotation], background: .lavender, padding: padding, cornerRadius: 0))
        #expect(rendered.pixelsWide == Int(bounds.width))
        #expect(rendered.pixelsHigh == Int(bounds.height))
        let pad = Int(padding.rounded())
        let sourceOrigin = CGPoint(x: pad - Int(min(0, AnnotationGeometry(annotation).exportBounds.minX)),
                                   y: pad - Int(min(0, AnnotationGeometry(annotation).exportBounds.minY)))
        try expectSamePixel(rendered, at: (Int(sourceOrigin.x) + 8, Int(sourceOrigin.y) + 8), matching: original, at: (8, 8))
        try expectSamePixel(rendered, at: (Int(sourceOrigin.x) + 8, Int(sourceOrigin.y) + 72), matching: original, at: (8, 72))
        let addedArea = try #require(rendered.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        #expect(addedArea.alphaComponent > 0.99)
    }

    @Test func excludedLiveTextKeepsItsExpandedCanvasDimensions() throws {
        let model = AnnotationEditorModel(image: transparentImage(width: 120, height: 90), sourceURL: nil)
        model.tool = .text
        model.begin(at: CGPoint(x: 116, y: 44))
        model.updateText("Live text beyond the right edge\nSecond line")
        let textID = try #require(model.editingTextID)
        let liveImage = try bitmap(model.renderedImage())
        let previewImage = try bitmap(model.renderedImage(excluding: textID))
        #expect(liveImage.pixelsWide > 120)
        #expect(liveImage.size == previewImage.size)
    }

    @Test func liveTextUndoRedoAndDeletionRecalculateExpandedOutput() throws {
        let model = AnnotationEditorModel(image: transparentImage(width: 120, height: 90), sourceURL: nil)
        model.tool = .text
        model.begin(at: CGPoint(x: 116, y: 44))
        model.updateText("Live text beyond the right edge\nSecond line")
        let liveSize = try bitmap(model.renderedImage()).size
        #expect(liveSize.width > 120)
        #expect(model.editingTextID != nil)

        model.finishTextEditing()
        let annotation = try #require(model.annotations.first)
        model.undo()
        #expect(model.annotations.isEmpty)
        #expect(try bitmap(model.renderedImage()).size == CGSize(width: 120, height: 90))
        model.redo()
        #expect(model.annotations == [annotation])
        #expect(try bitmap(model.renderedImage()).size == liveSize)

        model.selectedID = annotation.id
        model.deleteSelection()
        #expect(model.annotations.isEmpty)
        #expect(try bitmap(model.renderedImage()).size == CGSize(width: 120, height: 90))
    }

    private func transparentImage(width: Int, height: Int) -> NSImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return NSImage(cgImage: context.makeImage()!, size: CGSize(width: width, height: height))
    }

    private func orientationFixture(width: Int, height: Int) -> NSImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)); context.fill(CGRect(x: width / 2, y: height / 2, width: width / 2, height: height / 2))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height / 2))
        return NSImage(cgImage: context.makeImage()!, size: CGSize(width: width, height: height))
    }

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        NSBitmapImageRep(cgImage: try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
    }

    private func expectSamePixel(_ bitmap: NSBitmapImageRep, at outputPoint: (Int, Int), matching source: NSBitmapImageRep, at sourcePoint: (Int, Int)) throws {
        let actual = try #require(bitmap.colorAt(x: outputPoint.0, y: outputPoint.1)?.usingColorSpace(.deviceRGB))
        let expected = try #require(source.colorAt(x: sourcePoint.0, y: sourcePoint.1)?.usingColorSpace(.deviceRGB))
        #expect(actual.alphaComponent > 0.99)
        #expect(abs(actual.redComponent - expected.redComponent) < 0.02)
        #expect(abs(actual.greenComponent - expected.greenComponent) < 0.02)
        #expect(abs(actual.blueComponent - expected.blueComponent) < 0.02)
    }

    private func assertRaster(_ actual: NSBitmapImageRep, equals reference: NSBitmapImageRep, at origin: CGPoint) throws {
        var mismatches = 0
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                let a = try #require(actual.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try #require(reference.colorAt(x: Int(origin.x) + x, y: Int(origin.y) + y)?.usingColorSpace(.deviceRGB))
                if abs(a.alphaComponent - b.alphaComponent) >= 0.03
                    || abs(a.redComponent * a.alphaComponent - b.redComponent * b.alphaComponent) >= 0.03
                    || abs(a.greenComponent * a.alphaComponent - b.greenComponent * b.alphaComponent) >= 0.03
                    || abs(a.blueComponent * a.alphaComponent - b.blueComponent * b.alphaComponent) >= 0.03 {
                    mismatches += 1
                }
            }
        }
        #expect(mismatches == 0, "Expanded output differs from reference at \(mismatches) pixels")
    }

    private func assertNoPaintOutside(_ actual: NSBitmapImageRep, in reference: NSBitmapImageRep, at origin: CGPoint) throws {
        let minX = Int(origin.x), minY = Int(origin.y)
        var outsidePaint = 0
        for y in 0..<reference.pixelsHigh {
            for x in 0..<reference.pixelsWide {
                let inside = x >= minX && x < minX + actual.pixelsWide && y >= minY && y < minY + actual.pixelsHigh
                if !inside {
                    let alpha = try #require(reference.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)).alphaComponent
                    if alpha >= 0.01 { outsidePaint += 1 }
                }
            }
        }
        #expect(outsidePaint == 0, "Reference raster paints outside expanded output at \(outsidePaint) pixels")
    }

    private func translated(_ annotation: EditorAnnotation, by offset: CGPoint) -> EditorAnnotation {
        var result = annotation
        result.start = CGPoint(x: result.start.x + offset.x, y: result.start.y + offset.y)
        result.end = CGPoint(x: result.end.x + offset.x, y: result.end.y + offset.y)
        result.points = result.points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
        return result
    }
}
