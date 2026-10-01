import Foundation
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct CaptureRetentionTests {
    @Test func screenshotRetentionAgesUseInclusiveCutoffForAllOptions() throws {
        let now = date("2100-06-01T12:00:00Z")

        for days in [10, 30, 90, 120] {
            let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
            let newer = capture("newer-\(days)", date: cutoff.addingTimeInterval(0.001))
            let exact = capture("exact-\(days)", date: cutoff)
            let older = capture("older-\(days)", date: cutoff.addingTimeInterval(-0.001))
            let (store, directory) = try makeStore(with: [newer, exact, older])
            defer { try? FileManager.default.removeItem(at: directory) }

            try store.prune(now: now, screenshotDays: days, recordingDays: 0)

            #expect(store.items.map(\.id) == [newer.id])
            #expect(try persistedItems(in: directory).map(\.id) == [newer.id])
            #expect(FileManager.default.fileExists(atPath: store.url(for: newer).path))
            #expect(!FileManager.default.fileExists(atPath: store.url(for: exact).path))
            #expect(!FileManager.default.fileExists(atPath: store.url(for: older).path))
        }
    }

    @Test func screenshotRetentionOffPreservesOldScreenshotsWhileRecordingPolicyStillApplies() throws {
        let oldImage = capture("old-image-off", date: date("2090-01-01T00:00:00Z"))
        let oldRecording = capture("old-recording-off", date: date("2090-01-01T00:00:00Z"), kind: .video)
        let (store, directory) = try makeStore(with: [oldImage, oldRecording])
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = directory.appendingPathComponent("off-export.png")
        let bytes = Data([2, 4, 6])
        try bytes.write(to: export)
        try store.markExported(oldImage, at: export)
        let persistedImage = try #require(store.items.first { $0.id == oldImage.id })

        try store.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 0, recordingDays: 10)

        #expect(store.items == [persistedImage])
        #expect(try persistedItems(in: directory) == [persistedImage])
        #expect(FileManager.default.fileExists(atPath: store.url(for: oldImage).path))
        #expect(!FileManager.default.fileExists(atPath: store.url(for: oldRecording).path))
        #expect(try Data(contentsOf: export) == bytes)
    }

    @Test func expiredRecordingHistoryKeepsItsExportedFile() throws {
        let oldRecording = capture("old-recording-forever", date: date("2090-01-01T00:00:00Z"), kind: .video)
        let (_, directory) = try makeStore(with: [oldRecording])
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = directory.appendingPathComponent("recording-export.mp4")
        let exportBytes = Data([3, 1, 4, 1, 5, 9])
        try exportBytes.write(to: export)
        var itemWithExport = oldRecording
        itemWithExport.exportedPath = export.path
        itemWithExport.exportedPaths = [export.path]
        try writeIndex([itemWithExport], in: directory)
        let reopened = CaptureStore(directory: directory)

        try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 0, recordingDays: 120)

        #expect(reopened.items.isEmpty)
        #expect(try persistedItems(in: directory).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: reopened.url(for: oldRecording).path))
        #expect(try Data(contentsOf: export) == exportBytes)
    }

    @Test func expiredScreenshotDeletesAllExportsIncludingLegacyExportPath() throws {
        let first = capture("old-multi-export", date: date("2090-01-01T00:00:00Z"))
        let (store, directory) = try makeStore(with: [first])
        defer { try? FileManager.default.removeItem(at: directory) }
        let exports = ["export-one.png", "export-two.png"].map { directory.appendingPathComponent($0) }
        for (index, export) in exports.enumerated() {
            try Data([UInt8(index + 10)]).write(to: export)
            try store.markExported(try #require(store.items.first), at: export)
        }
        let second = try #require(store.items.first)
        #expect(second.exportedPath == exports[1].path)
        #expect(Set(second.exportedPaths ?? []) == Set(exports.map(\.path)))

        let legacy = capture("old-legacy-export", date: date("2090-01-01T00:00:00Z"))
        let legacyExport = directory.appendingPathComponent("legacy-export.png")
        try Data([44, 55]).write(to: legacyExport)
        var legacyWithExport = legacy
        legacyWithExport.exportedPath = legacyExport.path
        try writeIndex([second, legacyWithExport], in: directory)
        try Data([0x54, 0x53]).write(to: directory.appendingPathComponent(legacy.filename))
        let reopened = CaptureStore(directory: directory)

        try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(reopened.items.isEmpty)
        #expect(try persistedItems(in: directory).isEmpty)
        for url in exports + [legacyExport] {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func olderScreenshotExpiryDoesNotDeleteExportReassignedToNewerScreenshot() throws {
        let older = capture("older-export-owner", date: date("2090-01-01T00:00:00Z"))
        let newer = capture("newer-export-owner", date: date("2100-05-15T00:00:00Z"))
        let (store, directory) = try makeStore(with: [older, newer])
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = directory.appendingPathComponent("save-as.png")
        let bytes = Data([21, 34, 55])
        try bytes.write(to: export)
        try store.markExported(older, at: export)
        try store.markExported(newer, at: export)

        let reopened = CaptureStore(directory: directory)
        try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(reopened.items.map(\.id) == [newer.id])
        #expect(try persistedItems(in: directory).map(\.id) == [newer.id])
        #expect(!FileManager.default.fileExists(atPath: store.url(for: older).path))
        #expect(FileManager.default.fileExists(atPath: store.url(for: newer).path))
        #expect(try Data(contentsOf: export) == bytes)
    }

    @Test func legacySharedExportRemainsUntilItsNewerScreenshotExpires() throws {
        var older = capture("legacy-older-owner", date: date("2090-01-01T00:00:00Z"))
        var newer = capture("legacy-newer-owner", date: date("2100-05-15T00:00:00Z"))
        let (_, directory) = try makeStore(with: [older, newer])
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = directory.appendingPathComponent("legacy-shared.png")
        let bytes = Data([13, 21, 34])
        try bytes.write(to: export)
        older.exportedPath = export.path
        newer.exportedPath = export.path
        try writeIndex([older, newer], in: directory)
        let store = CaptureStore(directory: directory)

        try store.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(store.items == [newer])
        #expect(try Data(contentsOf: export) == bytes)
        try store.prune(now: date("2100-12-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: export.path))
    }

    @Test func failedScreenshotExportDeletionRetainsEntryAndContinuesPruning() throws {
        let blocked = capture("old-immutable-export", date: date("2090-01-01T00:00:00Z"))
        let removable = capture("old-removable", date: date("2090-01-02T00:00:00Z"))
        let (store, directory) = try makeStore(with: [blocked, removable])
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = directory.appendingPathComponent("immutable-export.png")
        try Data([31, 32, 33]).write(to: export)
        try store.markExported(blocked, at: export)
        let persistedBlocked = try #require(store.items.first { $0.id == blocked.id })
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: export.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: export.path) }

        #expect(throws: (any Error).self) {
            try store.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)
        }
        #expect(store.items == [persistedBlocked])
        #expect(try persistedItems(in: directory) == [persistedBlocked])
        #expect(FileManager.default.fileExists(atPath: store.url(for: blocked).path))
        #expect(FileManager.default.fileExists(atPath: export.path))
        #expect(!FileManager.default.fileExists(atPath: store.url(for: removable).path))

        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: export.path)
        try store.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(store.items.isEmpty)
        #expect(try persistedItems(in: directory).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: blocked).path))
        #expect(!FileManager.default.fileExists(atPath: export.path))
    }

    @Test func failedPruneIndexWriteRetainsCaptureAndRetryPersistsRemoval() throws {
        let old = capture("old-index-retry", date: date("2090-01-01T00:00:00Z"))
        let (store, directory) = try makeStore(with: [old])
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = directory.appendingPathComponent("history.json")
        let saved = directory.appendingPathComponent("history-saved.json")
        try FileManager.default.moveItem(at: history, to: saved)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: false)

        #expect(throws: (any Error).self) {
            try store.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 10, recordingDays: 0)
        }
        #expect(store.items == [old])
        #expect(FileManager.default.fileExists(atPath: store.url(for: old).path))

        try FileManager.default.removeItem(at: history)
        try FileManager.default.moveItem(at: saved, to: history)
        try store.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 10, recordingDays: 0)

        #expect(store.items.isEmpty)
        #expect(try persistedItems(in: directory).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: old).path))
    }

    private func makeStore(with items: [CaptureItem]) throws -> (CaptureStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TobyShot-Retention-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for item in items {
            try Data([0x54, 0x53]).write(to: directory.appendingPathComponent(item.filename))
        }
        try writeIndex(items, in: directory)
        return (CaptureStore(directory: directory), directory)
    }

    private func capture(_ name: String, date: Date, kind: CaptureItem.Kind = .image) -> CaptureItem {
        CaptureItem(id: UUID(), filename: "\(name).\(kind == .image ? "png" : "mp4")", title: name,
                    date: date, kind: kind, width: 2, height: 2)
    }

    private func writeIndex(_ items: [CaptureItem], in directory: URL) throws {
        let data = try JSONEncoder().encode(items)
        try data.write(to: directory.appendingPathComponent("history.json"), options: .atomic)
    }

    private func persistedItems(in directory: URL) throws -> [CaptureItem] {
        try JSONDecoder().decode([CaptureItem].self,
            from: Data(contentsOf: directory.appendingPathComponent("history.json")))
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
