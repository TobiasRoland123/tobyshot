import AppKit
import SwiftUI

@MainActor
final class CaptureLauncher: NSWindowController {
    init(app: AppCoordinator) {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 570, height: 154),
                            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "All-in-One — TobyShot"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        super.init(window: panel)
        panel.contentView = NSHostingView(rootView: CaptureLauncherView(app: app, shortcuts: app.shortcuts) { [weak self] in self?.close() }.preferredColorScheme(.dark))
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - 285, y: screen.visibleFrame.minY + 80))
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private struct CaptureLauncherView: View {
    @ObservedObject var app: AppCoordinator
    @ObservedObject var shortcuts: HotKeyManager
    let close: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                captureButton("Area", symbol: "viewfinder", shortcut: .captureArea) { app.capture(.area) }
                captureButton("Fullscreen", symbol: "display", shortcut: .captureFullScreen) { app.capture(.fullscreen) }
                captureButton("Window", symbol: "macwindow", shortcut: .captureWindow) { app.capture(.window) }
                captureButton(app.isRecording ? "Stop Recording" : "Record Screen", symbol: app.isRecording ? "stop.circle" : "record.circle", shortcut: .recordScreen) { app.toggleRecording() }
            }
            HStack {
                Text("Choose what to capture").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
            }
        }.padding(18)
    }
    private func captureButton(_ title: String, symbol: String, shortcut: ShortcutAction, action: @escaping () -> Void) -> some View {
        Button {
            close()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 23)).foregroundStyle(Color.accentColor)
                Text(title).font(.system(size: 12, weight: .medium))
                Text(shortcuts.bindings[shortcut]?.displayString ?? " ").font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 78)
        }.buttonStyle(.bordered)
    }
}
