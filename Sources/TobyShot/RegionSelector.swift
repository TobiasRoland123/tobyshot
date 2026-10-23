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
    // Global AppKit screen coordinates, in points (origin at the bottom left).
    let rect: CGRect
    let window: SCWindow?
}

final class AreaSelection {
    private(set) var anchor: CGPoint?
    private(set) var rect: CGRect = .zero
    private var bounds: CGRect = .zero
    var didChange: (() -> Void)?

    func begin(at point: CGPoint, bounds: CGRect) {
        anchor = point
        self.bounds = bounds
        rect = .zero
        didChange?()
    }

    func drag(to point: CGPoint) {
        guard let anchor else { return }
        rect = CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                      width: abs(point.x - anchor.x), height: abs(point.y - anchor.y)).intersection(bounds)
        didChange?()
    }

    func end(at point: CGPoint) -> CGRect? {
        guard anchor != nil else { return nil }
        drag(to: point)
        anchor = nil
        return rect.width >= 2 && rect.height >= 2 ? rect : nil
    }
}

final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RegionSelector {
    private var panels: [NSPanel] = []
    private var continuation: CheckedContinuation<ScreenSelection?, Never>?
    private var previousApplication: NSRunningApplication?

    func select(snapshots: [ScreenSnapshot], windows: [SCWindow], instruction: String, spansDisplays: Bool = true) async -> ScreenSelection? {
        guard !snapshots.isEmpty else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let area = AreaSelection()
            area.didChange = { [weak self] in
                for panel in self?.panels ?? [] { panel.contentView?.needsDisplay = true }
            }
            let displays = snapshots.map { CaptureDisplayImage(frame: $0.screen.frame, image: $0.image) }
            let desktopBounds = displays.reduce(CGRect.null) { $0.union($1.frame) }
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
            previousApplication = frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier ? frontmostApplication : nil
            NSApp.activate(ignoringOtherApps: true)
            for snapshot in snapshots {
                let panel = CapturePanel(contentRect: snapshot.screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.level = .screenSaver
                panel.isOpaque = true
                panel.animationBehavior = .none
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.acceptsMouseMovedEvents = true
                let image = CaptureDisplayImage(frame: snapshot.screen.frame, image: snapshot.image)
                let view = SelectionView(snapshot: image, displayFrame: snapshot.display.frame, windows: windows, instruction: instruction,
                                         area: area, displays: spansDisplays ? displays : [image],
                                         selectionBounds: spansDisplays ? desktopBounds : snapshot.screen.frame) { [weak self] selection in
                    self?.finish(selection.map { ScreenSelection(snapshot: snapshot, rect: $0.rect, window: $0.window) })
                }
                panel.contentView = view
                panels.append(panel)
                panel.orderFrontRegardless()
                if snapshot.screen.frame.contains(NSEvent.mouseLocation) { panel.makeKey(); panel.makeFirstResponder(view) }
            }
            NSCursor.crosshair.push()
            NSCursor.setHiddenUntilMouseMoves(false)
        }
    }

    private func finish(_ selection: ScreenSelection?) {
        guard let continuation else { return }
        self.continuation = nil
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        NSCursor.pop()
        previousApplication?.activate(options: [])
        previousApplication = nil
        continuation.resume(returning: selection)
    }
}

final class SelectionView: NSView {
    let snapshot: CaptureDisplayImage
    let displayFrame: CGRect
    let candidates: [SCWindow]
    let instruction: String
    let completion: ((rect: CGRect, window: SCWindow?)?) -> Void
    let area: AreaSelection
    let displays: [CaptureDisplayImage]
    let selectionBounds: CGRect
    var selection: CGRect {
        if candidates.isEmpty { return CaptureGeometry.localRect(area.rect, in: snapshot.frame) }
        return selectedWindow.map { $0.frame.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY).intersection(bounds) } ?? .zero
    }
    var selectedWindow: SCWindow?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(snapshot: CaptureDisplayImage, displayFrame: CGRect, windows: [SCWindow], instruction: String, area: AreaSelection,
         displays: [CaptureDisplayImage], selectionBounds: CGRect, completion: @escaping ((rect: CGRect, window: SCWindow?)?) -> Void) {
        self.snapshot = snapshot; self.instruction = instruction; self.completion = completion
        self.displayFrame = displayFrame
        self.area = area; self.displays = displays; self.selectionBounds = selectionBounds
        let order = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        self.candidates = windows.sorted { (order.firstIndex(of: $0.windowID) ?? Int.max) < (order.firstIndex(of: $1.windowID) ?? Int.max) }
        super.init(frame: CGRect(origin: .zero, size: snapshot.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseMoved, .mouseEnteredAndExited], owner: self))
        // AppKit does not deliver cursor updates for .activeAlways tracking areas.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .cursorUpdate], owner: self))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func draw(_ dirtyRect: NSRect) {
        let image = NSImage(cgImage: snapshot.image, size: bounds.size)
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let selection = selection
        let visibleSelection = selection.intersection(bounds)
        if !visibleSelection.isEmpty {
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: selection); outline.lineWidth = 2; outline.stroke()
            for point in [selection.origin, CGPoint(x: selection.maxX, y: selection.minY), CGPoint(x: selection.minX, y: selection.maxY), CGPoint(x: selection.maxX, y: selection.maxY)] {
                NSColor.white.setFill(); NSBezierPath(ovalIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)).fill()
            }
            let size = candidates.isEmpty ? AreaCaptureComposition.pixelSize(for: area.rect, displays: displays)
                : CGSize(width: selection.width * snapshot.scale, height: selection.height * snapshot.scale)
            let label = "\(Int(size.width)) × \(Int(size.height))"
            drawPill(label, at: CGPoint(x: min(max(visibleSelection.midX - 55, 12), bounds.width - 122), y: max(12, visibleSelection.minY - 37)), width: 110)
        }
        drawPill("\(instruction)   ·   esc to cancel", at: CGPoint(x: (bounds.width - 390) / 2, y: bounds.height - 82), width: 390)
    }

    private func drawPill(_ text: String, at point: CGPoint, width: CGFloat) {
        NSColor(white: 0.1, alpha: 0.95).setFill()
        NSBezierPath(roundedRect: CGRect(origin: point, size: CGSize(width: width, height: 32)), xRadius: 10, yRadius: 10).fill()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (text as NSString).draw(in: CGRect(x: point.x, y: point.y + 8, width: width, height: 20), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
    }
    override func mouseEntered(with event: NSEvent) {
        if area.anchor == nil { window?.makeKey(); window?.makeFirstResponder(self) }
        NSCursor.crosshair.set()
    }
    override func mouseMoved(with event: NSEvent) {
        guard !candidates.isEmpty else { return }
        let p = convert(event.locationInWindow, from: nil)
        let global = CGPoint(x: p.x + displayFrame.minX, y: p.y + displayFrame.minY)
        selectedWindow = candidates.first { $0.frame.contains(global) }
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        if !candidates.isEmpty { mouseMoved(with: event); return }
        window?.makeKey(); window?.makeFirstResponder(self)
        area.begin(at: screenPoint(for: event), bounds: selectionBounds)
    }
    override func mouseDragged(with event: NSEvent) {
        guard candidates.isEmpty else { return }
        // AppKit keeps delivering this drag to the view where it began, even
        // after it leaves that window. Share its global rectangle with all views.
        area.drag(to: screenPoint(for: event))
    }
    override func mouseUp(with event: NSEvent) {
        if candidates.isEmpty {
            guard let rect = area.end(at: screenPoint(for: event)) else { return }
            completion((rect: rect, window: nil))
            return
        }
        guard selectedWindow != nil else { return }
        guard selection.width >= 2 && selection.height >= 2 else { return }
        let rect = CGRect(x: snapshot.frame.minX + selection.minX,
                          y: snapshot.frame.maxY - selection.maxY,
                          width: selection.width, height: selection.height)
        completion((rect: rect, window: selectedWindow))
    }
    private func screenPoint(for event: NSEvent) -> CGPoint {
        (event.window ?? window)?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { completion(nil) } }
}
