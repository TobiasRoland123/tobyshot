import AppKit
import Combine
import Foundation
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct CaptureHistoryRecoveryTests {
    @Test func malformedHistoryBlocksEveryMutationAndRetryRestoresTheLibrary() throws {
        try malformedHistoryBlocksEveryMutationAndRetryRestoresTheLibrary(corruption: .malformedJSON)
    }

    @Test func incompatibleEntryBlocksEveryMutationAndRetryRestoresTheLibrary() throws {
        try malformedHistoryBlocksEveryMutationAndRetryRestoresTheLibrary(corruption: .incompatibleEntry)
    }

    @Test func retryPublishesOneCompleteSnapshotAfterFilteringMissingFilesAndClearingThumbnails() async throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let seedStore = CaptureStore(directory: directory)
        let prior = try seedStore.add(image: fixture(), title: "Restored capture")
        let missing = CaptureItem(id: UUID(), filename: "missing.png", title: "Missing capture",
                                  date: prior.date, kind: .image, width: 4, height: 3)
        let history = historyURL(in: directory)
        try Data("invalid history".utf8).write(to: history)
        let blocked = CaptureStore(directory: directory)
        #expect(blocked.historyLoadError != nil)
        #expect(try #require(await blocked.thumbnail(for: prior)).size == NSSize(width: 4, height: 3))
        try ImageOutput.data(fixture(width: 8, height: 6), format: "PNG").write(to: blocked.url(for: prior), options: .atomic)
        let restoredHistory = try JSONEncoder().encode([prior, missing])
        try restoredHistory.write(to: history, options: .atomic)
        var publications: [CaptureStore.HistoryLoadState] = []
        let observation = blocked.$historyLoadState.dropFirst().sink { state in
            publications.append(state)
            // Inspect the emitted snapshot: @Published notifies before its property is set.
            guard case let .loaded(items) = state else {
                Issue.record("Recovery must publish a complete loaded snapshot")
                return
            }
            #expect(items == [prior])
        }

        try blocked.retryHistoryLoad()

        #expect(publications.count == 1)
        #expect(blocked.items == [prior])
        #expect(blocked.historyLoadError == nil)
        #expect(await blocked.thumbnail(for: prior)?.size == NSSize(width: 8, height: 6))
        #expect(try Data(contentsOf: history) == restoredHistory)
        // A retry on an already loaded store must not republish its state.
        try blocked.retryHistoryLoad()
        #expect(publications.count == 1)
        withExtendedLifetime(observation) {}
    }

    @Test func absentAndEmptyIndexesStartAsWritableLibrariesAndMissingRetryStaysBlocked() throws {
        Preferences.register()
        let absentDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: absentDirectory) }

        let absentStore = CaptureStore(directory: absentDirectory)
        #expect(absentStore.historyLoadError == nil)
        #expect(absentStore.items.isEmpty)
        let absentCapture = try absentStore.add(image: fixture(), title: "Created without an index")
        #expect(CaptureStore(directory: absentDirectory).items == [absentCapture])

        let emptyDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: emptyDirectory) }
        try Data("[]".utf8).write(to: historyURL(in: emptyDirectory))
        let emptyStore = CaptureStore(directory: emptyDirectory)
        #expect(emptyStore.historyLoadError == nil)
        #expect(emptyStore.items.isEmpty)
        let emptyCapture = try emptyStore.add(image: fixture(), title: "Created from an empty index")
        #expect(CaptureStore(directory: emptyDirectory).items == [emptyCapture])

        let missingDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: missingDirectory) }
        let history = historyURL(in: missingDirectory)
        let validEmptyIndex = Data("[]".utf8)
        try Data("not json".utf8).write(to: history)
        let blockedStore = CaptureStore(directory: missingDirectory)
        #expect(blockedStore.historyLoadError != nil)
        try FileManager.default.removeItem(at: history)

        #expect(throws: (any Error).self) { try blockedStore.retryHistoryLoad() }
        #expect(blockedStore.historyLoadError != nil)
        #expect(throws: (any Error).self) { try blockedStore.add(image: fixture(), title: "Still blocked") }
        #expect(!FileManager.default.fileExists(atPath: history.path))

        try validEmptyIndex.write(to: history)
        try blockedStore.retryHistoryLoad()
        #expect(blockedStore.historyLoadError == nil)
        #expect(blockedStore.items.isEmpty)
        let recoveredCapture = try blockedStore.add(image: fixture(), title: "Created after index recovery")
        #expect(CaptureStore(directory: missingDirectory).items == [recoveredCapture])
    }

    @Test func transientReadFailureCanBeRetriedAfterReopeningAndMutationPersistsPriorState() throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let seedStore = CaptureStore(directory: directory)
        let prior = try seedStore.add(image: fixture(), title: "Prior title")
        let priorDate = prior.date
        let exported = directory.appendingPathComponent("prior-export.png")
        let exportBytes = Data([19, 23, 29, 31])
        try exportBytes.write(to: exported)
        try seedStore.markExported(prior, at: exported)
        let persistedPrior = try #require(seedStore.items.first)
        let persistedBytes = try Data(contentsOf: historyURL(in: directory))
        var failuresRemaining = 2

        let reopened = CaptureStore(directory: directory) { url in
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw CocoaError(.fileReadNoPermission)
            }
            return try Data(contentsOf: url)
        }

        #expect(failuresRemaining == 1)
        #expect(reopened.historyLoadError != nil)
        #expect(reopened.items.isEmpty)
        var publications: [CaptureStore.HistoryLoadState] = []
        let observation = reopened.$historyLoadState.dropFirst().sink { publications.append($0) }
        let failedDescription = try #require(reopened.historyLoadError?.localizedDescription)
        #expect(failedDescription.lowercased().contains("history.json"))
        #expect(throws: (any Error).self) { try reopened.add(image: fixture(), title: "Blocked during read failure") }
        #expect(publications.isEmpty)

        #expect(throws: (any Error).self) { try reopened.retryHistoryLoad() }
        #expect(reopened.historyLoadError != nil)
        #expect(reopened.items.isEmpty)
        #expect(publications.count == 1)
        guard case .failed = try #require(publications.first) else {
            Issue.record("Failed reads must not publish loaded captures")
            return
        }
        #expect(try Data(contentsOf: historyURL(in: directory)) == persistedBytes)
        #expect(try Data(contentsOf: exported) == exportBytes)

        try reopened.retryHistoryLoad()
        #expect(reopened.historyLoadError == nil)
        #expect(reopened.items == [persistedPrior])
        #expect(publications.count == 2)
        guard case let .loaded(publishedItems) = try #require(publications.last) else {
            Issue.record("Expected the recovered capture snapshot")
            return
        }
        #expect(publishedItems == [persistedPrior])
        let inserted = try reopened.add(image: fixture(), title: "After recovery")

        let finalStore = CaptureStore(directory: directory)
        #expect(finalStore.historyLoadError == nil)
        #expect(finalStore.items == [inserted, persistedPrior])
        #expect(finalStore.items[1].title == "Prior title")
        #expect(finalStore.items[1].date == priorDate)
        #expect(finalStore.items[1].exports == persistedPrior.exports)
        #expect(finalStore.items[1].exportedPath == exported.path)
        #expect(try Data(contentsOf: exported) == exportBytes)
        withExtendedLifetime(observation) {}
    }

    @Test(arguments: [false, true])
    func unreadableIndexIsNotTreatedAsAbsentAndRestoringItEnablesRetry(symbolicLink: Bool) throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let seedStore = CaptureStore(directory: directory)
        let prior = try seedStore.add(image: fixture(), title: "Preserved during filesystem failure")
        let history = historyURL(in: directory)
        let savedHistory = directory.appendingPathComponent("saved-history.json")
        let savedBytes = try Data(contentsOf: history)
        try FileManager.default.moveItem(at: history, to: savedHistory)
        if symbolicLink {
            try FileManager.default.createSymbolicLink(at: history, withDestinationURL: directory.appendingPathComponent("missing-history.json"))
        } else {
            try FileManager.default.createDirectory(at: history, withIntermediateDirectories: false)
        }
        let namesBefore = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let blocked = CaptureStore(directory: directory)
        #expect(blocked.historyLoadError != nil)
        #expect(throws: (any Error).self) { try blocked.add(image: fixture(), title: "Blocked") }
        #expect(throws: (any Error).self) { try blocked.retryHistoryLoad() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == namesBefore)
        let attributes = try FileManager.default.attributesOfItem(atPath: history.path)
        #expect(attributes[.type] as? FileAttributeType == (symbolicLink ? .typeSymbolicLink : .typeDirectory))
        #expect(try Data(contentsOf: savedHistory) == savedBytes)
        #expect(CaptureStore(directory: directory).historyLoadError != nil)

        try FileManager.default.removeItem(at: history)
        try FileManager.default.moveItem(at: savedHistory, to: history)
        try blocked.retryHistoryLoad()
        #expect(blocked.historyLoadError == nil)
        #expect(blocked.items == [prior])
        let inserted = try blocked.add(image: fixture(), title: "After restoring the index")
        #expect(CaptureStore(directory: directory).items == [inserted, prior])
    }

    private enum Corruption {
        case malformedJSON
        case incompatibleEntry
    }

    private func malformedHistoryBlocksEveryMutationAndRetryRestoresTheLibrary(corruption: Corruption) throws {
        Preferences.register()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let seedStore = CaptureStore(directory: directory)
        let prior = try seedStore.add(image: fixture(), title: "Retained capture")
        let export = directory.appendingPathComponent("retained-export.png")
        let captureBytes = try Data(contentsOf: seedStore.url(for: prior))
        let exportBytes = Data([2, 3, 5, 7, 11])
        try exportBytes.write(to: export)
        try seedStore.markExported(prior, at: export)
        let persistedPrior = try #require(seedStore.items.first)
        let goodHistory = try Data(contentsOf: historyURL(in: directory))
        let badHistory: Data
        switch corruption {
        case .malformedJSON:
            badHistory = Data("{ definitely not valid JSON".utf8)
        case .incompatibleEntry:
            var entries = try #require(JSONSerialization.jsonObject(with: goodHistory) as? [[String: Any]])
            var invalidEntry = try #require(entries.first)
            invalidEntry.removeValue(forKey: "title")
            entries.append(invalidEntry)
            badHistory = try JSONSerialization.data(withJSONObject: entries)
        }
        try badHistory.write(to: historyURL(in: directory), options: .atomic)
        let failedStore = CaptureStore(directory: directory)
        let loadDescription = try #require(failedStore.historyLoadError?.localizedDescription)
        let lowercasedDescription = loadDescription.lowercased()
        #expect(lowercasedDescription.contains("capture library"))
        #expect(lowercasedDescription.contains("history has been kept"))
        #expect(lowercasedDescription.contains("retry"))
        #expect(loadDescription.contains(historyURL(in: directory).path))
        let videoSource = directory.appendingPathComponent("video-source.mp4")
        let videoBytes = Data([0, 255, 4, 8, 15, 16, 23, 42])
        try videoBytes.write(to: videoSource)
        let beforeMutations = try directoryContents(in: directory)
        let priorItems = failedStore.items
        var publications: [CaptureStore.HistoryLoadState] = []
        let observation = failedStore.$historyLoadState.dropFirst().sink { publications.append($0) }

        let imageError = #expect(throws: (any Error).self) {
            try failedStore.add(image: fixture(), title: "Must not be written")
        }
        expectRecoveryError(imageError, historyURL: historyURL(in: directory))
        let videoError = #expect(throws: (any Error).self) {
            try failedStore.add(video: videoSource, size: CGSize(width: 32, height: 24))
        }
        expectRecoveryError(videoError, historyURL: historyURL(in: directory))
        let exportError = #expect(throws: (any Error).self) { try failedStore.markExported(persistedPrior, at: export) }
        expectRecoveryError(exportError, historyURL: historyURL(in: directory))
        let removeError = #expect(throws: (any Error).self) { try failedStore.remove(persistedPrior) }
        expectRecoveryError(removeError, historyURL: historyURL(in: directory))
        let pruneError = #expect(throws: (any Error).self) {
            try failedStore.prune(now: Date().addingTimeInterval(40 * 86_400), screenshotDays: 1, recordingDays: 1)
        }
        expectRecoveryError(pruneError, historyURL: historyURL(in: directory))

        #expect(publications.isEmpty)
        #expect(throws: (any Error).self) { try failedStore.retryHistoryLoad() }
        #expect(publications.count == 1)
        guard case .failed = try #require(publications.first) else {
            Issue.record("Invalid indexes must not publish partial loaded captures")
            return
        }
        #expect(failedStore.items == priorItems)
        #expect(try directoryContents(in: directory) == beforeMutations)
        #expect(try Data(contentsOf: historyURL(in: directory)) == badHistory)
        #expect(try Data(contentsOf: seedStore.url(for: prior)) == captureBytes)
        #expect(try Data(contentsOf: export) == exportBytes)
        #expect(try Data(contentsOf: videoSource) == videoBytes)
        let stillFailed = CaptureStore(directory: directory)
        #expect(stillFailed.historyLoadError != nil)
        #expect(try Data(contentsOf: historyURL(in: directory)) == badHistory)

        try goodHistory.write(to: historyURL(in: directory), options: .atomic)
        try failedStore.retryHistoryLoad()
        #expect(failedStore.historyLoadError == nil)
        #expect(failedStore.items == [persistedPrior])
        #expect(publications.count == 2)
        guard case let .loaded(publishedItems) = try #require(publications.last) else {
            Issue.record("Expected the recovered capture snapshot")
            return
        }
        #expect(publishedItems == [persistedPrior])
        let recovered = try failedStore.add(image: fixture(), title: "New capture")
        let reopened = CaptureStore(directory: directory)
        #expect(reopened.historyLoadError == nil)
        #expect(reopened.items == [recovered, persistedPrior])
        #expect(reopened.items[1].title == "Retained capture")
        #expect(reopened.items[1].date == persistedPrior.date)
        #expect(reopened.items[1].exports == persistedPrior.exports)
        #expect(reopened.items[1].exportedPath == export.path)
        #expect(try Data(contentsOf: reopened.url(for: persistedPrior)) == captureBytes)
        #expect(try Data(contentsOf: export) == exportBytes)
        withExtendedLifetime(observation) {}
    }

    private func expectRecoveryError(_ error: (any Error)?, historyURL: URL, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let error else {
            Issue.record("Expected a history recovery error", sourceLocation: sourceLocation)
            return
        }
        let description = error.localizedDescription.lowercased()
        #expect(description.contains("capture library"), sourceLocation: sourceLocation)
        #expect(description.contains("history has been kept"), sourceLocation: sourceLocation)
        #expect(description.contains("retry"), sourceLocation: sourceLocation)
        #expect(error.localizedDescription.contains(historyURL.path), sourceLocation: sourceLocation)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TobyShot-CaptureHistoryRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func historyURL(in directory: URL) -> URL {
        directory.appendingPathComponent("history.json")
    }

    private func directoryContents(in directory: URL) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(atPath: directory.path).map { name in
            (name, try Data(contentsOf: directory.appendingPathComponent(name)))
        })
    }

    private func fixture(width: Int = 4, height: Int = 3) -> NSImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSImage(cgImage: context.makeImage()!, size: CGSize(width: width, height: height))
    }
}
