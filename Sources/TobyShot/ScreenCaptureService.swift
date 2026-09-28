import AppKit
import ScreenCaptureKit
import AVFoundation

enum CaptureMode: String { case area, fullscreen, window }

struct CaptureResult {
    let image: NSImage
    let scale: CGFloat
    let isWindow: Bool
}

struct RecordingTarget {
    let filter: SCContentFilter
    let rect: CGRect
    let scale: CGFloat
}

@MainActor
final class ScreenCaptureService {
    private let selector = RegionSelector()
    private var previousArea: (displayID: CGDirectDisplayID, rect: CGRect)?

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func isPermissionError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
    }

    func checkPermission() async throws { _ = try await content() }

    private func content() async throws -> SCShareableContent {
        // Preflight can remain false after a permission change or local rebuild.
        // Let ScreenCaptureKit request/check access instead of blocking capture
        // or opening System Settings based on that advisory flag.
        return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    private func displayFilter(_ display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        // Exclude the application, not only its current windows: the recording
        // controls and previews may be created after this filter is constructed.
        let ownApplications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let desktopIcons = content.windows.filter { window in
            Preferences.bool("hideDesktopIcons") && window.owningApplication?.bundleIdentifier == "com.apple.finder" && window.windowLayer < 0
        }
        return SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: desktopIcons)
    }

    private func configuration(size: CGSize, scale: CGFloat, cursor: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = max(1, Int(size.width * scale))
        config.height = max(1, Int(size.height * scale))
        config.showsCursor = cursor
        config.captureResolution = .best
        config.captureDynamicRange = .SDR
        return config
    }

    func capture(_ mode: CaptureMode) async throws -> CaptureResult? {
        let content = try await content()
        guard let active = activeDisplay(in: content) else { throw TobyError.message("No display is available to capture.") }
        if mode == .fullscreen {
            let scale = screen(for: active)?.backingScaleFactor ?? 2
            let filter = displayFilter(active, content: content)
            let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration(size: active.frame.size, scale: scale, cursor: Preferences.bool("screenshotCursor")))
            return CaptureResult(image: NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height)), scale: scale, isWindow: false)
        }
        let snapshots = try await snapshots(content: content)
        let windows = content.windows.filter { $0.windowLayer == 0 && $0.frame.width > 20 && $0.frame.height > 20 && $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier }
        if mode == .window && windows.isEmpty { throw TobyError.message("No windows are available to capture. Open a window in another app and try again.") }
        guard let selection = await selector.select(snapshots: snapshots, windows: mode == .window ? windows : [], instruction: mode == .window ? "Click a window to capture" : "Drag to capture an area") else { return nil }
        if let window = selection.window {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            let config = configuration(size: filter.contentRect.size, scale: scale, cursor: false)
            config.ignoreShadowsSingleWindow = !Preferences.bool("windowShadow")
            config.shouldBeOpaque = false
            let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return CaptureResult(image: NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height)), scale: scale, isWindow: true)
        }
        let snapshot = selection.snapshot
        previousArea = (snapshot.display.displayID, selection.rect)
        let pixels = CaptureGeometry.pixelRect(selection.rect, scale: snapshot.scale, bounds: CGRect(x: 0, y: 0, width: snapshot.image.width, height: snapshot.image.height))
        guard let cropped = snapshot.image.cropping(to: pixels) else { throw TobyError.message("The selected area could not be captured.") }
        return CaptureResult(image: NSImage(cgImage: cropped, size: CGSize(width: cropped.width, height: cropped.height)), scale: snapshot.scale, isWindow: false)
    }

    func capturePreviousArea() async throws -> CaptureResult? {
        guard let previousArea else { throw TobyError.message("Capture an area first, then use Capture Previous Area.") }
        let content = try await content()
        guard let snapshot = try await snapshots(content: content).first(where: { $0.display.displayID == previousArea.displayID }) else {
            throw TobyError.message("The display used for the previous capture is no longer connected.")
        }
        let pixels = CaptureGeometry.pixelRect(previousArea.rect, scale: snapshot.scale,
            bounds: CGRect(x: 0, y: 0, width: snapshot.image.width, height: snapshot.image.height))
        guard !pixels.isEmpty, let cropped = snapshot.image.cropping(to: pixels) else { throw TobyError.message("The previous capture area is outside the display. Capture a new area first.") }
        return CaptureResult(image: NSImage(cgImage: cropped, size: CGSize(width: cropped.width, height: cropped.height)), scale: snapshot.scale, isWindow: false)
    }

    func recordingTarget(area: Bool) async throws -> RecordingTarget? {
        let content = try await content()
        guard let display = activeDisplay(in: content) else { throw TobyError.message("No display is available to record.") }
        if !area { return RecordingTarget(filter: displayFilter(display, content: content), rect: CGRect(origin: .zero, size: display.frame.size), scale: screen(for: display)?.backingScaleFactor ?? 2) }
        let snapshots = try await snapshots(content: content)
        guard let selection = await selector.select(snapshots: snapshots, windows: [], instruction: "Drag to choose the recording area") else { return nil }
        return RecordingTarget(filter: displayFilter(selection.snapshot.display, content: content), rect: selection.rect, scale: selection.snapshot.scale)
    }

    private func snapshots(content: SCShareableContent) async throws -> [ScreenSnapshot] {
        var results: [ScreenSnapshot] = []
        for display in content.displays {
            guard let screen = screen(for: display) else { continue }
            let cg = try await SCScreenshotManager.captureImage(contentFilter: displayFilter(display, content: content), configuration: configuration(size: display.frame.size, scale: screen.backingScaleFactor, cursor: false))
            results.append(ScreenSnapshot(screen: screen, display: display, image: cg, scale: CGFloat(cg.width) / display.frame.width))
        }
        return results
    }

    private func screen(for display: SCDisplay) -> NSScreen? { NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID } }
    private func activeDisplay(in content: SCShareableContent) -> SCDisplay? {
        let activeScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let id = (activeScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        return content.displays.first { $0.displayID == id } ?? content.displays.first
    }
}

enum CaptureGeometry {
    static func pixelRect(_ rect: CGRect, scale: CGFloat, bounds: CGRect) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral.intersection(bounds)
    }
    static func recordingSize(_ size: CGSize, scale: CGFloat, maximum: String) -> CGSize {
        var width = size.width * scale, height = size.height * scale
        let cap: CGFloat = maximum == "1080p" ? 1080 : maximum == "720p" ? 720 : .greatestFiniteMagnitude
        // Resolution limits constrain the shorter edge and preserve aspect ratio.
        let factor = min(1, cap / min(width, height), 4096 / max(width, height))
        width *= factor; height *= factor
        return CGSize(width: max(2, Int(width) / 2 * 2), height: max(2, Int(height) / 2 * 2))
    }
}

@MainActor
final class ScreenRecorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var file: URL?
    private(set) var size: CGSize = .zero

    func start(target: RecordingTarget, completion: @escaping (Result<URL, Error>) -> Void) async throws {
        if Preferences.bool("recordingMicrophone") {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else { throw TobyError.message("Microphone access is disabled. Allow it in System Settings, or turn off microphone audio in TobyShot settings.") }
        }
        let config = SCStreamConfiguration()
        config.sourceRect = target.rect
        size = CaptureGeometry.recordingSize(target.rect.size, scale: Preferences.bool("recordingOneX") ? 1 : target.scale, maximum: Preferences.string("recordingResolution"))
        config.width = Int(size.width); config.height = Int(size.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(max(1, Preferences.int("recordingFPS"))))
        config.showsCursor = Preferences.bool("recordingCursor")
        config.capturesAudio = Preferences.bool("recordingSystemAudio")
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = Preferences.bool("recordingMicrophone")
        config.captureDynamicRange = .SDR
        config.queueDepth = 5
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TobyShot-\(UUID().uuidString).mp4")
        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = url
        recordingConfig.outputFileType = .mp4
        recordingConfig.videoCodecType = .h264
        let stream = SCStream(filter: target.filter, configuration: config, delegate: self)
        let output = SCRecordingOutput(configuration: recordingConfig, delegate: self)
        try stream.addRecordingOutput(output)
        self.stream = stream; self.output = output; self.file = url; self.completion = completion
        do { try await stream.startCapture() }
        catch { self.completion = nil; self.stream = nil; self.output = nil; try? FileManager.default.removeItem(at: url); throw error }
    }

    func stop() async {
        do { try await stream?.stopCapture() }
        catch { finish(.failure(error)) }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            guard let file else { return }
            finish(.success(file))
        }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in finish(.failure(error)) }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in finish(.failure(error)) }
    }
    private func finish(_ result: Result<URL, Error>) {
        let callback = completion
        completion = nil
        if case .failure = result {
            let activeStream = stream
            Task { try? await activeStream?.stopCapture() }
            if let file { try? FileManager.default.removeItem(at: file) }
        }
        stream = nil; output = nil; file = nil
        callback?(result)
    }
}
