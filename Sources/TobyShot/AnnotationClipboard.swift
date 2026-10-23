import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Keeps an editor's file representation current without adding captures to history.
final class AnnotationClipboard {
    let fileURL: URL
    private let pasteboard: NSPasteboard

    static func image(from pasteboard: NSPasteboard = .general) -> CGImage? {
        let preferred: [NSPasteboard.PasteboardType] = [.png, .tiff]
        let otherImages = (pasteboard.types ?? []).filter {
            !preferred.contains($0) && UTType($0.rawValue)?.conforms(to: .image) == true
        }
        for type in preferred + otherImages {
            if let data = pasteboard.data(forType: type),
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = image(from: source) {
                return image
            }
        }

        guard let value = pasteboard.string(forType: .fileURL),
              let url = URL(string: value), url.isFileURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = image(from: source) else {
            return nil
        }
        return image
    }

    private static func image(from source: CGImageSource) -> CGImage? {
        guard let type = CGImageSourceGetType(source),
              UTType(type as String)?.conforms(to: .image) == true else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    init(pasteboard: NSPasteboard = .general, directory: URL = FileManager.default.temporaryDirectory) {
        self.pasteboard = pasteboard
        fileURL = directory.appendingPathComponent("TobyShot-Annotation-\(UUID().uuidString)")
            .appendingPathComponent("Annotation.png")
    }

    func copy(_ image: NSImage) {
        copy { image }
    }

    func copy(_ render: @escaping () -> NSImage) {
        let mode = Preferences.string("clipboardMode")
        var types: [NSPasteboard.PasteboardType] = mode == "File" ? [] : [.png, .tiff]
        if mode != "Image" { types.insert(.fileURL, at: 0) }
        let item = NSPasteboardItem()
        let provider = AnnotationClipboardProvider(render: render, fileURL: fileURL, pasteboard: pasteboard, types: types)
        item.setDataProvider(provider, forTypes: types)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}

/// The pasteboard retains the snapshot even after its editor closes.
private final class AnnotationClipboardProvider: NSObject, NSPasteboardItemDataProvider {
    private var render: (() -> NSImage)?
    private var image: NSImage?
    private var png: Data?
    private let fileURL: URL
    private var pasteboard: NSPasteboard?
    private let types: [NSPasteboard.PasteboardType]

    init(render: @escaping () -> NSImage, fileURL: URL, pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) {
        self.render = render
        self.fileURL = fileURL
        self.pasteboard = pasteboard
        self.types = types
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate),
                                               name: NSApplication.willTerminateNotification, object: nil)
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if image == nil { image = render?(); render = nil }
        guard let image else { return }
        do {
            if type == .tiff {
                if let tiff = image.tiffRepresentation { item.setData(tiff, forType: type) }
            } else {
                if png == nil { png = try ImageOutput.data(image, format: "PNG") }
                guard let png else { return }
                if type == .fileURL {
                    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try png.write(to: fileURL, options: .atomic)
                    item.setString(fileURL.absoluteString, forType: type)
                    // Keep the file available after the editor closes for later pastes.
                } else if type == .png {
                    item.setData(png, forType: type)
                }
            }
        } catch {
            NSLog("TobyShot annotation clipboard: %@", error.localizedDescription)
        }
    }

    @objc private func applicationWillTerminate() {
        // Fulfill promises while the app can still render, so copies survive quitting.
        for type in types { _ = pasteboard?.data(forType: type) }
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        NotificationCenter.default.removeObserver(self)
        self.pasteboard = nil
        render = nil
        image = nil
        png = nil
    }
}
