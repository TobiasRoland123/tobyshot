import SwiftUI
import AppKit
import Carbon

struct ShortcutSettingsView: View {
    @ObservedObject var shortcuts: HotKeyManager
    @State private var recordingAction: ShortcutAction?

    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Click a shortcut to change it. Capture shortcuts work everywhere; annotation shortcuts work in the editor.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Search shortcuts", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search shortcuts")

            ForEach(ShortcutGroup.allCases) { group in
                let actions = group.actions.filter {
                    search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || group.rawValue.localizedCaseInsensitiveContains(search)
                }
                if !actions.isEmpty { shortcutGroup(group.rawValue, actions: actions) }
            }

            if ShortcutAction.allCases.allSatisfy({ !search.isEmpty && !$0.title.localizedCaseInsensitiveContains(search) && !$0.group.rawValue.localizedCaseInsensitiveContains(search) }) {
                Text("No matching shortcuts").foregroundStyle(.secondary)
            }

            if search.isEmpty {
                Text("Shortcuts for cloud sharing, scrolling capture, video editing, and additional annotation tools will appear when those features are available.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Restore Defaults", action: shortcuts.resetDefaults)
                    .controlSize(.small)
                    .accessibilityHint("Restore all keyboard shortcuts to their default key combinations.")
            }
        }
        .sheet(item: $recordingAction) { action in
            ShortcutRecorderSheet(action: action, shortcuts: shortcuts) {
                recordingAction = nil
            }
        }
    }

    private func shortcutGroup(_ title: String, actions: [ShortcutAction]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 3)

            VStack(spacing: 0) {
                ForEach(actions) { action in
                    shortcutRow(action)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(action.title)
                    .font(.system(size: 13))
                Spacer(minLength: 8)

                Button {
                    recordingAction = action
                } label: {
                    Text(shortcuts.bindings[action]?.displayString ?? "Record Shortcut")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(shortcuts.bindings[action] == nil ? Color.secondary : Color.primary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change shortcut for \(action.title)")
                .accessibilityValue(shortcuts.bindings[action]?.displayString ?? "Not set")
                .accessibilityHint("Opens the shortcut recorder.")

                Button {
                    _ = shortcuts.setShortcut(nil, for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(shortcuts.bindings[action] == nil ? Color.secondary.opacity(0.45) : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(shortcuts.bindings[action] == nil)
                .accessibilityLabel("Clear shortcut for \(action.title)")
            }

            if let issue = shortcuts.issues[action] {
                Text(issue)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Shortcut issue for \(action.title): \(issue)")
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.065)).frame(height: 1)
        }
    }
}

private struct ShortcutRecorderSheet: View {
    let action: ShortcutAction
    @ObservedObject var shortcuts: HotKeyManager
    let onFinish: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "keyboard")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.tint)

            Text("Record Shortcut")
                .font(.system(size: 16, weight: .semibold))

            Text("Press the keys for \(action.title)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(action.scope == .global
                 ? "Use Command, Option, or Control. Press Escape to cancel, or Delete without modifiers to clear."
                 : "Press a key or key combination. This shortcut works only in the annotation editor. Escape cancels; Delete clears.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Shortcut error: \(errorMessage)")
            }

            Button("Cancel", action: onFinish)
                .keyboardShortcut(.cancelAction)
                .controlSize(.small)
                .padding(.top, 2)
        }
        .padding(24)
        .frame(width: 340)
        .background(Color(white: 0.10))
        .preferredColorScheme(.dark)
        .background {
            ShortcutKeyCaptureView { event in
                handle(event)
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            shortcuts.beginRecording()
        }
        .onDisappear {
            shortcuts.endRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            onFinish()
        }
    }

    private func handle(_ event: NSEvent) {
        guard !event.isARepeat else { return }

        if event.keyCode == UInt16(kVK_Escape) {
            onFinish()
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
        if modifiers.isEmpty && (event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)) {
            if let error = shortcuts.setShortcut(nil, for: action) {
                errorMessage = error
            } else {
                onFinish()
            }
            return
        }

        if let error = shortcuts.setShortcut(ShortcutBinding(event: event), for: action) {
            errorMessage = error
        } else {
            onFinish()
        }
    }
}

private struct ShortcutKeyCaptureView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onKeyDown: (NSEvent) -> Void
        private var monitor: Any?

        init(onKeyDown: @escaping (NSEvent) -> Void) {
            self.onKeyDown = onKeyDown
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                self.onKeyDown(event)
                return nil
            }
        }

        func stop() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        deinit {
            stop()
        }
    }
}
