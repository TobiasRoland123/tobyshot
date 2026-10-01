import AppKit
import Carbon
import CoreText
import SwiftUI

/// A self-contained annotation editor window. The source image is retained at full pixel
/// resolution; the canvas only scales its presentation and the renderer exports pixels.
public final class AnnotationEditorWindow: NSWindowController, NSWindowDelegate {
    let editorModel: AnnotationEditorModel
    private let shortcuts: HotKeyManager
    private let clipboard = AnnotationClipboard()
    private var keyMonitor: Any?
    var onSaveAndClose: ((AnnotationEditorWindow) -> Void)?

    init(
        image: NSImage,
        sourceURL: URL?,
        shortcuts: HotKeyManager,
        onSave: @escaping (NSImage, Bool) -> Bool,
        onCopy: @escaping (NSImage) -> Void,
        onPin: @escaping (NSImage) -> Void
    ) {
        let model = AnnotationEditorModel(image: image, sourceURL: sourceURL)
        editorModel = model
        self.shortcuts = shortcuts
        self.onSave = onSave
        self.onCopy = onCopy
        self.onPin = onPin
        let root = AnnotationEditorRoot(model: model, shortcuts: shortcuts, onSave: onSave, onCopy: onCopy, onPin: onPin)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        // Keep the editor out of automatic tiling without changing its focus or window level.
        window.setAccessibilitySubrole(.floatingWindow)
        window.title = "Annotate — TobyShot"
        window.setContentSize(NSSize(width: 1040, height: 700))
        window.minSize = NSSize(width: 680, height: 460)
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = hosting
        super.init(window: window)
        window.delegate = self
        model.windowController = self
        model.onImageChange = { [weak self] image in self?.clipboard.copy(image) }
        if UserDefaults.standard.bool(forKey: "editorAlwaysOnTop") {
            window.level = .floating
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window,
                  NSApp.keyWindow === window,
                  (event.window == nil || event.window === window), window.attachedSheet == nil,
                  NSApp.modalWindow == nil else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
        _ = hosting
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        editorModel.finishTextEditing()
        guard editorModel.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Close this annotation?"
        alert.informativeText = "Use Save as… to save your changes before closing."
        alert.addButton(withTitle: "Keep editing")
        alert.addButton(withTitle: "Discard changes")
        return alert.runModal() == .alertSecondButtonReturn
    }

    private static func isEditingText(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard !shortcuts.isRecordingShortcut else { return false }
        let action = shortcuts.action(for: event, scope: .editor)
        if let window, Self.isEditingText(in: window), action != .editorSave, action != .editorSaveAs { return false }
        if let action {
            switch action {
            case .editorCopyObject:
                guard let image = editorModel.renderedSelection() else { return false }
                editorModel.flushImageChange()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            case .editorDuplicate:
                guard editorModel.duplicateSelection() else { return false }
            case .editorSave:
                saveAndClose()
            case .editorSaveAs:
                guard onSave(editorModel.renderedImage(), true) else { return true }
                editorModel.markSaved()
            case .editorCopyScreenshot:
                editorModel.flushImageChange()
                onCopy(editorModel.renderedImage())
            case .editorPrint:
                let image = editorModel.renderedImage()
                let operation = NSPrintOperation(view: NSImageView(image: image))
                operation.run()
            case .editorPin:
                onPin(editorModel.renderedImage())
            case .increaseToolSize:
                editorModel.adjustToolSize(by: 1)
            case .decreaseToolSize:
                editorModel.adjustToolSize(by: -1)
            case .backgroundTool:
                editorModel.showBackgroundPanel.toggle()
            case .moveTool: editorModel.tool = .select
            case .cropTool: editorModel.tool = .crop
            case .drawTool: editorModel.tool = .freehand
            case .lineTool: editorModel.tool = .line
            case .textTool: editorModel.tool = .text
            case .arrowTool: editorModel.tool = .arrow
            case .counterTool: editorModel.tool = .step
            case .ellipseTool: editorModel.tool = .ellipse
            case .redactionTool: editorModel.tool = .redact
            case .rectangleTool: editorModel.tool = .rectangle
            case .filledRectangleTool: editorModel.tool = .filledRectangle
            case .pixelateTool: editorModel.tool = .pixelate
            default: return false
            }
            return true
        }

        guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let modifiers = ShortcutBinding(event: event).appKitModifiers
        if (modifiers == .command || modifiers == [.command, .shift]), chars == "z" {
            modifiers.contains(.shift) ? editorModel.redo() : editorModel.undo()
            return true
        }
        if modifiers == .command, event.keyCode == UInt16(kVK_Return) {
            saveAndClose()
            return true
        }
        if (modifiers.isEmpty || modifiers == .command), [UInt16(kVK_Delete), UInt16(kVK_ForwardDelete)].contains(event.keyCode) {
            editorModel.deleteSelection()
            return true
        }
        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            editorModel.clearSelection()
            editorModel.tool = .select
            return true
        }
        return false
    }

    func saveAndClose() {
        editorModel.finishTextEditing()
        guard onSave(editorModel.renderedImage(), false) else { return }
        editorModel.markSaved()
        close()
        onSaveAndClose?(self)
    }

    private let onSave: (NSImage, Bool) -> Bool
    private let onCopy: (NSImage) -> Void
    private let onPin: (NSImage) -> Void

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, crop, arrow, rectangle, filledRectangle, ellipse, line, freehand, text, step, redact, pixelate
    var id: String { rawValue }
    var supportsDrawingConstraint: Bool {
        switch self {
        case .arrow, .rectangle, .filledRectangle, .ellipse, .line: true
        default: false
        }
    }
    var title: String {
        switch self {
        case .select: "Select"; case .crop: "Crop"; case .arrow: "Arrow"; case .rectangle: "Rectangle"
        case .filledRectangle: "Filled rectangle"; case .ellipse: "Ellipse"; case .line: "Line"
        case .freehand: "Freehand"; case .text: "Text"; case .step: "Numbered step"
        case .redact: "Redact"; case .pixelate: "Pixelate"
        }
    }
    var symbol: String {
        switch self {
        case .select: "cursorarrow"; case .crop: "crop.rotate"; case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"; case .filledRectangle: "rectangle.fill"; case .ellipse: "circle"
        case .line: "line.diagonal"; case .freehand: "pencil.tip.crop.circle"; case .text: "textformat"
        case .step: "1.circle.fill"; case .redact: "rectangle.fill"; case .pixelate: "checkerboard.rectangle"
        }
    }
}

enum AnnotationBackground: String, CaseIterable, Identifiable {
    case none, midnight, lavender, peach
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct EditorAnnotation: Identifiable, Equatable {
    enum Kind: Equatable { case arrow, rectangle, filledRectangle, ellipse, line, freehand, text, step, redaction, pixelation }
    var id = UUID()
    var kind: Kind
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []
    var color: NSColor = .systemRed
    var width: CGFloat = 5
    var text: String = ""
    var textSize: CGFloat?
    var step: Int = 1
    var shadow = true
    var reversed = false
    var font: AnnotationFont = .system
    // Shared shape appearance; retain the original arrow fields and preference keys.
    var arrowStyle: AnnotationArrowStyle = .clean
    var arrowStroke: AnnotationArrowStroke = .solid
    var arrowSeed: UInt64 = .random(in: 1...UInt64.max)
    // Displacement from the endpoints' midpoint; translation preserves the curve.
    var arrowBend: CGPoint = .zero

    var arrowBendPoint: CGPoint {
        CGPoint(x: (start.x + end.x) / 2 + arrowBend.x,
                y: (start.y + end.y) / 2 + arrowBend.y)
    }
}

struct EditorState {
    var image: NSImage
    var annotations: [EditorAnnotation]
    var crop: CGRect?
    var background: AnnotationBackground
    var padding: CGFloat
    var cornerRadius: CGFloat
}

@MainActor
final class AnnotationEditorModel: ObservableObject {
    @Published var image: NSImage {
        didSet { if image !== oldValue { scheduleImageChange() } }
    }
    @Published var tool: AnnotationTool = .select {
        didSet { finishTextEditing(); drawingAnnotationID = nil; resetSelectionDrag(); flushImageChange() }
    }
    @Published var selectedIDs: Set<UUID> = []
    var selectedID: UUID? {
        get { selectedIDs.count == 1 ? selectedIDs.first : nil }
        set { selectedIDs = Set(newValue.map { [$0] } ?? []) }
    }
    @Published private(set) var selectionRect: CGRect?
    @Published private(set) var editingTextID: UUID?
    @Published var showBackgroundPanel = false
    @Published var color: NSColor = .systemRed {
        didSet { updateSelectedAppearance(color: color) }
    }
    @Published var strokeWidth: CGFloat = 5 {
        didSet { updateSelectedAppearance(width: strokeWidth) }
    }
    @Published private(set) var background: AnnotationBackground = .none {
        didSet { if background != oldValue { scheduleImageChange() } }
    }
    @Published private(set) var padding: CGFloat = 36 {
        didSet { if padding != oldValue { scheduleImageChange() } }
    }
    @Published private(set) var cornerRadius: CGFloat = 18 {
        didSet { if cornerRadius != oldValue { scheduleImageChange() } }
    }
    @Published var zoom: CGFloat = 0
    @Published var annotations: [EditorAnnotation] = [] {
        didSet { if annotations != oldValue { scheduleImageChange() } }
    }
    @Published var cropRect: CGRect?
    @Published var showColorNames = UserDefaults.standard.bool(forKey: "showColorNames")
    @Published var smoothDrawing = UserDefaults.standard.object(forKey: "smoothDrawing") == nil || UserDefaults.standard.bool(forKey: "smoothDrawing")
    @Published var annotationShadow = UserDefaults.standard.object(forKey: "annotationShadow") == nil || UserDefaults.standard.bool(forKey: "annotationShadow")
    let sourceURL: URL?
    weak var windowController: AnnotationEditorWindow?
    var onImageChange: ((NSImage) -> Void)?
    private var imageChangePending = false
    private var imageChangeScheduled = false
    private var undoStack: [EditorState] = []
    private var redoStack: [EditorState] = []
    private var stepCount = 0
    private var dragOrigin: CGPoint = .zero
    private var movingOriginals: [UUID: EditorAnnotation] = [:]
    private var selectionAnchor: CGPoint?
    private var selectionOriginalIDs: Set<UUID> = []
    private var moveCheckpointed = false
    private var textResize: AnnotationTextResize?
    private var arrowEdit: AnnotationArrowEdit?
    private var shapeEdit: AnnotationShapeEdit?
    private var drawingAnnotationID: UUID?
    private var cropAnchor: CGPoint?
    private var savedState: EditorState?
    private var isEditingBackground = false
    private var backgroundEditCheckpointed = false
    private var textEditOriginalState: EditorState?

    init(image: NSImage, sourceURL: URL?) {
        self.image = image
        self.sourceURL = sourceURL
        savedState = state()
    }

    private func scheduleImageChange() {
        guard onImageChange != nil else { return }
        imageChangePending = true
        guard !imageChangeScheduled else { return }
        imageChangeScheduled = true
        // Render after compound changes such as crop and undo have updated every field.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.imageChangeScheduled = false
            self.flushImageChange()
        }
    }

    func flushImageChange() {
        // Export completed gestures instead of encoding an image at every mouse movement.
        guard imageChangePending, drawingAnnotationID == nil, movingOriginals.isEmpty,
              textResize == nil, arrowEdit == nil, shapeEdit == nil, !isEditingBackground else { return }
        imageChangePending = false
        onImageChange?(renderedImage())
    }

    var pixelSize: NSSize {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) { return NSSize(width: cg.width, height: cg.height) }
        return image.size
    }
    var canUndo: Bool { !undoStack.isEmpty || textEditOriginalState.map { $0.annotations != annotations } == true }
    var canRedo: Bool { !redoStack.isEmpty }

    var hasUnsavedChanges: Bool {
        guard let savedState else { return false }
        return image !== savedState.image || annotations != savedState.annotations || background != savedState.background || padding != savedState.padding || cornerRadius != savedState.cornerRadius
    }
    func markSaved() { finishTextEditing(); savedState = state() }
    private func state() -> EditorState { EditorState(image: image, annotations: annotations, crop: nil, background: background, padding: padding, cornerRadius: cornerRadius) }
    private func checkpoint(coalescingBackgroundEdit: Bool = false) {
        finishTextEditing()
        if coalescingBackgroundEdit, isEditingBackground {
            guard !backgroundEditCheckpointed else { return }
            backgroundEditCheckpointed = true
        } else {
            setBackgroundEditing(false)
        }
        undoStack.append(state()); redoStack.removeAll(); selectedID = nil
    }

    func setBackgroundEditing(_ isEditing: Bool) {
        let wasEditing = isEditingBackground
        isEditingBackground = isEditing
        backgroundEditCheckpointed = false
        if wasEditing, !isEditing { flushImageChange() }
    }

    func updateBackground(style: AnnotationBackground) {
        guard style != background else { return }
        checkpoint()
        background = style
    }

    func updateBackground(padding: CGFloat? = nil, cornerRadius: CGFloat? = nil) {
        let newPadding = padding ?? self.padding
        let newCornerRadius = cornerRadius ?? self.cornerRadius
        guard newPadding != self.padding || newCornerRadius != self.cornerRadius else { return }
        // Checkpoint the first changed value of a slider gesture; subsequent values update its preview.
        checkpoint(coalescingBackgroundEdit: true)
        self.padding = newPadding
        self.cornerRadius = newCornerRadius
    }

    func undo() {
        finishTextEditing()
        setBackgroundEditing(false)
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(state()); restore(previous)
    }
    func redo() {
        finishTextEditing()
        setBackgroundEditing(false)
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state()); restore(next)
    }
    private func restore(_ state: EditorState) { image = state.image; annotations = state.annotations; cropRect = state.crop; background = state.background; padding = state.padding; cornerRadius = state.cornerRadius; stepCount = annotations.filter { $0.kind == .step }.map(\.step).max() ?? 0; clearSelection() }
    func clearSelection() {
        selectedIDs.removeAll()
        resetSelectionDrag()
        flushImageChange()
    }

    private func resetSelectionDrag() {
        selectionRect = nil
        selectionAnchor = nil
        selectionOriginalIDs.removeAll()
        movingOriginals.removeAll()
        textResize = nil
        arrowEdit = nil
        shapeEdit = nil
    }

    func deleteSelection() {
        let ids = selectedIDs
        guard annotations.contains(where: { ids.contains($0.id) }) else { clearSelection(); return }
        checkpoint(); annotations.removeAll { ids.contains($0.id) }
        resetSelectionDrag()
    }

    @discardableResult
    func duplicateSelection() -> Bool {
        let selected = annotations.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return false }
        checkpoint()
        let copies = selected.map { annotation in
            var copy = translated(annotation, by: CGPoint(x: 12, y: 12))
            copy.id = UUID()
            return copy
        }
        annotations.append(contentsOf: copies)
        selectedIDs = Set(copies.map(\.id))
        resetSelectionDrag()
        return true
    }

    func adjustToolSize(by delta: CGFloat) {
        strokeWidth = min(40, max(1, currentStrokeWidth + delta))
    }

    var currentColor: NSColor {
        appearanceSelection.first(where: { $0.kind != .redaction && $0.kind != .pixelation })?.color ?? color
    }

    var currentStrokeWidth: CGFloat {
        appearanceSelection.first(where: { $0.kind != .redaction })?.width ?? strokeWidth
    }

    private var appearanceSelection: [EditorAnnotation] {
        guard tool == .select || editingTextID != nil else { return [] }
        return annotations.filter { selectedIDs.contains($0.id) }
    }

    func renderedSelection() -> NSImage? {
        AnnotationRenderer.render(annotations: annotations.filter { selectedIDs.contains($0.id) }, sourceImage: image)
    }

    @discardableResult
    func beginTextEditing(_ id: UUID) -> Bool {
        guard annotations.contains(where: { $0.id == id && $0.kind == .text }) else { return false }
        if editingTextID == id { return true }
        finishTextEditing()
        setBackgroundEditing(false)
        textEditOriginalState = state()
        selectedID = id
        editingTextID = id
        return true
    }

    func updateText(_ text: String) {
        guard let id = editingTextID, let index = annotations.firstIndex(where: { $0.id == id }),
              annotations[index].text != text else { return }
        annotations[index].text = text
    }

    func finishTextEditing() {
        guard let id = editingTextID, let original = textEditOriginalState else { return }
        editingTextID = nil
        textEditOriginalState = nil
        if let annotation = annotations.first(where: { $0.id == id }),
           annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annotations.removeAll { $0.id == id }
            if selectedID == id { selectedID = nil }
        }
        if annotations != original.annotations {
            undoStack.append(original)
            redoStack.removeAll()
        }
        if tool == .text { tool = .select }
        flushImageChange()
    }

    private func updateSelectedAppearance(color: NSColor? = nil, width: CGFloat? = nil) {
        if let id = editingTextID, let index = annotations.firstIndex(where: { $0.id == id }) {
            if let color { annotations[index].color = color }
            if let width { annotations[index].width = width; annotations[index].textSize = nil }
            return
        }
        guard tool == .select else { return }
        let ids = selectedIDs
        let updated = annotations.map { annotation in
            guard ids.contains(annotation.id), annotation.kind != .redaction else { return annotation }
            var edited = annotation
            if let color, annotation.kind != .pixelation { edited.color = color }
            if let width {
                edited.width = width
                if annotation.kind == .text { edited.textSize = nil }
            }
            return edited
        }
        guard updated != annotations else { return }
        checkpoint()
        annotations = updated
        selectedIDs = ids
        resetSelectionDrag()
    }

    func textSelectionBounds(_ annotation: EditorAnnotation) -> CGRect {
        CGRect(origin: annotation.start, size: AnnotationTextLayout(annotation).selectionSize)
    }

    @discardableResult
    func beginTextResize(corner: AnnotationResizeCorner, at point: CGPoint) -> Bool {
        guard tool == .select || tool == .text,
              let id = selectedID, let annotation = annotations.first(where: { $0.id == id }),
              annotation.kind == .text, !annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        finishTextEditing()
        textResize = AnnotationTextResize(original: annotation, corner: corner, start: point, bounds: textSelectionBounds(annotation))
        moveCheckpointed = false
        return true
    }

    func annotation(at point: CGPoint) -> EditorAnnotation? {
        annotations.last(where: { hitTest($0, point: point) })
    }

    @discardableResult
    func beginArrowEdit(handle: AnnotationArrowHandle, at point: CGPoint) -> Bool {
        guard tool == .select || tool == .arrow,
              let annotation = annotations.first(where: { $0.id == selectedID }),
              annotation.kind == .arrow else { return false }
        finishTextEditing()
        arrowEdit = AnnotationArrowEdit(original: annotation, handle: handle, start: point)
        moveCheckpointed = false
        return true
    }

    func straightenSelectedArrow() {
        guard let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id }),
              annotations[index].kind == .arrow, annotations[index].arrowBend != .zero else { return }
        checkpoint()
        annotations[index].arrowBend = .zero
        selectedID = id
    }

    @discardableResult
    func beginShapeEdit(handle: AnnotationShapeHandle, at point: CGPoint) -> Bool {
        guard tool == .select,
              let annotation = annotations.first(where: { $0.id == selectedID }),
              AnnotationShapeHandle.handles(for: annotation).contains(handle) else { return false }
        finishTextEditing()
        resetSelectionDrag()
        shapeEdit = AnnotationShapeEdit(original: annotation, handle: handle, start: point)
        moveCheckpointed = false
        return true
    }

    func begin(at point: CGPoint, extendingSelection: Bool = false) {
        finishTextEditing()
        resetSelectionDrag()
        if tool == .select {
            moveCheckpointed = false
            if let hit = annotation(at: point) {
                if extendingSelection {
                    if selectedIDs.remove(hit.id) != nil { return }
                    selectedIDs.insert(hit.id)
                } else if !selectedIDs.contains(hit.id) {
                    selectedID = hit.id
                }
                dragOrigin = point
                movingOriginals = Dictionary(uniqueKeysWithValues: annotations.filter { selectedIDs.contains($0.id) }.map { ($0.id, $0) })
            } else {
                if !extendingSelection { selectedIDs.removeAll() }
                selectionOriginalIDs = selectedIDs
                selectionAnchor = point
                selectionRect = CGRect(origin: point, size: .zero)
            }
            return
        }
        if tool == .text {
            if let hit = annotation(at: point), hit.kind == .text {
                beginTextEditing(hit.id)
            } else {
                setBackgroundEditing(false)
                textEditOriginalState = state()
                let annotation = make(.text, at: point, end: point)
                annotations.append(annotation)
                selectedID = annotation.id
                editingTextID = annotation.id
            }
            return
        }
        if tool == .step {
            checkpoint(); stepCount += 1
            let annotation = make(.step, at: point, end: point, step: stepCount)
            annotations.append(annotation)
            selectedID = annotation.id
            drawingAnnotationID = annotation.id
            return
        }
        if tool == .crop { cropAnchor = point; cropRect = CGRect(origin: point, size: .zero); return }
        checkpoint()
        let kind: EditorAnnotation.Kind
        switch tool {
        case .arrow: kind = .arrow; case .rectangle: kind = .rectangle; case .filledRectangle: kind = .filledRectangle
        case .ellipse: kind = .ellipse; case .line: kind = .line; case .freehand: kind = .freehand
        case .redact: kind = .redaction; case .pixelate: kind = .pixelation; default: return
        }
        var a = make(kind, at: point, end: point)
        if kind == .redaction { a.color = NSColor.black }
        if kind == .pixelation { a.color = .black }
        if kind == .freehand { a.points = [point] }
        annotations.append(a); selectedID = a.id
        drawingAnnotationID = a.id
    }

    func continueDrag(to point: CGPoint, constrained: Bool = false) {
        guard editingTextID == nil else { return }
        if let edit = shapeEdit, let index = annotations.firstIndex(where: { $0.id == edit.original.id }) {
            let edited = edit.annotation(at: point)
            guard edited != annotations[index] else { return }
            if !moveCheckpointed { checkpoint(); selectedID = edit.original.id; moveCheckpointed = true }
            annotations[index] = edited
            return
        }
        if let edit = arrowEdit, let index = annotations.firstIndex(where: { $0.id == edit.original.id }) {
            let edited = edit.annotation(at: point)
            guard edited != annotations[index] else { return }
            if !moveCheckpointed { checkpoint(); selectedID = edit.original.id; moveCheckpointed = true }
            annotations[index] = edited
            return
        }
        if let resize = textResize, let index = annotations.firstIndex(where: { $0.id == resize.original.id }) {
            let resized = resize.annotation(at: point)
            guard resized != annotations[index] else { return }
            if !moveCheckpointed { checkpoint(); selectedID = resize.original.id; moveCheckpointed = true }
            annotations[index] = resized
            return
        }
        if tool == .select {
            if let anchor = selectionAnchor {
                let selection = rect(from: anchor, to: point)
                selectionRect = selection
                selectedIDs = selectionOriginalIDs.union(annotations.filter { annotation in
                    let bounds = annotation.kind == .text ? textSelectionBounds(annotation) : annotationBounds(annotation)
                    return !selection.isEmpty && selection.intersects(bounds)
                }.map(\.id))
                return
            }
            guard !movingOriginals.isEmpty else { return }
            let delta = CGPoint(x: point.x - dragOrigin.x, y: point.y - dragOrigin.y)
            guard delta != .zero || moveCheckpointed else { return }
            if !moveCheckpointed { checkpoint(); selectedIDs = Set(movingOriginals.keys); moveCheckpointed = true }
            for index in annotations.indices {
                if let original = movingOriginals[annotations[index].id] {
                    annotations[index] = translated(original, by: delta)
                }
            }
            return
        }
        if tool == .crop {
            if let cropAnchor { cropRect = rect(from: cropAnchor, to: point) }
            return
        }
        guard let id = drawingAnnotationID, let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].end = constrained
            ? AnnotationGeometry.constrainedEndpoint(from: annotations[index].start, to: point, kind: annotations[index].kind)
            : point
        if annotations[index].kind == .freehand {
            if smoothDrawing, let last = annotations[index].points.last {
                annotations[index].points.append(CGPoint(x: (last.x + point.x) / 2, y: (last.y + point.y) / 2))
            } else { annotations[index].points.append(point) }
        }
    }

    func endDrag() {
        textResize = nil
        arrowEdit = nil
        if tool == .freehand, let id = drawingAnnotationID, let index = annotations.firstIndex(where: { $0.id == id }), annotations[index].points.last != annotations[index].end {
            annotations[index].points.append(annotations[index].end)
        }
        resetSelectionDrag()
        if tool == .crop, cropAnchor != nil {
            if let cropRect, cropRect.width > 2, cropRect.height > 2 { applyCrop(cropRect) }
            cropAnchor = nil; cropRect = nil
            tool = .select
        }
        if let id = drawingAnnotationID, annotations.contains(where: { $0.id == id }) {
            selectedID = id
            tool = .select
        }
        drawingAnnotationID = nil
        flushImageChange()
    }
    private func applyCrop(_ rect: CGRect) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { cropRect = nil; return }
        let bounded = rect.integral.intersection(CGRect(origin: .zero, size: CGSize(width: cg.width, height: cg.height)))
        guard bounded.width >= 2, bounded.height >= 2,
              let cropped = cg.cropping(to: bounded) else { cropRect = nil; return }
        // CGImage cropping and the model both use top-left image coordinates.
        // Preserve annotations that remain inside the crop.
        checkpoint()
        let delta = CGPoint(x: bounded.minX, y: bounded.minY)
        image = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        annotations = annotations.compactMap { a in
            let moved = translated(a, by: CGPoint(x: -delta.x, y: -delta.y))
            if !CGRect(origin: .zero, size: CGSize(width: cropped.width, height: cropped.height)).intersects(annotationBounds(moved)) { return nil }
            return moved
        }
        cropRect = nil; selectedID = nil
    }

    private func make(_ kind: EditorAnnotation.Kind, at start: CGPoint, end: CGPoint, text: String = "", step: Int = 1) -> EditorAnnotation {
        EditorAnnotation(kind: kind, start: start, end: end, color: color, width: strokeWidth, text: text, step: step, shadow: annotationShadow,
                         reversed: UserDefaults.standard.bool(forKey: "inverseArrow") != NSEvent.modifierFlags.contains(.option),
                         font: AnnotationFont(rawValue: Preferences.string("annotationFont")) ?? .system,
                         arrowStyle: AnnotationArrowStyle(rawValue: Preferences.string("annotationArrowStyle")) ?? .clean,
                         arrowStroke: AnnotationArrowStroke(rawValue: Preferences.string("annotationArrowStroke")) ?? .solid)
    }
    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect { CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y)) }
    func annotationBounds(_ a: EditorAnnotation) -> CGRect { AnnotationGeometry(a, imageSize: pixelSize).renderedBounds }

    nonisolated static func bounds(for a: EditorAnnotation) -> CGRect {
        AnnotationGeometry(a).renderedBounds
    }
    private func hitTest(_ a: EditorAnnotation, point: CGPoint) -> Bool {
        annotationBounds(a).insetBy(dx: -6, dy: -6).contains(point)
    }
    private func translated(_ a: EditorAnnotation, by delta: CGPoint) -> EditorAnnotation {
        var b = a; b.start.x += delta.x; b.start.y += delta.y; b.end.x += delta.x; b.end.y += delta.y
        b.points = b.points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }; return b
    }

    var canvasBounds: CGRect {
        AnnotationRenderer.canvasBounds(imageSize: pixelSize, annotations: annotations, background: background, padding: padding)
    }

    func renderedImage(excluding annotationID: UUID? = nil) -> NSImage {
        AnnotationRenderer.render(image: image, annotations: annotations.filter { $0.id != annotationID }, background: background, padding: padding, cornerRadius: cornerRadius, canvasBounds: canvasBounds)
    }
}

private struct AnnotationEditorRoot: View {
    @ObservedObject var model: AnnotationEditorModel
    @ObservedObject var shortcuts: HotKeyManager
    let onSave: (NSImage, Bool) -> Bool
    let onCopy: (NSImage) -> Void
    let onPin: (NSImage) -> Void
    @State private var showHelp = false
    private let palette: [(String, NSColor)] = [("Red", .systemRed), ("Orange", .systemOrange), ("Yellow", .systemYellow), ("Green", .systemGreen), ("Blue", .systemBlue), ("Purple", .systemPurple), ("White", .white), ("Black", .black)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                canvas
                if model.showBackgroundPanel { backgroundPanel.frame(width: 190).padding(.trailing, 14) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showHelp) { helpPanel }
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                drawingTools
                Divider().frame(height: 22)
                appearanceControls
                historyControls
                exportActions
            }.fixedSize(horizontal: true, vertical: false)
            VStack(spacing: 10) {
                HStack { drawingTools; Spacer(minLength: 12); exportActions }
                HStack { appearanceControls; Spacer(); historyControls }
            }
        }
        .buttonStyle(.plain).font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var drawingTools: some View {
        HStack(spacing: 0) {
            toolButton(.select, action: .moveTool); toolButton(.crop, action: .cropTool)
            Divider().frame(height: 20).padding(.horizontal, 2)
            toolButton(.arrow, action: .arrowTool); toolButton(.rectangle, action: .rectangleTool); toolButton(.filledRectangle, action: .filledRectangleTool)
            toolButton(.ellipse, action: .ellipseTool); toolButton(.line, action: .lineTool); toolButton(.freehand, action: .drawTool)
            toolButton(.text, action: .textTool); toolButton(.step, action: .counterTool); toolButton(.redact, action: .redactionTool); toolButton(.pixelate, action: .pixelateTool)
        }.fixedSize()
    }

    private var appearanceControls: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(palette, id: \.0) { name, value in
                    Button { model.color = value } label: { Label(name, systemImage: model.currentColor == value ? "checkmark.circle.fill" : "circle.fill") }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "circle.fill").foregroundStyle(Color(nsColor: model.currentColor)).font(.system(size: 16))
                    if model.showColorNames, let name = palette.first(where: { $0.1 == model.currentColor })?.0 { Text(name) }
                }.padding(5)
            }.menuStyle(.borderlessButton).fixedSize().help("Annotation color")
            Picker("Stroke width", selection: Binding(get: { model.currentStrokeWidth }, set: { model.strokeWidth = $0 })) {
                ForEach(Array(Set([CGFloat(2), 5, 10, 20, model.currentStrokeWidth])).sorted(), id: \.self) { width in
                    Text("\(Int(width)) pt").tag(width)
                }
            }.labelsHidden().pickerStyle(.menu).frame(width: 74).help("Selection or new annotation size; controls stroke width, text, numbered steps, and pixelation")
            Menu {
                ForEach(AnnotationBackground.allCases) { background in Button(background.title) { model.updateBackground(style: background); model.showBackgroundPanel = true } }
            } label: { Label("Background", systemImage: "square.on.square") }
                .menuStyle(.borderlessButton).fixedSize().help("Canvas background (\(shortcuts.label(for: .backgroundTool)))")
        }.fixedSize()
    }

    private var historyControls: some View {
        HStack(spacing: 12) {
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!model.canUndo).help("Undo (⌘Z)")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!model.canRedo).help("Redo (⇧⌘Z)")
            Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }.help("Shortcuts and help")
        }.fixedSize()
    }

    private var exportActions: some View {
        Button("Save as…") { if onSave(model.renderedImage(), true) { model.markSaved() } }
            .buttonStyle(.bordered).fixedSize().help("Save as… (\(shortcuts.label(for: .editorSaveAs)))")
    }

    private func toolButton(_ tool: AnnotationTool, action: ShortcutAction) -> some View {
        Button { model.tool = tool } label: {
            Image(systemName: tool.symbol).frame(width: 30, height: 28)
                .background(model.tool == tool ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
            .help("\(tool.title) (\(shortcuts.label(for: action)))").accessibilityLabel(tool.title).accessibilityValue(model.tool == tool ? "Selected" : "")
    }
    private var canvas: some View {
        AnnotationCanvasRepresentable(model: model).padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))
    }
    private var backgroundPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BACKGROUND").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(AnnotationBackground.allCases) { b in Button { model.updateBackground(style: b) } label: { HStack { Circle().fill(backgroundColor(b)).frame(width: 16, height: 16); Text(b.title); Spacer(); if model.background == b { Image(systemName: "checkmark") } }.contentShape(Rectangle()) }.buttonStyle(.plain) }
            Divider(); VStack(alignment: .leading) {
                Text("Padding")
                Slider(value: Binding(get: { model.padding }, set: { model.updateBackground(padding: $0) }), in: 0...120, step: 4, onEditingChanged: model.setBackgroundEditing)
            }
            VStack(alignment: .leading) {
                Text("Corner radius")
                Slider(value: Binding(get: { model.cornerRadius }, set: { model.updateBackground(cornerRadius: $0) }), in: 0...48, step: 2, onEditingChanged: model.setBackgroundEditing)
            }
            Spacer()
        }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12)).padding(.vertical, 14)
            .onDisappear { model.setBackgroundEditing(false) }
    }
    private func backgroundColor(_ b: AnnotationBackground) -> Color {
        switch b { case .none: .clear; case .midnight: Color(red: 0.14, green: 0.17, blue: 0.25); case .lavender: Color(red: 0.48, green: 0.38, blue: 0.68); case .peach: Color(red: 0.88, green: 0.48, blue: 0.35) }
    }
    private var footer: some View {
        HStack(spacing: 10) {
            Menu { Button("Fit") { model.zoom = 0 }; ForEach([CGFloat(0.5), 1, 2], id: \.self) { scale in Button("\(Int(scale * 100))%") { model.zoom = scale } } } label: { Text(model.zoom == 0 ? "Fit" : "\(Int(model.zoom * 100))%").font(.system(.caption, design: .rounded).weight(.semibold)).frame(width: 58) }.fixedSize().help("Zoom level")
            Text("\(Int(model.canvasBounds.width)) × \(Int(model.canvasBounds.height)) px").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { model.flushImageChange(); onCopy(model.renderedImage()) } label: { Label("Copy", systemImage: "doc.on.doc") }.help("Copy rendered image (\(shortcuts.label(for: .editorCopyScreenshot)))")
            Button { onPin(model.renderedImage()) } label: { Label("Pin", systemImage: "pin") }.help("Pin rendered image (\(shortcuts.label(for: .editorPin)))")
        }.padding(.horizontal, 14).padding(.vertical, 9).background(Color(nsColor: .controlBackgroundColor))
    }
    private var helpPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Annotation shortcuts").font(.title2.bold())
            Text("Move \(shortcuts.label(for: .moveTool))   Crop \(shortcuts.label(for: .cropTool))   Draw \(shortcuts.label(for: .drawTool))   Line \(shortcuts.label(for: .lineTool))\nText \(shortcuts.label(for: .textTool))   Arrow \(shortcuts.label(for: .arrowTool))   Counter \(shortcuts.label(for: .counterTool))   Ellipse \(shortcuts.label(for: .ellipseTool))\nRedact \(shortcuts.label(for: .redactionTool))   Rectangle \(shortcuts.label(for: .rectangleTool))   Filled rectangle \(shortcuts.label(for: .filledRectangleTool))   Pixelate \(shortcuts.label(for: .pixelateTool))\nBackground \(shortcuts.label(for: .backgroundTool))   Smaller/larger \(shortcuts.label(for: .decreaseToolSize))/\(shortcuts.label(for: .increaseToolSize))\nCopy object \(shortcuts.label(for: .editorCopyObject))   Duplicate \(shortcuts.label(for: .editorDuplicate))   Save \(shortcuts.label(for: .editorSave))   Save as \(shortcuts.label(for: .editorSaveAs))\nCopy image \(shortcuts.label(for: .editorCopyScreenshot))   Print \(shortcuts.label(for: .editorPrint))   Pin \(shortcuts.label(for: .editorPin))\nUndo ⌘Z   Redo ⇧⌘Z   Delete Remove   Escape Select")
            Text("Tools return to the pointer after drawing, placing a numbered step, applying a crop, or finishing text entry. New annotations stay selected. Hold Shift while drawing to snap lines and arrows to 45° increments, make rectangles square, or make ellipses circular. With the pointer, drag empty canvas space to select multiple annotations, then drag any selected annotation to move the group. Hold Shift to add to the selection. Drag an arrow endpoint to adjust it, or the middle handle to bend it; double-click the middle handle to straighten it. Drag the arrow itself to move it. Click with Text to type on the image; double-click existing text to edit it. Drag shape corners to resize rectangles, ellipses, freehand drawings, numbered steps, redactions, and pixelation regions; drag line endpoints to adjust them. Color and size controls update selected annotations. Drag a text corner to resize. Return finishes editing, Shift-Return adds a line. Crop applies when you finish the crop selection.").foregroundStyle(.secondary)
            HStack { Spacer(); Button("Close") { showHelp = false }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 420)
    }
}

enum AnnotationRenderer {
    static func canvasBounds(imageSize: CGSize, annotations: [EditorAnnotation], background: AnnotationBackground = .none, padding: CGFloat = 0) -> CGRect {
        var bounds = CGRect(origin: .zero, size: imageSize)
        for annotation in annotations {
            // Pixelation only paints existing source pixels. Empty text paints nothing.
            guard annotation.kind != .pixelation,
                  annotation.kind != .text || !annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let geometry = AnnotationGeometry(annotation, imageSize: imageSize)
            guard !geometry.renderedBounds.isNull, !geometry.renderedBounds.isEmpty else { continue }
            bounds = bounds.union(geometry.exportBounds)
        }
        let pad = background == .none ? 0 : max(0, padding.rounded())
        return bounds.insetBy(dx: -pad, dy: -pad)
    }

    static func render(annotation: EditorAnnotation, sourceImage: NSImage) -> NSImage? {
        render(annotations: [annotation], sourceImage: sourceImage)
    }

    static func render(annotations: [EditorAnnotation], sourceImage: NSImage) -> NSImage? {
        guard !annotations.isEmpty else { return nil }
        guard let source = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let pixelSize = CGSize(width: source.width, height: source.height)
        let geometries = annotations.map { AnnotationGeometry($0, imageSize: pixelSize) }
        let bounds = geometries.reduce(CGRect.null) { $0.union($1.exportBounds) }
        guard !bounds.isNull, !bounds.isEmpty else { return nil }
        let width = max(1, Int(ceil(bounds.width)))
        let height = max(1, Int(ceil(bounds.height)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        let sourcePixels = annotations.contains(where: { $0.kind == .pixelation }) ? pixelationSourcePixels(source) : []
        for (annotation, geometry) in zip(annotations, geometries) {
            draw(annotation, geometry: geometry, in: context, pixelSize: pixelSize, sourcePixels: sourcePixels)
        }
        guard let rendered = context.makeImage() else { return nil }
        return NSImage(cgImage: rendered, size: NSSize(width: width, height: height))
    }

    static func render(image: NSImage, annotations: [EditorAnnotation], background: AnnotationBackground = .none, padding: CGFloat = 0, cornerRadius: CGFloat = 0, canvasBounds suppliedBounds: CGRect? = nil) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let bounds = suppliedBounds ?? canvasBounds(imageSize: CGSize(width: cg.width, height: cg.height), annotations: annotations, background: background, padding: padding)
        let width = Int(bounds.width), height = Int(bounds.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        drawBackground(background, in: context, size: CGSize(width: width, height: height))
        let imageRect = CGRect(x: -bounds.minX, y: bounds.maxY - CGFloat(cg.height), width: CGFloat(cg.width), height: CGFloat(cg.height))
        if cornerRadius > 0, background != .none {
            context.saveGState(); context.addPath(CGPath(roundedRect: imageRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)); context.clip(); context.draw(cg, in: imageRect); context.restoreGState()
        } else { context.draw(cg, in: imageRect) }
        // Use a top-left image coordinate system for all annotation geometry.
        context.saveGState(); context.translateBy(x: -bounds.minX, y: bounds.maxY); context.scaleBy(x: 1, y: -1)
        let sourcePixels = annotations.contains(where: { $0.kind == .pixelation }) ? pixelationSourcePixels(cg) : []
        for annotation in annotations { draw(annotation, in: context, pixelSize: CGSize(width: cg.width, height: cg.height), sourcePixels: sourcePixels) }
        context.restoreGState()
        guard let result = context.makeImage() else { return image }
        return NSImage(cgImage: result, size: NSSize(width: width, height: height))
    }

    static func pixelationSourcePixels(_ source: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: source.width * source.height * 4)
        pixels.withUnsafeMutableBytes { raw in
            if let bitmap = CGContext(data: raw.baseAddress, width: source.width, height: source.height, bitsPerComponent: 8,
                                      bytesPerRow: source.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                bitmap.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            }
        }
        return pixels
    }

    static func draw(_ a: EditorAnnotation, geometry suppliedGeometry: AnnotationGeometry? = nil, in c: CGContext, pixelSize: CGSize, sourcePixels: [UInt8], shadowScale: CGSize = CGSize(width: 1, height: 1)) {
        let geometry = suppliedGeometry ?? AnnotationGeometry(a, imageSize: pixelSize)
        let col = a.color.cgColor
        c.saveGState(); c.setStrokeColor(col); c.setFillColor(col); c.setLineWidth(geometry.lineWidth); c.setLineCap(.round); c.setLineJoin(.round)
        if let shadow = geometry.shadow {
            // Quartz shadows ignore subsequent transforms; scale them explicitly for the preview.
            c.setShadow(offset: CGSize(width: shadow.offset.width * shadowScale.width, height: shadow.offset.height * shadowScale.height),
                        blur: shadow.blur * abs(shadowScale.width), color: shadow.color)
        }
        if a.kind == .pixelation {
            pixelate(a, rect: geometry.pixelationRect, in: c, imageSize: pixelSize, sourcePixels: sourcePixels)
        } else {
            if a.kind == .redaction { c.setFillColor(NSColor.black.cgColor) }
            c.addPath(geometry.path)
            if geometry.stroked { c.strokePath() } else { c.fillPath() }
            if let text = geometry.text {
                if a.kind == .step { c.setShadow(offset: .zero, blur: 0, color: nil) }
                drawText(text, in: c)
            }
            geometry.textLayout?.draw(at: a.start, in: c)
        }
        c.restoreGState()
    }

    private static func pixelate(_ a: EditorAnnotation, rect r: CGRect, in c: CGContext, imageSize: CGSize, sourcePixels: [UInt8]) {
        guard r.width > 0, r.height > 0 else { return }
        // Bitmap data and annotation coordinates both start at the top-left row.
        let step = max(8, Int(a.width * 5))
        for y in stride(from: Int(r.minY), to: Int(r.maxY), by: step) { for x in stride(from: Int(r.minX), to: Int(r.maxX), by: step) {
            let x1 = min(Int(r.maxX), x + step), y1 = min(Int(r.maxY), y + step); var sum = [Int](repeating: 0, count: 4); var count = 0
            for sy in stride(from: y, to: y1, by: max(1, step / 4)) { for sx in stride(from: x, to: x1, by: max(1, step / 4)) { let i = (sy * Int(imageSize.width) + sx) * 4; for ch in 0..<3 { sum[ch] += Int(sourcePixels[i+ch]) }; count += 1 } }
            let color = CGColor(srgbRed: CGFloat(sum[0] / max(count,1))/255, green: CGFloat(sum[1] / max(count,1))/255, blue: CGFloat(sum[2] / max(count,1))/255, alpha: 1)
            c.setFillColor(color); c.fill(CGRect(x:x,y:y,width:x1-x,height:y1-y))
        } }
    }

    private static func drawText(_ text: AnnotationGeometry.Text, in c: CGContext) {
        c.saveGState(); c.translateBy(x: text.baseline.x, y: text.baseline.y); c.scaleBy(x: 1, y: -1)
        c.textMatrix = .identity; c.textPosition = .zero; CTLineDraw(text.line, c); c.restoreGState()
    }
    private static func backgroundCGColor(_ b: AnnotationBackground) -> CGColor {
        switch b { case .none: NSColor.clear.cgColor; case .midnight: NSColor(calibratedRed:0.12,green:0.15,blue:0.22,alpha:1).cgColor; case .lavender: NSColor(calibratedRed:0.47,green:0.36,blue:0.67,alpha:1).cgColor; case .peach: NSColor(calibratedRed:0.9,green:0.5,blue:0.36,alpha:1).cgColor }
    }
    static func drawBackground(_ background: AnnotationBackground, in context: CGContext, size: CGSize) {
        let colors: [CGColor]
        switch background {
        case .none: colors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
        case .midnight: colors = [NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.18, alpha: 1).cgColor, NSColor(calibratedRed: 0.23, green: 0.28, blue: 0.39, alpha: 1).cgColor]
        case .lavender: colors = [NSColor(calibratedRed: 0.36, green: 0.27, blue: 0.57, alpha: 1).cgColor, NSColor(calibratedRed: 0.64, green: 0.49, blue: 0.79, alpha: 1).cgColor]
        case .peach: colors = [NSColor(calibratedRed: 0.84, green: 0.36, blue: 0.3, alpha: 1).cgColor, NSColor(calibratedRed: 0.98, green: 0.66, blue: 0.43, alpha: 1).cgColor]
        }
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) else { return }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
    }
}
