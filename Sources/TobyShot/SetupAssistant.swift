import AppKit
import Carbon
import Combine

/// First-run checklist for the macOS settings TobyShot needs before it can capture.
@MainActor
final class SetupAssistant: ObservableObject {
    enum AccessState: Equatable { case unchecked, checking, ready, denied, failed(String) }

    struct ShortcutStatus: Identifiable, Equatable {
        let action: ShortcutAction
        let binding: ShortcutBinding
        let issue: String?
        let conflictsWithMacOS: Bool
        var id: ShortcutAction { action }
        var isReady: Bool { issue == nil }
        /// The name System Settings shows for the standard macOS screenshot shortcut on this binding.
        var macOSScreenshotName: String? { conflictsWithMacOS ? Self.macOSScreenshotNames[binding] : nil }

        static let macOSScreenshotNames: [ShortcutBinding: String] = {
            let save = UInt32(cmdKey | shiftKey)
            let copy = UInt32(cmdKey | shiftKey | controlKey)
            return [
                ShortcutBinding(keyCode: UInt32(kVK_ANSI_3), modifiers: save): "Save picture of screen as a file",
                ShortcutBinding(keyCode: UInt32(kVK_ANSI_3), modifiers: copy): "Copy picture of screen to the clipboard",
                ShortcutBinding(keyCode: UInt32(kVK_ANSI_4), modifiers: save): "Save picture of selected area as a file",
                ShortcutBinding(keyCode: UInt32(kVK_ANSI_4), modifiers: copy): "Copy picture of selected area to the clipboard",
                ShortcutBinding(keyCode: UInt32(kVK_ANSI_5), modifiers: save): "Screenshot and recording options"
            ]
        }()
    }

    static let completedKey = "setupCompleted"
    static let skippedKey = "setupSkipped"
    static let exportChosenKey = "setupExportLocationChosen"
    static let keyboardSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    @Published private(set) var access: AccessState = .unchecked
    @Published private(set) var testScreenshotTaken = false
    @Published private(set) var exportLocationChosen: Bool
    @Published private(set) var exportError: String?
    @Published private(set) var isComplete: Bool
    let shortcuts: HotKeyManager
    private let defaults: UserDefaults
    private let advisoryAccess: () -> Bool
    private let verifyAccess: () async throws -> Bool
    private var shortcutsObserver: AnyCancellable?
    private var defaultsObserver: AnyCancellable?

    /// `advisoryAccess` may be stale; only `verifyAccess` can mark screen access ready.
    init(shortcuts: HotKeyManager, defaults: UserDefaults = .standard,
         advisoryAccess: @escaping () -> Bool, verifyAccess: @escaping () async throws -> Bool) {
        self.shortcuts = shortcuts
        self.defaults = defaults
        self.advisoryAccess = advisoryAccess
        self.verifyAccess = verifyAccess
        isComplete = defaults.bool(forKey: Self.completedKey)
        exportLocationChosen = defaults.bool(forKey: Self.exportChosenKey)
        shortcutsObserver = shortcuts.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        // Settings can change the save folder while setup is open.
        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var shouldShowOnLaunch: Bool { !isComplete && !defaults.bool(forKey: Self.skippedKey) }

    /// Every global shortcut TobyShot registers, using the user's current bindings.
    var shortcutStatuses: [ShortcutStatus] {
        ShortcutAction.allCases.compactMap { action in
            guard action.scope == .global, let binding = shortcuts.bindings[action] else { return nil }
            return ShortcutStatus(action: action, binding: binding, issue: shortcuts.issues[action],
                                  conflictsWithMacOS: shortcuts.systemConflicts.contains(action))
        }
    }
    var shortcutsReady: Bool { shortcutStatuses.allSatisfy(\.isReady) }
    var accessReady: Bool { access == .ready }
    var canFinish: Bool { shortcutsReady && accessReady && exportLocationChosen }

    /// Where screenshots and recordings are saved, read from the same setting Settings edits.
    var exportDirectory: URL {
        let path = defaults.string(forKey: "exportPath") ?? ExportLocation.defaultPath
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Saves the folder for all captures once TobyShot can create and write to it.
    @discardableResult
    func chooseExportLocation(_ directory: URL) -> Bool {
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch {
            exportError = (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSFileWriteNoPermissionError
                ? "macOS didn’t allow TobyShot to use this folder. Allow access in System Settings → Privacy & Security → Files & Folders, or choose another folder."
                : "TobyShot couldn’t use this folder: \(error.localizedDescription)"
            return false
        }
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            exportError = "TobyShot can’t save to this folder. Choose another one."
            return false
        }
        defaults.set(ExportLocation.storedPath(for: directory), forKey: "exportPath")
        defaults.set(true, forKey: Self.exportChosenKey)
        exportLocationChosen = true
        exportError = nil
        return true
    }

    /// Starts a setup pass. A screenshot counts as the test only once setup is visible.
    func begin() {
        testScreenshotTaken = false
        refresh()
    }

    /// Refreshes shortcut conflicts and confirms access that macOS already reports as granted.
    func refresh() {
        shortcuts.register()
        if access != .ready && access != .checking && advisoryAccess() { Task { await checkAccess() } }
    }

    /// Refreshes shortcuts and runs the full access check, which may show the macOS prompt.
    func recheck() async {
        shortcuts.register()
        await checkAccess()
    }

    func checkAccess() async {
        guard access != .checking else { return }
        let previous = access
        access = .checking
        do { access = try await verifyAccess() ? .ready : previous }
        catch { access = ScreenCaptureService.isPermissionError(error) ? .denied : .failed(error.localizedDescription) }
    }

    func screenshotCaptured() {
        testScreenshotTaken = true
        // A successful capture proves access even if the explicit check has not run yet.
        access = .ready
    }

    @discardableResult
    func finish() -> Bool {
        guard canFinish else { return false }
        defaults.set(true, forKey: Self.completedKey)
        isComplete = true
        return true
    }

    /// Leaves setup incomplete and stops it from opening automatically at launch.
    func skip() {
        guard !isComplete else { return }
        defaults.set(true, forKey: Self.skippedKey)
    }
}
