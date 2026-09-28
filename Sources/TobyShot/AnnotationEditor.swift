import AppKit
import Carbon
import CoreText
import SwiftUI

/// A self-contained annotation editor window. The source image is retained at full pixel
/// resolution; the canvas only scales its presentation and the renderer exports pixels.
public final class AnnotationEditorWindow: NSWindowController, NSWindowDelegate {
    private let editorModel: AnnotationEditorModel
    private let shortcuts: HotKeyManager
    private var keyMonitor: Any?

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
        if UserDefaults.standard.bool(forKey: "editorAlwaysOnTop") {
            window.level = .floating
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window,
                  NSApp.keyWindow === window,
                  (event.window == nil || event.window === window), window.attachedSheet == nil,
                  NSApp.modalWindow == nil,
                  !Self.isEditingText(in: window) else { return event }
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
        alert.informativeText = "Use Done or Save as… to save your changes before closing."
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
        if let action = shortcuts.action(for: event, scope: .editor) {
            switch action {
            case .editorCopyObject:
                guard let image = editorModel.renderedSelection() else { return false }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            case .editorDuplicate:
                guard editorModel.duplicateSelection() else { return false }
            case .editorSave:
                guard onSave(editorModel.renderedImage(), false) else { return true }
                editorModel.markSaved()
            case .editorSaveAs:
                guard onSave(editorModel.renderedImage(), true) else { return true }
                editorModel.markSaved()
            case .editorCopyScreenshot:
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
            editorModel.selectedID = nil
            editorModel.tool = .select
            return true
        }
        return false
    }

    private func saveAndClose() {
        guard onSave(editorModel.renderedImage(), false) else { return }
        editorModel.markSaved()
        close()
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
    var arrowStyle: AnnotationArrowStyle = .clean
    var arrowStroke: AnnotationArrowStroke = .solid
    var arrowSeed: UInt64 = .random(in: 1...UInt64.max)
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
    @Published var image: NSImage
    @Published var tool: AnnotationTool = .select {
        didSet { finishTextEditing() }
    }
    @Published var selectedID: UUID?
    @Published private(set) var editingTextID: UUID?
    @Published var showBackgroundPanel = false
    @Published var color: NSColor = .systemRed {
        didSet { updateEditingTextAppearance(color: color) }
    }
    @Published var strokeWidth: CGFloat = 5 {
        didSet { updateEditingTextAppearance(width: strokeWidth) }
    }
    @Published private(set) var background: AnnotationBackground = .none
    @Published private(set) var padding: CGFloat = 36
    @Published private(set) var cornerRadius: CGFloat = 18
    @Published var zoom: CGFloat = 0
    @Published var annotations: [EditorAnnotation] = []
    @Published var cropRect: CGRect?
    @Published var showColorNames = UserDefaults.standard.bool(forKey: "showColorNames")
    @Published var smoothDrawing = UserDefaults.standard.object(forKey: "smoothDrawing") == nil || UserDefaults.standard.bool(forKey: "smoothDrawing")
    @Published var annotationShadow = UserDefaults.standard.object(forKey: "annotationShadow") == nil || UserDefaults.standard.bool(forKey: "annotationShadow")
    let sourceURL: URL?
    weak var windowController: AnnotationEditorWindow?
    private var undoStack: [EditorState] = []
    private var redoStack: [EditorState] = []
    private var stepCount = 0
    private var draggingAnnotation: UUID?
    private var dragOrigin: CGPoint = .zero
    private var movingOriginal: EditorAnnotation?
    private var moveCheckpointed = false
    private var textResize: AnnotationTextResize?
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
        isEditingBackground = isEditing
        backgroundEditCheckpointed = false
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
    private func restore(_ state: EditorState) { image = state.image; annotations = state.annotations; cropRect = state.crop; background = state.background; padding = state.padding; cornerRadius = state.cornerRadius; stepCount = annotations.filter { $0.kind == .step }.map(\.step).max() ?? 0; selectedID = nil }
    func deleteSelection() {
        guard let id = selectedID, annotations.contains(where: { $0.id == id }) else { selectedID = nil; return }
        checkpoint(); annotations.removeAll { $0.id == id }
    }

    @discardableResult
    func duplicateSelection() -> Bool {
        guard let id = selectedID, let selected = annotations.first(where: { $0.id == id }) else { return false }
        checkpoint()
        var copy = translated(selected, by: CGPoint(x: 12, y: 12))
        copy.id = UUID()
        annotations.append(copy)
        selectedID = copy.id
        return true
    }

    func adjustToolSize(by delta: CGFloat) {
        strokeWidth = min(40, max(1, strokeWidth + delta))
    }

    func renderedSelection() -> NSImage? {
        guard let id = selectedID, let annotation = annotations.first(where: { $0.id == id }) else { return nil }
        return AnnotationRenderer.render(annotation: annotation, sourceImage: image)
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
    }

    private func updateEditingTextAppearance(color: NSColor? = nil, width: CGFloat? = nil) {
        guard let id = editingTextID, let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        if let color { annotations[index].color = color }
        if let width { annotations[index].width = width; annotations[index].textSize = nil }
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

    func begin(at point: CGPoint) {
        finishTextEditing()
        if tool == .select {
            if let hit = annotations.last(where: { hitTest($0, point: point) }) {
                moveCheckpointed = false
                selectedID = hit.id; draggingAnnotation = hit.id; dragOrigin = point; movingOriginal = hit
            } else { selectedID = nil }
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
        if tool == .step { checkpoint(); stepCount += 1; annotations.append(make(.step, at: point, end: point, step: stepCount)); return }
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
    }

    func continueDrag(to point: CGPoint) {
        guard editingTextID == nil else { return }
        if let resize = textResize, let index = annotations.firstIndex(where: { $0.id == resize.original.id }) {
            let resized = resize.annotation(at: point)
            guard resized != annotations[index] else { return }
            if !moveCheckpointed { checkpoint(); selectedID = resize.original.id; moveCheckpointed = true }
            annotations[index] = resized
            return
        }
        if tool == .select, let id = draggingAnnotation, let original = movingOriginal,
           let index = annotations.firstIndex(where: { $0.id == id }) {
            let delta = CGPoint(x: point.x - dragOrigin.x, y: point.y - dragOrigin.y)
            guard delta != .zero || moveCheckpointed else { return }
            if !moveCheckpointed { checkpoint(); selectedID = id; moveCheckpointed = true }
            annotations[index] = translated(original, by: delta); return
        }
        if tool == .crop { cropRect = rect(from: cropAnchor ?? point, to: point); return }
        guard let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].end = point
        if annotations[index].kind == .freehand {
            if smoothDrawing, let last = annotations[index].points.last {
                annotations[index].points.append(CGPoint(x: (last.x + point.x) / 2, y: (last.y + point.y) / 2))
            } else { annotations[index].points.append(point) }
        }
    }

    func endDrag() {
        textResize = nil
        if tool == .freehand, let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id }), annotations[index].points.last != annotations[index].end {
            annotations[index].points.append(annotations[index].end)
        }
        draggingAnnotation = nil; movingOriginal = nil
        if tool == .crop {
            if let cropRect, cropRect.width > 2, cropRect.height > 2 { applyCrop(cropRect) }
            cropAnchor = nil; cropRect = nil
        }
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

    func renderedImage(excluding annotationID: UUID? = nil) -> NSImage {
        AnnotationRenderer.render(image: image, annotations: annotations.filter { $0.id != annotationID }, background: background, padding: padding, cornerRadius: cornerRadius)
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
        HStack(spacing: 5) {
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
                    Button { model.color = value } label: { Label(name, systemImage: model.color == value ? "checkmark.circle.fill" : "circle.fill") }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "circle.fill").foregroundStyle(Color(nsColor: model.color)).font(.system(size: 16))
                    if model.showColorNames, let name = palette.first(where: { $0.1 == model.color })?.0 { Text(name) }
                }.padding(5)
            }.menuStyle(.borderlessButton).fixedSize().help("Annotation color")
            Picker("Stroke width", selection: $model.strokeWidth) {
                ForEach(Array(Set([CGFloat(2), 5, 10, 20, model.strokeWidth])).sorted(), id: \.self) { width in
                    Text("\(Int(width)) pt").tag(width)
                }
            }.labelsHidden().pickerStyle(.menu).frame(width: 74).help("Stroke width; also controls text size")
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
        HStack(spacing: 7) {
            Button("Save as…") { if onSave(model.renderedImage(), true) { model.markSaved() } }
                .buttonStyle(.bordered).fixedSize().help("Save as… (\(shortcuts.label(for: .editorSaveAs)))")
            Button("Done") { if onSave(model.renderedImage(), false) { model.markSaved(); model.windowController?.close() } }
                .buttonStyle(.borderedProminent).fixedSize().help("Save and close (⌘↩)")
        }.fixedSize()
    }

    private func toolButton(_ tool: AnnotationTool, action: ShortcutAction) -> some View {
        Button { model.tool = tool } label: { Image(systemName: tool.symbol).frame(width: 25, height: 24).background(model.tool == tool ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6)) }
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
            Text("\(Int(model.pixelSize.width)) × \(Int(model.pixelSize.height)) px").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { onCopy(model.renderedImage()) } label: { Label("Copy", systemImage: "doc.on.doc") }.help("Copy rendered image (\(shortcuts.label(for: .editorCopyScreenshot)))")
            Button { onPin(model.renderedImage()) } label: { Label("Pin", systemImage: "pin") }.help("Pin rendered image (\(shortcuts.label(for: .editorPin)))")
        }.padding(.horizontal, 14).padding(.vertical, 9).background(Color(nsColor: .controlBackgroundColor))
    }
    private var helpPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Annotation shortcuts").font(.title2.bold())
            Text("Move \(shortcuts.label(for: .moveTool))   Crop \(shortcuts.label(for: .cropTool))   Draw \(shortcuts.label(for: .drawTool))   Line \(shortcuts.label(for: .lineTool))\nText \(shortcuts.label(for: .textTool))   Arrow \(shortcuts.label(for: .arrowTool))   Counter \(shortcuts.label(for: .counterTool))   Ellipse \(shortcuts.label(for: .ellipseTool))\nRedact \(shortcuts.label(for: .redactionTool))   Rectangle \(shortcuts.label(for: .rectangleTool))   Filled rectangle \(shortcuts.label(for: .filledRectangleTool))   Pixelate \(shortcuts.label(for: .pixelateTool))\nBackground \(shortcuts.label(for: .backgroundTool))   Smaller/larger \(shortcuts.label(for: .decreaseToolSize))/\(shortcuts.label(for: .increaseToolSize))\nCopy object \(shortcuts.label(for: .editorCopyObject))   Duplicate \(shortcuts.label(for: .editorDuplicate))   Save \(shortcuts.label(for: .editorSave))   Save as \(shortcuts.label(for: .editorSaveAs))\nCopy image \(shortcuts.label(for: .editorCopyScreenshot))   Print \(shortcuts.label(for: .editorPrint))   Pin \(shortcuts.label(for: .editorPin))\nUndo ⌘Z   Redo ⇧⌘Z   Delete Remove   Escape Select")
            Text("Drag on the canvas to draw. Select and drag an annotation to move it. Click with Text to type on the image; double-click existing text to edit it. Drag a text corner to resize. Return finishes editing, Shift-Return adds a line. Crop applies when you finish the crop selection.").foregroundStyle(.secondary)
            HStack { Spacer(); Button("Close") { showHelp = false }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 420)
    }
}

enum AnnotationRenderer {
    static func render(annotation: EditorAnnotation, sourceImage: NSImage) -> NSImage? {
        guard let source = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let geometry = AnnotationGeometry(annotation, imageSize: CGSize(width: source.width, height: source.height))
        let bounds = geometry.exportBounds
        guard !bounds.isNull, !bounds.isEmpty else { return nil }
        let width = max(1, Int(ceil(bounds.width)))
        let height = max(1, Int(ceil(bounds.height)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        var sourcePixels = [UInt8](repeating: 0, count: annotation.kind == .pixelation ? source.width * source.height * 4 : 0)
        if !sourcePixels.isEmpty {
            sourcePixels.withUnsafeMutableBytes { raw in
                if let bitmap = CGContext(data: raw.baseAddress, width: source.width, height: source.height, bitsPerComponent: 8,
                                          bytesPerRow: source.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    bitmap.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
                }
            }
        }
        draw(annotation, geometry: geometry, in: context, pixelSize: CGSize(width: source.width, height: source.height), sourcePixels: sourcePixels)
        guard let rendered = context.makeImage() else { return nil }
        return NSImage(cgImage: rendered, size: NSSize(width: width, height: height))
    }

    static func render(image: NSImage, annotations: [EditorAnnotation], background: AnnotationBackground = .none, padding: CGFloat = 0, cornerRadius: CGFloat = 0) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let pad = background == .none ? 0 : Int(max(0, padding.rounded()))
        let width = cg.width + pad * 2, height = cg.height + pad * 2
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        drawBackground(background, in: context, size: CGSize(width: width, height: height))
        if cornerRadius > 0, background != .none {
            let bounds = CGRect(x: pad, y: pad, width: cg.width, height: cg.height)
            context.saveGState(); context.addPath(CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)); context.clip(); context.draw(cg, in: bounds); context.restoreGState()
        } else { context.draw(cg, in: CGRect(x: pad, y: pad, width: cg.width, height: cg.height)) }
        // Use a top-left image coordinate system for all annotation geometry.
        context.saveGState(); context.translateBy(x: CGFloat(pad), y: CGFloat(height - pad)); context.scaleBy(x: 1, y: -1)
        var sourcePixels = [UInt8](repeating: 0, count: annotations.contains(where: { $0.kind == .pixelation }) ? cg.width * cg.height * 4 : 0)
        if !sourcePixels.isEmpty {
        sourcePixels.withUnsafeMutableBytes { raw in
            if let bitmap = CGContext(data: raw.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                bitmap.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            }
        }
        }
        for annotation in annotations { draw(annotation, in: context, pixelSize: CGSize(width: cg.width, height: cg.height), sourcePixels: sourcePixels) }
        context.restoreGState()
        guard let result = context.makeImage() else { return image }
        return NSImage(cgImage: result, size: NSSize(width: width, height: height))
    }

    private static func draw(_ a: EditorAnnotation, geometry suppliedGeometry: AnnotationGeometry? = nil, in c: CGContext, pixelSize: CGSize, sourcePixels: [UInt8]) {
        let geometry = suppliedGeometry ?? AnnotationGeometry(a, imageSize: pixelSize)
        let col = a.color.cgColor
        c.saveGState(); c.setStrokeColor(col); c.setFillColor(col); c.setLineWidth(geometry.lineWidth); c.setLineCap(.round); c.setLineJoin(.round)
        if let shadow = geometry.shadow { c.setShadow(offset: shadow.offset, blur: shadow.blur, color: shadow.color) }
        if a.kind == .pixelation {
            pixelate(a, rect: geometry.pixelationRect, in: c, imageSize: pixelSize, sourcePixels: sourcePixels)
        } else {
            if a.kind == .redaction { c.setFillColor(NSColor.black.cgColor) }
            if a.kind == .rectangle {
                c.stroke(geometry.path.boundingBoxOfPath)
            } else {
                c.addPath(geometry.path)
                if geometry.stroked { c.strokePath() } else { c.fillPath() }
            }
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
    private static func drawBackground(_ background: AnnotationBackground, in context: CGContext, size: CGSize) {
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
