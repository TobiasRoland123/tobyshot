import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct CaptureItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case image, video }
    var id: UUID
    var filename: String
    var title: String
    var date: Date
    var kind: Kind
    var width: Int
    var height: Int
    var exportedPath: String?
    var exportedPaths: [String]? = nil
    var exportPaths: [String] {
        var paths = exportedPaths ?? []
        if let exportedPath, !paths.contains(exportedPath) { paths.append(exportedPath) }
        return paths
    }
    var dimensions: String { "\(width) × \(height)" }
}

@MainActor
final class CaptureStore: ObservableObject {
    @Published private(set) var items: [CaptureItem] = []
    let directory: URL
    private let indexURL: URL
    private var thumbnails: [UUID: NSImage] = [:]

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TobyShot/Captures")
        indexURL = self.directory.appendingPathComponent("history.json")
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                items = try JSONDecoder().decode([CaptureItem].self, from: Data(contentsOf: indexURL))
                items.removeAll { !FileManager.default.fileExists(atPath: url(for: $0).path) }
            }
            try prune()
        } catch { NSLog("TobyShot history: %@", error.localizedDescription) }
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
        let id = UUID()
        let pixels = try ImageOutput.cgImage(image)
        let item = CaptureItem(id: id, filename: "\(id.uuidString).png", title: title ?? CaptureNaming.filename(template: Preferences.string("filenameTemplate")), date: Date(), kind: .image, width: pixels.width, height: pixels.height)
        let file = url(for: item)
        try commit([item] + items, creating: file) {
            try ImageOutput.data(image, format: "PNG").write(to: file, options: .atomic)
        }
        return item
    }

    @discardableResult
    func add(video url: URL, size: CGSize) throws -> CaptureItem {
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
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updatedItems = items
        // A Save As replacement belongs to the capture that most recently exported it.
        for otherIndex in updatedItems.indices where otherIndex != index {
            let other = updatedItems[otherIndex]
            guard other.exportPaths.contains(url.path) else { continue }
            updatedItems[otherIndex].exportedPaths = other.exportPaths.filter { $0 != url.path }
            if other.exportedPath == url.path {
                updatedItems[otherIndex].exportedPath = updatedItems[otherIndex].exportedPaths?.last
            }
        }
        var paths = updatedItems[index].exportPaths
        if !paths.contains(url.path) { paths.append(url.path) }
        updatedItems[index].exportedPaths = paths
        updatedItems[index].exportedPath = url.path
        try commit(updatedItems)
    }

    func remove(_ item: CaptureItem) throws {
        // Only TobyShot's own history copy is removed. Exported originals stay where the user saved them.
        // Retain the original file until the index commits, so failure needs no file restoration.
        try commit(items.filter { $0.id != item.id }, removing: url(for: item))
        thumbnails[item.id] = nil
    }

    func prune(now: Date = Date(), screenshotDays: Int? = nil, recordingDays: Int? = nil) throws {
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
                if item.kind == .image {
                    for path in item.exportPaths {
                        // Older indexes can contain a path shared with a newer capture.
                        guard !items.contains(where: { !expiredIDs.contains($0.id) && $0.exportPaths.contains(path) }),
                              FileManager.default.fileExists(atPath: path) else { continue }
                        let attributes = try FileManager.default.attributesOfItem(atPath: path)
                        guard attributes[.type] as? FileAttributeType == .typeRegular else { continue }
                        try FileManager.default.removeItem(atPath: path)
                    }
                }
                try remove(item)
            } catch {
                // Keep failed entries so the next cleanup can retry, and continue with other captures.
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    private func commit(_ updatedItems: [CaptureItem], creating newFile: URL? = nil, removing obsoleteFile: URL? = nil, prepare: () throws -> Void = {}) throws {
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
        items = updatedItems
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
