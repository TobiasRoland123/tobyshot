import AppKit

enum AnnotationDuplicateDragBinding: String, CaseIterable, Identifiable {
    case disabled
    case option
    case command
    case optionShift
    case commandShift
    case commandOption

    static let preferenceKey = "annotationDuplicateDragBinding"

    static func load(from defaults: UserDefaults) -> AnnotationDuplicateDragBinding {
        guard let rawValue = defaults.string(forKey: preferenceKey),
              let binding = AnnotationDuplicateDragBinding(rawValue: rawValue) else { return .option }
        return binding
    }

    var id: String { rawValue }

    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .disabled: return []
        case .option: return .option
        case .command: return .command
        case .optionShift: return [.option, .shift]
        case .commandShift: return [.command, .shift]
        case .commandOption: return [.command, .option]
        }
    }

    var title: String {
        switch self {
        case .disabled: return "Disabled"
        case .option: return "Option (⌥)"
        case .command: return "Command (⌘)"
        case .optionShift: return "Option + Shift (⌥⇧)"
        case .commandShift: return "Command + Shift (⌘⇧)"
        case .commandOption: return "Command + Option (⌘⌥)"
        }
    }

    func matches(_ flags: NSEvent.ModifierFlags) -> Bool {
        guard self != .disabled else { return false }
        let significantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return flags.intersection(significantFlags) == modifiers
    }
}
