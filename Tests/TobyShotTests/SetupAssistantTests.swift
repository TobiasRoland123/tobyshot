import Carbon
import Foundation
import ScreenCaptureKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct SetupAssistantTests {
    private let macOSScreenshots: Set<ShortcutBinding> = [
        ShortcutAction.captureFullScreen.defaultBinding!, ShortcutAction.captureArea.defaultBinding!, ShortcutAction.allInOne.defaultBinding!
    ]

    private func makeSetup(system: Set<ShortcutBinding> = [], verify: @escaping () async throws -> Bool = { true })
        -> (SetupAssistant, SetupHotKeyBackend, UserDefaults, String) {
        let name = "TobyShot.SetupAssistantTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let backend = SetupHotKeyBackend()
        backend.system = system
        let setup = SetupAssistant(shortcuts: HotKeyManager(defaults: defaults, backend: backend), defaults: defaults,
                                   advisoryAccess: { false }, verifyAccess: verify)
        return (setup, backend, defaults, name)
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TobyShot-SetupTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func checkingAgainRegistersShortcutsOnceMacOSReleasesThem() async {
        let (setup, backend, defaults, name) = makeSetup(system: macOSScreenshots)
        defer { defaults.removePersistentDomain(forName: name) }
        setup.begin()

        let blocked = setup.shortcutStatuses.filter { !$0.isReady }
        #expect(Set(blocked.map { $0.action }) == [.captureArea, .captureFullScreen, .allInOne])
        #expect(blocked.allSatisfy { $0.conflictsWithMacOS })
        #expect(blocked.first { $0.action == .captureFullScreen }?.macOSScreenshotName == "Save picture of screen as a file")
        #expect(blocked.first { $0.action == .allInOne }?.macOSScreenshotName == "Screenshot and recording options")
        #expect(setup.shortcutStatuses.contains { $0.action == .openClipboard && $0.isReady })
        #expect(backend.registered[.captureArea] == nil)
        #expect(!setup.shortcutsReady)

        // The user turns off the macOS shortcuts and returns without changing TobyShot's bindings.
        backend.system = []
        await setup.recheck()
        #expect(setup.shortcutsReady)
        #expect(backend.registered[.captureArea] == ShortcutAction.captureArea.defaultBinding)
        #expect(setup.shortcuts.activeBinding(for: .captureFullScreen) == ShortcutAction.captureFullScreen.defaultBinding)
    }

    @Test func customizedBindingsOnlyFlagShortcutsThatStillConflict() {
        let (setup, _, defaults, name) = makeSetup(system: macOSScreenshots)
        defer { defaults.removePersistentDomain(forName: name) }
        let custom = ShortcutBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey | optionKey))
        #expect(setup.shortcuts.setShortcut(custom, for: .captureArea) == nil)
        #expect(setup.shortcuts.setShortcut(nil, for: .allInOne) == nil)
        setup.begin()

        let statuses = setup.shortcutStatuses
        #expect(statuses.first { $0.action == .captureArea } == .init(action: .captureArea, binding: custom, issue: nil, conflictsWithMacOS: false))
        #expect(!statuses.contains { $0.action == .allInOne })
        #expect(statuses.filter { !$0.isReady }.map { $0.action } == [.captureFullScreen])
    }

    @Test func screenAccessIsReadyOnlyAfterAVerifiedCheck() async {
        var granted = false
        var checks = 0
        let (setup, _, defaults, name) = makeSetup {
            checks += 1
            guard granted else { throw NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue) }
            return true
        }
        defer { defaults.removePersistentDomain(forName: name) }

        // Returning from System Settings refreshes shortcuts but never assumes access.
        setup.begin()
        setup.refresh()
        #expect(checks == 0)
        #expect(setup.access == .unchecked)
        #expect(!setup.finish())

        await setup.recheck()
        #expect(setup.access == .denied)
        #expect(setup.shortcutsReady)
        #expect(!setup.canFinish)
        #expect(!setup.finish())

        granted = true
        await setup.recheck()
        #expect(setup.access == .ready)
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(setup.chooseExportLocation(folder))
        #expect(setup.finish())
        #expect(checks == 2)
    }

    @Test func finishingRequiresAWritableSaveFolder() async throws {
        let (setup, _, defaults, name) = makeSetup()
        defer { defaults.removePersistentDomain(forName: name) }
        await setup.recheck()
        #expect(setup.shortcutsReady && setup.accessReady)
        #expect(!setup.exportLocationChosen)
        #expect(!setup.finish())

        let originalPath = defaults.string(forKey: "exportPath")
        #expect(!setup.chooseExportLocation(URL(fileURLWithPath: "/System/TobyShot-\(UUID().uuidString)", isDirectory: true)))
        #expect(setup.exportError != nil)
        #expect(!setup.exportLocationChosen)
        #expect(defaults.string(forKey: "exportPath") == originalPath)

        // A missing folder is created so the first screenshot or recording can be saved there.
        let parent = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let folder = parent.appendingPathComponent("Captures", isDirectory: true)
        #expect(setup.chooseExportLocation(folder))
        #expect(setup.exportError == nil)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(defaults.string(forKey: "exportPath") == folder.path)
        #expect(setup.exportDirectory.standardizedFileURL == folder.standardizedFileURL)
        #expect(setup.finish())

        let relaunched = SetupAssistant(shortcuts: setup.shortcuts, defaults: defaults, advisoryAccess: { false }, verifyAccess: { true })
        #expect(relaunched.exportLocationChosen)
    }

    @Test func newUsersDefaultToDocumentsCapturesWhileExistingUsersKeepTheirFolder() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(URL(fileURLWithPath: ExportLocation.defaultPath) == home.appendingPathComponent("Documents/Captures"))

        let name = "TobyShot.ExportLocationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        ExportLocation.preserveLegacyDefault(in: defaults, domain: name, legacyFolderExists: false)
        #expect(defaults.persistentDomain(forName: name)?["exportPath"] == nil)

        ExportLocation.preserveLegacyDefault(in: defaults, domain: name, legacyFolderExists: true)
        #expect(defaults.persistentDomain(forName: name)?["exportPath"] as? String == ExportLocation.legacyPath)

        defaults.set("~/Desktop/Shots", forKey: "exportPath")
        ExportLocation.preserveLegacyDefault(in: defaults, domain: name, legacyFolderExists: true)
        #expect(defaults.string(forKey: "exportPath") == "~/Desktop/Shots")
    }

    @Test func skippedCheckLeavesAccessUnchanged() async {
        let (setup, _, defaults, name) = makeSetup(verify: { false })
        defer { defaults.removePersistentDomain(forName: name) }
        await setup.checkAccess()
        #expect(setup.access == .unchecked)
        setup.screenshotCaptured()
        #expect(setup.testScreenshotTaken)
        #expect(setup.access == .ready)
    }

    @Test func completionSurvivesRelaunchAndSkippingDoesNot() async {
        let (setup, backend, defaults, name) = makeSetup(system: macOSScreenshots)
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(setup.shouldShowOnLaunch)

        await setup.recheck()
        setup.skip()
        #expect(!setup.isComplete)
        #expect(!setup.shouldShowOnLaunch)
        let afterSkip = SetupAssistant(shortcuts: setup.shortcuts, defaults: defaults, advisoryAccess: { false }, verifyAccess: { true })
        #expect(!afterSkip.isComplete)

        // Shortcut conflicts block completion even when screen access is ready.
        #expect(!afterSkip.finish())
        backend.system = []
        await afterSkip.recheck()
        #expect(!afterSkip.finish())
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(afterSkip.chooseExportLocation(folder))
        #expect(afterSkip.finish())
        let relaunched = SetupAssistant(shortcuts: setup.shortcuts, defaults: defaults, advisoryAccess: { false }, verifyAccess: { true })
        #expect(relaunched.isComplete)
        #expect(!relaunched.shouldShowOnLaunch)
    }
}

private final class SetupHotKeyBackend: HotKeyBackend {
    var onAction: ((UInt32) -> Void)?
    var registered: [ShortcutAction: ShortcutBinding] = [:]
    var system: Set<ShortcutBinding> = []
    func register(_ binding: ShortcutBinding, for action: ShortcutAction) -> OSStatus {
        registered[action] = binding
        return noErr
    }
    func unregister(_ action: ShortcutAction) { registered[action] = nil }
    func systemShortcuts() -> Set<ShortcutBinding> { system }
}
