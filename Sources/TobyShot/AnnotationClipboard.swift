import AppKit

/// Keeps an editor's file representation current without adding captures to history.
final class AnnotationClipboard {
    let fileURL: URL
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general, directory: URL = FileManager.default.temporaryDirectory) {
        self.pasteboard = pasteboard
        fileURL = directory.appendingPathComponent("TobyShot-Annotation-\(UUID().uuidString)")
            .appendingPathComponent("Annotation.png")
    }

    func copy(_ image: NSImage) {
        var file: URL?
        if Preferences.string("clipboardMode") != "Image" {
            do {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try ImageOutput.data(image, format: "PNG").write(to: fileURL, options: .atomic)
                file = fileURL
            } catch {
                NSLog("TobyShot annotation clipboard: %@", error.localizedDescription)
            }
        }
        ImageOutput.copy(image, file: file, to: pasteboard)
        // Leave the temporary file available after the editor closes so it can still be pasted.
    }
}
