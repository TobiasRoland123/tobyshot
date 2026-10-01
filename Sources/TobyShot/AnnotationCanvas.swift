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
        let size = canvas.layoutCanvasBounds.size
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
    private var lastDrawingPoint: CGPoint?
    private var resizingText = false
    private var editingArrow = false
    private var editingShape = false
    private var textEditor: AnnotationTextView?
    private var textEditorID: UUID?
    private var settledCanvasBounds: CGRect?
    private let previewRenderer = AnnotationPreviewRenderer()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var layoutCanvasBounds: CGRect {
        guard let model else { return .zero }
        // Keep the coordinate mapping steady under the pointer and insertion point.
        // Fit/scroll to the expanded canvas once drawing, moving, or typing finishes.
        if settledCanvasBounds == nil || (dragStart == nil && model.editingTextID == nil) {
            settledCanvasBounds = model.canvasBounds
        }
        return settledCanvasBounds ?? .zero
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let model else { return }
        NSColor(calibratedWhite: 0.095, alpha: 1).setFill(); bounds.fill()
        updateImageGeometry()
        let expandedRect = viewRect(model.canvasBounds, scale: imageScale)
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill(); expandedRect.fill()
        if let context = NSGraphicsContext.current?.cgContext {
            previewRenderer.draw(image: model.image, annotations: model.annotations.filter { $0.id != model.editingTextID },
                                 canvasBounds: model.canvasBounds, background: model.background, cornerRadius: model.cornerRadius,
                                 imageOrigin: displayedImageRect.origin, scale: imageScale,
                                 backingScale: window?.backingScaleFactor ?? 1, in: context)
        }
        for selected in model.annotations where model.selectedIDs.contains(selected.id) {
            let selection = selectionRect(for: selected)
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(roundedRect: selection, xRadius: 4, yRadius: 4)
            outline.lineWidth = 1; outline.setLineDash([4, 3], count: 2, phase: 0); outline.stroke()
        }
        for rect in textResizeHandles().map(\.rect) + shapeHandles().map(\.rect) {
            NSColor.white.setFill()
            NSColor.controlAccentColor.setStroke()
            let square = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
            square.fill(); square.stroke()
        }
        for handle in arrowHandles() {
            NSColor.white.setFill()
            NSColor.controlAccentColor.setStroke()
            let circle = NSBezierPath(ovalIn: handle.rect)
            circle.lineWidth = 2
            circle.fill(); circle.stroke()
        }
        if let selection = model.selectionRect, !selection.isEmpty {
            let rect = viewRect(selection, scale: imageScale)
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill(); rect.fill()
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 1
            outline.stroke()
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
        let canvasBounds = layoutCanvasBounds
        let size = canvasBounds.size
        imageScale = model.zoom == 0 ? max(0.01, min((bounds.width - 48) / size.width, (bounds.height - 48) / size.height)) : model.zoom
        renderedImageRect = CGRect(x: (bounds.width - size.width * imageScale) / 2, y: (bounds.height - size.height * imageScale) / 2, width: size.width * imageScale, height: size.height * imageScale)
        displayedImageRect = CGRect(x: renderedImageRect.minX - canvasBounds.minX * imageScale, y: renderedImageRect.minY - canvasBounds.minY * imageScale, width: model.pixelSize.width * imageScale, height: model.pixelSize.height * imageScale)
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
        if AnnotationShapeHandle.handles(for: annotation).contains(.corner(.topLeft)) {
            return viewRect(AnnotationShapeEdit.bounds(for: annotation), scale: imageScale)
        }
        let rect: CGRect
        if annotation.kind == .text {
            rect = annotation.text.isEmpty ? textEditor?.frame ?? .zero : viewRect(model.textSelectionBounds(annotation), scale: imageScale)
        } else {
            rect = viewRect(model.annotationBounds(annotation), scale: imageScale)
        }
        return rect.insetBy(dx: -4, dy: -4)
    }

    private func textResizeHandles() -> [(corner: AnnotationResizeCorner, rect: CGRect)] {
        guard let model, model.selectionRect == nil, model.tool == .select || model.tool == .text,
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

    private func arrowHandles() -> [(handle: AnnotationArrowHandle, rect: CGRect)] {
        guard let model, model.selectionRect == nil, model.tool == .select || model.tool == .arrow,
              let selected = model.annotations.first(where: { $0.id == model.selectedID }),
              selected.kind == .arrow else { return [] }
        return AnnotationArrowHandle.allCases.map { handle in
            let point = viewRect(CGRect(origin: handle.point(in: selected), size: .zero), scale: imageScale).origin
            return (handle, CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
        }
    }

    private func arrowHandle(at point: CGPoint) -> AnnotationArrowHandle? {
        // Pick the nearest handle when short arrows have overlapping hit areas.
        // Reverse drawing order gives the visible end handle priority on a tie.
        arrowHandles().reversed().filter { $0.rect.insetBy(dx: -4, dy: -4).contains(point) }
            .min { hypot($0.rect.midX - point.x, $0.rect.midY - point.y) < hypot($1.rect.midX - point.x, $1.rect.midY - point.y) }?.handle
    }

    private func shapeHandles() -> [(handle: AnnotationShapeHandle, rect: CGRect)] {
        guard let model, model.selectionRect == nil, model.tool == .select,
              let selected = model.annotations.first(where: { $0.id == model.selectedID }) else { return [] }
        return AnnotationShapeHandle.handles(for: selected).map { handle in
            let point = viewRect(CGRect(origin: handle.point(in: selected), size: .zero), scale: imageScale).origin
            return (handle, CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
        }
    }

    private func shapeHandle(at point: CGPoint) -> AnnotationShapeHandle? {
        shapeHandles().reversed().filter { $0.rect.insetBy(dx: -4, dy: -4).contains(point) }
            .min { hypot($0.rect.midX - point.x, $0.rect.midY - point.y) < hypot($1.rect.midX - point.x, $1.rect.midY - point.y) }?.handle
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
        for handle in arrowHandles() { addCursorRect(handle.rect.insetBy(dx: -4, dy: -4), cursor: .openHand) }
        for handle in shapeHandles() { addCursorRect(handle.rect.insetBy(dx: -4, dy: -4), cursor: .crosshair) }
    }
    override func mouseDown(with event: NSEvent) {
        updateImageGeometry()
        lastDrawingPoint = nil
        let location = convert(event.locationInWindow, from: nil)
        let extendingSelection = model?.tool == .select && event.modifierFlags.contains(.shift)
        let corner = extendingSelection ? nil : resizeCorner(at: location)
        window?.makeFirstResponder(self)
        model?.finishTextEditing()
        if !extendingSelection, let handle = shapeHandle(at: location),
           let point = imagePoint(location, requireInside: false, clampToImage: false),
           model?.beginShapeEdit(handle: handle, at: point) == true {
            editingShape = true
            dragStart = point
            needsDisplay = true
            return
        }
        if !extendingSelection, let handle = arrowHandle(at: location),
           let point = imagePoint(location, requireInside: false, clampToImage: false) {
            if event.clickCount == 2, handle == .bend {
                model?.straightenSelectedArrow()
            } else if model?.beginArrowEdit(handle: handle, at: point) == true {
                editingArrow = true
                dragStart = point
            }
            needsDisplay = true
            return
        }
        if let corner, let point = imagePoint(location, requireInside: false, clampToImage: false),
           model?.beginTextResize(corner: corner, at: point) == true {
            resizingText = true
            dragStart = point
            synchronizeTextEditor()
            return
        }
        let constrainToImage = model?.tool == .crop || model?.tool == .pixelate
        guard let model, let point = imagePoint(location, requireInside: constrainToImage, clampToImage: constrainToImage) else {
            synchronizeTextEditor()
            return
        }
        if event.clickCount == 2, model.tool == .select, !extendingSelection,
           let annotation = model.annotation(at: point), annotation.kind == .text {
            model.beginTextEditing(annotation.id)
        } else {
            model.begin(at: point, extendingSelection: extendingSelection)
            dragStart = model.editingTextID == nil ? point : nil
            lastDrawingPoint = model.tool.supportsDrawingConstraint ? point : nil
        }
        synchronizeTextEditor()
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let constrainToImage = !resizingText && (model?.tool == .crop || model?.tool == .pixelate)
        guard dragStart != nil, let point = imagePoint(convert(event.locationInWindow, from: nil), requireInside: false, clampToImage: constrainToImage) else { return }
        if lastDrawingPoint != nil { lastDrawingPoint = point }
        model?.continueDrag(to: point, constrained: event.modifierFlags.contains(.shift)); needsDisplay = true
    }
    override func flagsChanged(with event: NSEvent) {
        guard dragStart != nil, let point = lastDrawingPoint, model?.tool.supportsDrawingConstraint == true else { return }
        model?.continueDrag(to: point, constrained: event.modifierFlags.contains(.shift))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        if model?.selectionRect != nil || editingShape,
           let point = imagePoint(convert(event.locationInWindow, from: nil), requireInside: false, clampToImage: false) {
            model?.continueDrag(to: point)
        } else if let point = lastDrawingPoint {
            model?.continueDrag(to: point, constrained: event.modifierFlags.contains(.shift))
        }
        lastDrawingPoint = nil
        dragStart = nil; resizingText = false; editingArrow = false; editingShape = false; model?.endDrag(); needsDisplay = true
        enclosingScrollView?.needsLayout = true
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
