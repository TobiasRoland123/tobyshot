import Foundation
import Darwin
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct CaptureExportDeletionTests {
    @Test func replacementImmediatelyBeforeStagingIsRestoredAndPreserved() throws {
        let (store, directory, export) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let replacement = Data([7, 8, 9])
        var injected = false
        store.exportDeletionOperations.move = { from, name, to, destination in
            if !injected {
                injected = true
                try! replacement.write(to: export, options: .atomic)
            }
            return renameatx_np(from, name, to, destination, UInt32(RENAME_EXCL))
        }

        try prune(store)

        #expect(injected)
        #expect(try Data(contentsOf: export) == replacement)
        #expect(store.items.isEmpty)
        #expect(try recoveryFolders(in: directory).isEmpty)
        #expect(try journals(in: directory).isEmpty)
    }

    @Test func replacementImmediatelyBeforeStagedUnlinkSurvives() throws {
        let (store, directory, export) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let replacement = Data([7, 8, 9])
        var injected = false
        store.exportDeletionOperations.unlink = { descriptor, name, flags in
            if flags == 0 {
                injected = true
                try! replacement.write(to: export, options: .atomic)
            }
            return unlinkat(descriptor, name, flags)
        }

        try prune(store)

        #expect(injected)
        #expect(try Data(contentsOf: export) == replacement)
        #expect(store.items.isEmpty)
        #expect(try recoveryFolders(in: directory).isEmpty)
    }

    @Test(arguments: ["directory", "symlink"])
    func nonregularReplacementDuringStagingIsRestored(_ kind: String) throws {
        let (store, directory, export) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var injected = false
        store.exportDeletionOperations.move = { from, name, to, destination in
            if !injected {
                injected = true
                try! FileManager.default.removeItem(at: export)
                if kind == "directory" {
                    try! FileManager.default.createDirectory(at: export, withIntermediateDirectories: false)
                    try! Data([9]).write(to: export.appendingPathComponent("user-file"))
                } else {
                    try! FileManager.default.createSymbolicLink(atPath: export.path, withDestinationPath: "missing-user-file")
                }
            }
            return renameatx_np(from, name, to, destination, UInt32(RENAME_EXCL))
        }

        try prune(store)

        #expect(injected)
        if kind == "directory" {
            #expect(try Data(contentsOf: export.appendingPathComponent("user-file")) == Data([9]))
        } else {
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: export.path) == "missing-user-file")
        }
        #expect(store.items.isEmpty)
    }

    @Test func parentReplacementDoesNotRedirectStagingOrDeletion() throws {
        let (store, directory, export) = try fixture(exportFolder: "exports")
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = directory.appendingPathComponent("exports", isDirectory: true)
        let moved = directory.appendingPathComponent("moved-exports", isDirectory: true)
        var injected = false
        store.exportDeletionOperations.move = { from, name, to, destination in
            if name == export.lastPathComponent && !injected {
                injected = true
                try! FileManager.default.moveItem(at: parent, to: moved)
                try! FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
                try! Data([7, 8, 9]).write(to: export)
            }
            return renameatx_np(from, name, to, destination, UInt32(RENAME_EXCL))
        }

        try prune(store)

        #expect(injected)
        #expect(try Data(contentsOf: export) == Data([7, 8, 9]))
        #expect(!FileManager.default.fileExists(atPath: moved.appendingPathComponent("export.png").path))
        #expect(try recoveryFolders(in: moved).isEmpty)
        #expect(store.items.isEmpty)
    }

    @Test func restoreCollisionKeepsBothFilesAndRetriesAfterReopeningAndParentRename() throws {
        let (store, directory, export) = try fixture(exportFolder: "exports")
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = directory.appendingPathComponent("exports", isDirectory: true)
        var moves = 0
        store.exportDeletionOperations.move = { from, name, to, destination in
            if name == export.lastPathComponent {
                moves += 1
                if moves == 1 { try! Data([7, 8, 9]).write(to: export, options: .atomic) }
                if moves == 2 { try! Data([10, 11, 12]).write(to: export, options: .atomic) }
            }
            return renameatx_np(from, name, to, destination, UInt32(RENAME_EXCL))
        }

        #expect(throws: (any Error).self) { try prune(store) }
        #expect(store.items.count == 1)
        #expect(try persistedItems(in: directory) == store.items)
        #expect(try Data(contentsOf: export) == Data([10, 11, 12]))
        let recovery = try #require(recoveryFolders(in: parent).first)
        #expect(try Data(contentsOf: recovery.appendingPathComponent("export.png")) == Data([7, 8, 9]))
        let permissions = try FileManager.default.attributesOfItem(atPath: recovery.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o700)
        #expect(try journals(in: directory).count == 1)

        let moved = directory.appendingPathComponent("moved-exports", isDirectory: true)
        try FileManager.default.moveItem(at: parent, to: moved)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        try Data([99]).write(to: export)
        let reopened = CaptureStore(directory: directory)
        #expect(throws: (any Error).self) { try prune(reopened) }
        #expect(try Data(contentsOf: export) == Data([99]))
        #expect(try Data(contentsOf: moved.appendingPathComponent("export.png")) == Data([10, 11, 12]))

        try FileManager.default.removeItem(at: moved.appendingPathComponent("export.png"))
        try prune(reopened)

        #expect(reopened.items.isEmpty)
        #expect(try Data(contentsOf: moved.appendingPathComponent("export.png")) == Data([7, 8, 9]))
        #expect(try Data(contentsOf: export) == Data([99]))
        #expect(try journals(in: directory).isEmpty)
        #expect(try recoveryFolders(in: moved).isEmpty)
    }

    @Test func failedStagedDeletionRetainsCandidateAndRetriesWithoutOriginalPath() throws {
        let (store, directory, export) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.exportDeletionOperations.unlink = { descriptor, name, flags in
            if flags == 0 { errno = EACCES; return -1 }
            return unlinkat(descriptor, name, flags)
        }

        #expect(throws: (any Error).self) { try prune(store) }
        #expect(!FileManager.default.fileExists(atPath: export.path))
        let recovery = try #require(recoveryFolders(in: directory).first)
        #expect(try Data(contentsOf: recovery.appendingPathComponent("export.png")) == Data([1, 2, 3]))
        #expect(try persistedItems(in: directory) == store.items)
        try Data([7, 8, 9]).write(to: export)
        let reopened = CaptureStore(directory: directory)

        try prune(reopened)

        #expect(reopened.items.isEmpty)
        #expect(try Data(contentsOf: export) == Data([7, 8, 9]))
        #expect(try recoveryFolders(in: directory).isEmpty)
        #expect(try journals(in: directory).isEmpty)
    }

    @Test func failedEmptyFolderCleanupRemainsRetryable() throws {
        let (store, directory, export) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.exportDeletionOperations.unlink = { descriptor, name, flags in
            if flags == AT_REMOVEDIR { errno = EACCES; return -1 }
            return unlinkat(descriptor, name, flags)
        }

        #expect(throws: (any Error).self) { try prune(store) }
        #expect(!FileManager.default.fileExists(atPath: export.path))
        #expect(try journals(in: directory).count == 1)
        #expect(store.items.count == 1)
        let reopened = CaptureStore(directory: directory)

        try prune(reopened)

        #expect(reopened.items.isEmpty)
        #expect(try journals(in: directory).isEmpty)
        #expect(try recoveryFolders(in: directory).isEmpty)
    }

    @Test(arguments: [false, true])
    func failedJournalCleanupAfterFolderRemovalRetries(_ failsMove: Bool) throws {
        let (store, directory, export) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var journal: URL?
        if failsMove { store.exportDeletionOperations.move = { _, _, _, _ in errno = EACCES; return -1 } }
        store.exportDeletionOperations.unlink = { descriptor, name, flags in
            if flags == AT_REMOVEDIR {
                journal = try! journals(in: directory).first
                try! FileManager.default.setAttributes([.immutable: true], ofItemAtPath: journal!.path)
            }
            return unlinkat(descriptor, name, flags)
        }
        defer { if let journal { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: journal.path) } }

        #expect(throws: (any Error).self) { try prune(store) }
        #expect(FileManager.default.fileExists(atPath: export.path) == failsMove)
        #expect(try recoveryFolders(in: directory).isEmpty)
        #expect(store.items.count == 1)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: try #require(journal).path)
        let reopened = CaptureStore(directory: directory)

        try prune(reopened)

        #expect(reopened.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: export.path))
        #expect(try journals(in: directory).isEmpty)
    }

    @Test func failedJournalCreationDoesNotMoveTheExport() throws {
        let (store, directory, export) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([0]).write(to: directory.appendingPathComponent("Export Recovery"))

        #expect(throws: (any Error).self) { try prune(store) }

        #expect(store.items.count == 1)
        #expect(try Data(contentsOf: export) == Data([1, 2, 3]))
        #expect(try recoveryFolders(in: directory).isEmpty)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("Export Recovery"))
        try prune(store)
        #expect(store.items.isEmpty)
    }

    @Test func failedMoveAndCleanupRetriesTheUnmovedSource() throws {
        let (store, directory, export) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.exportDeletionOperations.move = { _, _, _, _ in errno = EACCES; return -1 }
        store.exportDeletionOperations.unlink = { _, _, _ in errno = EACCES; return -1 }

        #expect(throws: (any Error).self) { try prune(store) }
        #expect(try Data(contentsOf: export) == Data([1, 2, 3]))
        #expect(store.items.count == 1)
        #expect(try journals(in: directory).count == 1)
        let reopened = CaptureStore(directory: directory)

        try prune(reopened)

        #expect(reopened.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: export.path))
        #expect(try recoveryFolders(in: directory).isEmpty)
        #expect(try journals(in: directory).isEmpty)
    }

    @Test func failedStagedReadPreservesCandidateForRetry() throws {
        let (store, directory, export) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.exportDeletionOperations.move = { from, name, to, destination in
            let result = renameatx_np(from, name, to, destination, UInt32(RENAME_EXCL))
            if result == 0 { precondition(fchmodat(to, destination, 0, 0) == 0) }
            return result
        }

        #expect(throws: (any Error).self) { try prune(store) }
        #expect(store.items.count == 1)
        #expect(!FileManager.default.fileExists(atPath: export.path))
        let recovery = try #require(recoveryFolders(in: directory).first)
        let candidate = recovery.appendingPathComponent("export.png")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: candidate.path)
        #expect(try Data(contentsOf: candidate) == Data([1, 2, 3]))
        let reopened = CaptureStore(directory: directory)

        try prune(reopened)

        #expect(reopened.items.isEmpty)
        #expect(try journals(in: directory).isEmpty)
        #expect(try recoveryFolders(in: directory).isEmpty)
    }

    @Test func danglingSymlinkAtRestoreDestinationIsNeverOverwritten() throws {
        let (store, directory, export) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var moves = 0
        store.exportDeletionOperations.move = { from, name, to, destination in
            moves += 1
            if moves == 1 { try! Data([7, 8, 9]).write(to: export, options: .atomic) }
            if moves == 2 {
                try! FileManager.default.createSymbolicLink(atPath: export.path, withDestinationPath: "missing-user-file")
            }
            return renameatx_np(from, name, to, destination, UInt32(RENAME_EXCL))
        }

        #expect(throws: (any Error).self) { try prune(store) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: export.path) == "missing-user-file")
        let recovery = try #require(recoveryFolders(in: directory).first)
        #expect(try Data(contentsOf: recovery.appendingPathComponent("export.png")) == Data([7, 8, 9]))
        #expect(store.items.count == 1)
        try FileManager.default.removeItem(at: export)
        let reopened = CaptureStore(directory: directory)

        try prune(reopened)

        #expect(reopened.items.isEmpty)
        #expect(try Data(contentsOf: export) == Data([7, 8, 9]))
        #expect(try journals(in: directory).isEmpty)
    }

    private func fixture(exportFolder: String? = nil) throws -> (CaptureStore, URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TobyShot-Deletion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = CaptureItem(id: UUID(), filename: "capture.png", title: "old",
                              date: ISO8601DateFormatter().date(from: "2090-01-01T00:00:00Z")!,
                              kind: .image, width: 2, height: 2)
        try Data([0]).write(to: directory.appendingPathComponent(old.filename))
        try JSONEncoder().encode([old]).write(to: directory.appendingPathComponent("history.json"), options: .atomic)
        let store = CaptureStore(directory: directory)
        let parent = exportFolder.map { directory.appendingPathComponent($0, isDirectory: true) } ?? directory
        if exportFolder != nil { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false) }
        let export = parent.appendingPathComponent("export.png")
        try Data([1, 2, 3]).write(to: export)
        try store.markExported(old, at: export)
        return (store, directory, export)
    }

    private func prune(_ store: CaptureStore) throws {
        try store.prune(now: ISO8601DateFormatter().date(from: "2100-06-01T12:00:00Z")!, screenshotDays: 120, recordingDays: 0)
    }

    private func recoveryFolders(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("TobyShot Export Recovery - ") }
    }

    private func journals(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("Export Recovery"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
    }

    private func persistedItems(in directory: URL) throws -> [CaptureItem] {
        try JSONDecoder().decode([CaptureItem].self, from: Data(contentsOf: directory.appendingPathComponent("history.json")))
    }
}
