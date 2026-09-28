import Testing
import AppKit
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct TobyShotTests {
    @Test
    func testFilenameSanitizesPathsAndExpandsTokens() {
        let name = CaptureNaming.filename(template: "../capture:{date}/{time}\n", date: Date(timeIntervalSince1970: 1_700_000_000), retina: true)
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
        #expect(!name.contains("\n"))
        #expect(!name.contains("{date}"))
        #expect(name.hasSuffix("@2x"))
        #expect(CaptureNaming.filename(template: "  ").hasPrefix("TobyShot "))
    }

    @Test
    func testUniqueFilenameDoesNotOverwriteExistingFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([1]).write(to: dir.appendingPathComponent("Capture.png"))
        try Data([2]).write(to: dir.appendingPathComponent("Capture 2.png"))
        #expect(CaptureNaming.uniqueURL(directory: dir, name: "Capture", ext: "png").lastPathComponent == "Capture 3.png")
    }

    @Test
    func testAreaCoordinatesPreserveRetinaAndClipToScreen() {
        let result = CaptureGeometry.pixelRect(CGRect(x: 10.2, y: 15.1, width: 90, height: 100), scale: 2, bounds: CGRect(x: 0, y: 0, width: 150, height: 140))
        #expect(result == CGRect(x: 20, y: 30, width: 130, height: 110))
    }

    @Test
    func testRecordingDimensionsAreEvenAndPreserveAspectRatio() {
        let size = CaptureGeometry.recordingSize(CGSize(width: 1512, height: 982), scale: 2, maximum: "1080p")
        #expect(Int(size.width) % 2 == 0)
        #expect(size.height == 1080)
        #expect(abs(size.width / size.height - 1512.0 / 982.0) < 0.003)
        let large = CaptureGeometry.recordingSize(CGSize(width: 6000, height: 3000), scale: 2, maximum: "Original")
        #expect(large == CGSize(width: 4096, height: 2048))
    }

    @Test
    func testImageFormatsAndOpaqueJPEG() throws {
        let image = fixture()
        for (format, ext) in [("PNG", "png"), ("JPEG", "jpg"), ("TIFF", "tiff")] {
            let data = try ImageOutput.data(image, format: format)
            let decoded = try #require(NSBitmapImageRep(data: data))
            #expect(decoded.pixelsWide == 120)
            #expect(decoded.pixelsHigh == 100)
            #expect(ImageOutput.fileExtension(format) == ext)
        }
    }

    @Test
    func testRedactionReplacesPixelsWithOpaqueBlack() throws {
        let source = fixture()
        let annotation = EditorAnnotation(kind: .redaction, start: CGPoint(x: 5, y: 5), end: CGPoint(x: 45, y: 30), shadow: false)
        let rendered = AnnotationRenderer.render(image: source, annotations: [annotation])
        let bitmap = NSBitmapImageRep(cgImage: try ImageOutput.cgImage(rendered))
        let pixel = try #require(bitmap.colorAt(x: 20, y: 15)?.usingColorSpace(.deviceRGB))
        #expect(pixel.redComponent < 0.01)
        #expect(pixel.greenComponent < 0.01)
        #expect(pixel.blueComponent < 0.01)
        #expect(pixel.alphaComponent > 0.99)
        #expect(rendered.size == source.size)
    }

    @Test
    func testBackgroundAddsExactPixelPadding() throws {
        let image = AnnotationRenderer.render(image: fixture(), annotations: [], background: .lavender, padding: 24, cornerRadius: 8)
        let cg = try ImageOutput.cgImage(image)
        #expect(cg.width == 168)
        #expect(cg.height == 148)
    }

    @Test
    func testPixelationSamplesTheSelectedRows() throws {
        let annotation = EditorAnnotation(kind: .pixelation, start: CGPoint(x: 5, y: 5), end: CGPoint(x: 45, y: 30), width: 5, shadow: false)
        let image = AnnotationRenderer.render(image: fixture(), annotations: [annotation])
        let bitmap = NSBitmapImageRep(cgImage: try ImageOutput.cgImage(image))
        let pixel = try #require(bitmap.colorAt(x: 20, y: 15)?.usingColorSpace(.deviceRGB))
        #expect(pixel.redComponent > 0.9)
        #expect(pixel.blueComponent < 0.1)
        #expect(pixel.alphaComponent > 0.99)
    }

    @Test
    func testPixelationObjectExportClipsToSourcePixelsWithoutShadow() throws {
        let source = fixture()
        let annotation = EditorAnnotation(kind: .pixelation, start: CGPoint(x: -12.3, y: -5.4), end: CGPoint(x: 32.2, y: 25.1), width: 20, shadow: true)
        let model = AnnotationEditorModel(image: source, sourceURL: nil)
        // Pixelation paints whole pixels inside the source, even when dragged beyond it.
        #expect(model.annotationBounds(annotation) == CGRect(x: 0, y: 0, width: 33, height: 26))
        let exported = try #require(AnnotationRenderer.render(annotation: annotation, sourceImage: source))
        let bitmap = NSBitmapImageRep(cgImage: try ImageOutput.cgImage(exported))
        #expect(bitmap.pixelsWide == 35)
        #expect(bitmap.pixelsHigh == 28)
        for point in [(0, 14), (34, 14), (17, 0), (17, 27)] {
            #expect(try #require(bitmap.colorAt(x: point.0, y: point.1)).alphaComponent == 0)
        }
        let pixel = try #require(bitmap.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB))
        #expect(pixel.redComponent > 0.9)
        #expect(pixel.blueComponent < 0.1)
        #expect(pixel.alphaComponent == 1)

        let outside = EditorAnnotation(kind: .pixelation, start: CGPoint(x: 130, y: 110), end: CGPoint(x: 150, y: 130))
        #expect(AnnotationRenderer.render(annotation: outside, sourceImage: source) == nil)
    }

    @Test
    func testCropUsesTopLeftCoordinatesAndUndoRestoresSource() throws {
        let original = fixture()
        let model = AnnotationEditorModel(image: original, sourceURL: nil)
        model.tool = .crop
        model.begin(at: CGPoint(x: 50, y: 35))
        model.continueDrag(to: CGPoint(x: 10, y: 5))
        model.continueDrag(to: CGPoint(x: 5, y: 2))
        model.endDrag()
        #expect(model.pixelSize == CGSize(width: 45, height: 33))
        let bitmap = NSBitmapImageRep(cgImage: try ImageOutput.cgImage(model.image))
        let pixel = try #require(bitmap.colorAt(x: 3, y: 3)?.usingColorSpace(.deviceRGB))
        #expect(pixel.redComponent > 0.9)
        #expect(pixel.blueComponent < 0.1)
        model.undo()
        #expect(model.pixelSize == CGSize(width: 120, height: 100))
        model.redo()
        #expect(model.pixelSize == CGSize(width: 45, height: 33))
    }

    @Test
    func testHistoryPersistsAndRemovalPreservesExportedOriginal() throws {
        Preferences.register()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let export = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: export) }
        let store = CaptureStore(directory: dir)
        let item = try store.add(image: fixture(), title: "Test capture")
        try FileManager.default.copyItem(at: store.url(for: item), to: export)
        try store.markExported(item, at: export)
        let reloaded = CaptureStore(directory: dir)
        #expect(reloaded.items.count == 1)
        #expect(reloaded.items.first?.exportedPath == export.path)
        try reloaded.remove(item)
        #expect(reloaded.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: export.path))
        #expect(!FileManager.default.fileExists(atPath: store.url(for: item).path))
    }

    private func fixture() -> NSImage {
        let ctx = CGContext(data: nil, width: 120, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 100))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 50, width: 120, height: 50))
        return NSImage(cgImage: ctx.makeImage()!, size: CGSize(width: 120, height: 100))
    }
}
