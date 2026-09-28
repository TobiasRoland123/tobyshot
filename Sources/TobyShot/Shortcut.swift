import AppKit
import Carbon

struct ShortcutBinding: Codable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32
    static let modifierMask = UInt32(cmdKey | controlKey | optionKey | shiftKey)

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.modifierMask
    }

    init(event: NSEvent) {
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    var appKitModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    var displayString: String {
        var parts: [String] = []
        for (flag, symbol) in [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")] {
            if modifiers & UInt32(flag) != 0 { parts.append(symbol) }
        }
        parts.append(Self.specialKeys[keyCode]?.label ?? keyboardCharacter.uppercased())
        return parts.joined(separator: " ")
    }

    var menuKey: String { Self.specialKeys[keyCode]?.equivalent ?? keyboardCharacter.lowercased() }

    var validationMessage: String? { validationMessage(for: .captureArea) }

    func validationMessage(for action: ShortcutAction) -> String? {
        if action.scope == .global, modifiers & UInt32(cmdKey | controlKey | optionKey) == 0 {
            return "Include Command (⌘), Option (⌥), or Control (⌃) in a global shortcut."
        }
        guard modifiers & ~Self.modifierMask == 0, !menuKey.isEmpty else { return "Choose a letter, number, function key, or navigation key." }
        if [kVK_Escape, kVK_Delete, kVK_ForwardDelete].contains(Int(keyCode)), modifiers == 0 {
            return "Escape and Delete are reserved for canceling and removing objects."
        }
        let reserved = [kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_H, kVK_ANSI_M, kVK_ANSI_Z,
                        kVK_ANSI_X, kVK_ANSI_V, kVK_ANSI_A, kVK_ANSI_Comma, kVK_Return]
        if modifiers == UInt32(cmdKey), reserved.contains(Int(keyCode)) {
            return "This shortcut is used by a standard macOS menu command. Choose another combination."
        }
        if modifiers == UInt32(cmdKey), keyCode == UInt32(kVK_ANSI_C), action != .editorCopyObject {
            return "Command C is reserved for copying the selected object or text."
        }
        if modifiers == UInt32(cmdKey | shiftKey), keyCode == UInt32(kVK_ANSI_Z) {
            return "This shortcut is reserved for Redo."
        }
        return nil
    }

    /// Symbol defaults follow the current keyboard layout, including Danish keyboards.
    static func forCharacter(_ character: String, fallback: Int) -> ShortcutBinding {
        for key in UInt32(0)...UInt32(50) {
            let binding = ShortcutBinding(keyCode: key, modifiers: 0)
            if binding.menuKey == character { return binding }
        }
        if character == "+" { return ShortcutBinding(keyCode: UInt32(kVK_ANSI_Equal), modifiers: UInt32(shiftKey)) }
        return ShortcutBinding(keyCode: UInt32(fallback), modifiers: 0)
    }

    private var keyboardCharacter: String {
        guard keyCode <= UInt32(UInt16.max),
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKey: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                    &deadKey, characters.count, &length, &characters)
        guard status == noErr, length > 0 else { return "" }
        let result = String(utf16CodeUnits: characters, count: length)
        return result.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } ? result : ""
    }

    private static let specialKeys: [UInt32: (label: String, equivalent: String)] = {
        var keys: [UInt32: (String, String)] = [
            UInt32(kVK_Space): ("Space", " "), UInt32(kVK_Return): ("↩", "\r"),
            UInt32(kVK_Tab): ("⇥", "\t"), UInt32(kVK_Delete): ("⌫", "\u{8}"),
            UInt32(kVK_ForwardDelete): ("⌦", "\u{F728}"), UInt32(kVK_Escape): ("⎋", "\u{1B}"),
            UInt32(kVK_LeftArrow): ("←", "\u{F702}"), UInt32(kVK_RightArrow): ("→", "\u{F703}"),
            UInt32(kVK_UpArrow): ("↑", "\u{F700}"), UInt32(kVK_DownArrow): ("↓", "\u{F701}"),
            UInt32(kVK_Home): ("Home", "\u{F729}"), UInt32(kVK_End): ("End", "\u{F72B}"),
            UInt32(kVK_PageUp): ("Page Up", "\u{F72C}"), UInt32(kVK_PageDown): ("Page Down", "\u{F72D}")
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (index, code) in functionKeys.enumerated() {
            keys[UInt32(code)] = ("F\(index + 1)", String(UnicodeScalar(0xF704 + index)!))
        }
        return keys
    }()
}

struct ShortcutPreferences {
    let defaults: UserDefaults

    func load() -> [ShortcutAction: ShortcutBinding] {
        migrateDefaults()
        var bindings: [ShortcutAction: ShortcutBinding] = [:]
        for action in ShortcutAction.allCases {
            guard let data = defaults.data(forKey: action.preferenceKey) else {
                bindings[action] = action.defaultBinding
                continue
            }
            do {
                let saved = try JSONDecoder().decode(ShortcutBinding?.self, from: data)
                bindings[action] = saved?.validationMessage(for: action) == nil ? saved : action.defaultBinding
            } catch { bindings[action] = action.defaultBinding }
        }
        return bindings
    }

    func save(_ binding: ShortcutBinding?, for action: ShortcutAction) {
        if let data = try? JSONEncoder().encode(binding) { defaults.set(data, forKey: action.preferenceKey) }
    }

    private func migrateDefaults() {
        guard defaults.integer(forKey: "shortcutDefaultsVersion") < 2 else { return }
        let previous: [(ShortcutAction, Int)] = [(.captureArea, kVK_ANSI_2), (.captureFullScreen, kVK_ANSI_3),
            (.captureWindow, kVK_ANSI_4), (.recordScreen, kVK_ANSI_5), (.openImage, kVK_ANSI_O)]
        for (action, code) in previous {
            guard let data = defaults.data(forKey: action.preferenceKey),
                  let saved = try? JSONDecoder().decode(ShortcutBinding.self, from: data),
                  saved == ShortcutBinding(keyCode: UInt32(code), modifiers: UInt32(cmdKey | shiftKey)) else { continue }
            defaults.removeObject(forKey: action.preferenceKey)
        }
        defaults.set(2, forKey: "shortcutDefaultsVersion")
    }

    func reset() { ShortcutAction.allCases.forEach { defaults.removeObject(forKey: $0.preferenceKey) } }
}
