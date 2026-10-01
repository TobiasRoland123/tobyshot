import AppKit
import SwiftUI
import Vision
import UniformTypeIdentifiers

enum CaptureIntent {
    case preferences, copy, save, annotate, pin, recognizeText(keepLines: Bool?)
}

@MainActor
final class AppCoordinator: ObservableObject {
    let store: CaptureStore
    let shortcuts: HotKeyManager

    init(shortcuts: HotKeyManager, store: CaptureStore? = nil) {
        self.shortcuts = shortcuts
        self.store = store ?? CaptureStore()
    }
    @Published var isBusy = false
    @Published var isRecording = false
    @Published var isStopping = false
    @Published var recordingSeconds = 0
    @Published var countdown: Int?
    @Published var screenPermission = ScreenCaptureService.hasPermission
    @Published var isCheckingPermission = false
    @Published var notice: String?
    var showLibrary: (() -> Void)?
    var showSettings: (() -> Void)?
    var hideLibrary: (() -> Void)?
    var recordingChanged: (() -> Void)?
    private let captureService = ScreenCaptureService()
    private let recorder = ScreenRecorder()
    private var editors: [AnnotationEditorWindow] = []
    private var lastSavedEditor: AnnotationEditorWindow?
    private var lastSavedClipboardChangeCount: Int?
    private var pins: [NSWindowController] = []
    private var preview: QuickAccessWindow?
    private var previewItem: CaptureItem?
    private var pinsHidden = false
    private var recordingPanel: NSPanel?
    private var countdownPanel: NSPanel?
    private var recordingTimer: Timer?
    private var countdownTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var recordingStarted: Date?
    private var verifiedScreenPermission: Bool?
    private var shutterSound: NSSound?

    var recordingTime: String { String(format: "%02d:%02d", recordingSeconds / 60, recordingSeconds % 60) }

    func refreshPermission() { screenPermission = verifiedScreenPermission ?? ScreenCaptureService.hasPermission }
    func requestPermission() {
        guard !isBusy, !isRecording, !isCheckingPermission else { return }
        isCheckingPermission = true
        Task {
            defer { isCheckingPermission = false }
            do {
                try await captureService.checkPermission()
                confirmScreenPermission()
                toast("Screen access is ready. Choose a capture above.")
            } catch { report(error) }
        }
    }
    private func confirmScreenPermission() {
        verifiedScreenPermission = true
        screenPermission = true
    }
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }

    func capture(_ mode: CaptureMode, delayed: Bool = false, intent: CaptureIntent = .preferences, previousArea: Bool = false) {
        guard !isBusy, !isRecording, !isCheckingPermission else { return }
        isBusy = true
        preview?.close(); hideLibrary?()
        countdownTask = Task { [self] in
            defer { isBusy = false; countdown = nil; countdownPanel?.close(); countdownPanel = nil; countdownTask = nil }
            do {
                if delayed { try await runCountdown(Preferences.int("selfTimer")) }
                else if mode != .area { try await Task.sleep(for: .milliseconds(250)) }
                guard !Task.isCancelled else { return }
                let result = try await (previousArea ? captureService.capturePreviousArea() : captureService.capture(mode))
                confirmScreenPermission()
                guard let result else { return }
                let background = result.isWindow && Preferences.string("windowBackground") == "Wallpaper" ? Preferences.string("wallpaperStyle") : nil
                let image = try ImageOutput.prepared(result.image, scale: result.scale, background: background, padding: CGFloat(Preferences.double("windowPadding")))
                let item = try store.add(image: image)
                playShutter()
                switch intent {
                case .preferences:
                    if Preferences.bool("afterScreenshotSave") { _ = try export(item, ask: Preferences.bool("askFilename"), retina: result.scale > 1 && !Preferences.bool("retinaOneX")) }
                    if Preferences.bool("afterScreenshotCopy") { copy(item, notify: false) }
                    if Preferences.bool("afterScreenshotOverlay") { showPreview(item) }
                    if Preferences.bool("afterScreenshotAnnotate") { annotate(item) }
                    if Preferences.bool("afterScreenshotPin") { pin(image) }
                case .copy: copy(item)
                case .save: save(item)
                case .annotate: annotate(item)
                case .pin: pin(image)
                case .recognizeText(let keepLines): recognizeText(item, keepLines: keepLines)
                }
            } catch is CancellationError { return }
            catch { showLibrary?(); report(error) }
        }
    }

    func toggleRecording(area: Bool = true) {
        if isRecording { stopRecording(); return }
        guard !isBusy, !isCheckingPermission else { return }
        isBusy = true; hideLibrary?(); preview?.close()
        countdownTask = Task { [self] in
            defer { isBusy = false; countdown = nil; countdownPanel?.close(); countdownPanel = nil; countdownTask = nil }
            do {
                try await Task.sleep(for: .milliseconds(250))
                let target = try await captureService.recordingTarget(area: area)
                confirmScreenPermission()
                guard let target else { showLibrary?(); return }
                if Preferences.bool("recordingCountdown") { try await runCountdown(3) }
                guard !Task.isCancelled else { return }
                try await recorder.start(target: target) { [weak self] result in self?.recordingFinished(result) }
                isRecording = true; recordingSeconds = 0; recordingStarted = Date()
                recordingChanged?()
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.recordingSeconds = Int(Date().timeIntervalSince(self.recordingStarted ?? Date()))
                        self.recordingChanged?()
                    }
                }
                if Preferences.bool("recordingControls") { showRecordingControls() }
            } catch is CancellationError { showLibrary?() }
            catch { showLibrary?(); report(error) }
        }
    }

    func stopRecording() {
        guard isRecording, !isStopping else { return }
        isStopping = true
        Task { await recorder.stop() }
    }

    private func recordingFinished(_ result: Result<URL, Error>) {
        isRecording = false; isStopping = false; recordingTimer?.invalidate(); recordingTimer = nil
        recordingPanel?.close(); recordingPanel = nil; recordingChanged?()
        do {
            let file = try result.get()
            let item = try store.add(video: file, size: recorder.size)
            if Preferences.bool("afterRecordingSave") { _ = try export(item, ask: Preferences.bool("askFilename")) }
            if Preferences.bool("afterRecordingCopy") { copy(item, notify: false) }
            if Preferences.bool("afterRecordingOverlay") { showPreview(item) }
            if Preferences.bool("afterRecordingOpen") { NSWorkspace.shared.open(store.url(for: item)) }
        } catch { report(error) }
    }

    func cancelCountdown() { countdownTask?.cancel() }
    private func runCountdown(_ seconds: Int) async throws {
        let panel = floatingPanel(size: CGSize(width: 240, height: 120))
        panel.contentView = NSHostingView(rootView: CountdownView(app: self).preferredColorScheme(.dark))
        panel.center(); panel.orderFrontRegardless(); countdownPanel = panel
        for value in stride(from: max(1, seconds), through: 1, by: -1) {
            countdown = value
            try await Task.sleep(for: .seconds(1))
        }
        countdown = nil; panel.orderOut(nil)
        try await Task.sleep(for: .milliseconds(180))
    }

    func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Open an image to annotate in TobyShot."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openImage(at: url)
    }
    func openImage(at url: URL) {
        guard let image = NSImage(contentsOf: url), image.isValid else { report(TobyError.message("TobyShot couldn't open this image.")); return }
        openEditor(image, source: url)
    }
    func pasteImage() {
        if let editor = lastSavedEditor, lastSavedClipboardChangeCount == NSPasteboard.general.changeCount {
            if !editors.contains(where: { $0 === editor }) { editors.append(editor) }
            preview?.close()
            editor.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage], let image = images.first { openEditor(image) }
        else if let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL], let url = urls.first { openImage(at: url) }
        else { toast("Copy an image first, then paste it here.") }
    }
    func openDemo() { openEditor(DemoImage.make()) }

    func annotate(_ item: CaptureItem) {
        guard item.kind == .image else { NSWorkspace.shared.open(store.url(for: item)); return }
        guard let image = store.image(for: item) else { report(TobyError.message("This capture is no longer available.")); return }
        openEditor(image, source: store.url(for: item))
    }

    @discardableResult
    func openEditor(_ image: NSImage, source: URL? = nil) -> AnnotationEditorWindow {
        editors.removeAll { $0.window?.isVisible == false }
        weak var editorWindow: NSWindow?
        let editor = AnnotationEditorWindow(image: image, sourceURL: source, shortcuts: shortcuts, onSave: { [weak self] image, ask in
            guard let self else { return false }
            do {
                let item = try self.store.add(image: image)
                if let url = try self.export(item, ask: ask || Preferences.bool("askFilename")) {
                    self.toast("Saved \(url.lastPathComponent)")
                    if !ask { self.showPreview(item) }
                    else { editorWindow?.title = "\(url.lastPathComponent) — TobyShot" }
                    return true
                }
                try self.store.remove(item)
            } catch { self.report(error) }
            return false
        }, onCopy: { [weak self] image in
            do {
                guard let self else { return }
                let item = try self.store.add(image: image)
                self.copy(item)
            } catch { self?.report(error) }
        }, onPin: { [weak self] image in self?.pin(image) })
        editor.onSaveAndClose = { [weak self] editor in
            self?.lastSavedEditor = editor
            self?.lastSavedClipboardChangeCount = NSPasteboard.general.changeCount
        }
        editorWindow = editor.window
        editors.append(editor); editor.showWindow(nil); editor.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return editor
    }

    func confirmClosingEditors() -> Bool {
        for editor in editors {
            if let window = editor.window, window.isVisible, !editor.windowShouldClose(window) { return false }
        }
        return true
    }

    func save(_ item: CaptureItem, ask: Bool = false) {
        do {
            if let url = try export(item, ask: ask || Preferences.string("saveBehavior") == "Ask every time") { toast("Saved to \(url.deletingLastPathComponent().lastPathComponent)") }
        } catch { report(error) }
    }

    @discardableResult
    func export(_ item: CaptureItem, ask: Bool, retina: Bool = false) throws -> URL? {
        let format = Preferences.string("imageFormat")
        let ext = item.kind == .video ? "mp4" : ImageOutput.fileExtension(format)
        var url: URL
        let name = item.title + (retina && Preferences.bool("retinaSuffix") ? "@2x" : "")
        if ask {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name + "." + ext
            panel.directoryURL = Preferences.exportDirectory
            panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
            panel.canCreateDirectories = true
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let destination = panel.url else { return nil }
            url = destination
        } else {
            try FileManager.default.createDirectory(at: Preferences.exportDirectory, withIntermediateDirectories: true)
            url = CaptureNaming.uniqueURL(directory: Preferences.exportDirectory, name: name, ext: ext)
        }
        if item.kind == .image {
            guard let image = store.image(for: item) else { throw TobyError.message("The original image is missing.") }
            try ImageOutput.data(image, format: format).write(to: url, options: .atomic)
        } else {
            // Use an atomic replacement for an explicitly confirmed Save As destination.
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).mp4")
            try FileManager.default.copyItem(at: store.url(for: item), to: temporary)
            do {
                if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary) }
                else { try FileManager.default.moveItem(at: temporary, to: url) }
            } catch { try? FileManager.default.removeItem(at: temporary); throw error }
        }
        try store.markExported(item, at: url)
        return url
    }

    func copy(_ item: CaptureItem, notify: Bool = true) {
        ImageOutput.copy(item.kind == .image ? store.image(for: item) : nil, file: store.url(for: item))
        if notify { toast(item.kind == .image ? "Copied to clipboard" : "Recording copied to clipboard") }
    }
    func reveal(_ item: CaptureItem) {
        let exported = store.items.first { $0.id == item.id }?.exportedPath.map { URL(fileURLWithPath: $0) }
        let url = exported.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? store.url(for: item)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    func remove(_ item: CaptureItem) {
        do { try store.remove(item) } catch { report(error) }
    }
    func showPreview(_ item: CaptureItem) {
        preview?.close()
        previewItem = item
        preview = QuickAccessWindow(item: item, app: self)
        preview?.showWindow(nil)
    }

    func pin(_ image: NSImage) {
        pins.removeAll { $0.window == nil }
        if pinsHidden { pins.forEach { $0.window?.orderFrontRegardless() } }
        pinsHidden = false
        let maxSize: CGFloat = 540
        let factor = min(1, maxSize / max(image.size.width, image.size.height))
        let size = CGSize(width: max(120, image.size.width * factor), height: max(80, image.size.height * factor))
        let panel = floatingPanel(size: size, resizable: true)
        panel.hasShadow = Preferences.bool("pinnedShadow")
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: PinnedImageView(image: image, close: { [weak self, weak panel] in panel?.close(); self?.pins.removeAll { $0.window === panel } }))
        panel.center(); panel.orderFrontRegardless()
        pins.append(NSWindowController(window: panel))
    }

    func recognizeText(_ item: CaptureItem, keepLines override: Bool? = nil) {
        guard let image = store.image(for: item), let cg = try? ImageOutput.cgImage(image) else { return }
        toast("Reading text…")
        let language = Preferences.string("ocrLanguage")
        let keepLines = override ?? Preferences.bool("ocrLineBreaks")
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    request.automaticallyDetectsLanguage = language == "Automatic"
                    if language == "English" { request.recognitionLanguages = ["en-US"] }
                    if language == "Danish" { request.recognitionLanguages = ["da-DK"] }
                    try VNImageRequestHandler(cgImage: cg).perform([request])
                    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: keepLines ? "\n" : " ")
                }.value
                guard !result.isEmpty else { toast("No readable text found in this capture."); return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string)
                toast("Recognized text copied to clipboard")
                let alert = NSAlert()
                alert.messageText = "Text copied"
                alert.informativeText = "Recognized on your Mac. You can paste this text into any app."
                let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 460, height: 240))
                scroll.hasVerticalScroller = true
                let text = NSTextView(frame: scroll.bounds)
                text.string = result; text.isEditable = false; text.font = .systemFont(ofSize: 13)
                text.autoresizingMask = [.width]; scroll.documentView = text
                alert.accessoryView = scroll
                NSApp.activate(ignoringOtherApps: true); alert.runModal()
            } catch { report(error) }
        }
    }

    func restoreLastCapture() {
        guard let item = store.items.first else { toast("No captures in history yet."); showLibrary?(); return }
        showPreview(item)
    }

    func annotateLastScreenshot() {
        guard let item = store.items.first(where: { $0.kind == .image }) else { toast("No screenshots in history yet."); showLibrary?(); return }
        annotate(item)
    }

    func pinLastScreenshot() {
        guard let item = store.items.first(where: { $0.kind == .image }), let image = store.image(for: item) else { toast("No screenshots in history yet."); showLibrary?(); return }
        pin(image)
    }

    func chooseAndPinImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) { pin(image) }
    }

    func togglePins() {
        pinsHidden.toggle()
        for controller in pins {
            if pinsHidden { controller.window?.orderOut(nil) }
            else { controller.window?.orderFrontRegardless() }
        }
    }
    func closePins() { pins.forEach { $0.close() }; pins.removeAll(); pinsHidden = false }
    func toggleOverlays() {
        guard let preview, !preview.isClosed else { return }
        if preview.window?.isVisible == true { preview.window?.orderOut(nil) }
        else { preview.window?.orderFrontRegardless() }
    }
    func saveOverlays() {
        if let item = previewItem, preview?.isClosed == false { save(item) }
    }
    func closeOverlays() { preview?.close(); preview = nil; previewItem = nil }

    func toast(_ text: String) {
        noticeTask?.cancel(); notice = text
        noticeTask = Task { try? await Task.sleep(for: .seconds(4)); if !Task.isCancelled { notice = nil } }
    }
    func report(_ error: Error) {
        if ScreenCaptureService.isPermissionError(error) {
            verifiedScreenPermission = false
            screenPermission = false
            showScreenPermissionHelp()
            return
        }
        let alert = NSAlert(); alert.messageText = "TobyShot couldn’t finish that"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    private func showScreenPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = "macOS hasn’t allowed this copy of TobyShot to capture"
        alert.informativeText = "In System Settings → Privacy & Security → Screen & System Audio Recording, enable TobyShot, then quit and reopen it.\n\nIf TobyShot is already enabled, its entry may belong to an older build. Remove that TobyShot entry with the − button, then use + to add the current app shown in Finder.\n\nCurrent app: \(Bundle.main.bundleURL.path)"
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Show App in Finder")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: openPrivacySettings()
        case .alertSecondButtonReturn: NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        default: break
        }
    }
    private func playShutter() {
        let name = Preferences.string("shutterSound")
        guard Preferences.bool("playSounds"), name != "None" else { return }
        if name == "Native capture" {
            let directory = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system"
            shutterSound = NSSound(contentsOfFile: "\(directory)/Screen Capture.aif", byReference: true)
                ?? NSSound(contentsOfFile: "\(directory)/Grab.aif", byReference: true)
        } else {
            shutterSound = NSSound(named: NSSound.Name(name))
        }
        shutterSound?.play()
    }
    private func showRecordingControls() {
        let panel = floatingPanel(size: CGSize(width: 268, height: 60))
        panel.contentView = NSHostingView(rootView: RecordingControls(app: self).preferredColorScheme(.dark))
        if let screen = NSScreen.main {
            panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - 134, y: screen.visibleFrame.minY + 30))
        }
        panel.isMovableByWindowBackground = true
        panel.orderFrontRegardless(); recordingPanel = panel
    }
}

@MainActor
func floatingPanel(size: CGSize, resizable: Bool = false) -> NSPanel {
    var style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    if resizable { style.insert(.resizable) }
    let panel = CapturePanel(contentRect: CGRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
    panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
    panel.hasShadow = true; panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    return panel
}
