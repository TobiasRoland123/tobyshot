import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import CryptoKit

struct CaptureExport: Codable, Equatable {
    struct FileVersion: Codable, Equatable {
        var volume: UInt64
        var file: UInt64
        var size: UInt64
        var creationDate: Date
        var modificationDate: Date

        init?(attributes: [FileAttributeKey: Any]) {
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let volume = attributes[.systemNumber] as? NSNumber,
                  let file = attributes[.systemFileNumber] as? NSNumber,
                  let size = attributes[.size] as? NSNumber,
                  let creationDate = attributes[.creationDate] as? Date,
                  let modificationDate = attributes[.modificationDate] as? Date else { return nil }
            self.volume = volume.uint64Value
            self.file = file.uint64Value
            self.size = size.uint64Value
            self.creationDate = creationDate
            self.modificationDate = modificationDate
        }
    }

    struct Ownership: Codable, Equatable {
        let version: FileVersion
        let contentHash: Data
    }

    let path: String
    // Path-only legacy exports and recordings have no deletion evidence.
    let ownership: Ownership?

    static func read(at url: URL, matching expectedVersion: FileVersion? = nil) throws -> CaptureExport? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let version = FileVersion(attributes: attributes),
              expectedVersion == nil || version == expectedVersion else { return nil }
        let data = try Data(contentsOf: url)
        let contentHash = Data(SHA256.hash(data: data))
        // A change while reading cannot establish ownership of a stable file version.
        let currentAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard FileVersion(attributes: currentAttributes) == version else { return nil }
        return CaptureExport(path: url.path, ownership: Ownership(version: version, contentHash: contentHash))
    }
}

struct CaptureItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case image, video }
    var id: UUID
    var filename: String
    var title: String
    var date: Date
    var kind: Kind
    var width: Int
    var height: Int
    // Oldest export first; exporting an existing path moves it to the end.
    var exports: [CaptureExport] = []
    // Nil until the screenshot has been read; empty when it contains no text.
    var recognizedText: String? = nil
    var exportedPath: String? { exports.last?.path }
    var dimensions: String { "\(width) × \(height)" }

    func matches(_ search: String) -> Bool {
        search.isEmpty || title.localizedCaseInsensitiveContains(search)
            || recognizedText?.localizedCaseInsensitiveContains(search) == true
    }
}

extension CaptureItem {
    private enum CodingKeys: String, CodingKey {
        case id, filename, title, date, kind, width, height, exports, recognizedText
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case exportedPath, exportedPaths, exportedFiles
    }

    private struct LegacyExport: Decodable {
        let path: String
        let version: CaptureExport.FileVersion
        let contentHash: Data
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        filename = try values.decode(String.self, forKey: .filename)
        title = try values.decode(String.self, forKey: .title)
        date = try values.decode(Date.self, forKey: .date)
        kind = try values.decode(Kind.self, forKey: .kind)
        width = try values.decode(Int.self, forKey: .width)
        height = try values.decode(Int.self, forKey: .height)
        recognizedText = try values.decodeIfPresent(String.self, forKey: .recognizedText)
        if let canonical = try values.decodeIfPresent([CaptureExport].self, forKey: .exports) {
            exports = canonical
            return
        }

        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let paths = try legacy.decodeIfPresent([String].self, forKey: .exportedPaths) ?? []
        let files = try legacy.decodeIfPresent([LegacyExport].self, forKey: .exportedFiles) ?? []
        var orderedPaths: [String] = []
        for path in paths + files.map(\.path) where !orderedPaths.contains(path) {
            orderedPaths.append(path)
        }
        // The scalar field records the last export even when legacy arrays disagree.
        if let latest = try legacy.decodeIfPresent(String.self, forKey: .exportedPath) {
            orderedPaths.removeAll { $0 == latest }
            orderedPaths.append(latest)
        }
        exports = orderedPaths.map { path in
            let ownership = files.last(where: { $0.path == path }).map {
                CaptureExport.Ownership(version: $0.version, contentHash: $0.contentHash)
            }
            return CaptureExport(path: path, ownership: ownership)
        }
    }
}

@MainActor
final class CaptureStore: ObservableObject {
    enum HistoryLoadState {
        case loaded([CaptureItem])
        case failed(Error)
    }
    typealias TextRecognizer = (URL) async throws -> String

    @Published private(set) var historyLoadState: HistoryLoadState = .loaded([])
    let directory: URL
    private let indexURL: URL
    private let readHistory: (URL) throws -> Data
    private var thumbnails: [UUID: NSImage] = [:]
    private var recognizeText: TextRecognizer?
    private var textIndexing: Task<Void, Never>?
    // Captures whose text could not be read are retried on the next launch.
    private var unreadableTextIDs: Set<UUID> = []
    // Internal operations seam lets regression tests schedule replacements at the syscalls.
    var exportDeletionOperations = CaptureExportDeletion.Operations()

    var items: [CaptureItem] {
        if case let .loaded(items) = historyLoadState { return items }
        return []
    }

    var historyLoadError: Error? {
        if case let .failed(error) = historyLoadState { return error }
        return nil
    }

    init(directory: URL? = nil, readHistory: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TobyShot/Captures")
        indexURL = self.directory.appendingPathComponent("history.json")
        self.readHistory = readHistory
        do {
            try loadHistory(allowMissingIndex: true)
            try prune()
        } catch { NSLog("TobyShot history: %@", error.localizedDescription) }
    }

    func retryHistoryLoad() throws {
        guard historyLoadError != nil else { return }
        try loadHistory(allowMissingIndex: false)
        try prune()
        indexPendingText()
    }

    /// Reads the text in screenshots in the background so library search can match it.
    /// Covers screenshots already in the library and every screenshot added afterwards.
    func startTextIndexing(using recognizer: @escaping TextRecognizer = TextRecognition.searchableText) {
        recognizeText = recognizer
        indexPendingText()
    }

    /// Returns once no screenshot is waiting for text recognition.
    func waitForTextIndexing() async {
        await textIndexing?.value
    }

    private func indexPendingText() {
        guard let recognizeText, textIndexing == nil else { return }
        // Newest captures come first, so recent screenshots become searchable soonest.
        textIndexing = Task {
            while historyLoadError == nil, let item = items.first(where: {
                $0.kind == .image && $0.recognizedText == nil && !unreadableTextIDs.contains($0.id)
            }) {
                do {
                    let text = try await recognizeText(url(for: item))
                    try saveRecognizedText(text, for: item.id)
                } catch {
                    unreadableTextIDs.insert(item.id)
                    NSLog("TobyShot text search for %@: %@", item.filename, error.localizedDescription)
                }
            }
            textIndexing = nil
        }
    }

    private func saveRecognizedText(_ text: String, for id: UUID) throws {
        // The capture may have been removed while its text was being read.
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var updatedItems = items
        updatedItems[index].recognizedText = text
        try commit(updatedItems)
    }

    private func loadHistory(allowMissingIndex: Bool) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var hasIndex = true
            do {
                _ = try FileManager.default.attributesOfItem(atPath: indexURL.path)
            } catch let error as CocoaError where allowMissingIndex && error.code == .fileReadNoSuchFile {
                // Only confirmed absence is a new library. Permission errors and unreadable
                // existing indexes must never become writable empty history.
                hasIndex = false
            }
            let loadedItems = hasIndex ? try JSONDecoder().decode([CaptureItem].self, from: readHistory(indexURL)) : []
            let existingItems = loadedItems.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
            thumbnails.removeAll()
            historyLoadState = .loaded(existingItems)
        } catch {
            let recoveryError = TobyError.message("TobyShot couldn’t load your capture library. Your existing history has been kept and library changes are paused. Restore access to the history file, or restore it from a backup, then choose Retry in the library.\n\nHistory file: \(indexURL.path)\n\n\(error.localizedDescription)")
            historyLoadState = .failed(recoveryError)
            throw recoveryError
        }
    }

    private func requireLoadedHistory() throws {
        if let error = historyLoadError { throw error }
    }

    func url(for item: CaptureItem) -> URL { directory.appendingPathComponent(item.filename) }
    func image(for item: CaptureItem) -> NSImage? { NSImage(contentsOf: url(for: item)) }

    func thumbnail(for item: CaptureItem) -> NSImage? {
        if let image = thumbnails[item.id] { return image }
        guard item.kind == .image,
              let source = CGImageSourceCreateWithURL(url(for: item) as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 720,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let result = NSImage(cgImage: cg, size: .zero)
        thumbnails[item.id] = result
        return result
    }

    @discardableResult
    func add(image: NSImage, title: String? = nil) throws -> CaptureItem {
        try requireLoadedHistory()
        let id = UUID()
        let pixels = try ImageOutput.cgImage(image)
        let item = CaptureItem(id: id, filename: "\(id.uuidString).png", title: title ?? CaptureNaming.filename(template: Preferences.string("filenameTemplate")), date: Date(), kind: .image, width: pixels.width, height: pixels.height)
        let file = url(for: item)
        try commit([item] + items, creating: file) {
            try ImageOutput.data(image, format: "PNG").write(to: file, options: .atomic)
        }
        indexPendingText()
        return item
    }

    @discardableResult
    func add(video url: URL, size: CGSize) throws -> CaptureItem {
        try requireLoadedHistory()
        let id = UUID()
        let item = CaptureItem(id: id, filename: "\(id.uuidString).mp4", title: CaptureNaming.filename(template: Preferences.string("filenameTemplate")), date: Date(), kind: .video, width: Int(size.width), height: Int(size.height))
        let file = self.url(for: item)
        // Keep the source recoverable until its history entry is durable.
        try commit([item] + items, creating: file, removing: url) {
            try FileManager.default.copyItem(at: url, to: file)
        }
        return item
    }

    func markExported(_ item: CaptureItem, at url: URL) throws {
        try requireLoadedHistory()
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        // Recording exports are kept indefinitely, so they need no deletion evidence.
        let exportedFile = item.kind == .image ? try CaptureExport.read(at: url) : nil
        let export = exportedFile ?? CaptureExport(path: url.path, ownership: nil)
        var updatedItems = items
        // A Save As replacement belongs to the capture that most recently exported it.
        for otherIndex in updatedItems.indices {
            updatedItems[otherIndex].exports.removeAll { $0.path == url.path }
        }
        updatedItems[index].exports.append(export)
        try commit(updatedItems)
    }

    func remove(_ item: CaptureItem) throws {
        // Only TobyShot's own history copy is removed. Exported originals stay where the user saved them.
        // Retain the original file until the index commits, so failure needs no file restoration.
        try commit(items.filter { $0.id != item.id }, removing: url(for: item))
        thumbnails[item.id] = nil
    }

    func prune(now: Date = Date(), screenshotDays: Int? = nil, recordingDays: Int? = nil) throws {
        try requireLoadedHistory()
        let imageDays = screenshotDays ?? Preferences.int("screenshotRetentionDays")
        let videoDays = recordingDays ?? Preferences.int("historyDays")
        let expired = items.filter { item in
            let days = item.kind == .image ? imageDays : videoDays
            return days > 0 && item.date <= now.addingTimeInterval(-Double(days) * 86_400)
        }
        let expiredIDs = Set(expired.map(\.id))
        var firstError: Error?
        for item in expired {
            do {
                var retryExports: [CaptureExport] = []
                if item.kind == .image {
                    for export in item.exports {
                        switch pruneExport(export, expiredIDs: expiredIDs) {
                        case .retired:
                            break
                        case .retry(let retryExport, let error):
                            retryExports.append(retryExport)
                            if firstError == nil { firstError = error }
                        }
                    }
                }
                if retryExports.isEmpty {
                    try remove(item)
                } else if retryExports != item.exports {
                    // Retire resolved associations even when another export needs retry.
                    // commit publishes the reduced metadata only after it is durable.
                    var updatedItems = items
                    if let index = updatedItems.firstIndex(where: { $0.id == item.id }) {
                        updatedItems[index].exports = retryExports
                        try commit(updatedItems)
                    }
                }
            } catch {
                // Keep failed entries so the next cleanup can retry, and continue with other captures.
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    private func pruneExport(_ export: CaptureExport, expiredIDs: Set<UUID>) -> CaptureExportDeletion.Outcome {
        // Older indexes can contain a path shared with a newer capture. Resolve
        // any staged recovery, but leave that capture's original path untouched.
        let preservingSource = items.contains {
            !expiredIDs.contains($0.id) && $0.exports.contains { $0.path == export.path }
        }
        // Success also covers unowned or missing files, after recovery is resolved.
        return CaptureExportDeletion(directory: directory, operations: exportDeletionOperations)
            .remove(export, preservingSource: preservingSource)
    }

    private func commit(_ updatedItems: [CaptureItem], creating newFile: URL? = nil, removing obsoleteFile: URL? = nil, prepare: () throws -> Void = {}) throws {
        try requireLoadedHistory()
        let data = try JSONEncoder().encode(updatedItems)
        do {
            try prepare()
            try data.write(to: indexURL, options: .atomic)
        } catch {
            if let newFile { cleanUp(newFile) }
            throw error
        }
        // The index is committed. Cleanup failures retain an extra file and must not report
        // the mutation as failed when it will be visible after reopening the store.
        if let obsoleteFile { cleanUp(obsoleteFile) }
        historyLoadState = .loaded(updatedItems)
    }

    private func cleanUp(_ file: URL) {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { try FileManager.default.removeItem(at: file) }
        catch { NSLog("TobyShot history cleanup at %@: %@", file.path, error.localizedDescription) }
    }
}

enum TobyError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}

enum ImageOutput {
    static func cgImage(_ image: NSImage) throws -> CGImage {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw TobyError.message("This image could not be read. Try a PNG, JPEG, or TIFF file.")
        }
        return cg
    }

    static func fileExtension(_ format: String) -> String { format == "JPEG" ? "jpg" : format == "TIFF" ? "tiff" : "png" }

    static func data(_ image: NSImage, format: String) throws -> Data {
        var cg = try cgImage(image)
        if format == "JPEG" {
            // JPEG has no alpha; composite transparency onto white.
            guard let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw TobyError.message("Could not prepare the image for export.") }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            cg = ctx.makeImage() ?? cg
        }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        let type: NSBitmapImageRep.FileType = format == "JPEG" ? .jpeg : format == "TIFF" ? .tiff : .png
        guard let data = bitmap.representation(using: type, properties: [.compressionFactor: 0.92]) else { throw TobyError.message("The image could not be exported.") }
        return data
    }

    static func prepared(_ image: NSImage, scale: CGFloat = 1, background: String? = nil, padding: CGFloat = 64) throws -> NSImage {
        let source = try cgImage(image)
        let factor = Preferences.bool("retinaOneX") ? max(1, scale) : 1
        let width = max(1, Int(CGFloat(source.width) / factor)), height = max(1, Int(CGFloat(source.height) / factor))
        let colorSpace = Preferences.bool("convertSRGB") ? CGColorSpace(name: CGColorSpace.sRGB)! : (source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw TobyError.message("Could not process the captured image.") }
        ctx.interpolationQuality = .high
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        if Preferences.bool("imageBorder") {
            ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.5)); ctx.setLineWidth(1)
            ctx.stroke(CGRect(x: 0.5, y: 0.5, width: CGFloat(width) - 1, height: CGFloat(height) - 1))
        }
        guard let rendered = ctx.makeImage() else { throw TobyError.message("Could not finish processing the capture.") }
        let result = NSImage(cgImage: rendered, size: NSSize(width: width, height: height))
        let preset = background ?? Preferences.string("backgroundPreset")
        return preset == "None" ? result : withBackground(result, style: preset, padding: padding)
    }

    static func withBackground(_ image: NSImage, style: String, padding: CGFloat) -> NSImage {
        let size = CGSize(width: image.size.width + padding * 2, height: image.size.height + padding * 2)
        let result = NSImage(size: size)
        result.lockFocus()
        let colors: [NSColor]
        switch style {
        case "Lavender": colors = [NSColor(red: 0.62, green: 0.50, blue: 0.92, alpha: 1), NSColor(red: 0.29, green: 0.36, blue: 0.65, alpha: 1)]
        case "Peach": colors = [NSColor(red: 1, green: 0.74, blue: 0.62, alpha: 1), NSColor(red: 0.84, green: 0.36, blue: 0.52, alpha: 1)]
        default: colors = [NSColor(red: 0.16, green: 0.24, blue: 0.37, alpha: 1), NSColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1)]
        }
        NSGradient(colors: colors)?.draw(in: NSRect(origin: .zero, size: size), angle: -35)
        image.draw(in: NSRect(origin: CGPoint(x: padding, y: padding), size: image.size))
        result.unlockFocus()
        // Normalize bitmap resolution; lockFocus otherwise inherits the screen's backing scale.
        guard let cg = try? cgImage(result), let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return result }
        ctx.draw(cg, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage().map { NSImage(cgImage: $0, size: size) } ?? result
    }

    static func copy(_ image: NSImage?, file: URL?, to board: NSPasteboard = .general) {
        board.clearContents()
        let item = NSPasteboardItem()
        let mode = Preferences.string("clipboardMode")
        if let file, mode != "Image" || image == nil { item.setString(file.absoluteString, forType: .fileURL) }
        if let image, mode != "File" || file == nil {
            if let png = try? data(image, format: "PNG") { item.setData(png, forType: .png) }
            if let tiff = image.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        }
        board.writeObjects([item])
    }
}
