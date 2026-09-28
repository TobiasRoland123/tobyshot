import AppKit
import ScreenCaptureKit

struct ScreenSnapshot {
    let screen: NSScreen
    let display: SCDisplay
    let image: CGImage
    let scale: CGFloat
}
struct ScreenSelection {
    let snapshot: ScreenSnapshot
    let rect: CGRect
    let window: SCWindow?
}

final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RegionSelector {
    private var panels: [NSPanel] = []
    private var continuation: CheckedContinuation<ScreenSelection?, Never>?

    func select(snapshots: [ScreenSnapshot], windows: [SCWindow], instruction: String) async -> ScreenSelection? {
        guard !snapshots.isEmpty else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            for snapshot in snapshots {
                let panel = CapturePanel(contentRect: snapshot.screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.level = .screenSaver
                panel.isOpaque = true
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.acceptsMouseMovedEvents = true
                let view = SelectionView(snapshot: snapshot, windows: windows, instruction: instruction) { [weak self] selection in self?.finish(selection) }
                panel.contentView = view
                panels.append(panel)
                panel.orderFrontRegardless()
                if snapshot.screen.frame.contains(NSEvent.mouseLocation) { panel.makeKey(); panel.makeFirstResponder(view) }
            }
            NSCursor.crosshair.push()
        }
    }

    private func finish(_ selection: ScreenSelection?) {
        NSCursor.pop()
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        continuation?.resume(returning: selection)
        continuation = nil
    }
}

private final class SelectionView: NSView {
    let snapshot: ScreenSnapshot
    let candidates: [SCWindow]
    let instruction: String
    let completion: (ScreenSelection?) -> Void
    var anchor: CGPoint?
    var selection: CGRect = .zero
    var selectedWindow: SCWindow?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(snapshot: ScreenSnapshot, windows: [SCWindow], instruction: String, completion: @escaping (ScreenSelection?) -> Void) {
        self.snapshot = snapshot; self.instruction = instruction; self.completion = completion
        let order = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        self.candidates = windows.sorted { (order.firstIndex(of: $0.windowID) ?? Int.max) < (order.firstIndex(of: $1.windowID) ?? Int.max) }
        super.init(frame: CGRect(origin: .zero, size: snapshot.screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseMoved, .mouseEnteredAndExited], owner: self))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let image = NSImage(cgImage: snapshot.image, size: bounds.size)
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let shade = NSBezierPath(rect: bounds)
        if !selection.isEmpty { shade.appendRect(selection); shade.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(0.35).setFill(); shade.fill()
        if !selection.isEmpty {
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: selection); outline.lineWidth = 2; outline.stroke()
            for point in [selection.origin, CGPoint(x: selection.maxX, y: selection.minY), CGPoint(x: selection.minX, y: selection.maxY), CGPoint(x: selection.maxX, y: selection.maxY)] {
                NSColor.white.setFill(); NSBezierPath(ovalIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)).fill()
            }
            let label = "\(Int(selection.width * snapshot.scale)) × \(Int(selection.height * snapshot.scale))"
            drawPill(label, at: CGPoint(x: min(max(selection.midX - 55, 12), bounds.width - 122), y: max(12, selection.minY - 37)), width: 110)
        }
        drawPill("\(instruction)   ·   esc to cancel", at: CGPoint(x: (bounds.width - 390) / 2, y: bounds.height - 82), width: 390)
    }

    private func drawPill(_ text: String, at point: CGPoint, width: CGFloat) {
        NSColor(white: 0.1, alpha: 0.95).setFill()
        NSBezierPath(roundedRect: CGRect(origin: point, size: CGSize(width: width, height: 32)), xRadius: 10, yRadius: 10).fill()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (text as NSString).draw(in: CGRect(x: point.x, y: point.y + 8, width: width, height: 20), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
    }
    override func mouseEntered(with event: NSEvent) { window?.makeKey(); window?.makeFirstResponder(self) }
    override func mouseMoved(with event: NSEvent) {
        guard !candidates.isEmpty else { return }
        let p = convert(event.locationInWindow, from: nil)
        let global = CGPoint(x: p.x + snapshot.display.frame.minX, y: p.y + snapshot.display.frame.minY)
        selectedWindow = candidates.first { $0.frame.contains(global) }
        selection = selectedWindow.map { $0.frame.offsetBy(dx: -snapshot.display.frame.minX, dy: -snapshot.display.frame.minY).intersection(bounds) } ?? .zero
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        if !candidates.isEmpty { mouseMoved(with: event); return }
        anchor = convert(event.locationInWindow, from: nil); selection = .zero
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor, candidates.isEmpty else { return }
        let p = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(anchor.x, p.x), y: min(anchor.y, p.y), width: abs(p.x - anchor.x), height: abs(p.y - anchor.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if !candidates.isEmpty, selectedWindow == nil { return }
        guard selection.width >= 2 && selection.height >= 2 else { return }
        completion(ScreenSelection(snapshot: snapshot, rect: selection, window: selectedWindow))
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { completion(nil) } }
}
