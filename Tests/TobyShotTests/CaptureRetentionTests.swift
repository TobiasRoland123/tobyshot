import Foundation
import Combine
import Darwin
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
        let (store, directory) = try makeStore(with: [oldRecording])
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = directory.appendingPathComponent("recording-export.mp4")
        let exportBytes = Data([3, 1, 4, 1, 5, 9])
        try exportBytes.write(to: export)
        try store.markExported(oldRecording, at: export)
        let itemWithExport = try #require(store.items.first)
        #expect(itemWithExport.exports == [CaptureExport(path: export.path, ownership: nil)])
        let reopened = CaptureStore(directory: directory)
        #expect(reopened.items == [itemWithExport])

        try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 0, recordingDays: 120)

        #expect(reopened.items.isEmpty)
        #expect(try persistedItems(in: directory).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: reopened.url(for: oldRecording).path))
        #expect(try Data(contentsOf: export) == exportBytes)
    }

    @Test func expiredScreenshotDeletesOwnedExportsAndPreservesLegacyExportPath() throws {
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
        #expect(second.exports.map(\.path) == exports.map(\.path))

        let legacy = capture("old-legacy-export", date: date("2090-01-01T00:00:00Z"))
        let legacyExport = directory.appendingPathComponent("legacy-export.png")
        try Data([44, 55]).write(to: legacyExport)
        var legacyWithExport = legacy
        legacyWithExport.exports = [CaptureExport(path: legacyExport.path, ownership: nil)]
        try writeIndex([second, legacyWithExport], in: directory)
        try Data([0x54, 0x53]).write(to: directory.appendingPathComponent(legacy.filename))
        let reopened = CaptureStore(directory: directory)

        try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(reopened.items.isEmpty)
        #expect(try persistedItems(in: directory).isEmpty)
        for url in exports {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
        #expect(try Data(contentsOf: legacyExport) == Data([44, 55]))
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

    @Test func legacySharedExportRemainsAfterAllScreenshotsExpire() throws {
        var older = capture("legacy-older-owner", date: date("2090-01-01T00:00:00Z"))
        var newer = capture("legacy-newer-owner", date: date("2100-05-15T00:00:00Z"))
        let (_, directory) = try makeStore(with: [older, newer])
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = directory.appendingPathComponent("legacy-shared.png")
        let bytes = Data([13, 21, 34])
        try bytes.write(to: export)
        older.exports = [CaptureExport(path: export.path, ownership: nil)]
        newer.exports = [CaptureExport(path: export.path, ownership: nil)]
        try writeIndex([older, newer], in: directory)
        let store = CaptureStore(directory: directory)

        try store.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(store.items == [newer])
        #expect(try Data(contentsOf: export) == bytes)
        try store.prune(now: date("2100-12-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)
        #expect(store.items.isEmpty)
        #expect(try Data(contentsOf: export) == bytes)
    }

    @Test func externallyReplacedExportIsPreservedAfterReopening() throws {
        let old = capture("replaced-export", date: date("2090-01-01T00:00:00Z"))
        let (store, directory) = try makeStore(with: [old])
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = directory.appendingPathComponent("replacement.png")
        try Data([1, 2, 3]).write(to: export)
        try store.markExported(old, at: export)
        try FileManager.default.removeItem(at: export)
        let replacement = Data([7, 8, 9])
        try replacement.write(to: export)
        let reopened = CaptureStore(directory: directory)
        #expect(reopened.items.map(\.id) == [old.id])

        try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(reopened.items.isEmpty)
        #expect(try persistedItems(in: directory).isEmpty)
        #expect(try Data(contentsOf: export) == replacement)
    }

    @Test func identicalByteReplacementIsPreservedByFileIdentity() throws {
        let old = capture("identical-replacement", date: date("2090-01-01T00:00:00Z"))
        let (store, directory) = try makeStore(with: [old])
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = directory.appendingPathComponent("identical.png")
        let original = directory.appendingPathComponent("original.png")
        let bytes = Data([11, 12, 13, 14])
        try bytes.write(to: export)
        try store.markExported(old, at: export)
        try FileManager.default.moveItem(at: export, to: original)
        try bytes.write(to: export)
        let reopened = CaptureStore(directory: directory)
        #expect(reopened.items.map(\.id) == [old.id])

        try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(reopened.items.isEmpty)
        #expect(try persistedItems(in: directory).isEmpty)
        #expect(try Data(contentsOf: export) == bytes)
        #expect(try Data(contentsOf: original) == bytes)
    }

    @Test func sameSizeInPlaceEditIsPreservedEvenWhenOriginalModificationDateIsRestored() throws {
        let old = capture("edited-export", date: date("2090-01-01T00:00:00Z"))
        let (store, directory) = try makeStore(with: [old])
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = directory.appendingPathComponent("edited.png")
        let original = Data([21, 22, 23, 24])
        let edited = Data([31, 32, 33, 34])
        try original.write(to: export)
        let modified = date("2100-01-01T00:00:00Z")
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: export.path)
        try store.markExported(old, at: export)
        let attributes = try FileManager.default.attributesOfItem(atPath: export.path)
        try edited.write(to: export)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: export.path)
        let editedAttributes = try FileManager.default.attributesOfItem(atPath: export.path)
        #expect(editedAttributes[.systemFileNumber] as? NSNumber == attributes[.systemFileNumber] as? NSNumber)
        #expect(editedAttributes[.creationDate] as? Date == attributes[.creationDate] as? Date)
        #expect(editedAttributes[.modificationDate] as? Date == modified)
        let reopened = CaptureStore(directory: directory)
        #expect(reopened.items.map(\.id) == [old.id])

        try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(reopened.items.isEmpty)
        #expect(try persistedItems(in: directory).isEmpty)
        #expect(try Data(contentsOf: export) == edited)
    }

    @Test func metadataOnlyModificationDateChangePreservesExport() throws {
        let old = capture("metadata-export", date: date("2090-01-01T00:00:00Z"))
        let (store, directory) = try makeStore(with: [old])
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = directory.appendingPathComponent("metadata.png")
        let bytes = Data([41, 42, 43])
        try bytes.write(to: export)
        try store.markExported(old, at: export)
        try FileManager.default.setAttributes(
            [.modificationDate: date("2099-01-01T00:00:00Z")], ofItemAtPath: export.path)
        let reopened = CaptureStore(directory: directory)
        #expect(reopened.items.map(\.id) == [old.id])

        try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(reopened.items.isEmpty)
        #expect(try persistedItems(in: directory).isEmpty)
        #expect(try Data(contentsOf: export) == bytes)
    }

    @Test(arguments: ["exportedPath", "exportedPaths"])
    func pathOnlyLegacyJSONIsDecodedAndPreserved(_ pathKey: String) throws {
        let old = capture("path-only-legacy-\(pathKey)", date: date("2090-01-01T00:00:00Z"))
        let (_, directory) = try makeStore(with: [old])
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = directory.appendingPathComponent("path-only-\(pathKey).png")
        let bytes = Data([51, 52, 53])
        try bytes.write(to: export)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object.removeValue(forKey: "exports")
        object[pathKey] = pathKey == "exportedPath" ? export.path as Any : [export.path] as Any
        let legacyJSON = try JSONSerialization.data(withJSONObject: [object])
        try legacyJSON.write(to: directory.appendingPathComponent("history.json"), options: .atomic)
        let reopened = CaptureStore(directory: directory)
        #expect(reopened.items.map(\.id) == [old.id])
        #expect(reopened.items.first?.exports == [CaptureExport(path: export.path, ownership: nil)])
        #expect(reopened.items.first?.exportedPath == export.path)

        try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(reopened.items.isEmpty)
        #expect(try persistedItems(in: directory).isEmpty)
        #expect(try Data(contentsOf: export) == bytes)
    }

    @Test func reexportingSameCaptureAtSamePathRefreshesEvidence() throws {
        let old = capture("refreshed-export", date: date("2090-01-01T00:00:00Z"))
        let (store, directory) = try makeStore(with: [old])
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = directory.appendingPathComponent("refreshed.png")
        try Data([61, 62, 63]).write(to: export)
        try store.markExported(old, at: export)
        let latest = Data([71, 72, 73])
        try latest.write(to: export)
        try store.markExported(old, at: export)
        let reopened = CaptureStore(directory: directory)

        try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(reopened.items.isEmpty)
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

    @Test(arguments: ["replacement", "missing"], [false, true])
    func staleExportRetiresDurablyWhenAnotherExportIsBlocked(_ staleState: String, _ blockedFirst: Bool) throws {
        let old = capture("stale-export-retry", date: date("2090-01-01T00:00:00Z"))
        let (store, directory) = try makeStore(with: [old])
        defer { try? FileManager.default.removeItem(at: directory) }
        let stale = directory.appendingPathComponent("stale.png")
        let moved = directory.appendingPathComponent("moved-original.png")
        let blocked = directory.appendingPathComponent("blocked.png")
        let original = Data([1, 2, 3])
        let replacement = Data([7, 8, 9])
        try original.write(to: stale)
        try Data([4, 5, 6]).write(to: blocked)
        for export in blockedFirst ? [blocked, stale] : [stale, blocked] {
            try store.markExported(old, at: export)
        }
        var retained = try #require(store.items.first)
        let staleRecord = try #require(retained.exports.first { $0.path == stale.path })
        retained.exports.removeAll { $0.path == stale.path }
        try FileManager.default.moveItem(at: stale, to: moved)
        if staleState == "replacement" { try replacement.write(to: stale) }
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: blocked.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: blocked.path) }

        #expect(throws: (any Error).self) {
            try store.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)
        }

        #expect(store.items == [retained])
        #expect(try persistedItems(in: directory) == [retained])
        #expect(FileManager.default.fileExists(atPath: store.url(for: old).path))
        let reopened = CaptureStore(directory: directory)
        #expect(reopened.items == [retained])
        let preservedReplacement = directory.appendingPathComponent("preserved-replacement.png")
        if staleState == "replacement" {
            #expect(try Data(contentsOf: stale) == replacement)
            try FileManager.default.moveItem(at: stale, to: preservedReplacement)
        } else {
            #expect(!FileManager.default.fileExists(atPath: stale.path))
        }
        // Matching evidence must never regain authority after durable retirement.
        try FileManager.default.moveItem(at: moved, to: stale)
        #expect(try CaptureExport.read(at: stale) == staleRecord)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: blocked.path)

        try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(reopened.items.isEmpty)
        #expect(try persistedItems(in: directory).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: blocked.path))
        #expect(!FileManager.default.fileExists(atPath: reopened.url(for: old).path))
        #expect(try Data(contentsOf: stale) == original)
        if staleState == "replacement" {
            #expect(try Data(contentsOf: preservedReplacement) == replacement)
        }
    }

    @Test func failedRetirementWritePublishesNothingAndRetryRetiresOnlyResolvedExports() throws {
        let old = capture("retirement-index-retry", date: date("2090-01-01T00:00:00Z"))
        let (store, directory) = try makeStore(with: [old])
        defer { try? FileManager.default.removeItem(at: directory) }
        let stale = directory.appendingPathComponent("stale.png")
        let blocked = directory.appendingPathComponent("blocked.png")
        try Data([1, 2, 3]).write(to: stale)
        try Data([4, 5, 6]).write(to: blocked)
        try store.markExported(old, at: stale)
        try store.markExported(old, at: blocked)
        let priorItems = store.items
        try FileManager.default.moveItem(at: stale, to: directory.appendingPathComponent("moved-original.png"))
        let replacement = Data([7, 8, 9])
        try replacement.write(to: stale)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: blocked.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: blocked.path) }
        let history = directory.appendingPathComponent("history.json")
        let saved = directory.appendingPathComponent("history-saved.json")
        let priorBytes = try Data(contentsOf: history)
        var publications: [CaptureStore.HistoryLoadState] = []
        let observation = store.$historyLoadState.dropFirst().sink { publications.append($0) }
        try FileManager.default.moveItem(at: history, to: saved)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: false)

        #expect(throws: (any Error).self) {
            try store.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)
        }

        #expect(publications.isEmpty)
        #expect(store.items == priorItems)
        #expect(try Data(contentsOf: saved) == priorBytes)
        #expect(try Data(contentsOf: stale) == replacement)
        try FileManager.default.removeItem(at: history)
        try FileManager.default.moveItem(at: saved, to: history)
        let reopened = CaptureStore(directory: directory)
        #expect(reopened.items == priorItems)

        #expect(throws: (any Error).self) {
            try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)
        }
        #expect(reopened.items.first?.exports == priorItems[0].exports.filter { $0.path == blocked.path })
        #expect(try persistedItems(in: directory) == reopened.items)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: blocked.path)
        try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(reopened.items.isEmpty)
        #expect(try persistedItems(in: directory).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: blocked.path))
        #expect(try Data(contentsOf: stale) == replacement)
        withExtendedLifetime(observation) {}
    }

    @Test(arguments: [false, true])
    func retiringStaleExportKeepsFailedStagedDeletionDiscoverableForRetry(_ claimedByNewer: Bool) throws {
        let old = capture("staged-export-retry", date: date("2090-01-01T00:00:00Z"))
        var newer = capture("newer-staged-export-owner", date: date("2100-05-15T00:00:00Z"))
        let (store, directory) = try makeStore(with: [old, newer])
        defer { try? FileManager.default.removeItem(at: directory) }
        let stale = directory.appendingPathComponent("stale.png")
        let blocked = directory.appendingPathComponent("blocked.png")
        try Data([1, 2, 3]).write(to: stale)
        let owned = Data([4, 5, 6])
        try owned.write(to: blocked)
        try store.markExported(old, at: stale)
        try store.markExported(old, at: blocked)
        let blockedRecord = try #require(store.items.first?.exports.last)
        try FileManager.default.moveItem(at: stale, to: directory.appendingPathComponent("moved-original.png"))
        try Data([7, 8, 9]).write(to: stale)
        store.exportDeletionOperations.unlink = { descriptor, name, flags in
            if flags == 0 { errno = EACCES; return -1 }
            return unlinkat(descriptor, name, flags)
        }

        #expect(throws: (any Error).self) {
            try store.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)
        }

        #expect(store.items.first?.exports == [blockedRecord])
        #expect(try persistedItems(in: directory) == store.items)
        #expect(!FileManager.default.fileExists(atPath: blocked.path))
        let recovery = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("TobyShot Export Recovery - ") })
        #expect(try Data(contentsOf: recovery.appendingPathComponent(blocked.lastPathComponent)) == owned)
        let journalDirectory = directory.appendingPathComponent("Export Recovery")
        #expect(try FileManager.default.contentsOfDirectory(atPath: journalDirectory.path).count == 1)
        var reopened = CaptureStore(directory: directory)
        #expect(reopened.items == store.items)
        let replacement = Data([10, 11, 12])
        try replacement.write(to: blocked)
        if claimedByNewer {
            // An older index can contain both claims while recovery is pending.
            newer.exports = [try #require(try CaptureExport.read(at: blocked))]
            try writeIndex([try #require(reopened.items.first), newer], in: directory)
            reopened = CaptureStore(directory: directory)
        }

        try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(reopened.items == [newer])
        #expect(try persistedItems(in: directory) == [newer])
        #expect(!FileManager.default.fileExists(atPath: reopened.url(for: old).path))
        #expect(FileManager.default.fileExists(atPath: reopened.url(for: newer).path))
        #expect(try Data(contentsOf: stale) == Data([7, 8, 9]))
        #expect(try Data(contentsOf: blocked) == replacement)
        #expect(!FileManager.default.fileExists(atPath: recovery.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: journalDirectory.path).isEmpty)
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

    @Test(arguments: [false, true], [false, true])
    func stagedMismatchCannotRegainOwnershipAfterFailedRestore(_ failedHistoryWrite: Bool, _ candidateMovedAway: Bool) throws {
        let old = capture("staged-mismatch-retry", date: date("2090-01-01T00:00:00Z"))
        let (store, directory) = try makeStore(with: [old])
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = directory.appendingPathComponent("export.png")
        let original = Data([1, 2, 3])
        try original.write(to: export)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: export.path)
        try store.markExported(old, at: export)
        let priorItems = store.items
        let ownership = try #require(priorItems.first?.exports.first?.ownership)
        var moves = 0
        store.exportDeletionOperations.move = { from, name, to, destination in
            moves += 1
            if moves == 1 {
                // Keep the version intact so staging disproves ownership by hash.
                try! Data([7, 8, 9]).write(to: export)
                try! FileManager.default.setAttributes([.modificationDate: ownership.version.modificationDate], ofItemAtPath: export.path)
            } else if moves == 2 {
                try! Data([10, 11, 12]).write(to: export)
            }
            return renameatx_np(from, name, to, destination, UInt32(RENAME_EXCL))
        }
        let history = directory.appendingPathComponent("history.json")
        let saved = directory.appendingPathComponent("history-saved.json")
        if failedHistoryWrite {
            try FileManager.default.moveItem(at: history, to: saved)
            try FileManager.default.createDirectory(at: history, withIntermediateDirectories: false)
        }

        #expect(throws: (any Error).self) {
            try store.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)
        }
        if failedHistoryWrite {
            #expect(store.items == priorItems)
            try FileManager.default.removeItem(at: history)
            try FileManager.default.moveItem(at: saved, to: history)
        } else {
            #expect(store.items.first?.exports == [CaptureExport(path: export.path, ownership: nil)])
        }
        #expect(try persistedItems(in: directory) == store.items)
        let recovery = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("TobyShot Export Recovery - ") })
        let candidate = recovery.appendingPathComponent(export.lastPathComponent)
        #expect(try Data(contentsOf: candidate) == Data([7, 8, 9]))
        // Even fully matching bytes and metadata cannot revive disproven ownership.
        try original.write(to: candidate)
        try FileManager.default.setAttributes([.modificationDate: ownership.version.modificationDate], ofItemAtPath: candidate.path)
        let matchingCandidate = try #require(try CaptureExport.read(at: candidate))
        #expect(matchingCandidate.ownership == ownership)
        let occupant = directory.appendingPathComponent("preserved-occupant.png")
        if candidateMovedAway {
            try FileManager.default.moveItem(at: export, to: occupant)
            try FileManager.default.moveItem(at: candidate, to: export)
        }
        let reopened = CaptureStore(directory: directory)

        if !candidateMovedAway {
            #expect(throws: (any Error).self) {
                try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)
            }
            #expect(reopened.items.first?.exports == [CaptureExport(path: export.path, ownership: nil)])
            #expect(try persistedItems(in: directory) == reopened.items)
            #expect(try Data(contentsOf: candidate) == original)
            #expect(try Data(contentsOf: export) == Data([10, 11, 12]))
            try FileManager.default.removeItem(at: export)
        } else {
            #expect(try Data(contentsOf: occupant) == Data([10, 11, 12]))
        }

        try reopened.prune(now: date("2100-06-01T12:00:00Z"), screenshotDays: 120, recordingDays: 0)

        #expect(reopened.items.isEmpty)
        #expect(try persistedItems(in: directory).isEmpty)
        #expect(try Data(contentsOf: export) == original)
        #expect(!FileManager.default.fileExists(atPath: recovery.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Export Recovery").path).isEmpty)
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
