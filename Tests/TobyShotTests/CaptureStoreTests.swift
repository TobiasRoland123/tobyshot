import AppKit
import Combine
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct CaptureStoreTests {
    @Test func legacyExportFieldsNormalizeIntoOrderedRecordsAndWriteOnlyCanonicalState() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let latest = directory.appendingPathComponent("latest.png")
        let fileOnly = directory.appendingPathComponent("file-only.png")
        let pathOnly = directory.appendingPathComponent("path-only.png")
        try Data([1, 2, 3]).write(to: latest)
        try Data([4, 5, 6]).write(to: fileOnly)
        let owned = try [latest, fileOnly].map { try #require(try CaptureExport.read(at: $0)) }
        let item = CaptureItem(id: UUID(), filename: "capture.png", title: "Legacy", date: Date(),
                               kind: .image, width: 4, height: 3)
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        legacy.removeValue(forKey: "exports")
        legacy["exportedPaths"] = [latest.path, pathOnly.path, latest.path]
        legacy["exportedPath"] = latest.path
        legacy["exportedFiles"] = try owned.map { export -> [String: Any] in
            let record = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(export)) as? [String: Any])
            var evidence = try #require(record["ownership"] as? [String: Any])
            evidence["path"] = export.path
            return evidence
        }

        let migrated = try JSONDecoder().decode(CaptureItem.self, from: JSONSerialization.data(withJSONObject: legacy))

        #expect(migrated.exports == [CaptureExport(path: pathOnly.path, ownership: nil), owned[1], owned[0]])
        #expect(migrated.exportedPath == latest.path)
        let encoded = try JSONEncoder().encode(migrated)
        let canonical = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(canonical["exportedPath"] == nil)
        #expect(canonical["exportedPaths"] == nil)
        #expect(canonical["exportedFiles"] == nil)
        #expect(try JSONDecoder().decode(CaptureItem.self, from: encoded) == migrated)

        // Once canonical records exist, stale legacy fields cannot resurrect associations.
        var mixed = canonical
        mixed["exportedPath"] = "/stale.png"
        mixed["exportedPaths"] = ["/stale.png"]
        #expect(try JSONDecoder().decode(CaptureItem.self, from: JSONSerialization.data(withJSONObject: mixed)) == migrated)
    }

    @Test func historyWithoutExportFieldsDecodesToEmptyCanonicalRecords() throws {
        let item = CaptureItem(id: UUID(), filename: "capture.png", title: "Unexported", date: Date(),
                               kind: .image, width: 4, height: 3)
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        legacy.removeValue(forKey: "exports")

        let decoded = try JSONDecoder().decode(CaptureItem.self, from: JSONSerialization.data(withJSONObject: legacy))

        #expect(decoded == item)
        #expect(decoded.exports.isEmpty)
        #expect(decoded.exportedPath == nil)
    }

    @Test func reexportMovesPathToEndAndRefreshesOwnershipAcrossReopening() throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureStore(directory: directory)
        let item = try store.add(image: fixture())
        let first = directory.appendingPathComponent("first.png")
        let second = directory.appendingPathComponent("second.png")
        try Data([1, 2, 3]).write(to: first)
        try Data([4, 5, 6]).write(to: second)
        try store.markExported(item, at: first)
        try store.markExported(item, at: second)
        let previous = try #require(store.items.first?.exports.first?.ownership)
        #expect(store.items.first?.exportedPath == second.path)
        try Data([7, 8, 9]).write(to: first, options: .atomic)

        try store.markExported(item, at: first)

        let updated = try #require(store.items.first)
        #expect(updated.exports.map(\.path) == [second.path, first.path])
        #expect(updated.exportedPath == first.path)
        let refreshed = try #require(updated.exports.last?.ownership)
        #expect(refreshed != previous)
        #expect(refreshed.contentHash != previous.contentHash)
        #expect(updated.exports.last == (try CaptureExport.read(at: first)))
        #expect(CaptureStore(directory: directory).items == [updated])
    }

    @Test func reassignmentRemovesEveryOlderAssociationAndDerivesEachRemainingPath() throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureStore(directory: directory)
        var first = try store.add(image: fixture(), title: "First owner")
        var second = try store.add(image: fixture(), title: "Second owner")
        let claimant = try store.add(image: fixture(), title: "Latest owner")
        let shared = directory.appendingPathComponent("shared.png")
        let firstRemaining = directory.appendingPathComponent("first-remaining.png")
        let secondRemaining = directory.appendingPathComponent("second-remaining.png")
        try Data([1, 2, 3]).write(to: shared)
        first.exports = [try #require(try CaptureExport.read(at: shared)), CaptureExport(path: firstRemaining.path, ownership: nil)]
        second.exports = [CaptureExport(path: secondRemaining.path, ownership: nil), CaptureExport(path: shared.path, ownership: nil)]
        try JSONEncoder().encode([claimant, second, first]).write(to: historyURL(in: directory), options: .atomic)
        let reopened = CaptureStore(directory: directory)
        try Data([7, 8, 9]).write(to: shared, options: .atomic)

        try reopened.markExported(claimant, at: shared)

        first.exports.removeAll { $0.path == shared.path }
        second.exports.removeAll { $0.path == shared.path }
        let updated = try #require(reopened.items.first)
        let refreshed = try #require(try CaptureExport.read(at: shared))
        #expect(reopened.items == [updated, second, first])
        #expect(updated.exports == [refreshed])
        #expect(updated.exportedPath == shared.path)
        #expect(reopened.items[1].exportedPath == secondRemaining.path)
        #expect(reopened.items[2].exportedPath == firstRemaining.path)
        #expect(CaptureStore(directory: directory).items == reopened.items)
    }

    @Test func failedReassignmentPublishesNothingAndPreservesAllCanonicalRecordsUntilRetry() throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureStore(directory: directory)
        let owner = try store.add(image: fixture(), title: "Original owner")
        let claimant = try store.add(image: fixture(), title: "New owner")
        let shared = directory.appendingPathComponent("shared.png")
        try Data([1, 2, 3]).write(to: shared)
        try store.markExported(owner, at: shared)
        let priorItems = store.items
        let priorBytes = try Data(contentsOf: historyURL(in: directory))
        let replacement = Data([7, 8, 9])
        try replacement.write(to: shared, options: .atomic)
        var publications: [CaptureStore.HistoryLoadState] = []
        let observation = store.$historyLoadState.dropFirst().sink { publications.append($0) }

        try withBlockedHistoryWrite(in: directory) {
            #expect(throws: (any Error).self) { try store.markExported(claimant, at: shared) }
        }

        #expect(publications.isEmpty)
        #expect(store.items == priorItems)
        #expect(try Data(contentsOf: historyURL(in: directory)) == priorBytes)
        #expect(CaptureStore(directory: directory).items == priorItems)
        #expect(try Data(contentsOf: shared) == replacement)
        try store.markExported(claimant, at: shared)
        let refreshed = try #require(try CaptureExport.read(at: shared))
        #expect(store.items[0].exports == [refreshed])
        #expect(store.items[1].exports.isEmpty)
        #expect(store.items[1].exportedPath == nil)
        #expect(publications.count == 1)
        guard case let .loaded(publishedItems) = try #require(publications.first) else {
            Issue.record("Expected committed capture history")
            return
        }
        #expect(publishedItems == store.items)
        #expect(CaptureStore(directory: directory).items == store.items)
        withExtendedLifetime(observation) {}
    }

    @Test func failedImageInsertionPreservesExistingHistoryAndLeavesNoOrphan() throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CaptureStore(directory: directory)
        let prior = try store.add(image: fixture(), title: "Prior capture")
        let priorBytes = try Data(contentsOf: historyURL(in: directory))
        var publications: [CaptureStore.HistoryLoadState] = []
        let observation = store.$historyLoadState.dropFirst().sink { publications.append($0) }

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
        var publications: [CaptureStore.HistoryLoadState] = []
        let observation = store.$historyLoadState.dropFirst().sink { publications.append($0) }

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
        var publications: [CaptureStore.HistoryLoadState] = []
        let observation = store.$historyLoadState.dropFirst().sink { state in
            publications.append(state)
            guard case let .loaded(items) = state else {
                Issue.record("A regular commit must not change the history load status")
                return
            }
            do {
                let persisted = try JSONDecoder().decode([CaptureItem].self, from: Data(contentsOf: historyURL(in: directory)))
                #expect(persisted == items)
            } catch { Issue.record(error) }
        }

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
        #expect(publications.count == 1)
        guard case let .loaded(publishedItems) = try #require(publications.first) else {
            Issue.record("Expected committed recording history")
            return
        }
        #expect(publishedItems == [inserted, prior])
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
        var publications: [CaptureStore.HistoryLoadState] = []
        let observation = store.$historyLoadState.dropFirst().sink { publications.append($0) }

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
        var publications: [CaptureStore.HistoryLoadState] = []
        let observation = store.$historyLoadState.dropFirst().sink { publications.append($0) }

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
        var publications: [CaptureStore.HistoryLoadState] = []
        let observation = store.$historyLoadState.dropFirst().sink { publications.append($0) }

        try store.remove(item)

        #expect(store.items.isEmpty)
        #expect(publications.count == 1)
        guard case let .loaded(publishedItems) = try #require(publications.first) else {
            Issue.record("Expected committed capture history")
            return
        }
        #expect(publishedItems.isEmpty)
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
