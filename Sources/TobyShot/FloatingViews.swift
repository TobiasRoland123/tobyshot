import SwiftUI
import AppKit

@MainActor
final class QuickAccessWindow: NSWindowController {
    private(set) var isClosed = false
    private var timer: Timer?
    private var hovered = false
    private var remaining: TimeInterval
    private var lastTick = Date()

    init(item: CaptureItem, app: AppCoordinator) {
        let width = CGFloat(Preferences.double("overlaySize"))
        let panel = floatingPanel(size: CGSize(width: width, height: width * 0.64 + 82))
        remaining = Preferences.double("overlayInterval")
        super.init(window: panel)
        panel.contentView = NSHostingView(rootView: QuickAccessView(item: item, app: app, hover: { [weak self] value in self?.hovered = value }, close: { [weak self] in self?.close() }).preferredColorScheme(.dark))
        let screen = (Preferences.bool("overlayActiveScreen") ? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) : NSScreen.screens.first) ?? NSScreen.main
        if let screen {
            let left = Preferences.string("overlayPosition") == "Left"
            panel.setFrameOrigin(CGPoint(x: left ? screen.visibleFrame.minX + 22 : screen.visibleFrame.maxX - width - 22, y: screen.visibleFrame.minY + 22))
        }
        panel.orderFrontRegardless()
        if Preferences.bool("overlayAutoClose") {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let now = Date()
                    if !self.hovered && self.window?.isVisible == true { self.remaining -= now.timeIntervalSince(self.lastTick) }
                    self.lastTick = now
                    if self.remaining <= 0 { self.close() }
                }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func close() { isClosed = true; timer?.invalidate(); timer = nil; super.close() }
    deinit { timer?.invalidate() }
}

private struct QuickAccessView: View {
    let item: CaptureItem
    @ObservedObject var app: AppCoordinator
    let hover: (Bool) -> Void
    let close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: item.kind == .image ? "checkmark.circle.fill" : "video.fill").foregroundStyle(.green)
                Text(item.kind == .image ? "Captured" : "Recording saved").font(.system(size: 11, weight: .medium))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }.buttonStyle(.plain)
            }.padding(.horizontal, 12).frame(height: 32)
            if let image = app.store.thumbnail(for: item) {
                DraggableCapture(image: image, file: app.store.url(for: item), onOpen: { app.annotate(item); close() }, onDragEnd: {
                    if Preferences.bool("overlayCloseAfterDrag") && !NSEvent.modifierFlags.contains(.option) { close() }
                }).frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 8)
            } else {
                Button { app.annotate(item) } label: { Image(systemName: "play.circle.fill").font(.system(size: 42)).frame(maxWidth: .infinity, maxHeight: .infinity) }.buttonStyle(.plain)
            }
            HStack(spacing: 17) {
                action("square.and.arrow.down", "Save") { app.save(item, ask: NSEvent.modifierFlags.contains(.option)) }
                action("doc.on.doc", "Copy") { app.copy(item); close() }
                if item.kind == .image {
                    action("pencil.tip.crop.circle", "Annotate") { app.annotate(item); close() }
                    action("pin", "Pin to screen") { if let image = app.store.image(for: item) { app.pin(image) }; close() }
                    action("text.viewfinder", "Recognize text") { app.recognizeText(item); close() }
                }
                Spacer(minLength: 0)
                action("folder", "Show in Finder") { app.reveal(item) }
            }.padding(.horizontal, 14).frame(height: 43)
        }.background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.16)))
            .padding(1).onHover(perform: hover)
    }
    private func action(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 14)).frame(height: 23) }.buttonStyle(.plain).help(help)
    }
}

private struct DraggableCapture: NSViewRepresentable {
    var image: NSImage
    var file: URL
    var onOpen: () -> Void
    var onDragEnd: () -> Void
    func makeNSView(context: Context) -> DragImageView { DragImageView() }
    func updateNSView(_ view: DragImageView, context: Context) {
        view.image = image; view.file = file; view.onOpen = onOpen; view.onDragEnd = onDragEnd
        view.imageScaling = .scaleProportionallyUpOrDown
    }
}

private final class DragImageView: NSImageView, NSDraggingSource {
    var file: URL?
    var onOpen: (() -> Void)?
    var onDragEnd: (() -> Void)?
    private var isDragging = false
    override func mouseDown(with event: NSEvent) { isDragging = false }
    override func mouseUp(with event: NSEvent) { if !isDragging { onOpen?() } }
    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let file else { return }
        isDragging = true
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { if !operation.isEmpty { onDragEnd?() } }
}

struct PinnedImageView: View {
    let image: NSImage
    let close: () -> Void
    @State private var hovered = false
    var body: some View {
        Image(nsImage: image).resizable().scaledToFit()
            .background(Color.black.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: Preferences.bool("pinnedRounded") ? 10 : 0))
            .overlay(RoundedRectangle(cornerRadius: Preferences.bool("pinnedRounded") ? 10 : 0).stroke(Color.white.opacity(Preferences.bool("pinnedBorder") ? 0.45 : 0), lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if hovered { Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).padding(7).background(.black.opacity(0.75), in: Circle()) }.buttonStyle(.plain).padding(7) }
            }.onHover { hovered = $0 }
            .contextMenu { Button("Close pinned image", action: close) }
    }
}

struct RecordingControls: View {
    @ObservedObject var app: AppCoordinator
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(.red).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.isStopping ? "Finishing…" : "Recording").font(.system(size: 10)).foregroundStyle(.secondary)
                Text(app.recordingTime).font(.system(size: 15, weight: .medium, design: .monospaced))
            }
            Spacer()
            Button(action: app.stopRecording) { Label("Stop", systemImage: "stop.fill").font(.system(size: 12, weight: .medium)) }.buttonStyle(.borderedProminent).tint(.red).disabled(app.isStopping)
        }.padding(15).background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.15)))
    }
}

private struct CountdownContent: View {
    let value: Int
    let cancel: () -> Void
    var body: some View {
        HStack(spacing: 20) {
            Text("\(value)").font(.system(size: 46, weight: .medium, design: .rounded)).monospacedDigit()
            VStack(alignment: .leading, spacing: 10) {
                Text("Get ready…").font(.system(size: 14, weight: .medium))
                Button("Cancel", action: cancel).buttonStyle(.bordered).controlSize(.small)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
struct CountdownView: View {
    @ObservedObject var app: AppCoordinator
    var body: some View { CountdownContent(value: app.countdown ?? 3, cancel: app.cancelCountdown) }
}
