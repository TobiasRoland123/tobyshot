import AppKit
import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct ImageDropImporterTests {
    @Test(arguments: [UTType.png, UTType.jpeg])
    func importsImageDataWithoutAFileURL(type: UTType) async throws {
        let data = try imageData(format: type == .jpeg ? "JPEG" : "PNG")
        let provider = NSItemProvider(item: data as NSData, typeIdentifier: type.identifier)

        let imported = try await load(provider)

        #expect(imported.sourceURL == nil)
        #expect(try ImageOutput.cgImage(imported.image).width == 2)
    }

    @Test
    func importsFinderFileURLAndPreservesItsSource() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("fixture.png")
        try imageData(format: "PNG").write(to: file)
        let provider = try #require(NSItemProvider(contentsOf: file))

        let imported = try await load(provider)

        #expect(imported.sourceURL == file)
        #expect(try ImageOutput.cgImage(imported.image).height == 2)
    }

    @Test
    func fileURLTakesPriorityWhenProviderAlsoHasImage() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("from-url.png")
        try imageData(format: "PNG").write(to: file)
        let provider = NSItemProvider(object: file as NSURL)
        let otherImage = NSImage(cgImage: try #require(makeCGImage()), size: NSSize(width: 2, height: 2))
        provider.registerObject(otherImage, visibility: .all)

        let imported = try await load(provider)

        #expect(imported.sourceURL == file)
    }

    @Test
    func missingFileURLFails() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingFile = directory.appendingPathComponent("missing.png")
        let provider = NSItemProvider(object: missingFile as NSURL)

        await #expect(throws: (any Error).self) { try await load(provider) }
    }

    @Test
    func rejectsUnsupportedTextWithoutCallingCompletion() async {
        let provider = NSItemProvider(object: "plain text" as NSString)
        var callbackCount = 0

        let accepted = ImageDropImporter.load(from: provider) { _ in callbackCount += 1 }

        #expect(!accepted)
        await Task.yield()
        #expect(callbackCount == 0)
    }

    @Test
    func malformedImageDataFails() async throws {
        let provider = NSItemProvider(item: Data("not a PNG".utf8) as NSData, typeIdentifier: UTType.png.identifier)

        await #expect(throws: (any Error).self) { try await load(provider) }
    }

    @Test
    func providerDataLoadErrorIsReported() async throws {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(nil, CocoaError(.fileReadUnknown))
            return nil
        }

        await #expect(throws: (any Error).self) { try await load(provider) }
    }

    private func load(_ provider: NSItemProvider) async throws -> ImageDropImporter.ImportedImage {
        try await withCheckedThrowingContinuation { continuation in
            let accepted = ImageDropImporter.load(from: provider) { result in
                continuation.resume(with: result)
            }
            if !accepted { continuation.resume(throwing: CocoaError(.fileReadUnsupportedScheme)) }
        }
    }

    private func imageData(format: String) throws -> Data {
        try ImageOutput.data(NSImage(cgImage: try #require(makeCGImage()), size: NSSize(width: 2, height: 2)), format: format)
    }

    private func makeCGImage() -> CGImage? {
        guard let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return context.makeImage()
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
