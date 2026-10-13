import AppKit
import Testing
import UniformTypeIdentifiers
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct ImageDropCoordinatorTests {
    @Test
    func imageOnlyDropOpensAnEditorWithTheDroppedPixels() async throws {
        let application = NSApplication.shared
        Preferences.register()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaultsName = "TobyShot.ImageDropTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        let app = AppCoordinator(shortcuts: HotKeyManager(defaults: defaults), store: CaptureStore(directory: directory))
        var editor: AnnotationEditorWindow?
        defer {
            editor?.close()
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: directory)
        }
        let context = try #require(CGContext(data: nil, width: 17, height: 13, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 17, height: 13))
        let image = NSImage(cgImage: try #require(context.makeImage()), size: CGSize(width: 17, height: 13))
        let data = try ImageOutput.data(image, format: "PNG")
        let provider = NSItemProvider(item: data as NSData, typeIdentifier: UTType.png.identifier)
        let existingWindows = Set(application.windows.map(ObjectIdentifier.init))

        #expect(!app.openDroppedImage([]))
        #expect(!app.openDroppedImage([NSItemProvider(object: "Text" as NSString)]))
        #expect(app.openDroppedImage([provider]))
        for _ in 0..<500 {
            editor = application.windows.lazy
                .filter { !existingWindows.contains(ObjectIdentifier($0)) }
                .compactMap { $0.windowController as? AnnotationEditorWindow }
                .first { $0.editorModel.image.size == image.size }
            if editor != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let opened = try #require(editor)
        #expect(opened.window?.isVisible == true)
        #expect(opened.editorModel.sourceURL == nil)
        let pixels = NSBitmapImageRep(cgImage: try ImageOutput.cgImage(opened.editorModel.image))
        #expect(pixels.pixelsWide == 17)
        #expect(pixels.pixelsHigh == 13)
        let color = try #require(pixels.colorAt(x: 8, y: 6)?.usingColorSpace(.sRGB))
        let original = try #require(NSBitmapImageRep(data: data))
        let expected = try #require(original.colorAt(x: 8, y: 6)?.usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - expected.redComponent) < 0.01)
        #expect(abs(color.greenComponent - expected.greenComponent) < 0.01)
        #expect(abs(color.blueComponent - expected.blueComponent) < 0.01)
        #expect(abs(color.alphaComponent - expected.alphaComponent) < 0.01)
        #expect(app.store.items.isEmpty)
    }
}
