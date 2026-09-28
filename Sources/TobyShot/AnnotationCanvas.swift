import AppKit
import SwiftUI

struct AnnotationCanvasRepresentable: NSViewRepresentable {
    @ObservedObject var model: AnnotationEditorModel
    func makeNSView(context: Context) -> AnnotationScrollView {
        let scroll = AnnotationScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let canvas = AnnotationCanvasView()
        canvas.model = model
        scroll.documentView = canvas
        return scroll
    }
    func updateNSView(_ view: AnnotationScrollView, context: Context) {
        if let canvas = view.documentView as? AnnotationCanvasView {
            canvas.model = model
            canvas.window?.invalidateCursorRects(for: canvas)
        }
        view.needsLayout = true
    }
}

final class AnnotationScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let canvas = documentView as? AnnotationCanvasView, let model = canvas.model else { return }
        let pad = model.background == .none ? 0 : model.padding.rounded() * 2
        let size = CGSize(width: model.pixelSize.width + pad, height: model.pixelSize.height + pad)
        let available = contentView.bounds.size
        let documentSize = model.zoom == 0 ? available : CGSize(width: max(available.width, size.width * model.zoom + 48), height: max(available.height, size.height * model.zoom + 48))
        if canvas.frame.size != documentSize { canvas.setFrameSize(documentSize) }
        canvas.needsDisplay = true
    }
}

final class AnnotationCanvasView: NSView {
    weak var model: AnnotationEditorModel? { didSet { needsDisplay = true } }
    private var displayedImageRect: CGRect = .zero
    private var dragStart: CGPoint?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let model else { return }
        NSColor(calibratedWhite: 0.095, alpha: 1).setFill(); bounds.fill()
        let image = model.renderedImage()
        let size = image.size
        let scale = model.zoom == 0 ? max(0.01, min((bounds.width - 48) / size.width, (bounds.height - 48) / size.height)) : model.zoom
        let renderedRect = CGRect(x: (bounds.width - size.width * scale) / 2, y: (bounds.height - size.height * scale) / 2, width: size.width * scale, height: size.height * scale)
        let pad = model.background == .none ? 0 : model.padding.rounded() * scale
        displayedImageRect = CGRect(x: renderedRect.minX + pad, y: renderedRect.minY + pad, width: model.pixelSize.width * scale, height: model.pixelSize.height * scale)
        // The preview and exported file share a renderer, including redaction and pixelation.
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill(); renderedRect.fill()
        image.draw(in: renderedRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        if let selected = model.annotations.first(where: { $0.id == model.selectedID }) {
            let selection = viewRect(model.annotationBounds(selected), scale: scale).insetBy(dx: -4, dy: -4)
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(roundedRect: selection, xRadius: 4, yRadius: 4)
            outline.lineWidth = 1; outline.setLineDash([4, 3], count: 2, phase: 0); outline.stroke()
        }
        if let crop = model.cropRect {
            let rect = viewRect(crop, scale: scale)
            NSColor.systemBlue.withAlphaComponent(0.18).setFill(); rect.fill()
            NSColor.systemBlue.setStroke(); NSBezierPath(rect: rect).stroke()
        }
    }
    private func viewRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: displayedImageRect.minX + rect.minX * scale, y: displayedImageRect.minY + rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }
    private func imagePoint(_ point: CGPoint, requireInside: Bool) -> CGPoint? {
        guard let model, displayedImageRect.width > 0, displayedImageRect.height > 0,
              !requireInside || displayedImageRect.contains(point) else { return nil }
        return CGPoint(x: min(model.pixelSize.width, max(0, (point.x - displayedImageRect.minX) / displayedImageRect.width * model.pixelSize.width)), y: min(model.pixelSize.height, max(0, (point.y - displayedImageRect.minY) / displayedImageRect.height * model.pixelSize.height)))
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: model?.tool == .select ? .arrow : .crosshair) }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let model, let point = imagePoint(convert(event.locationInWindow, from: nil), requireInside: true) else { return }
        dragStart = point; model.begin(at: point); needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil, let point = imagePoint(convert(event.locationInWindow, from: nil), requireInside: false) else { return }
        model?.continueDrag(to: point); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil; model?.endDrag(); needsDisplay = true
    }
    // Keyboard commands are dispatched by the window using the shared shortcut settings.
}
