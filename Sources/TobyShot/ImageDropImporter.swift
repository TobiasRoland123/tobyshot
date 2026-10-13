import AppKit
import UniformTypeIdentifiers

@MainActor
enum ImageDropImporter {
    struct ImportedImage {
        let image: NSImage
        let sourceURL: URL?
    }

    @discardableResult
    static func load(from provider: NSItemProvider, completion: @escaping @MainActor (Result<ImportedImage, Error>) -> Void) -> Bool {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                Task { @MainActor in
                    completion(Result {
                        if let error { throw error }
                        guard let url, url.isFileURL, let image = NSImage(contentsOf: url), image.isValid else {
                            throw TobyError.message("TobyShot couldn't open the dropped image file.")
                        }
                        return ImportedImage(image: image, sourceURL: url)
                    })
                }
            }
            return true
        }
        guard provider.canLoadObject(ofClass: NSImage.self) else { return false }
        _ = provider.loadObject(ofClass: NSImage.self) { (object: NSItemProviderReading?, error: Error?) in
            Task { @MainActor in
                completion(Result {
                    if let error { throw error }
                    guard let image = object as? NSImage, image.isValid else {
                        throw TobyError.message("TobyShot couldn't read the dropped image.")
                    }
                    return ImportedImage(image: image, sourceURL: nil)
                })
            }
        }
        return true
    }
}
