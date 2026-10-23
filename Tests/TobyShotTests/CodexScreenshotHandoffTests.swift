import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct CodexScreenshotHandoffTests {
    @Test func opensLatestScreenshotDespiteNewerRecordingWithoutChangingHistoryOrClipboard() async throws {
        try await withStore { store, directory in
            _ = try store.add(image: image(.red), title: "Older screenshot")
            let latest = try store.add(image: image(.blue), title: "Latest screenshot")
            try addRecording(to: store, in: directory)
            let application = try application(in: directory, documentTypes: [["LSItemContentTypes": ["public.data"]]])
            let expectedURL = store.url(for: latest)
            let expectedData = try Data(contentsOf: expectedURL)
            let history = store.items
            let clipboard = NSPasteboard.general.changeCount
            var opened = 0

            try await CodexScreenshotHandoff.openLatestScreenshot(in: store, findApplication: { application }) { urls, target, configuration in
                opened += 1
                #expect(urls == [expectedURL])
                #expect(target == application)
                #expect(try Data(contentsOf: #require(urls.first)) == expectedData)
                let pixels = try #require(NSBitmapImageRep(data: expectedData))
                #expect(pixels.pixelsWide == 17)
                #expect(pixels.pixelsHigh == 13)
                #expect(configuration.activates)
                #expect(!configuration.createsNewApplicationInstance)
                #expect(!configuration.promptsUserIfNeeded)
                #expect(configuration.arguments.isEmpty)
                #expect(configuration.appleEvent == nil)
            }

            #expect(opened == 1)
            #expect(store.items == history)
            #expect(NSPasteboard.general.changeCount == clipboard)
        }
    }

    @Test(arguments: [false, true])
    func noScreenshotExplainsWhatToDoWithoutOpeningCodex(recordingsOnly: Bool) async throws {
        try await withStore { store, directory in
            if recordingsOnly { try addRecording(to: store, in: directory) }
            let error = await #expect(throws: (any Error).self) {
                try await CodexScreenshotHandoff.openLatestScreenshot(in: store, findApplication: {
                    Issue.record("Should not look for Codex without a screenshot")
                    return nil
                }) { _, _, _ in Issue.record("Should not open Codex without a screenshot") }
            }
            #expect(error?.localizedDescription.contains("No screenshots in history") == true)
            #expect(error?.localizedDescription.contains("Take a screenshot") == true)
        }
    }

    @Test(arguments: [false, true])
    func unreadableLatestScreenshotDoesNotFallBackToAnOlderImage(deleted: Bool) async throws {
        try await withStore { store, _ in
            _ = try store.add(image: image(.red))
            let latest = try store.add(image: image(.blue))
            let url = store.url(for: latest)
            if deleted { try FileManager.default.removeItem(at: url) }
            else { try Data("not an image".utf8).write(to: url) }

            let error = await #expect(throws: (any Error).self) {
                try await CodexScreenshotHandoff.openLatestScreenshot(in: store, findApplication: { nil }) { _, _, _ in
                    Issue.record("Should not open an unreadable screenshot")
                }
            }
            #expect(error?.localizedDescription.contains("latest screenshot could not be read") == true)
            #expect(error?.localizedDescription.contains(url.path) == true)
        }
    }

    @Test func missingCodexExplainsInstallation() async throws {
        try await withStore { store, _ in
            _ = try store.add(image: image(.blue))
            let error = await #expect(throws: (any Error).self) {
                try await CodexScreenshotHandoff.openLatestScreenshot(in: store, findApplication: { nil }) { _, _, _ in
                    Issue.record("Should not open a missing application")
                }
            }
            #expect(error?.localizedDescription.contains("Codex Desktop is not installed") == true)
        }
    }

    @Test func oldCodexWithoutFileSupportRequiresAnUpdate() async throws {
        try await withStore { store, directory in
            _ = try store.add(image: image(.blue))
            let application = try application(in: directory, documentTypes: [["LSItemContentTypes": ["public.folder"]]])
            let error = await #expect(throws: (any Error).self) {
                try await CodexScreenshotHandoff.openLatestScreenshot(in: store, findApplication: { application }) { _, _, _ in
                    Issue.record("Should not hand an image to an app that only opens folders")
                }
            }
            #expect(error?.localizedDescription.contains("Update Codex") == true)
        }
    }

    @Test func failedHandoffIncludesTheUnderlyingFailureAndRecovery() async throws {
        try await withStore { store, directory in
            _ = try store.add(image: image(.blue))
            let application = try application(in: directory, documentTypes: [["CFBundleTypeExtensions": ["png"]]])
            let error = await #expect(throws: (any Error).self) {
                try await CodexScreenshotHandoff.openLatestScreenshot(in: store, findApplication: { application }) { _, _, _ in
                    // A failure may arrive asynchronously, after Launch Services tries to start Codex.
                    await Task.yield()
                    throw TobyError.message("Launch Services rejected the file")
                }
            }
            #expect(error?.localizedDescription.contains("couldn’t open the screenshot in Codex") == true)
            #expect(error?.localizedDescription.contains("Open Codex and finish any setup") == true)
            #expect(error?.localizedDescription.contains("Launch Services rejected the file") == true)
        }
    }

    @Test func unreadableHistoryKeepsItsRecoveryMessage() async throws {
        try await withStore { _, directory in
            let history = directory.appendingPathComponent("history.json")
            try Data("broken history".utf8).write(to: history)
            let store = CaptureStore(directory: directory)
            let error = await #expect(throws: (any Error).self) {
                try await CodexScreenshotHandoff.openLatestScreenshot(in: store, findApplication: { nil }) { _, _, _ in
                    Issue.record("Should not open Codex when history could not be read")
                }
            }
            #expect(error?.localizedDescription == store.historyLoadError?.localizedDescription)
            #expect(error?.localizedDescription.contains("Retry") == true)
            #expect(try Data(contentsOf: history) == Data("broken history".utf8))
        }
    }

    private func withStore(_ body: (CaptureStore, URL) async throws -> Void) async throws {
        _ = NSApplication.shared
        Preferences.register()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TobyShot-CodexTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(CaptureStore(directory: directory), directory)
    }

    private func image(_ color: NSColor) throws -> NSImage {
        let context = try #require(CGContext(data: nil, width: 17, height: 13, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 17, height: 13))
        return NSImage(cgImage: try #require(context.makeImage()), size: CGSize(width: 17, height: 13))
    }

    private func addRecording(to store: CaptureStore, in directory: URL) throws {
        let video = directory.appendingPathComponent("recording.mp4")
        try Data([0, 1, 2]).write(to: video)
        try store.add(video: video, size: CGSize(width: 17, height: 13))
    }

    private func application(in directory: URL, documentTypes: [[String: Any]]) throws -> URL {
        // The application name need not be Codex.app (the installed build is named ChatGPT.app).
        let application = directory.appendingPathComponent("ChatGPT.app")
        let contents = application.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "TobyShot.CodexTests.\(UUID().uuidString)",
                                   "CFBundlePackageType": "APPL", "CFBundleDocumentTypes": documentTypes]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return application
    }
}
