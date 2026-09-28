import AppKit
import Carbon
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct ShortcutTests {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let name = "TobyShot.ShortcutTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private var custom: ShortcutBinding { ShortcutBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey | optionKey)) }

    @Test func defaultsMatchCleanShot() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let bindings = ShortcutPreferences(defaults: defaults).load()
        #expect(bindings[.captureArea] == ShortcutBinding(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey)))
        #expect(bindings[.captureFullScreen] == ShortcutBinding(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | shiftKey)))
        #expect(bindings[.allInOne] == ShortcutBinding(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey)))
        #expect(bindings[.captureWindow] == nil)
        #expect(bindings[.recordScreen] == nil)
        #expect(bindings[.openImage] == nil)
        #expect(Set(bindings.values).count == bindings.count)
        let tools: [(ShortcutAction, String)] = [(.backgroundTool, "b"), (.moveTool, "v"), (.cropTool, "k"),
            (.drawTool, "d"), (.lineTool, "l"), (.textTool, "t"), (.arrowTool, "a"), (.counterTool, "c"),
            (.ellipseTool, "e"), (.redactionTool, "p"), (.rectangleTool, "r"), (.filledRectangleTool, "f")]
        for (action, key) in tools {
            #expect(bindings[action]?.menuKey == key)
            #expect(bindings[action]?.modifiers == 0)
        }
        #expect(bindings[.editorSave]?.appKitModifiers == .command)
        #expect(bindings[.editorSaveAs]?.appKitModifiers == [.command, .shift])
        #expect(bindings[.editorCopyObject]?.menuKey == "c")
        #expect(bindings[.editorCopyScreenshot]?.appKitModifiers == [.command, .shift])
    }

    @Test func customAndDisabledShortcutsSurviveRelaunch() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let manager = HotKeyManager(defaults: defaults, backend: FakeHotKeyBackend())
        #expect(manager.setShortcut(custom, for: .captureArea) == nil)
        #expect(manager.setShortcut(nil, for: .captureWindow) == nil)
        let reloaded = HotKeyManager(defaults: defaults, backend: FakeHotKeyBackend())
        #expect(reloaded.bindings[.captureArea] == custom)
        #expect(reloaded.bindings[.captureWindow] == nil)
        #expect(reloaded.bindings[.openImage] == ShortcutAction.openImage.defaultBinding)
    }

    @Test func duplicateAndSystemConflictsKeepPreviousBinding() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = FakeHotKeyBackend()
        let manager = HotKeyManager(defaults: defaults, backend: backend)
        manager.register()
        let previous = manager.bindings[.captureArea]
        #expect(manager.setShortcut(ShortcutAction.allInOne.defaultBinding, for: .captureArea)?.contains("All-in-One") == true)
        backend.system = [custom]
        #expect(manager.setShortcut(custom, for: .captureArea)?.contains("macOS") == true)
        #expect(manager.bindings[.captureArea] == previous)
        #expect(backend.registered[.captureArea] == previous)
        #expect(ShortcutPreferences(defaults: defaults).load()[.captureArea] == previous)
    }

    @Test func registrationFailurePreservesWorkingShortcut() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = FakeHotKeyBackend()
        let manager = HotKeyManager(defaults: defaults, backend: backend)
        manager.register()
        backend.rejected = custom
        #expect(manager.setShortcut(custom, for: .captureArea)?.contains("another app") == true)
        #expect(manager.bindings[.captureArea] == ShortcutAction.captureArea.defaultBinding)
        #expect(backend.registered[.captureArea] == ShortcutAction.captureArea.defaultBinding)
        #expect(ShortcutPreferences(defaults: defaults).load()[.captureArea] == ShortcutAction.captureArea.defaultBinding)
    }

    @Test func recordingSuspendsActionsAndResumesWithNewBinding() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = FakeHotKeyBackend()
        let manager = HotKeyManager(defaults: defaults, backend: backend)
        var fired: [UInt32] = []
        manager.onAction = { fired.append($0) }
        manager.register()
        backend.onAction?(1)
        manager.beginRecording()
        manager.beginRecording()
        #expect(backend.registered.isEmpty)
        #expect(manager.activeBinding(for: .captureArea) == nil)
        backend.onAction?(1)
        #expect(fired == [1])
        #expect(manager.setShortcut(custom, for: .captureArea) == nil)
        #expect(backend.registered.isEmpty)
        manager.endRecording()
        manager.endRecording()
        #expect(backend.registered[.captureArea] == custom)
        #expect(backend.registered.count == manager.bindings.filter { $0.key.scope == .global }.count)
        backend.onAction?(1)
        #expect(fired == [1, 1])
    }

    @Test func retryAndResetReportUnavailableDefaults() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = FakeHotKeyBackend()
        backend.system = [ShortcutAction.captureFullScreen.defaultBinding!]
        let manager = HotKeyManager(defaults: defaults, backend: backend)
        manager.register()
        #expect(manager.issues[.captureFullScreen] != nil)
        #expect(manager.activeBinding(for: .captureFullScreen) == nil)
        #expect(backend.registered[.captureFullScreen] == nil)
        #expect(manager.setShortcut(custom, for: .captureFullScreen) == nil)
        #expect(manager.issues[.captureFullScreen] == nil)
        manager.resetDefaults()
        #expect(manager.bindings[.captureFullScreen] == ShortcutAction.captureFullScreen.defaultBinding)
        #expect(manager.issues[.captureFullScreen] != nil)
        backend.system = []
        manager.register()
        #expect(manager.issues.isEmpty)
        #expect(backend.registered.count == manager.bindings.filter { $0.key.scope == .global }.count)
    }

    @Test func editorBindingsStayLocalAndRemainCustomizable() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = FakeHotKeyBackend()
        let manager = HotKeyManager(defaults: defaults, backend: backend)
        manager.register()
        #expect(backend.registered.keys.allSatisfy { $0.scope == .global })
        let j = ShortcutBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: 0)
        #expect(manager.setShortcut(j, for: .drawTool) == nil)
        #expect(manager.setShortcut(j, for: .captureArea) != nil)
        #expect(manager.setShortcut(j, for: .cropTool)?.contains("Draw Tool") == true)
        #expect(manager.setShortcut(ShortcutAction.captureArea.defaultBinding, for: .cropTool) != nil)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "j", charactersIgnoringModifiers: "j", isARepeat: false, keyCode: UInt16(kVK_ANSI_J))!
        #expect(manager.action(for: event, scope: .editor) == .drawTool)
        #expect(manager.action(for: event, scope: .global) == nil)
        manager.beginRecording()
        #expect(manager.action(for: event, scope: .editor) == nil)
        manager.endRecording()
        let reloaded = HotKeyManager(defaults: defaults, backend: FakeHotKeyBackend())
        #expect(reloaded.bindings[.drawTool] == j)
    }

    @Test func migratesOldDefaultsButPreservesCustomAndDisabledBindings() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ShortcutPreferences(defaults: defaults)
        preferences.save(ShortcutBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey)), for: .captureArea)
        preferences.save(ShortcutBinding(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey)), for: .captureWindow)
        preferences.save(custom, for: .recordScreen)
        preferences.save(nil, for: .openImage)
        let migrated = preferences.load()
        #expect(migrated[.captureArea] == ShortcutAction.captureArea.defaultBinding)
        #expect(migrated[.captureWindow] == nil)
        #expect(migrated[.recordScreen] == custom)
        #expect(migrated[.openImage] == nil)
        // Migration runs only once, so a later explicit assignment to the old keys is respected.
        let old = ShortcutBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey))
        preferences.save(old, for: .captureArea)
        #expect(preferences.load()[.captureArea] == old)
    }

    @Test func nativeRegistrationIsExclusiveAndCanBeReleased() throws {
        _ = NSApplication.shared
        let first = CarbonHotKeyBackend()
        let second = CarbonHotKeyBackend()
        let binding = ShortcutBinding(keyCode: UInt32(kVK_F19), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
        defer { first.unregister(.openImage); second.unregister(.openImage) }
        try #require(first.register(binding, for: .openImage) == noErr)
        #expect(second.register(binding, for: .openImage) == OSStatus(eventHotKeyExistsErr))
        first.unregister(.openImage)
        #expect(second.register(binding, for: .openImage) == noErr)
    }

    @Test func invalidShortcutsDoNotSwallowTypingOrStandardCommands() {
        #expect(ShortcutBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: 0).validationMessage != nil)
        #expect(ShortcutBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(shiftKey)).validationMessage != nil)
        #expect(ShortcutBinding(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey)).validationMessage != nil)
        #expect(ShortcutBinding(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey)).validationMessage != nil)
        #expect(custom.validationMessage == nil)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift, .capsLock], timestamp: 0, windowNumber: 0, context: nil, characters: "K", charactersIgnoringModifiers: "K", isARepeat: false, keyCode: UInt16(kVK_ANSI_K))!
        let binding = ShortcutBinding(event: event)
        #expect(binding.modifiers == UInt32(cmdKey | shiftKey))
        #expect(binding.menuKey == "k")
    }

    @Test func corruptPreferencesFallBackWithoutReenablingClearedShortcuts() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("broken".utf8), forKey: ShortcutAction.captureArea.preferenceKey)
        let preferences = ShortcutPreferences(defaults: defaults)
        preferences.save(ShortcutBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: 0), for: .captureWindow)
        preferences.save(nil, for: .openImage)
        let result = preferences.load()
        #expect(result[.captureArea] == ShortcutAction.captureArea.defaultBinding)
        #expect(result[.captureWindow] == ShortcutAction.captureWindow.defaultBinding)
        #expect(result[.openImage] == nil)
    }
}

private final class FakeHotKeyBackend: HotKeyBackend {
    var onAction: ((UInt32) -> Void)?
    var registered: [ShortcutAction: ShortcutBinding] = [:]
    var system: Set<ShortcutBinding> = []
    var rejected: ShortcutBinding?
    func register(_ binding: ShortcutBinding, for action: ShortcutAction) -> OSStatus {
        guard binding != rejected else { return OSStatus(eventHotKeyExistsErr) }
        registered[action] = binding
        return noErr
    }
    func unregister(_ action: ShortcutAction) { registered[action] = nil }
    func systemShortcuts() -> Set<ShortcutBinding> { system }
}
