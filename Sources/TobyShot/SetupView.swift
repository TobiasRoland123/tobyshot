import SwiftUI
import AppKit

struct SetupView: View {
    @ObservedObject var setup: SetupAssistant
    @ObservedObject var app: AppCoordinator
    let openShortcutSettings: () -> Void
    let quitAndReopen: () -> Void
    let close: () -> Void

    private let accent = Color(red: 0.26, green: 0.62, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    shortcutStep
                    accessStep
                    exportStep
                    testStep
                }
                .padding(.horizontal, 28)
                .padding(.top, 30)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            footer
        }
        .frame(minWidth: 580, idealWidth: 600, minHeight: 640, idealHeight: 800)
        .background(Color(white: 0.10))
        .preferredColorScheme(.dark)
        .tint(accent)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in setup.refresh() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().scaledToFit()
                .frame(width: 52, height: 52).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up TobyShot").font(.system(size: 20, weight: .bold))
                Text("Get your Mac ready for TobyShot’s shortcuts and choose where your captures are saved.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Shortcuts

    private var shortcutStep: some View {
        let statuses = setup.shortcutStatuses
        let macOSConflicts = statuses.filter { !$0.isReady && $0.conflictsWithMacOS }
        let otherIssues = statuses.filter { !$0.isReady && !$0.conflictsWithMacOS }
        return step(1, "Turn off conflicting macOS shortcuts", ready: setup.shortcutsReady) {
            Text(setup.shortcutsReady
                 ? "Your TobyShot shortcuts are free to use."
                 : "macOS keeps these shortcuts for its own screenshot tools, so they can’t open TobyShot until you turn them off.")
                .detailStyle()
            VStack(spacing: 0) {
                ForEach(statuses) { shortcutRow($0) }
            }
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            if !macOSConflicts.isEmpty {
                directions(macOSConflicts)
                HStack(spacing: 8) {
                    Button("Open Keyboard Settings") { NSWorkspace.shared.open(SetupAssistant.keyboardSettingsURL) }
                    Button("Change TobyShot Shortcuts…", action: openShortcutSettings)
                }
                .controlSize(.small)
            } else if !otherIssues.isEmpty {
                Text("Choose different combinations in Settings → Shortcuts.").detailStyle()
                Button("Change TobyShot Shortcuts…", action: openShortcutSettings).controlSize(.small)
            }
        }
    }

    private func shortcutRow(_ status: SetupAssistant.ShortcutStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(status.binding.displayString)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 74, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.action.title).font(.system(size: 12))
                if let detail = shortcutDetail(status) {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            statusLabel(status.isReady ? "Ready" : "In use", ready: status.isReady)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private func shortcutDetail(_ status: SetupAssistant.ShortcutStatus) -> String? {
        guard let issue = status.issue else { return nil }
        if let name = status.macOSScreenshotName { return "Used by macOS for “\(name)”." }
        if status.conflictsWithMacOS { return "Used by another macOS shortcut." }
        return issue
    }

    private func directions(_ conflicts: [SetupAssistant.ShortcutStatus]) -> some View {
        let screenshots = conflicts.compactMap(\.macOSScreenshotName)
        return VStack(alignment: .leading, spacing: 5) {
            Text("In System Settings:").font(.system(size: 11, weight: .semibold))
            Text("1. Go to Keyboard and click Keyboard Shortcuts…")
            if screenshots.count == conflicts.count {
                Text("2. Choose Screenshots.")
                Text("3. Turn off \(screenshots.map { "“\($0)”" }.formatted(.list(type: .and))).")
            } else {
                Text("2. Find the shortcuts marked above, such as those in Screenshots or Mission Control, and turn them off.")
            }
            Text("Come back here and TobyShot will check again. You can also keep the macOS shortcuts and choose different TobyShot shortcuts.")
                .foregroundStyle(.secondary).padding(.top, 2)
        }
        .font(.system(size: 11))
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Screen access

    private var accessStep: some View {
        step(2, "Allow screen recording", ready: setup.accessReady) {
            switch setup.access {
            case .ready:
                Text("TobyShot can capture your screen.").detailStyle()
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking screen access…").detailStyle()
                }
            case .unchecked:
                Text("TobyShot needs Screen & System Audio Recording access. macOS will ask you to allow it.").detailStyle()
                Button("Allow Access") { Task { await setup.checkAccess() } }
                    .controlSize(.small).disabled(app.isBusy || app.isRecording)
            case .denied:
                deniedDirections
            case .failed(let message):
                Text("TobyShot couldn’t check screen access: \(message)").detailStyle()
                Button("Try Again") { Task { await setup.checkAccess() } }
                    .controlSize(.small).disabled(app.isBusy || app.isRecording)
            }
        }
    }

    private var deniedDirections: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text("1. Open System Settings → Privacy & Security → Screen & System Audio Recording.")
                Text("2. Turn on TobyShot.")
                Text("3. Quit and reopen TobyShot. macOS applies the change only after the app restarts.")
                Text("Already on? The entry may belong to an older copy. Remove it with −, then add this copy with +.")
                    .foregroundStyle(.secondary).padding(.top, 2)
            }
            .font(.system(size: 11))
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Open Privacy Settings") { NSWorkspace.shared.open(SetupAssistant.privacySettingsURL) }
                Button("Show App in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                Button("Quit & Reopen", action: quitAndReopen)
            }
            .controlSize(.small)
        }
    }

    // MARK: Save location

    private var exportStep: some View {
        step(3, "Choose where to save captures", ready: setup.exportLocationChosen) {
            Text(setup.exportLocationChosen
                 ? "Screenshots and recordings are saved here. You can change this later in Settings → General."
                 : "TobyShot saves your screenshots and recordings to this folder. Keep it or choose another one.")
                .detailStyle()
            HStack(spacing: 8) {
                Image(systemName: "folder.fill").foregroundStyle(accent).accessibilityHidden(true)
                Text((setup.exportDirectory.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            if let error = setup.exportError {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if !setup.exportLocationChosen {
                    Button("Use This Folder") { setup.chooseExportLocation(setup.exportDirectory) }
                }
                Button(setup.exportLocationChosen ? "Change Folder…" : "Choose Another Folder…") {
                    if let url = ExportLocation.choose(startingAt: setup.exportDirectory) { setup.chooseExportLocation(url) }
                }
            }
            .controlSize(.small)
        }
    }

    // MARK: Test capture

    private var testStep: some View {
        step(4, "Take a test screenshot", ready: setup.testScreenshotTaken, optional: true) {
            if setup.testScreenshotTaken {
                Text("Test screenshot captured. TobyShot is ready to use.").detailStyle()
            } else if setup.canFinish {
                Text(testPrompt).detailStyle()
                Button("Take Test Screenshot") { app.capture(.area) }
                    .controlSize(.small).disabled(app.isBusy || app.isRecording)
            } else {
                Text("Available once the steps above are ready.").detailStyle()
            }
        }
    }

    private var testPrompt: String {
        guard let binding = setup.shortcuts.activeBinding(for: .captureArea) else { return "Drag to select any area of your screen." }
        return "Press \(binding.displayString), or click the button below, then drag to select any area of your screen."
    }

    // MARK: Layout

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Check Again") { Task { await setup.recheck() } }
                .disabled(setup.access == .checking || app.isBusy || app.isRecording)
            if !setup.canFinish {
                Text("Setup finishes when steps 1 to 3 are ready.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !setup.isComplete { Button("Skip for Now", action: close) }
            Button(setup.isComplete ? "Done" : "Finish Setup") { if setup.finish() { close() } }
                .keyboardShortcut(.defaultAction)
                .disabled(!setup.canFinish)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    private func step<Content: View>(_ number: Int, _ title: String, ready: Bool, optional: Bool = false,
                                     @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                Circle().fill(ready ? Color.green.opacity(0.2) : Color.white.opacity(0.08))
                if ready { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.green) }
                else { Text("\(number)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 8)
                    if !optional || ready { statusLabel(ready ? "Ready" : "Needs attention", ready: ready) }
                    else { Text("Optional").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                content()
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number): \(title), \(ready ? "ready" : optional ? "optional" : "needs attention")")
    }

    private func statusLabel(_ text: String, ready: Bool) -> some View {
        Label(text, systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ready ? Color.green : Color.orange)
            .labelStyle(.titleAndIcon)
    }
}

private extension Text {
    func detailStyle() -> some View {
        font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
