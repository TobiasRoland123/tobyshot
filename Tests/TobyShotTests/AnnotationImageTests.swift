import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationImageTests {
    @Test func multiplePastesMoveResizeAndDeleteIndependentlyWithHistory() throws {
        let model = try makeModel()
        let mark = EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 5, y: 5),
                                    end: CGPoint(x: 15, y: 15), shadow: false)
        model.annotations = [mark]
        var states = [model.annotations]
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        model.tool = .arrow
        let first = try paste(width: 40, height: 20, into: model, board: board)
        #expect(model.tool == .select)
        #expect(model.selectedID == first.id)
        #expect(first.start == CGPoint(x: 40, y: 30))
        #expect(first.end == CGPoint(x: 80, y: 50))
        states.append(model.annotations)
        let second = try paste(width: 20, height: 40, into: model, board: board)
        #expect(second.id != first.id)
        #expect(second.start == CGPoint(x: 50, y: 20))
        #expect(second.end == CGPoint(x: 70, y: 60))
        #expect(model.annotations.map(\.id) == [first.id, second.id, mark.id])
        states.append(model.annotations)

        model.selectedID = first.id
        model.begin(at: CGPoint(x: 42, y: 32), hitTolerance: 0)
        model.continueDrag(to: CGPoint(x: 7, y: 32))
        model.endDrag()
        #expect(model.annotations[0].start == CGPoint(x: 5, y: 30))
        #expect(model.annotations[0].image === first.image)
        #expect(model.annotations[1] == second)
        #expect(model.annotations[2] == mark)
        states.append(model.annotations)

        #expect(model.beginShapeEdit(second.id, handle: .corner(.bottomRight), at: second.end))
        model.continueDrag(to: CGPoint(x: 80, y: 80))
        model.endDrag()
        #expect(model.annotations[1].start == second.start)
        #expect(model.annotations[1].end == CGPoint(x: 80, y: 80))
        #expect(model.annotations[0] == states[states.count - 1][0])
        states.append(model.annotations)
        model.selectedID = first.id
        model.deleteSelection()
        #expect(model.annotations.map(\.id) == [second.id, mark.id])
        states.append(model.annotations)

        for state in states.dropLast().reversed() {
            model.undo()
            #expect(model.annotations == state)
        }
        #expect(!model.canUndo)
        for state in states.dropFirst() {
            model.redo()
            #expect(model.annotations == state)
        }
        #expect(!model.canRedo)
    }

    @Test func duplicatedImageAndMarkMoveAndDeleteAsAGroup() throws {
        let model = try makeModel()
        let original = try imageAnnotation(at: CGPoint(x: 10, y: 10), width: 20, height: 10)
        let mark = EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 70, y: 20),
                                    end: CGPoint(x: 80, y: 30), shadow: false)
        model.annotations = [original, mark]
        model.selectedIDs = [original.id, mark.id]
        #expect(model.duplicateSelection())
        let duplicated = model.annotations
        let imageCopy = duplicated[1]
        let markCopy = duplicated[3]
        #expect(duplicated.map(\.kind) == [.image, .image, .filledRectangle, .filledRectangle])
        #expect(imageCopy.id != original.id)
        #expect(imageCopy.image === original.image)
        #expect(imageCopy.start == CGPoint(x: 22, y: 22))
        #expect(model.selectedIDs == [imageCopy.id, markCopy.id])
        model.begin(at: CGPoint(x: 25, y: 25), hitTolerance: 0)
        model.continueDrag(to: CGPoint(x: 45, y: 35))
        model.endDrag()
        let moved = model.annotations
        #expect(moved[0] == original && moved[2] == mark)
        #expect(moved[1].start == CGPoint(x: 42, y: 32))
        #expect(moved[3].start == CGPoint(x: 102, y: 42))
        model.deleteSelection()
        #expect(model.annotations == [original, mark])
        model.undo()
        #expect(model.annotations == moved)
        model.undo()
        #expect(model.annotations == duplicated)
        model.undo()
        #expect(model.annotations == [original, mark])
        model.redo()
        model.redo()
        model.redo()
        #expect(model.annotations == [original, mark])
    }

    @Test(arguments: AnnotationResizeCorner.allCases, [CGSize(width: 80, height: 40), CGSize(width: 40, height: 80)])
    func cornerResizeProjectsDragAndClampsWithoutFlipping(corner: AnnotationResizeCorner, size: CGSize) throws {
        let model = try makeModel()
        let original = try imageAnnotation(at: CGPoint(x: 20, y: 20), width: Int(size.width), height: Int(size.height))
        model.annotations = [original]
        let bounds = AnnotationShapeEdit.bounds(for: original)
        let handle = corner.point(in: bounds), anchor = corner.opposite.point(in: bounds)
        // A 50-pixel drag along the long axis projects to a 1.5x diagonal scale.
        let delta = size.width > size.height
            ? CGPoint(x: handle.x > anchor.x ? 50 : -50, y: 0)
            : CGPoint(x: 0, y: handle.y > anchor.y ? 50 : -50)
        #expect(model.beginShapeEdit(original.id, handle: .corner(corner), at: handle))
        model.continueDrag(to: CGPoint(x: handle.x + delta.x, y: handle.y + delta.y))
        model.endDrag()
        let resized = model.annotations[0]
        let resizedBounds = AnnotationShapeEdit.bounds(for: resized)
        #expect(resizedBounds.size == CGSize(width: size.width * 1.5, height: size.height * 1.5))
        #expect(corner.opposite.point(in: resizedBounds) == anchor)
        #expect(resized.image === original.image)

        #expect(model.beginShapeEdit(handle: .corner(corner), at: corner.point(in: resizedBounds)))
        model.continueDrag(to: CGPoint(x: 2 * anchor.x - handle.x, y: 2 * anchor.y - handle.y))
        model.endDrag()
        let minimum = AnnotationShapeEdit.bounds(for: model.annotations[0])
        #expect(abs(min(minimum.width, minimum.height) - 1) < 0.000001)
        #expect(abs(minimum.width / minimum.height - size.width / size.height) < 0.000001)
        #expect(corner.opposite.point(in: minimum) == anchor)
        model.undo()
        #expect(model.annotations == [resized])
        model.undo()
        #expect(model.annotations == [original])
        model.redo()
        #expect(model.annotations == [resized])
    }

    @Test(arguments: [(AnnotationTool.arrow, EditorAnnotation.Kind.arrow),
                      (.filledRectangle, .filledRectangle), (.text, .text), (.pixelate, .pixelation)])
    func drawingStartsOnImageInterior(tool: AnnotationTool, kind: EditorAnnotation.Kind) throws {
        let model = try makeModel()
        let image = try imageAnnotation(at: .zero, width: 120, height: 80)
        model.annotations = [image]
        model.selectedID = image.id
        model.tool = tool
        model.begin(at: CGPoint(x: 30, y: 25))
        if tool == .text {
            model.updateText("Over the image")
            model.finishTextEditing()
        } else {
            model.continueDrag(to: CGPoint(x: 70, y: 55))
        }
        model.endDrag()
        #expect(model.annotations.count == 2)
        #expect(model.annotations[0] == image)
        #expect(model.annotations[1].kind == kind)
        #expect(model.annotations[1].start == CGPoint(x: 30, y: 25))
        model.undo()
        #expect(model.annotations == [image])
    }

    @Test func existingMarkRemainsEditableAndVisibleAboveLaterPaste() throws {
        let model = try makeModel()
        let mark = EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 40, y: 20),
                                    end: CGPoint(x: 60, y: 40), color: .red, shadow: false)
        model.annotations = [mark]
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let image = try paste(width: 120, height: 80, into: model, board: board)
        model.tool = .arrow
        model.begin(at: CGPoint(x: 50, y: 30), hitTolerance: 0)
        model.continueDrag(to: CGPoint(x: 60, y: 35))
        model.endDrag()
        #expect(model.annotations.count == 2)
        #expect(model.annotations[0] == image)
        #expect(model.annotations[1].start == CGPoint(x: 50, y: 25))
        #expect(model.beginShapeEdit(mark.id, handle: .corner(.bottomRight), at: CGPoint(x: 70, y: 45)))
        model.continueDrag(to: CGPoint(x: 85, y: 55))
        model.endDrag()
        #expect(model.annotations[1].end == CGPoint(x: 85, y: 55))
        try expectColor(bitmap(model.renderedImage()), at: (60, 35), equals: .red)
    }

    @Test func imagesExpandEveryEdgeWithExactBoundsAndNoSelectionBorder() throws {
        let model = try makeModel(width: 40, height: 30)
        let origins = [CGPoint(x: -12, y: 5), CGPoint(x: 14, y: -9),
                       CGPoint(x: 44, y: 5), CGPoint(x: 14, y: 35)]
        model.annotations = try origins.map { try imageAnnotation(at: $0, width: 8, height: 6) }
        let expected = CGRect(x: -12, y: -9, width: 64, height: 50)
        #expect(model.canvasBounds == expected)
        #expect(model.imageBounds == expected)
        let rendered = try bitmap(model.renderedImage())
        #expect(rendered.pixelsWide == 64 && rendered.pixelsHigh == 50)
        for origin in origins {
            try expectColor(rendered, at: (Int(origin.x) + 16, Int(origin.y) + 12), equals: .blue)
        }
        try expectColor(rendered, at: (32, 24), equals: .white)
        try expectColor(rendered, at: (0, 0), equals: .clear)
        try assertRaster(preview(model), matches: rendered)
        model.selectedID = model.annotations[0].id
        let selection = try bitmap(#require(model.renderedSelection()))
        #expect(selection.pixelsWide == 8 && selection.pixelsHigh == 6)
        try expectColor(selection, at: (0, 0), equals: .blue)
        try expectColor(selection, at: (7, 5), equals: .blue)
    }

    @Test func imageOrientationAndAlphaSurviveExportSelectionAndPreview() throws {
        let model = try makeModel(width: 40, height: 32)
        let pixels = try fixture(width: 20, height: 16) { x, y in
            if y < 8 { return x < 10 ? .red : .green }
            if x < 10 { return .blue }
            if x < 16 && y < 14 { return NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 0.5) }
            return .clear
        }
        let image = EditorAnnotation(kind: .image, start: CGPoint(x: 10, y: 8),
                                     end: CGPoint(x: 30, y: 24), shadow: false, image: pixels)
        model.annotations = [image]
        let rendered = try bitmap(model.renderedImage())
        try expectColor(rendered, at: (13, 11), equals: .red)
        try expectColor(rendered, at: (23, 11), equals: .green)
        try expectColor(rendered, at: (13, 19), equals: .blue)
        try expectColor(rendered, at: (28, 22), equals: .white)
        try expectColor(rendered, at: (24, 20), equals: NSColor(deviceRed: 1, green: 0.5, blue: 0.5, alpha: 1))
        try assertRaster(preview(model), matches: rendered)
        model.selectedID = image.id
        try assertRaster(bitmap(#require(model.renderedSelection())), matches: NSBitmapImageRep(cgImage: pixels))
    }

    @Test(arguments: [CGPoint(x: -16, y: -16), CGPoint(x: 48, y: 32)])
    func pixelationSamplesImagesOutsideOriginalIncludingNegativeCoordinates(origin: CGPoint) throws {
        let model = try makeModel(width: 32, height: 24)
        let image = try stripedAnnotation(at: origin)
        let pixelation = EditorAnnotation(kind: .pixelation, start: image.start, end: image.end, width: 1, shadow: false)
        model.annotations = [image, pixelation]
        #expect(model.annotationBounds(pixelation) == CGRect(origin: origin, size: CGSize(width: 16, height: 16)))
        let bounds = model.canvasBounds
        let point = (Int(origin.x - bounds.minX) + 1, Int(origin.y - bounds.minY) + 1)
        let unpixelated = try bitmap(AnnotationRenderer.render(image: model.image, annotations: [image]))
        try expectColor(unpixelated, at: point, equals: .black)
        let rendered = try bitmap(model.renderedImage())
        try expectColor(rendered, at: point, equals: .gray)
        try expectColor(rendered, at: (point.0 + 2, point.1), equals: .gray)
        try assertRaster(preview(model), matches: rendered)
    }

    @Test func reusedPreviewInvalidatesPixelationAfterImageMoveDeleteAndUndo() throws {
        let model = try makeModel(width: 64, height: 48)
        let image = try stripedAnnotation(at: CGPoint(x: 8, y: 4))
        let pixelation = EditorAnnotation(kind: .pixelation, start: CGPoint(x: 8, y: 8),
                                         end: CGPoint(x: 48, y: 24), width: 1, shadow: false)
        model.annotations = [image, pixelation]
        let renderer = AnnotationPreviewRenderer()
        let first = try preview(model, renderer: renderer)
        try expectColor(first, at: (12, 12), equals: .gray)
        try expectColor(first, at: (36, 12), equals: .white)
        try assertRaster(first, matches: bitmap(model.renderedImage()))
        model.selectedID = image.id
        model.begin(at: CGPoint(x: 12, y: 5), hitTolerance: 0)
        model.continueDrag(to: CGPoint(x: 36, y: 5))
        model.endDrag()
        #expect(model.annotations[1] == pixelation)
        let moved = try preview(model, renderer: renderer)
        try expectColor(moved, at: (12, 12), equals: .white)
        try expectColor(moved, at: (36, 12), equals: .gray)
        try assertRaster(moved, matches: bitmap(model.renderedImage()))
        model.deleteSelection()
        let deleted = try preview(model, renderer: renderer)
        try expectColor(deleted, at: (36, 12), equals: .white)
        try assertRaster(deleted, matches: bitmap(model.renderedImage()))
        model.undo()
        try assertRaster(preview(model, renderer: renderer), matches: moved)
    }

    private func makeModel(width: Int = 120, height: Int = 80) throws -> AnnotationEditorModel {
        let pixels = try fixture(width: width, height: height) { _, _ in .white }
        let model = AnnotationEditorModel(image: NSImage(cgImage: pixels, size: CGSize(width: width, height: height)), sourceURL: nil)
        model.annotationShadow = false
        return model
    }

    private func paste(width: Int, height: Int, into model: AnnotationEditorModel, board: NSPasteboard) throws -> EditorAnnotation {
        let pixels = try fixture(width: width, height: height) { _, _ in .blue }
        let data = try #require(NSBitmapImageRep(cgImage: pixels).representation(using: .png, properties: [:]))
        board.clearContents()
        board.setData(data, forType: .png)
        #expect(model.pasteImage(from: board))
        return try #require(model.annotations.first { $0.id == model.selectedID })
    }

    private func imageAnnotation(at origin: CGPoint, width: Int, height: Int) throws -> EditorAnnotation {
        let pixels = try fixture(width: width, height: height) { _, _ in .blue }
        return EditorAnnotation(kind: .image, start: origin, end: CGPoint(x: origin.x + CGFloat(width), y: origin.y + CGFloat(height)),
                                shadow: false, image: pixels)
    }

    private func stripedAnnotation(at origin: CGPoint) throws -> EditorAnnotation {
        let pixels = try fixture(width: 16, height: 16) { x, _ in x % 4 < 2 ? .black : .white }
        return EditorAnnotation(kind: .image, start: origin, end: CGPoint(x: origin.x + 16, y: origin.y + 16),
                                shadow: false, image: pixels)
    }

    private func fixture(width: Int, height: Int, color: (Int, Int) -> NSColor) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for y in 0..<height { for x in 0..<width {
            context.setFillColor(color(x, y).cgColor)
            context.fill(CGRect(x: x, y: height - y - 1, width: 1, height: 1))
        } }
        return try #require(context.makeImage())
    }

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        NSBitmapImageRep(cgImage: try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
    }

    private func preview(_ model: AnnotationEditorModel, renderer: AnnotationPreviewRenderer? = nil) throws -> NSBitmapImageRep {
        let bounds = model.canvasBounds
        let context = try #require(CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        (renderer ?? AnnotationPreviewRenderer()).draw(image: model.image, annotations: model.annotations,
            canvasBounds: bounds, background: .none, cornerRadius: 0,
            imageOrigin: CGPoint(x: -bounds.minX, y: -bounds.minY), scale: 1, backingScale: 1, in: context)
        return NSBitmapImageRep(cgImage: try #require(context.makeImage()))
    }

    private func expectColor(_ bitmap: NSBitmapImageRep, at point: (Int, Int), equals expected: NSColor) throws {
        let actual = try #require(bitmap.colorAt(x: point.0, y: point.1)?.usingColorSpace(.deviceRGB))
        let expected = try #require(expected.usingColorSpace(.deviceRGB))
        #expect(colorDistance(actual, expected) < 0.03)
    }

    private func assertRaster(_ actual: NSBitmapImageRep, matches expected: NSBitmapImageRep) throws {
        #expect(actual.pixelsWide == expected.pixelsWide && actual.pixelsHigh == expected.pixelsHigh)
        var mismatches = 0
        for y in 0..<min(actual.pixelsHigh, expected.pixelsHigh) {
            for x in 0..<min(actual.pixelsWide, expected.pixelsWide) {
                let a = try #require(actual.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try #require(expected.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if colorDistance(a, b) >= 0.03 { mismatches += 1 }
            }
        }
        #expect(mismatches == 0, "Preview/export differ at \(mismatches) pixels")
    }

    private func colorDistance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        if a.alphaComponent < 0.01 && b.alphaComponent < 0.01 { return 0 }
        return max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent),
                   abs(a.blueComponent - b.blueComponent), abs(a.alphaComponent - b.alphaComponent))
    }
}
