import AppKit
import Carbon
import Combine

protocol HotKeyBackend: AnyObject {
    var onAction: ((UInt32) -> Void)? { get set }
    func register(_ binding: ShortcutBinding, for action: ShortcutAction) -> OSStatus
    func unregister(_ action: ShortcutAction)
    func systemShortcuts() -> Set<ShortcutBinding>
}

final class CarbonHotKeyBackend: HotKeyBackend {
    private var refs: [ShortcutAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    var onAction: ((UInt32) -> Void)?

    func register(_ binding: ShortcutBinding, for action: ShortcutAction) -> OSStatus {
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard result == noErr, id.signature == 0x544F4259 else { return OSStatus(eventNotHandledErr) }
                Unmanaged<CarbonHotKeyBackend>.fromOpaque(userData).takeUnretainedValue().onAction?(id.id)
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return status }
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(binding.keyCode, binding.modifiers,
                                        EventHotKeyID(signature: 0x544F4259, id: action.rawValue),
                                        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        if status == noErr, let ref {
            unregister(action)
            refs[action] = ref
        }
        return status
    }

    func unregister(_ action: ShortcutAction) {
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
    }

    func systemShortcuts() -> Set<ShortcutBinding> {
        var result: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&result) == noErr,
              let dictionaries = result?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return Set(dictionaries.compactMap { item in
            guard (item[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
                  let code = item[kHISymbolicHotKeyCode as String] as? NSNumber,
                  let flags = item[kHISymbolicHotKeyModifiers as String] as? NSNumber else { return nil }
            return ShortcutBinding(keyCode: code.uint32Value, modifiers: flags.uint32Value)
        })
    }

    deinit {
        refs.values.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}

/// Shared by settings, capture buttons, menus, and global keyboard events.
final class HotKeyManager: ObservableObject {
    @Published private(set) var bindings: [ShortcutAction: ShortcutBinding]
    @Published private(set) var issues: [ShortcutAction: String] = [:]
    @Published private(set) var isRecordingShortcut = false
    var onAction: ((UInt32) -> Void)?
    var onChange: (() -> Void)?
    private let preferences: ShortcutPreferences
    private let backend: HotKeyBackend

    init(defaults: UserDefaults = .standard, backend: HotKeyBackend = CarbonHotKeyBackend()) {
        preferences = ShortcutPreferences(defaults: defaults)
        bindings = preferences.load()
        self.backend = backend
        backend.onAction = { [weak self] id in
            guard let self, !self.isRecordingShortcut else { return }
            self.onAction?(id)
        }
    }

    func register() {
        guard !isRecordingShortcut else { return }
        unregisterAll()
        issues = [:]
        let system = backend.systemShortcuts()
        var used: [ShortcutBinding: ShortcutAction] = [:]
        for action in ShortcutAction.allCases {
            guard let binding = bindings[action] else { continue }
            if let message = binding.validationMessage(for: action) { issues[action] = message }
            else if let other = used[binding] { issues[action] = "Already assigned to \(other.title)." }
            else if action.scope == .global && system.contains(binding) { issues[action] = Self.systemConflict }
            else if action.scope == .global {
                let status = backend.register(binding, for: action)
                if status != noErr { issues[action] = Self.registrationMessage(status) }
            }
            used[binding] = action
        }
        onChange?()
    }

    func beginRecording() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        unregisterAll()
        onChange?()
    }

    func endRecording() {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        register()
    }

    /// The old binding and its saved value survive a rejected replacement.
    @discardableResult
    func setShortcut(_ binding: ShortcutBinding?, for action: ShortcutAction) -> String? {
        if let binding {
            if let message = binding.validationMessage(for: action) { return message }
            if let other = ShortcutAction.allCases.first(where: { $0 != action && bindings[$0] == binding }) {
                return "Already assigned to \(other.title). Choose another shortcut."
            }
            if action.scope == .global && backend.systemShortcuts().contains(binding) { return Self.systemConflict }
            if action.scope == .global && (bindings[action] != binding || isRecordingShortcut || issues[action] != nil) {
                let status = backend.register(binding, for: action)
                guard status == noErr else { return Self.registrationMessage(status) }
                if isRecordingShortcut { backend.unregister(action) }
            }
        } else { backend.unregister(action) }
        bindings[action] = binding
        issues[action] = nil
        preferences.save(binding, for: action)
        if !isRecordingShortcut && !issues.isEmpty { register() }
        else { onChange?() }
        return nil
    }

    func resetDefaults() {
        preferences.reset()
        bindings = preferences.load()
        register()
    }

    func label(for action: ShortcutAction) -> String { bindings[action]?.displayString ?? "No shortcut" }

    func activeBinding(for action: ShortcutAction) -> ShortcutBinding? {
        guard !isRecordingShortcut, issues[action] == nil else { return nil }
        return bindings[action]
    }

    func action(for event: NSEvent, scope: ShortcutScope) -> ShortcutAction? {
        guard !isRecordingShortcut else { return nil }
        let binding = ShortcutBinding(event: event)
        return ShortcutAction.allCases.first { $0.scope == scope && activeBinding(for: $0) == binding }
    }

    private func unregisterAll() { ShortcutAction.allCases.forEach { backend.unregister($0) } }
    private static let systemConflict = "Used by macOS. Choose another shortcut or change it in System Settings → Keyboard → Keyboard Shortcuts."
    private static func registrationMessage(_ status: OSStatus) -> String {
        status == OSStatus(eventHotKeyExistsErr)
            ? "This shortcut is in use by another app. Choose another combination."
            : "Could not activate this shortcut (macOS error \(status)). Choose another combination."
    }
}
