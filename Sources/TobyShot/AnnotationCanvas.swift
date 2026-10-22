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
            canvas.refreshPointerFeedback()
        }
        view.needsLayout = true
    }
}

final class AnnotationScrollView: NSScrollView {
    private var previousScale: CGFloat?
    private var previousCanvasBounds: CGRect?
    private var zoomAnchor: (image: CGPoint, viewport: CGPoint)?

    override func layout() {
        super.layout()
        guard let canvas = documentView as? AnnotationCanvasView, let model = canvas.model else { return }
        let canvasBounds = canvas.layoutCanvasBounds
        let size = canvasBounds.size
        let available = contentView.bounds.size
        let scale = model.zoom == 0 ? AnnotationCanvasView.fitScale(for: size, in: available) : model.zoom
        // Controls zoom around the visible center; a pinch supplies the pointer instead.
        let center = CGPoint(x: available.width / 2, y: available.height / 2)
        var anchor = zoomAnchor
        if anchor == nil, let previousScale, let previousCanvasBounds, previousScale != scale {
            anchor = (CGPoint(
                x: previousCanvasBounds.minX + (contentView.bounds.minX + center.x - (canvas.bounds.width - previousCanvasBounds.width * previousScale) / 2) / previousScale,
                y: previousCanvasBounds.minY + (contentView.bounds.minY + center.y - (canvas.bounds.height - previousCanvasBounds.height * previousScale) / 2) / previousScale), center)
        }
        zoomAnchor = nil
        let documentSize = model.zoom == 0 ? available : CGSize(width: max(available.width, size.width * model.zoom + 48), height: max(available.height, size.height * model.zoom + 48))
        if canvas.frame.size != documentSize { canvas.setFrameSize(documentSize) }
        canvas.synchronizeTextEditor()
        if model.zoom == 0 {
            contentView.scroll(to: .zero)
        } else if let anchor {
            let point = canvas.viewPoint(anchor.image)
            let proposed = CGRect(x: point.x - anchor.viewport.x, y: point.y - anchor.viewport.y, width: available.width, height: available.height)
            contentView.scroll(to: contentView.constrainBoundsRect(proposed).origin)
        }
        reflectScrolledClipView(contentView)
        previousScale = scale
        previousCanvasBounds = canvasBounds
        // Layout can run inside a SwiftUI update. Publish the fitted percentage afterwards.
        let fitScale = AnnotationCanvasView.fitScale(for: size, in: available)
        DispatchQueue.main.async { [weak self, weak model] in
            guard let self, let model,
                  (self.documentView as? AnnotationCanvasView)?.model === model else { return }
            model.updateFitZoom(fitScale)
        }
        canvas.refreshPointerFeedback()
        canvas.needsLayout = true
        canvas.needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        guard let canvas = documentView as? AnnotationCanvasView, let model = canvas.model,
              !canvas.isDraggingAnnotation, event.magnification.isFinite, event.magnification != 0 else { return }
        // Resolve any pending control or window-size change before mapping the pointer.
        layoutSubtreeIfNeeded()
        let scale = canvas.currentScale
        // A large image can fit below the manual minimum. Pinching out must not enlarge it.
        guard event.magnification > 0 || scale > AnnotationEditorModel.minimumZoom else { return }
        let location = canvas.convert(event.locationInWindow, from: nil)
        guard let point = canvas.imagePoint(location, requireInside: false, clampToImage: false) else { return }
        zoomAnchor = (point, CGPoint(x: location.x - contentView.bounds.minX, y: location.y - contentView.bounds.minY))
        model.setZoom(scale * max(0.01, 1 + event.magnification))
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
}

/// An editing handle that the pointer can drag without first switching to Select.
struct AnnotationEditHandle: Equatable {
    enum Kind: Equatable {
        case arrow(AnnotationArrowHandle)
        case shape(AnnotationShapeHandle)
        case text(AnnotationResizeCorner)
    }
    let annotationID: UUID
    let kind: Kind
    let rect: CGRect
}

/// The operation a gesture starting under the pointer performs. Hover feedback and
/// mouse-down use the same target so the cursor matches what a drag does.
enum AnnotationPointerTarget: Equatable {
    case handle(AnnotationEditHandle)
    case move(UUID)
    case editText(UUID)
    case canvas
}

final class AnnotationCanvasView: NSView, NSTextViewDelegate {
    weak var model: AnnotationEditorModel? { didSet { needsDisplay = true; needsLayout = true } }
    private var displayedImageRect: CGRect = .zero
    private var renderedImageRect: CGRect = .zero
    private var imageScale: CGFloat = 1
    private var dragStart: CGPoint?
    private var lastDrawingPoint: CGPoint?
    private var clampsDragToImage = false
    private var resizingText = false
    private var editingArrow = false
    private var editingShape = false
    private(set) var hoveredAnnotationID: UUID?
    private var pointerTrackingArea: NSTrackingArea?
    private var textEditor: AnnotationTextView?
    private var textEditorID: UUID?
    private var settledCanvasBounds: CGRect?
    private let previewRenderer = AnnotationPreviewRenderer()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var isDraggingAnnotation: Bool { dragStart != nil }
    var currentScale: CGFloat { updateImageGeometry(); return imageScale }

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
        for handle in editHandles() {
            NSColor.white.setFill()
            NSColor.controlAccentColor.setStroke()
            if case .arrow = handle.kind {
                let circle = NSBezierPath(ovalIn: handle.rect)
                circle.lineWidth = 2
                circle.fill(); circle.stroke()
            } else {
                let square = NSBezierPath(roundedRect: handle.rect, xRadius: 1, yRadius: 1)
                square.fill(); square.stroke()
            }
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
        imageScale = model.zoom == 0 ? Self.fitScale(for: size, in: bounds.size) : model.zoom
        renderedImageRect = CGRect(x: (bounds.width - size.width * imageScale) / 2, y: (bounds.height - size.height * imageScale) / 2, width: size.width * imageScale, height: size.height * imageScale)
        displayedImageRect = CGRect(x: renderedImageRect.minX - canvasBounds.minX * imageScale, y: renderedImageRect.minY - canvasBounds.minY * imageScale, width: model.pixelSize.width * imageScale, height: model.pixelSize.height * imageScale)
    }

    static func fitScale(for size: CGSize, in viewport: CGSize) -> CGFloat {
        min(AnnotationEditorModel.maximumZoom, max(1, viewport.width - 48) / max(1, size.width), max(1, viewport.height - 48) / max(1, size.height))
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

    /// Handles belong to the selected annotation and to the annotation under the pointer.
    /// Members of a multiple selection have none, so dragging any of them moves the group.
    private func editHandles() -> [AnnotationEditHandle] {
        guard let model, model.selectionRect == nil, model.tool != .crop else { return [] }
        let hovered = hoveredAnnotationID.flatMap { model.selectedIDs.count > 1 && model.selectedIDs.contains($0) ? nil : $0 }
        let ids = [model.selectedID, hovered].compactMap { $0 }
        return model.annotations.filter { ids.contains($0.id) }.flatMap { annotation -> [AnnotationEditHandle] in
            func handle(_ kind: AnnotationEditHandle.Kind, at point: CGPoint, radius: CGFloat = 4) -> AnnotationEditHandle {
                AnnotationEditHandle(annotationID: annotation.id, kind: kind,
                                     rect: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            }
            switch annotation.kind {
            case .arrow:
                return AnnotationArrowHandle.allCases.map { handle(.arrow($0), at: viewPoint($0.point(in: annotation)), radius: 5) }
            case .text:
                guard !annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
                let selection = selectionRect(for: annotation)
                return AnnotationResizeCorner.allCases.map { handle(.text($0), at: $0.point(in: selection)) }
            default:
                return AnnotationShapeHandle.handles(for: annotation).map { handle(.shape($0), at: viewPoint($0.point(in: annotation))) }
            }
        }
    }

    private func editHandle(at point: CGPoint) -> AnnotationEditHandle? {
        // Pick the nearest handle when short arrows have overlapping hit areas.
        // Reverse drawing order gives the visible end handle priority on a tie.
        editHandles().reversed().filter { $0.rect.insetBy(dx: -4, dy: -4).contains(point) }
            .min { hypot($0.rect.midX - point.x, $0.rect.midY - point.y) < hypot($1.rect.midX - point.x, $1.rect.midY - point.y) }
    }

    /// Six view points around visible strokes and fills, expressed in image pixels.
    private var hitTolerance: CGFloat { 6 / imageScale }

    func pointerTarget(at location: CGPoint) -> AnnotationPointerTarget {
        updateImageGeometry()
        guard let model, model.tool != .crop else { return .canvas }
        if let handle = editHandle(at: location) { return .handle(handle) }
        guard let point = imagePoint(location, requireInside: false, clampToImage: false),
              let hit = model.annotation(at: point, tolerance: hitTolerance) else { return .canvas }
        return hit.kind == .text && model.tool == .text ? .editText(hit.id) : .move(hit.id)
    }

    private func updateHover(at location: CGPoint) {
        let previous = hoveredAnnotationID
        defer { if hoveredAnnotationID != previous { needsDisplay = true } }
        guard let model, dragStart == nil, model.tool != .crop, model.selectionRect == nil else {
            if dragStart == nil { hoveredAnnotationID = nil }
            return
        }
        // Keep the hovered handles while the pointer is on them, including corners away from the outline.
        if editHandle(at: location) != nil { return }
        hoveredAnnotationID = imagePoint(location, requireInside: false, clampToImage: false)
            .flatMap { model.annotation(at: $0, tolerance: hitTolerance) }?.id
    }

    func refreshPointerFeedback(at suppliedLocation: CGPoint? = nil) {
        guard dragStart == nil,
              let location = suppliedLocation ?? window.map({ convert($0.mouseLocationOutsideOfEventStream, from: nil) }) else { return }
        updateImageGeometry()
        guard visibleRect.contains(location) else {
            if hoveredAnnotationID != nil { hoveredAnnotationID = nil; needsDisplay = true }
            return
        }
        updateHover(at: location)
        guard window?.isKeyWindow == true else { return }
        let target = pointerTarget(at: location)
        // The native text editor manages its own cursor except over handles.
        if let textEditor, textEditor.frame.contains(location), case .canvas = target { return }
        cursor(for: target).set()
    }

    private func cursor(for target: AnnotationPointerTarget) -> NSCursor {
        switch target {
        case let .handle(handle):
            switch handle.kind {
            case let .shape(.corner(corner)), let .text(corner):
                return .frameResize(position: corner.cursorPosition, directions: .all)
            case .shape, .arrow:
                return .pointingHand
            }
        case .move: return .openHand
        case .editText: return .iBeam
        case .canvas: return model?.tool == .text ? .iBeam : model?.tool == .select ? .arrow : .crosshair
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        updateImageGeometry()
        let local = convert(point, from: superview)
        // Handles stay draggable where their hit area overlaps the native text editor.
        if bounds.contains(local), editHandle(at: local) != nil { return self }
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
    func viewPoint(_ point: CGPoint) -> CGPoint {
        viewRect(CGRect(origin: point, size: .zero), scale: imageScale).origin
    }
    func imagePoint(_ point: CGPoint, requireInside: Bool, clampToImage: Bool = true) -> CGPoint? {
        guard let model, displayedImageRect.width > 0, displayedImageRect.height > 0,
              !requireInside || displayedImageRect.contains(point) else { return nil }
        let imagePoint = CGPoint(x: (point.x - displayedImageRect.minX) / imageScale, y: (point.y - displayedImageRect.minY) / imageScale)
        guard clampToImage else { return imagePoint }
        return CGPoint(x: min(model.pixelSize.width, max(0, imagePoint.x)), y: min(model.pixelSize.height, max(0, imagePoint.y)))
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard pointerTrackingArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        pointerTrackingArea = area
    }
    override func mouseMoved(with event: NSEvent) {
        refreshPointerFeedback(at: convert(event.locationInWindow, from: nil))
    }
    override func cursorUpdate(with event: NSEvent) {
        refreshPointerFeedback(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseExited(with event: NSEvent) {
        guard dragStart == nil, hoveredAnnotationID != nil else { return }
        hoveredAnnotationID = nil
        needsDisplay = true
    }
    override func magnify(with event: NSEvent) {
        enclosingScrollView?.magnify(with: event)
    }
    override func mouseDown(with event: NSEvent) {
        updateImageGeometry()
        lastDrawingPoint = nil
        clampsDragToImage = false
        let location = convert(event.locationInWindow, from: nil)
        // A press decides its operation from the same target that hover shows.
        updateHover(at: location)
        let extendingSelection = model?.tool == .select && event.modifierFlags.contains(.shift)
        let handle = extendingSelection ? nil : editHandle(at: location)
        window?.makeFirstResponder(self)
        model?.finishTextEditing()
        guard let model else { return }
        if let handle, let point = imagePoint(location, requireInside: false, clampToImage: false) {
            switch handle.kind {
            case let .shape(shapeHandle):
                if model.beginShapeEdit(handle.annotationID, handle: shapeHandle, at: point) { editingShape = true; dragStart = point }
            case let .arrow(arrowHandle):
                if event.clickCount == 2, arrowHandle == .bend {
                    model.straightenArrow(handle.annotationID)
                } else if model.beginArrowEdit(handle.annotationID, handle: arrowHandle, at: point) {
                    editingArrow = true
                    dragStart = point
                }
            case let .text(corner):
                if model.beginTextResize(handle.annotationID, corner: corner, at: point) { resizingText = true; dragStart = point }
            }
            synchronizeTextEditor()
            needsDisplay = true
            return
        }
        // Pixelation is drawn over source pixels, but existing annotations outside them stay movable.
        let startsOnAnnotation = imagePoint(location, requireInside: false, clampToImage: false)
            .flatMap { model.annotation(at: $0, tolerance: hitTolerance) } != nil
        let constrainToImage = model.tool == .crop || (model.tool == .pixelate && !startsOnAnnotation)
        guard let point = imagePoint(location, requireInside: constrainToImage, clampToImage: constrainToImage) else {
            synchronizeTextEditor()
            return
        }
        if event.clickCount == 2, model.tool != .crop, !extendingSelection,
           let annotation = model.annotation(at: point, tolerance: hitTolerance), annotation.kind == .text {
            model.beginTextEditing(annotation.id)
        } else {
            model.begin(at: point, extendingSelection: extendingSelection, hitTolerance: hitTolerance)
            dragStart = model.editingTextID == nil ? point : nil
            clampsDragToImage = model.tool == .crop || (model.tool == .pixelate && model.isDrawingAnnotation)
            lastDrawingPoint = model.isDrawingAnnotation && model.tool.supportsDrawingConstraint ? point : nil
        }
        synchronizeTextEditor()
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil, let point = imagePoint(convert(event.locationInWindow, from: nil), requireInside: false, clampToImage: clampsDragToImage) else { return }
        if lastDrawingPoint != nil { lastDrawingPoint = point }
        model?.continueDrag(to: point, constrained: event.modifierFlags.contains(.shift)); needsDisplay = true
    }
    override func flagsChanged(with event: NSEvent) {
        guard dragStart != nil, let point = lastDrawingPoint else { return }
        model?.continueDrag(to: point, constrained: event.modifierFlags.contains(.shift))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        let location = convert(event.locationInWindow, from: nil)
        if model?.selectionRect != nil || editingShape,
           let point = imagePoint(location, requireInside: false, clampToImage: false) {
            model?.continueDrag(to: point)
        } else if let point = lastDrawingPoint {
            model?.continueDrag(to: point, constrained: event.modifierFlags.contains(.shift))
        }
        lastDrawingPoint = nil
        dragStart = nil; clampsDragToImage = false; resizingText = false; editingArrow = false; editingShape = false; model?.endDrag(); needsDisplay = true
        enclosingScrollView?.needsLayout = true
        refreshPointerFeedback(at: location)
    }
    // Keyboard commands are dispatched by the window using the shared shortcut settings.
}

private extension AnnotationResizeCorner {
    var cursorPosition: NSCursor.FrameResizePosition {
        switch self {
        case .topLeft: .topLeft
        case .topRight: .topRight
        case .bottomLeft: .bottomLeft
        case .bottomRight: .bottomRight
        }
    }
}

private final class AnnotationTextView: NSTextView {
    let annotationLayout: AnnotationTextLayout
    private let textUndoManager = UndoManager()
    override var undoManager: UndoManager? { textUndoManager }

    override func magnify(with event: NSEvent) {
        enclosingScrollView?.magnify(with: event)
    }

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
