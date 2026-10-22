import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct CaptureThumbnailTests {
    @Test func decodesTo720PixelBoundPreservingAspectAndCachesImageIdentity() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = try store.add(image: fixture(width: 1_200, height: 600))

        let thumbnail = try #require(await store.thumbnail(for: item))
        let decoded = try #require(thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(decoded.width == 720)
        #expect(decoded.height == 360)
        #expect(await store.thumbnail(for: item) === thumbnail)
    }

    @Test func missingCorruptAndVideoCapturesHaveNoThumbnail() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageItem = try store.add(image: fixture())
        try Data("not an image".utf8).write(to: store.url(for: imageItem), options: .atomic)
        let missingItem = try store.add(image: fixture())
        try FileManager.default.removeItem(at: store.url(for: missingItem))
        let videoSource = directory.appendingPathComponent("source.mp4")
        try Data([1, 2, 3]).write(to: videoSource)
        let videoItem = try store.add(video: videoSource, size: CGSize(width: 16, height: 9))

        #expect(await store.thumbnail(for: imageItem) == nil)
        #expect(await store.thumbnail(for: missingItem) == nil)
        #expect(await store.thumbnail(for: videoItem) == nil)
    }

    @Test func canceledDecodeDoesNotPoisonTheNextRequest() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = try store.add(image: fixture(width: 1_200, height: 600))
        let canceledRequest = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await store.thumbnail(for: item)
        }

        #expect(await canceledRequest.value == nil)
        let thumbnail = try #require(await store.thumbnail(for: item))
        let decoded = try #require(thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(decoded.width == 720)
        #expect(decoded.height == 360)
    }

    @Test func removingCaptureInvalidatesItsCachedThumbnail() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = try store.add(image: fixture())
        #expect(await store.thumbnail(for: item) != nil)

        try store.remove(item)

        #expect(store.items.isEmpty)
        #expect(await store.thumbnail(for: item) == nil)
    }

    private func makeStore() throws -> (CaptureStore, URL) {
        Preferences.register()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TobyShot-Thumbnails-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (CaptureStore(directory: directory), directory)
    }

    private func fixture(width: Int = 4, height: Int = 3) -> NSImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSImage(cgImage: context.makeImage()!, size: CGSize(width: width, height: height))
    }
}
