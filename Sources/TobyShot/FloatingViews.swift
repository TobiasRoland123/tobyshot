import SwiftUI
import AppKit
import Combine

/// The Quick Access panel. It stacks recent captures in one panel anchored to the bottom corner of the screen.
@MainActor
final class QuickAccessWindow: NSWindowController, ObservableObject {
    @Published private(set) var stack = QuickAccessStack()
    @Published private(set) var width = CGFloat(Preferences.double("overlaySize"))
    @Published private(set) var isLeft = Preferences.string("overlayPosition") == "Left"
    /// How long a closing preview animates out before the panel shrinks to fit the rest.
    var outroDuration: TimeInterval = 0.3
    private(set) weak var app: AppCoordinator?
    private var timer: Timer?
    private var pendingFrame: Task<Void, Never>?
    private var lastTick = Date()
    private var screen: NSScreen?
    private var userHidden = false
    private var hiddenForCapture = false
    private var historyObserver: AnyCancellable?
    private var screenObserver: NSObjectProtocol?

    var items: [CaptureItem] { stack.items }
    var isVisible: Bool { window?.isVisible == true }

    init(app: AppCoordinator) {
        let initialWidth = CGFloat(Preferences.double("overlaySize"))
        let panel = floatingPanel(size: CGSize(width: initialWidth, height: QuickAccessStackLayout.height(count: 1, width: initialWidth)))
        self.app = app
        super.init(window: panel)
        let host = NSHostingView(rootView: QuickAccessStackView(controller: self).preferredColorScheme(.dark))
        // The stack controls the panel size, so the hosting view must not resize it.
        host.sizingOptions = []
        panel.contentView = host
        historyObserver = app.store.$historyLoadState.sink { [weak self] state in
            guard case let .loaded(items) = state else { return }
            MainActor.assumeIsolated { self?.retain(Set(items.map(\.id))) }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let screen = self.screen, !NSScreen.screens.contains(screen) { self.screen = nil }
                self.layout()
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        timer?.invalidate()
        pendingFrame?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    /// Adds a capture to the top of the stack on the preferred screen.
    func show(_ item: CaptureItem) {
        screen = preferredScreen()
        stack.push(item, duration: Preferences.double("overlayInterval"))
        userHidden = false
        lastTick = Date()
        layout()
    }

    func dismiss(_ id: UUID) {
        withOutro { stack.dismiss(id) }
        layout(animated: true)
    }

    func closeAll() {
        withOutro { stack.removeAll() }
        layout(animated: true)
    }

    func toggleVisibility() {
        guard let window, !stack.isEmpty else { return }
        if window.isVisible { userHidden = true; window.orderOut(nil) }
        else { userHidden = false; window.orderFrontRegardless() }
    }

    /// Hides the stack while a capture is prepared. Its countdown pauses until it is restored.
    func hideForCapture() {
        hiddenForCapture = true
        window?.orderOut(nil)
    }

    func restoreAfterCapture() {
        guard hiddenForCapture else { return }
        hiddenForCapture = false
        if !stack.isEmpty && !userHidden { window?.orderFrontRegardless() }
    }

    func beginDrag(_ id: UUID) { stack.beginDrag(id) }

    func endDrag(_ id: UUID, dropped: Bool) {
        let dismiss = Preferences.bool("overlayCloseAfterDrag") && !NSEvent.modifierFlags.contains(.option)
        if withOutro({ stack.endDrag(id, dropped: dropped, dismissOnDrop: dismiss) }) { layout(animated: true) }
    }

    /// Counts down the visible stack. Hovering over the stack or dragging from it pauses expiry.
    func advance(by elapsed: TimeInterval, hovered: Bool) {
        guard Preferences.bool("overlayAutoClose"), isVisible else { return }
        if !withOutro({ stack.advance(by: elapsed, paused: hovered) }).isEmpty { layout(animated: true) }
    }

    private func retain(_ ids: Set<UUID>) {
        let count = stack.entries.count
        withOutro { stack.retain(ids) }
        if stack.entries.count != count { layout(animated: true) }
    }

    /// Removes previews with an animation: they slide toward the screen edge and fade while the others close the gap.
    private func withOutro<Result>(_ change: () -> Result) -> Result {
        outroDuration > 0 ? withAnimation(.easeInOut(duration: outroDuration), change) : change()
    }

    private func preferredScreen() -> NSScreen? {
        (Preferences.bool("overlayActiveScreen") ? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) : NSScreen.screens.first) ?? NSScreen.main
    }

    /// Sizes and places the panel for the current stack. When previews were removed with an animation,
    /// the panel keeps its size until they finish animating out.
    private func layout(animated: Bool = false) {
        guard let window else { return }
        pendingFrame?.cancel(); pendingFrame = nil
        width = CGFloat(Preferences.double("overlaySize"))
        isLeft = Preferences.string("overlayPosition") == "Left"
        if let visible = (screen ?? preferredScreen())?.visibleFrame {
            stack.trim(to: QuickAccessStackLayout.capacity(width: width, availableHeight: visible.height - QuickAccessStackLayout.margin * 2))
        }
        let shrinking = stack.isEmpty || QuickAccessStackLayout.height(count: stack.entries.count, width: width) < window.frame.height
        if animated && shrinking && outroDuration > 0 && window.isVisible {
            let delay = outroDuration
            pendingFrame = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.applyFrame()
            }
        } else {
            applyFrame()
        }
        if stack.isEmpty {
            timer?.invalidate(); timer = nil
        } else if timer == nil {
            lastTick = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    private func applyFrame() {
        pendingFrame = nil
        guard let window else { return }
        guard !stack.isEmpty else { window.orderOut(nil); return }
        if let visible = (screen ?? preferredScreen())?.visibleFrame {
            let margin = QuickAccessStackLayout.margin
            let origin = CGPoint(x: isLeft ? visible.minX + margin : visible.maxX - width - margin, y: visible.minY + margin)
            window.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: QuickAccessStackLayout.height(count: stack.entries.count, width: width))), display: true)
        }
        if !userHidden && !hiddenForCapture { window.orderFrontRegardless() }
    }

    private func tick() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        lastTick = now
        advance(by: elapsed, hovered: window?.frame.contains(NSEvent.mouseLocation) == true)
    }
}

private struct QuickAccessStackView: View {
    @ObservedObject var controller: QuickAccessWindow
    var body: some View {
        let width = controller.width
        VStack(spacing: QuickAccessStackLayout.spacing) {
            if let app = controller.app {
                ForEach(Array(controller.stack.entries.enumerated()), id: \.element.id) { index, entry in
                    QuickAccessView(item: entry.item, compact: index > 0, app: app, controller: controller)
                        .frame(height: index == 0 ? QuickAccessStackLayout.cardHeight(width: width) : QuickAccessStackLayout.compactHeight(width: width))
                        .transition(.asymmetric(insertion: .identity,
                                                removal: .move(edge: controller.isLeft ? .leading : .trailing).combined(with: .opacity)))
                }
            }
        }.padding(1).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

private struct QuickAccessView: View {
    let item: CaptureItem
    /// Older captures show only their thumbnail. Their actions appear on hover.
    let compact: Bool
    let app: AppCoordinator
    let controller: QuickAccessWindow
    @State private var thumbnail: NSImage?
    @State private var hovered = false
    var body: some View {
        Group {
            if compact { compactCard } else { fullCard }
        }.background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.16)))
            .onHover { hovered = $0 }
            .task(id: item.id) {
                thumbnail = nil
                let loaded = await app.store.thumbnail(for: item)
                if !Task.isCancelled { thumbnail = loaded }
            }
    }
    private var fullCard: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: item.kind == .image ? "checkmark.circle.fill" : "video.fill").foregroundStyle(.green)
                Text(item.kind == .image ? "Captured" : "Recording saved").font(.system(size: 11, weight: .medium))
                Spacer()
                closeButton
            }.padding(.horizontal, 12).frame(height: 32)
            preview.padding(.horizontal, 8)
            actions
        }
    }
    private var compactCard: some View {
        preview.padding(6)
            .overlay {
                if hovered {
                    VStack(spacing: 0) {
                        HStack { Spacer(); closeButton.padding(6).background(.ultraThickMaterial, in: Circle()) }.padding(6)
                        Spacer(minLength: 0)
                        actions.background(.ultraThickMaterial)
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 14))
    }
    private var closeButton: some View {
        Button(action: close) { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }.buttonStyle(.plain).help("Close")
    }
    @ViewBuilder private var preview: some View {
        if let image = thumbnail {
            DraggableCapture(image: image, file: app.store.url(for: item), onOpen: { app.annotate(item); close() },
                             onDragStart: { controller.beginDrag(item.id) },
                             onDragEnd: { dropped in controller.endDrag(item.id, dropped: dropped) })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Button { app.annotate(item) } label: { Image(systemName: item.kind == .image ? "photo" : "play.circle.fill").font(.system(size: compact ? 30 : 42)).frame(maxWidth: .infinity, maxHeight: .infinity) }.buttonStyle(.plain)
        }
    }
    private var actions: some View {
        HStack(spacing: 13) {
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
    }
    private func close() { controller.dismiss(item.id) }
    private func action(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 14)).frame(height: 23) }.buttonStyle(.plain).help(help)
    }
}

private struct DraggableCapture: NSViewRepresentable {
    var image: NSImage
    var file: URL
    var onOpen: () -> Void
    var onDragStart: () -> Void
    var onDragEnd: (_ dropped: Bool) -> Void
    func makeNSView(context: Context) -> DragImageView { DragImageView() }
    func updateNSView(_ view: DragImageView, context: Context) {
        view.image = image; view.file = file; view.onOpen = onOpen
        view.onDragStart = onDragStart; view.onDragEnd = onDragEnd
        view.imageScaling = .scaleProportionallyUpOrDown
    }
}

private final class DragImageView: NSImageView, NSDraggingSource {
    var file: URL?
    var onOpen: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: ((Bool) -> Void)?
    private var isPressed = false
    private var isDragging = false
    // The preview supplies the size; the thumbnail must not enlarge its window.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
    override func mouseDown(with event: NSEvent) { isPressed = true; isDragging = false }
    override func mouseUp(with event: NSEvent) {
        if isPressed && !isDragging { onOpen?() }
        isPressed = false
    }
    override func mouseDragged(with event: NSEvent) {
        // Only the thumbnail that was pressed starts a drag. A thumbnail laid out under the pointer after another drop must not.
        guard isPressed, !isDragging, let file else { return }
        isDragging = true
        // Drag the original capture file, not the thumbnail.
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        onDragStart?()
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isPressed = false
        onDragEnd?(!operation.isEmpty)
    }
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
