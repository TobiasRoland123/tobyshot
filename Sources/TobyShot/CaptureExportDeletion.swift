import Foundation
import CryptoKit
import Darwin

// Only the private staged name is unlinked. An open file descriptor alone would
// not make unlinking the user's original pathname safe against replacement.
struct CaptureExportDeletion {
    enum Outcome {
        case retired
        case retry(CaptureExport, Error)
    }

    struct Operations {
        var move: (Int32, String, Int32, String) -> Int32 = {
            renameatx_np($0, $1, $2, $3, UInt32(RENAME_EXCL))
        }
        var unlink: (Int32, String, Int32) -> Int32 = { unlinkat($0, $1, $2) }
    }

    private struct Identity: Codable, Equatable {
        var volume: Int32
        var file: UInt64

        init(_ attributes: stat) {
            volume = attributes.st_dev
            file = attributes.st_ino
        }
    }

    private struct Recovery: Codable {
        enum State: String, Codable { case pending, disposed, sourceUnmoved }
        var export: CaptureExport
        var folder: String
        var bookmark: Data
        var parent: Identity
        var staging: Identity
        var state = State.pending
    }

    let directory: URL
    var operations = Operations()
    private var recoveryDirectory: URL { directory.appendingPathComponent("Export Recovery", isDirectory: true) }

    func remove(_ export: CaptureExport, preservingSource: Bool = false) -> Outcome {
        var retryExport = export
        do {
            try remove(export, preservingSource: preservingSource, retryExport: &retryExport)
            return .retired
        } catch {
            return .retry(retryExport, error)
        }
    }

    private func remove(_ export: CaptureExport, preservingSource: Bool, retryExport: inout CaptureExport) throws {
        let key = SHA256.hash(data: Data(export.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let journal = recoveryDirectory.appendingPathComponent(key + ".json")
        if FileManager.default.fileExists(atPath: journal.path) {
            var recovery = try JSONDecoder().decode(Recovery.self, from: Data(contentsOf: journal))
            // Either durable record can retire ownership. A failed history write
            // must not allow evidence already retired in the journal to return.
            if export.ownership == nil || recovery.export.ownership == nil {
                retryExport = CaptureExport(path: export.path, ownership: nil)
                if recovery.export.ownership != nil {
                    recovery.export = retryExport
                    try JSONEncoder().encode(recovery).write(to: journal, options: .atomic)
                }
            }
            if try resume(recovery, journal: journal, retryExport: &retryExport) { return }
        }
        // A record can retire only after its pending recovery is resolved. Legacy
        // exports and paths claimed by newer captures must not enter source deletion.
        guard !preservingSource, let ownership = retryExport.ownership else { return }

        let source = URL(fileURLWithPath: export.path)
        let parent = open(source.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parent >= 0 else {
            if errno == ENOENT { return }
            throw posixError()
        }
        defer { close(parent) }
        let name = source.lastPathComponent
        var attributes = stat()
        guard fstatat(parent, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return }
            throw posixError()
        }
        // Avoid disturbing known mismatches. This is an optimization; ownership
        // is established again after the atomic move, never at the original path.
        guard version(attributes) == ownership.version else { return }

        let folderName = "TobyShot Export Recovery - " + UUID().uuidString
        guard mkdirat(parent, folderName, 0o700) == 0 else { throw posixError() }
        let staging = openat(parent, folderName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard staging >= 0 else { throw posixError() }
        defer { close(staging) }

        let recovery: Recovery
        do {
            let folder = try url(for: staging)
            recovery = Recovery(export: export, folder: folder.path,
                                bookmark: try folder.bookmarkData(options: .minimalBookmark),
                                parent: Identity(try status(parent)), staging: Identity(try status(staging)))
            try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
            // Persist the locator before moving anything. A crash or failed restore
            // must leave a candidate the next cleanup can find, even after a rename
            // of the export's parent directory.
            try JSONEncoder().encode(recovery).write(to: journal, options: .atomic)
        } catch {
            // No candidate has moved yet. Never recursively remove staging folders.
            _ = operations.unlink(parent, folderName, AT_REMOVEDIR)
            throw error
        }

        guard operations.move(parent, name, staging, name) == 0 else {
            let code = errno
            try finish(recovery, parent: parent, staging: staging, journal: journal, state: .sourceUnmoved)
            if code == ENOENT { return }
            throw posixError(code)
        }
        try dispose(recovery, parent: parent, staging: staging, journal: journal, retryExport: &retryExport)
    }

    private func resume(_ recovery: Recovery, journal: URL, retryExport: inout CaptureExport) throws -> Bool {
        var stale = false
        let folder = (try? URL(resolvingBookmarkData: recovery.bookmark,
                               options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale))
            ?? URL(fileURLWithPath: recovery.folder)
        let staging = open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard staging >= 0 else {
            if errno == ENOENT && recovery.state != .pending {
                // Successful cleanup may have removed the folder before a failed
                // journal cleanup. There is no original pathname deletion here.
                try FileManager.default.removeItem(at: journal)
                return recovery.state == .disposed
            }
            throw recoveryError(recovery, underlying: posixError())
        }
        defer { close(staging) }
        guard Identity(try status(staging)) == recovery.staging else {
            throw recoveryError(recovery, staging: staging)
        }
        let parent = openat(staging, "..", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parent >= 0 else { throw recoveryError(recovery, staging: staging, underlying: posixError()) }
        defer { close(parent) }
        guard Identity(try status(parent)) == recovery.parent else { throw recoveryError(recovery, staging: staging) }
        var attributes = stat()
        let name = URL(fileURLWithPath: recovery.export.path).lastPathComponent
        let candidateExists = fstatat(staging, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0
        if !candidateExists && errno != ENOENT { throw recoveryError(recovery, staging: staging, underlying: posixError()) }
        try dispose(recovery, parent: parent, staging: staging, journal: journal, retryExport: &retryExport)
        // An empty, unresolved journal can precede the move (process interruption).
        // Finish that attempt, then apply retention to the still-present source.
        return candidateExists || recovery.state == .disposed
    }

    private func dispose(_ recovery: Recovery, parent: Int32, staging: Int32, journal: URL, retryExport: inout CaptureExport) throws {
        var recovery = recovery
        let name = URL(fileURLWithPath: recovery.export.path).lastPathComponent
        var attributes = stat()
        guard fstatat(staging, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT {
                try finish(recovery, parent: parent, staging: staging, journal: journal,
                           state: recovery.state == .pending ? .sourceUnmoved : recovery.state)
                return
            }
            throw recoveryError(recovery, staging: staging, underlying: posixError())
        }
        do {
            if try matches(recovery.export, staging: staging, name: name, attributes: attributes) {
                guard operations.unlink(staging, name, 0) == 0 else { throw posixError() }
            } else {
                // Retire disproven evidence before restoring. A failed restore or
                // cleanup keeps only the path needed to resume this recovery.
                retryExport = CaptureExport(path: recovery.export.path, ownership: nil)
                if recovery.export.ownership != nil {
                    recovery.export = retryExport
                    try JSONEncoder().encode(recovery).write(to: journal, options: .atomic)
                }
                // RENAME_EXCL never overwrites a newly arrived original-path occupant,
                // including a dangling symlink. Unsupported filesystems fail closed.
                guard operations.move(staging, name, parent, name) == 0 else { throw posixError() }
            }
        } catch {
            // Read/deletion errors also preserve the staged candidate for retry.
            throw recoveryError(recovery, staging: staging, underlying: error)
        }
        try finish(recovery, parent: parent, staging: staging, journal: journal)
    }

    private func matches(_ export: CaptureExport, staging: Int32, name: String, attributes: stat) throws -> Bool {
        guard let ownership = export.ownership,
              version(attributes) == ownership.version else { return false }
        let file = openat(staging, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { throw posixError() }
        defer { close(file) }
        guard version(try status(file)) == ownership.version else { return false }
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: false)
        let data = try handle.readToEnd() ?? Data()
        let currentVersion = version(try status(file))
        return Data(SHA256.hash(data: data)) == ownership.contentHash && currentVersion == ownership.version
    }

    private func finish(_ recovery: Recovery, parent: Int32, staging: Int32, journal: URL, state: Recovery.State = .disposed) throws {
        var updated = recovery
        updated.state = state
        try JSONEncoder().encode(updated).write(to: journal, options: .atomic)
        // Descriptor-relative cleanup remains attached to the pinned directory when
        // an ancestor path is replaced. rmdir cannot erase an unexpected candidate.
        let folderName = try url(for: staging).lastPathComponent
        guard operations.unlink(parent, folderName, AT_REMOVEDIR) == 0 else {
            throw recoveryError(recovery, staging: staging, underlying: posixError())
        }
        try FileManager.default.removeItem(at: journal)
    }

    private func status(_ descriptor: Int32) throws -> stat {
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0 else { throw posixError() }
        return attributes
    }

    private func version(_ attributes: stat) -> CaptureExport.FileVersion? {
        guard attributes.st_mode & S_IFMT == S_IFREG else { return nil }
        return CaptureExport.FileVersion(attributes: [
            .type: FileAttributeType.typeRegular,
            .systemNumber: NSNumber(value: UInt32(bitPattern: attributes.st_dev)),
            .systemFileNumber: NSNumber(value: attributes.st_ino),
            .size: NSNumber(value: attributes.st_size),
            .creationDate: date(attributes.st_birthtimespec),
            .modificationDate: date(attributes.st_mtimespec)
        ])
    }

    private func date(_ time: timespec) -> Date {
        // Match FileManager's reference-date conversion without losing precision
        // by adding the fractional seconds to the larger Unix epoch first.
        Date(timeIntervalSinceReferenceDate: Double(time.tv_sec) - Date.timeIntervalBetween1970AndReferenceDate
             + Double(time.tv_nsec) / 1_000_000_000)
    }

    private func url(for descriptor: Int32) throws -> URL {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) == 0 else { throw posixError() }
        return URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
    }

    private func posixError(_ code: Int32 = errno) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    private func recoveryError(_ recovery: Recovery, staging: Int32? = nil, underlying: Error? = nil) -> Error {
        let folder = staging.flatMap { try? url(for: $0).path } ?? recovery.folder
        return TobyError.message("Export cleanup needs retry. Preserved files: \(folder). Recovery record: \(recoveryDirectory.path). \(underlying?.localizedDescription ?? "Recovery folder identity changed.")")
    }
}
