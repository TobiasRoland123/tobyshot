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
            canvas.synchronizeTextEditor()
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
        canvas.needsLayout = true
        canvas.needsDisplay = true
    }
}

final class AnnotationCanvasView: NSView, NSTextViewDelegate {
    weak var model: AnnotationEditorModel? { didSet { needsDisplay = true; needsLayout = true } }
    private var displayedImageRect: CGRect = .zero
    private var renderedImageRect: CGRect = .zero
    private var imageScale: CGFloat = 1
    private var dragStart: CGPoint?
    private var resizingText = false
    private var textEditor: AnnotationTextView?
    private var textEditorID: UUID?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let model else { return }
        NSColor(calibratedWhite: 0.095, alpha: 1).setFill(); bounds.fill()
        updateImageGeometry()
        let image = model.renderedImage(excluding: model.editingTextID)
        // The preview and exported file share a renderer, including redaction and pixelation.
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill(); renderedImageRect.fill()
        image.draw(in: renderedImageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        if let selected = model.annotations.first(where: { $0.id == model.selectedID }) {
            let selection = selectionRect(for: selected)
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(roundedRect: selection, xRadius: 4, yRadius: 4)
            outline.lineWidth = 1; outline.setLineDash([4, 3], count: 2, phase: 0); outline.stroke()
            for handle in textResizeHandles() {
                NSColor.white.setFill()
                NSColor.controlAccentColor.setStroke()
                let square = NSBezierPath(roundedRect: handle.rect, xRadius: 1, yRadius: 1)
                square.fill(); square.stroke()
            }
        }
        if let crop = model.cropRect {
            let rect = viewRect(crop, scale: imageScale)
            NSColor.systemBlue.withAlphaComponent(0.18).setFill(); rect.fill()
            NSColor.systemBlue.setStroke(); NSBezierPath(rect: rect).stroke()
        }
    }

    override func layout() {
        super.layout()
        synchronizeTextEditor()
    }

    private func updateImageGeometry() {
        guard let model else { return }
        let padding = model.background == .none ? 0 : model.padding.rounded()
        let size = CGSize(width: model.pixelSize.width + padding * 2, height: model.pixelSize.height + padding * 2)
        imageScale = model.zoom == 0 ? max(0.01, min((bounds.width - 48) / size.width, (bounds.height - 48) / size.height)) : model.zoom
        renderedImageRect = CGRect(x: (bounds.width - size.width * imageScale) / 2, y: (bounds.height - size.height * imageScale) / 2, width: size.width * imageScale, height: size.height * imageScale)
        displayedImageRect = CGRect(x: renderedImageRect.minX + padding * imageScale, y: renderedImageRect.minY + padding * imageScale, width: model.pixelSize.width * imageScale, height: model.pixelSize.height * imageScale)
    }

    func synchronizeTextEditor() {
        updateImageGeometry()
        guard let model, let id = model.editingTextID,
              let annotation = model.annotations.first(where: { $0.id == id }) else {
            removeTextEditor()
            return
        }
        let isNewEditor = textEditorID != id
        if isNewEditor {
            removeTextEditor()
            let editor = AnnotationTextView(annotation: annotation)
            editor.delegate = self
            textEditor = editor
            textEditorID = id
            addSubview(editor)
        }
        guard let editor = textEditor else { return }
        let attributes = AnnotationTextLayout.attributes(for: annotation)
        if editor.font != attributes[.font] as? NSFont || editor.textColor != annotation.color {
            editor.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: editor.string.utf16.count))
            editor.typingAttributes = attributes
        }
        let size = editor.annotationLayout.editingSize
        editor.frame = viewRect(CGRect(origin: annotation.start, size: size), scale: imageScale)
        editor.bounds = CGRect(origin: .zero, size: size)
        if isNewEditor {
            window?.makeFirstResponder(editor)
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        }
        needsDisplay = true
    }

    private func selectionRect(for annotation: EditorAnnotation) -> CGRect {
        guard let model else { return .zero }
        let rect: CGRect
        if annotation.kind == .text {
            rect = annotation.text.isEmpty ? textEditor?.frame ?? .zero : viewRect(model.textSelectionBounds(annotation), scale: imageScale)
        } else {
            rect = viewRect(model.annotationBounds(annotation), scale: imageScale)
        }
        return rect.insetBy(dx: -4, dy: -4)
    }

    private func textResizeHandles() -> [(corner: AnnotationResizeCorner, rect: CGRect)] {
        guard let model, model.tool == .select || model.tool == .text,
              let selected = model.annotations.first(where: { $0.id == model.selectedID }),
              selected.kind == .text, !selected.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let selection = selectionRect(for: selected)
        return AnnotationResizeCorner.allCases.map { corner in
            let point = corner.point(in: selection)
            return (corner, CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
        }
    }

    private func resizeCorner(at point: CGPoint) -> AnnotationResizeCorner? {
        textResizeHandles().first { $0.rect.insetBy(dx: -4, dy: -4).contains(point) }?.corner
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        updateImageGeometry()
        let local = convert(point, from: superview)
        // Handles stay draggable where their hit area overlaps the native text editor.
        if bounds.contains(local), resizeCorner(at: local) != nil { return self }
        return super.hitTest(point)
    }

    private func removeTextEditor() {
        guard let editor = textEditor else { return }
        editor.delegate = nil
        if window?.firstResponder === editor { window?.makeFirstResponder(self) }
        editor.removeFromSuperview()
        textEditor = nil
        textEditorID = nil
    }

    func textDidChange(_ notification: Notification) {
        guard let editor = notification.object as? AnnotationTextView, editor === textEditor else { return }
        model?.updateText(editor.string)
        synchronizeTextEditor()
    }

    func textDidEndEditing(_ notification: Notification) {
        guard notification.object as? AnnotationTextView === textEditor else { return }
        model?.finishTextEditing()
        synchronizeTextEditor()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) ||
            (commandSelector == #selector(NSResponder.insertNewline(_:)) && !NSEvent.modifierFlags.contains(.shift)) {
            model?.finishTextEditing()
            synchronizeTextEditor()
            return true
        }
        return false
    }
    private func viewRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: displayedImageRect.minX + rect.minX * scale, y: displayedImageRect.minY + rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }
    private func imagePoint(_ point: CGPoint, requireInside: Bool, clampToImage: Bool = true) -> CGPoint? {
        guard let model, displayedImageRect.width > 0, displayedImageRect.height > 0,
              !requireInside || displayedImageRect.contains(point) else { return nil }
        let imagePoint = CGPoint(x: (point.x - displayedImageRect.minX) / imageScale, y: (point.y - displayedImageRect.minY) / imageScale)
        guard clampToImage else { return imagePoint }
        return CGPoint(x: min(model.pixelSize.width, max(0, imagePoint.x)), y: min(model.pixelSize.height, max(0, imagePoint.y)))
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: model?.tool == .text ? .iBeam : model?.tool == .select ? .arrow : .crosshair)
        for handle in textResizeHandles() { addCursorRect(handle.rect.insetBy(dx: -4, dy: -4), cursor: .crosshair) }
    }
    override func mouseDown(with event: NSEvent) {
        updateImageGeometry()
        let location = convert(event.locationInWindow, from: nil)
        let corner = resizeCorner(at: location)
        window?.makeFirstResponder(self)
        model?.finishTextEditing()
        if let corner, let point = imagePoint(location, requireInside: false, clampToImage: false),
           model?.beginTextResize(corner: corner, at: point) == true {
            resizingText = true
            dragStart = point
            synchronizeTextEditor()
            return
        }
        guard let model, let point = imagePoint(location, requireInside: true) else {
            synchronizeTextEditor()
            return
        }
        if event.clickCount == 2, model.tool == .select,
           let annotation = model.annotation(at: point), annotation.kind == .text {
            model.beginTextEditing(annotation.id)
        } else {
            model.begin(at: point)
            dragStart = model.editingTextID == nil ? point : nil
        }
        synchronizeTextEditor()
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil, let point = imagePoint(convert(event.locationInWindow, from: nil), requireInside: false, clampToImage: !resizingText) else { return }
        model?.continueDrag(to: point); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil; resizingText = false; model?.endDrag(); needsDisplay = true
    }
    // Keyboard commands are dispatched by the window using the shared shortcut settings.
}

private final class AnnotationTextView: NSTextView {
    let annotationLayout: AnnotationTextLayout
    private let textUndoManager = UndoManager()
    override var undoManager: UndoManager? { textUndoManager }

    init(annotation: EditorAnnotation) {
        annotationLayout = AnnotationTextLayout(annotation)
        super.init(frame: .zero, textContainer: annotationLayout.container)
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isHorizontallyResizable = false
        isVerticallyResizable = false
        textContainerInset = .zero
        typingAttributes = AnnotationTextLayout.attributes(for: annotation)
        insertionPointColor = annotation.color
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        setAccessibilityLabel("Annotation text")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
