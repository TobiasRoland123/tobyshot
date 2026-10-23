import AppKit
import UniformTypeIdentifiers

@MainActor
enum CodexScreenshotHandoff {
    nonisolated static let bundleIdentifier = "com.openai.codex"

    static func openLatestScreenshot(
        in store: CaptureStore,
        findApplication: () -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) },
        open: ([URL], URL, NSWorkspace.OpenConfiguration) async throws -> Void = { urls, application, configuration in
            _ = try await NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: configuration)
        }
    ) async throws {
        if let error = store.historyLoadError { throw error }
        guard let item = store.items.first(where: { $0.kind == .image }) else {
            throw TobyError.message("No screenshots in history yet. Take a screenshot before opening it in Codex.")
        }
        let url = store.url(for: item)
        guard let image = store.image(for: item), image.isValid else {
            throw TobyError.message("The latest screenshot could not be read. It may have been moved, deleted, or damaged.\n\n\(url.path)")
        }
        guard let application = findApplication() else {
            throw TobyError.message("Codex Desktop is not installed. Install Codex, open it once to finish setup, then try again.")
        }
        guard supportsImages(at: application) else {
            throw TobyError.message("This version of Codex does not support opening image files. Update Codex, then try again.")
        }

        // Codex's macOS open-file handler prefills a new composer with the image.
        // Use the capture's persistent file, including when Codex needs time to launch.
        // No clipboard changes, UI scripting, prompt, or submit action are needed.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = false
        do {
            try await open([url], application, configuration)
        } catch {
            throw TobyError.message("TobyShot couldn’t open the screenshot in Codex. Open Codex and finish any setup, then try again.\n\n\(error.localizedDescription)")
        }
    }

    private static func supportsImages(at application: URL) -> Bool {
        let types = Bundle(url: application)?.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
        return types.contains { type in
            let extensions = type["CFBundleTypeExtensions"] as? [String] ?? []
            if extensions.contains(where: { $0.lowercased() == "png" || $0 == "*" }) { return true }
            let identifiers = type["LSItemContentTypes"] as? [String] ?? []
            return identifiers.contains { identifier in
                guard let contentType = UTType(identifier) else { return false }
                return UTType.png.conforms(to: contentType)
            }
        }
    }
}
