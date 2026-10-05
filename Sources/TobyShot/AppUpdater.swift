import AppKit
import Combine
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var configurationError: String?

    var captureInProgress: () -> Bool = { false }

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
    )

    func start() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
        do { try controller.updater.start() }
        catch {
            configurationError = error.localizedDescription
            NSLog("TobyShot updater: %@", error.localizedDescription)
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func addMenuItem(to menu: NSMenu) {
        let title = availableVersion.map { "Update to \($0)…" } ?? "Check for Updates…"
        let item = NSMenuItem(title: title, action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        item.target = controller
        menu.addItem(item)
    }

    func validateUpdateCheck() throws {
        guard !captureInProgress() else {
            throw NSError(domain: "app.tobyshot.updates", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Finish your capture or recording before checking for updates."
            ])
        }
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        try validateUpdateCheck()
    }

    // Sparkle presents scheduled alerts without stealing focus. The menu also
    // shows the available version so this menu bar app has a persistent reminder.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
