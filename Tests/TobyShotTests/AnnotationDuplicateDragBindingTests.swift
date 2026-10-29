import AppKit
import Carbon
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationDuplicateDragBindingTests {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let name = "TobyShot.AnnotationDuplicateDragBindingTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func missingAndInvalidPreferencesUseOptionFallback() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(AnnotationDuplicateDragBinding.load(from: defaults) == .option)
        defaults.set("unknown", forKey: AnnotationDuplicateDragBinding.preferenceKey)
        #expect(AnnotationDuplicateDragBinding.load(from: defaults) == .option)
    }

    @Test func preferencesPersistEachBindingIncludingDisabled() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        for binding in AnnotationDuplicateDragBinding.allCases {
            defaults.set(binding.rawValue, forKey: AnnotationDuplicateDragBinding.preferenceKey)
            let reloadedDefaults = UserDefaults(suiteName: name)!
            #expect(AnnotationDuplicateDragBinding.load(from: reloadedDefaults) == binding)
        }
        defaults.removeObject(forKey: AnnotationDuplicateDragBinding.preferenceKey)
        #expect(AnnotationDuplicateDragBinding.load(from: defaults) == .option)
    }

    @Test func modifierMatchesRequireExactSignificantFlags() {
        #expect(AnnotationDuplicateDragBinding.option.matches(.option))
        #expect(AnnotationDuplicateDragBinding.command.matches(.command))
        #expect(AnnotationDuplicateDragBinding.optionShift.matches([.option, .shift]))
        #expect(AnnotationDuplicateDragBinding.commandShift.matches([.command, .shift]))
        #expect(AnnotationDuplicateDragBinding.commandOption.matches([.command, .option]))

        #expect(!AnnotationDuplicateDragBinding.option.matches([.option, .shift]))
        #expect(!AnnotationDuplicateDragBinding.option.matches([.option, .control]))
        #expect(!AnnotationDuplicateDragBinding.commandOption.matches([.command, .option, .shift]))
        #expect(AnnotationDuplicateDragBinding.option.matches([.option, .capsLock]))
    }

    @Test func disabledBindingNeverMatches() {
        #expect(AnnotationDuplicateDragBinding.disabled.modifiers.isEmpty)
        #expect(!AnnotationDuplicateDragBinding.disabled.matches([]))
        #expect(!AnnotationDuplicateDragBinding.disabled.matches(.option))
    }

    @Test func bareSpaceIsReservedForEditorPanning() {
        let bareSpace = ShortcutBinding(keyCode: UInt32(kVK_Space), modifiers: 0)
        let commandSpace = ShortcutBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))

        #expect(bareSpace.validationMessage(for: .editorDuplicate)?.contains("panning") == true)
        #expect(commandSpace.validationMessage(for: .editorDuplicate) == nil)
        #expect(bareSpace.validationMessage(for: .captureArea)?.contains("Command") == true)
    }

    @Test func savedSpaceShortcutFallsBackWithoutDroppingOtherCustomizations() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ShortcutPreferences(defaults: defaults)
        preferences.save(ShortcutBinding(keyCode: UInt32(kVK_Space), modifiers: 0), for: .editorDuplicate)
        let custom = ShortcutBinding(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey))
        preferences.save(custom, for: .rectangleTool)
        let loaded = preferences.load()
        #expect(loaded[.editorDuplicate] == ShortcutAction.editorDuplicate.defaultBinding)
        #expect(loaded[.rectangleTool] == custom)
    }
}
