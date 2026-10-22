import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct CaptureTextSearchTests {
    @Test func searchMatchesTitleOrRecognizedText() {
        var item = CaptureItem(id: UUID(), filename: "capture.png", title: "Screenshot 2026-10-21 at 14.02",
                               date: Date(), kind: .image, width: 4, height: 3)
        #expect(item.matches(""))
        #expect(item.matches("2026-10"))
        #expect(!item.matches("invoice"))

        item.recognizedText = "INVOICE No. 42 Total due"
        #expect(item.matches("invoice"))
        #expect(item.matches("no. 42 total"))
        #expect(item.matches("14.02"))
        #expect(!item.matches("receipt"))
    }

    @Test func historySavedBeforeTextSearchLoadsAndRecognizedTextRoundTrips() throws {
        let item = CaptureItem(id: UUID(), filename: "capture.png", title: "Old", date: Date(),
                               kind: .image, width: 4, height: 3)
        let legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        #expect(legacy["recognizedText"] == nil)
        #expect(try JSONDecoder().decode(CaptureItem.self, from: JSONSerialization.data(withJSONObject: legacy)) == item)

        var indexed = item
        indexed.recognizedText = ""
        #expect(try JSONDecoder().decode(CaptureItem.self, from: JSONEncoder().encode(indexed)) == indexed)
    }

    @Test func indexingReadsExistingAndNewScreenshotsAndSkipsRecordings() async throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("recording-source.mp4")
        try Data([1, 2, 3]).write(to: source)
        let store = CaptureStore(directory: directory)
        let older = try store.add(image: fixture(), title: "Older")
        let recording = try store.add(video: source, size: CGSize(width: 16, height: 12))
        let newer = try store.add(image: fixture(), title: "Newer")
        let reads = ReadLog()

        store.startTextIndexing { url in
            await reads.append(url.lastPathComponent)
            return "text in \(url.lastPathComponent)"
        }
        await store.waitForTextIndexing()

        #expect(await reads.names == [newer.filename, older.filename])
        #expect(store.items.map(\.recognizedText) == ["text in \(newer.filename)", nil, "text in \(older.filename)"])
        #expect(store.items.first { $0.id == recording.id }?.recognizedText == nil)

        let added = try store.add(image: fixture(), title: "Added later")
        await store.waitForTextIndexing()
        #expect(store.items.first?.id == added.id)
        #expect(store.items.first?.recognizedText == "text in \(added.filename)")

        // Recognized text is saved, so reopening the library does not read screenshots again.
        let reopened = CaptureStore(directory: directory)
        #expect(reopened.items == store.items)
        let rereads = ReadLog()
        reopened.startTextIndexing { url in
            await rereads.append(url.lastPathComponent)
            return ""
        }
        await reopened.waitForTextIndexing()
        #expect(await rereads.names.isEmpty)
    }

    @Test func unreadableScreenshotIsLeftForTheNextLaunch() async throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureStore(directory: directory)
        let unreadable = try store.add(image: fixture(), title: "Unreadable")
        let readable = try store.add(image: fixture(), title: "Readable")
        struct ReadFailure: Error {}

        store.startTextIndexing { url in
            if url.lastPathComponent == unreadable.filename { throw ReadFailure() }
            return ""
        }
        await store.waitForTextIndexing()

        #expect(store.items.first { $0.id == readable.id }?.recognizedText == "")
        #expect(store.items.first { $0.id == unreadable.id }?.recognizedText == nil)
        let reopened = CaptureStore(directory: directory)
        reopened.startTextIndexing { _ in "found later" }
        await reopened.waitForTextIndexing()
        #expect(reopened.items.first { $0.id == unreadable.id }?.recognizedText == "found later")
    }

    @Test func visionReadsTextFromSavedScreenshot() async throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureStore(directory: directory)
        let item = try store.add(image: textImage("Invoice 4821"))

        let text = try await TextRecognition.searchableText(in: store.url(for: item))

        #expect(text.localizedCaseInsensitiveContains("invoice"))
    }

    private actor ReadLog {
        private(set) var names: [String] = []
        func append(_ name: String) { names.append(name) }
    }

    private func textImage(_ text: String) -> NSImage {
        let size = CGSize(width: 640, height: 160)
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 64, weight: .semibold), .foregroundColor: NSColor.black])
            .draw(at: CGPoint(x: 32, y: 40))
        NSGraphicsContext.restoreGraphicsState()
        return NSImage(cgImage: context.makeImage()!, size: size)
    }

    private func fixture() -> NSImage {
        let context = CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        return NSImage(cgImage: context.makeImage()!, size: CGSize(width: 4, height: 3))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TobyShot-CaptureTextSearch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
