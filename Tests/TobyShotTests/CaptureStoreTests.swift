import AppKit
import Combine
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct CaptureStoreTests {
    @Test func failedImageInsertionPreservesExistingHistoryAndLeavesNoOrphan() throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CaptureStore(directory: directory)
        let prior = try store.add(image: fixture(), title: "Prior capture")
        let priorBytes = try Data(contentsOf: historyURL(in: directory))
        var publications: [[CaptureItem]] = []
        let observation = store.$items.dropFirst().sink { publications.append($0) }

        try withBlockedHistoryWrite(in: directory) {
            #expect(throws: (any Error).self) {
                try store.add(image: fixture(), title: "Should roll back")
            }
        }

        #expect(publications.isEmpty)
        #expect(store.items == [prior])
        #expect(try Data(contentsOf: historyURL(in: directory)) == priorBytes)
        #expect(try Set(fileNames(in: directory)) == Set(["history.json", prior.filename]))
        #expect(try Data(contentsOf: store.url(for: prior)).count > 0)

        let reopened = CaptureStore(directory: directory)
        #expect(reopened.items == [prior])
        withExtendedLifetime(observation) {}
    }

    @Test func failedVideoInsertionWithEmptyHistoryPreservesSourceAndReopensEmpty() throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("recording-source.mp4")
        let sourceBytes = Data([0, 1, 2, 3, 255, 10])
        try sourceBytes.write(to: source)
        let store = CaptureStore(directory: directory)
        var publications: [[CaptureItem]] = []
        let observation = store.$items.dropFirst().sink { publications.append($0) }

        try withBlockedHistoryWrite(in: directory) {
            #expect(throws: (any Error).self) {
                try store.add(video: source, size: CGSize(width: 16, height: 12))
            }
        }

        #expect(publications.isEmpty)
        #expect(store.items.isEmpty)
        #expect(try Data(contentsOf: source) == sourceBytes)
        #expect(try fileNames(in: directory) == ["recording-source.mp4"])

        let reopened = CaptureStore(directory: directory)
        #expect(reopened.items.isEmpty)
        #expect(try Data(contentsOf: source) == sourceBytes)
        withExtendedLifetime(observation) {}
    }

    @Test func failedVideoInsertionPreservesSourceAndPriorHistoryThenRetryPersists() throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureStore(directory: directory)
        let prior = try store.add(image: fixture(), title: "Prior capture")
        let priorBytes = try Data(contentsOf: historyURL(in: directory))
        let source = directory.appendingPathComponent("recording-source.mp4")
        let sourceBytes = Data([9, 8, 7, 6, 0, 255])
        try sourceBytes.write(to: source)
        var publications: [[CaptureItem]] = []
        let observation = store.$items.dropFirst().sink { publications.append($0) }

        try withBlockedHistoryWrite(in: directory) {
            #expect(throws: (any Error).self) {
                try store.add(video: source, size: CGSize(width: 32, height: 24))
            }
        }

        #expect(publications.isEmpty)
        #expect(store.items == [prior])
        #expect(CaptureStore(directory: directory).items == [prior])
        #expect(try Data(contentsOf: source) == sourceBytes)
        #expect(try Data(contentsOf: historyURL(in: directory)) == priorBytes)
        #expect(try Set(fileNames(in: directory)) == Set(["history.json", prior.filename, "recording-source.mp4"]))

        let inserted = try store.add(video: source, size: CGSize(width: 32, height: 24))
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: store.url(for: inserted)) == sourceBytes)
        #expect(store.items == [inserted, prior])
        let reopened = CaptureStore(directory: directory)
        #expect(reopened.items == [inserted, prior])
        #expect(try Data(contentsOf: reopened.url(for: inserted)) == sourceBytes)
        withExtendedLifetime(observation) {}
    }

    @Test func failedExportMetadataUpdateRetainsPriorMetadataAndExternalFile() throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureStore(directory: directory)
        let item = try store.add(image: fixture(), title: "Exported capture")
        let existingExport = directory.appendingPathComponent("existing-export.png")
        let newExport = directory.appendingPathComponent("new-export.png")
        let existingBytes = Data([11, 12, 13])
        try existingBytes.write(to: existingExport)
        try Data([21, 22, 23]).write(to: newExport)
        try store.markExported(item, at: existingExport)
        let persistedItem = try #require(store.items.first)
        let priorBytes = try Data(contentsOf: historyURL(in: directory))
        var publications: [[CaptureItem]] = []
        let observation = store.$items.dropFirst().sink { publications.append($0) }

        try withBlockedHistoryWrite(in: directory) {
            #expect(throws: (any Error).self) {
                try store.markExported(persistedItem, at: newExport)
            }
        }

        #expect(publications.isEmpty)
        #expect(store.items == [persistedItem])
        #expect(store.items.first?.exportedPath == existingExport.path)
        #expect(try Data(contentsOf: existingExport) == existingBytes)
        #expect(try Data(contentsOf: historyURL(in: directory)) == priorBytes)
        let reopened = CaptureStore(directory: directory)
        #expect(reopened.items == [persistedItem])
        #expect(reopened.items.first?.exportedPath == existingExport.path)
        #expect(try Data(contentsOf: existingExport) == existingBytes)
        withExtendedLifetime(observation) {}
    }

    @Test func failedRemovalKeepsCaptureReadableAndRetryRemovesOnlyHistoryCopy() throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureStore(directory: directory)
        let item = try store.add(image: fixture(), title: "Keep until removal succeeds")
        let exported = directory.appendingPathComponent("user-export.png")
        let exportedBytes = Data([31, 32, 33, 34])
        try exportedBytes.write(to: exported)
        try store.markExported(item, at: exported)
        let persistedItem = try #require(store.items.first)
        let captureURL = store.url(for: item)
        let captureBytes = try Data(contentsOf: captureURL)
        let priorBytes = try Data(contentsOf: historyURL(in: directory))
        var publications: [[CaptureItem]] = []
        let observation = store.$items.dropFirst().sink { publications.append($0) }

        try withBlockedHistoryWrite(in: directory) {
            #expect(throws: (any Error).self) {
                try store.remove(persistedItem)
            }
        }

        #expect(publications.isEmpty)
        #expect(store.items == [persistedItem])
        #expect(CaptureStore(directory: directory).items == [persistedItem])
        #expect(store.items.first?.exportedPath == exported.path)
        #expect(try Data(contentsOf: captureURL) == captureBytes)
        #expect(try Data(contentsOf: exported) == exportedBytes)
        #expect(try Data(contentsOf: historyURL(in: directory)) == priorBytes)
        #expect(try Set(fileNames(in: directory)) == Set(["history.json", item.filename, "user-export.png"]))

        try store.remove(persistedItem)
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: captureURL.path))
        #expect(try Data(contentsOf: exported) == exportedBytes)
        #expect(CaptureStore(directory: directory).items.isEmpty)
        withExtendedLifetime(observation) {}
    }

    @Test func immutableCaptureCleanupFailureStillCommitsRemoval() throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureStore(directory: directory)
        let item = try store.add(image: fixture(), title: "Retained cleanup file")
        let captureURL = store.url(for: item)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: captureURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: captureURL.path) }
        var publications: [[CaptureItem]] = []
        let observation = store.$items.dropFirst().sink { publications.append($0) }

        try store.remove(item)

        #expect(store.items.isEmpty)
        #expect(publications == [[]])
        #expect(FileManager.default.fileExists(atPath: captureURL.path))
        #expect(CaptureStore(directory: directory).items.isEmpty)
        withExtendedLifetime(observation) {}
    }

    @Test func immutableRecordingSourceCleanupFailureStillCommitsInsertion() throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("immutable-source.mp4")
        let sourceBytes = Data([41, 42, 43, 44, 0, 255])
        try sourceBytes.write(to: source)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: source.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: source.path) }
        let store = CaptureStore(directory: directory)

        let item = try store.add(video: source, size: CGSize(width: 8, height: 6))
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: store.url(for: item).path) }

        #expect(store.items == [item])
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: source) == sourceBytes)
        #expect(try Data(contentsOf: store.url(for: item)) == sourceBytes)
        let reopened = CaptureStore(directory: directory)
        #expect(reopened.items == [item])
        #expect(try Data(contentsOf: reopened.url(for: item)) == sourceBytes)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TobyShot-CaptureStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func withBlockedHistoryWrite(in directory: URL, operation: () throws -> Void) throws {
        let history = historyURL(in: directory)
        let saved = directory.appendingPathComponent("history-saved-\(UUID().uuidString)")
        let hadHistory = FileManager.default.fileExists(atPath: history.path)
        if hadHistory { try FileManager.default.moveItem(at: history, to: saved) }
        do {
            try FileManager.default.createDirectory(at: history, withIntermediateDirectories: false)
        } catch {
            if hadHistory { try? FileManager.default.moveItem(at: saved, to: history) }
            throw error
        }
        defer {
            try? FileManager.default.removeItem(at: history)
            if hadHistory { try? FileManager.default.moveItem(at: saved, to: history) }
        }
        try operation()
    }

    private func historyURL(in directory: URL) -> URL {
        directory.appendingPathComponent("history.json")
    }

    private func fileNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private func fixture() -> NSImage {
        let context = CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        return NSImage(cgImage: context.makeImage()!, size: CGSize(width: 4, height: 3))
    }
}
