import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationShapeEditModelTests {
    @Test(arguments: [EditorAnnotation.Kind.arrow, .rectangle, .filledRectangle, .ellipse, .line, .freehand, .text, .step])
    func appearanceControlsEditSelectionAndUndoSeparately(kind: EditorAnnotation.Kind) {
        let model = makeModel()
        let original = EditorAnnotation(kind: kind, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 140, y: 100),
            color: .systemBlue, width: 10, text: "Label", textSize: kind == .text ? 48 : nil,
            arrowStyle: .sketch, arrowStroke: .dashed)
        model.annotations = [original]
        model.selectedID = original.id
        model.markSaved()
        #expect(model.currentColor == .systemBlue)
        #expect(model.currentStrokeWidth == 10)
        #expect(!model.canUndo)
        #expect(!model.hasUnsavedChanges)

        // The selected color may differ even when the new value matches the tool default.
        model.color = .systemRed
        let recolored = model.annotations[0]
        #expect(recolored.color == .systemRed)
        #expect(recolored.width == original.width)
        #expect(model.selectedID == original.id)
        model.adjustToolSize(by: 1)
        let resized = model.annotations[0]
        #expect(resized.width == 11)
        if kind == .text { #expect(resized.textSize == nil) }
        #expect(resized.arrowStyle == original.arrowStyle)
        #expect(resized.arrowStroke == original.arrowStroke)
        #expect(resized.arrowSeed == original.arrowSeed)
        #expect(resized.start == original.start)
        #expect(resized.end == original.end)
        #expect(model.hasUnsavedChanges)

        model.undo()
        #expect(model.annotations == [recolored])
        model.undo()
        #expect(model.annotations == [original])
        #expect(!model.canUndo)
        #expect(!model.hasUnsavedChanges)
        model.redo()
        model.redo()
        #expect(model.annotations == [resized])
    }

    @Test func groupAppearanceChangesKeepSelectionAndRespectRedactionAndPixelation() {
        let model = makeModel()
        model.annotations = [
            EditorAnnotation(kind: .rectangle, start: .zero, end: CGPoint(x: 100, y: 100)),
            EditorAnnotation(kind: .ellipse, start: .zero, end: CGPoint(x: 100, y: 100)),
            EditorAnnotation(kind: .redaction, start: .zero, end: CGPoint(x: 100, y: 100), color: .black),
            EditorAnnotation(kind: .pixelation, start: .zero, end: CGPoint(x: 100, y: 100), color: .black),
            EditorAnnotation(kind: .line, start: .zero, end: CGPoint(x: 100, y: 100))
        ]
        let originals = model.annotations
        let ids = Set(originals.prefix(4).map(\.id))
        model.selectedIDs = ids
        model.color = .systemGreen
        #expect(model.annotations[0].color == .systemGreen)
        #expect(model.annotations[1].color == .systemGreen)
        #expect(model.annotations[2] == originals[2])
        #expect(model.annotations[3] == originals[3])
        #expect(model.annotations[4] == originals[4])
        #expect(model.selectedIDs == ids)
        let recolored = model.annotations
        model.strokeWidth = 20
        #expect(model.annotations[0].width == 20)
        #expect(model.annotations[1].width == 20)
        #expect(model.annotations[2] == originals[2])
        #expect(model.annotations[3].width == 20)
        #expect(model.annotations[4] == originals[4])
        #expect(model.selectedIDs == ids)
        model.undo()
        #expect(model.annotations == recolored)
        model.undo()
        #expect(model.annotations == originals)
        #expect(!model.canUndo)
    }

    @Test func unchangedAppearanceAndHandleClicksPreserveRedo() {
        let model = makeModel()
        let original = EditorAnnotation(kind: .rectangle, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 140, y: 100))
        model.annotations = [original]
        model.selectedID = original.id
        model.color = .systemBlue
        model.undo()
        model.selectedID = original.id
        model.color = original.color
        model.strokeWidth = original.width
        #expect(model.beginShapeEdit(handle: .corner(.bottomRight), at: original.end))
        model.continueDrag(to: original.end)
        model.endDrag()
        #expect(model.annotations == [original])
        #expect(!model.canUndo)
        #expect(model.canRedo)
        model.redo()
        #expect(model.annotations[0].color == .systemBlue)
    }

    @Test func drawingToolAppearanceOnlyChangesNewAnnotations() {
        let model = makeModel()
        let original = EditorAnnotation(kind: .rectangle, start: .zero, end: CGPoint(x: 100, y: 100))
        model.annotations = [original]
        model.selectedID = original.id
        model.tool = .ellipse
        model.color = .systemBlue
        model.strokeWidth = 20
        #expect(model.annotations == [original])
        #expect(!model.canUndo)
        #expect(model.currentColor == .systemBlue)
        #expect(model.currentStrokeWidth == 20)
        model.begin(at: CGPoint(x: 150, y: 100))
        model.continueDrag(to: CGPoint(x: 200, y: 150))
        model.endDrag()
        #expect(model.annotations[0] == original)
        #expect(model.annotations[1].color == .systemBlue)
        #expect(model.annotations[1].width == 20)
    }

    @Test func clearingSelectionOrUndoingDuringResizeStopsTheGesture() {
        let model = makeModel()
        let original = EditorAnnotation(kind: .rectangle, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 140, y: 100))
        model.annotations = [original]
        model.selectedID = original.id
        #expect(model.beginShapeEdit(handle: .corner(.bottomRight), at: original.end))
        model.continueDrag(to: CGPoint(x: 180, y: 120))
        let resized = model.annotations[0]
        model.clearSelection()
        model.continueDrag(to: CGPoint(x: 200, y: 150))
        model.endDrag()
        #expect(model.annotations == [resized])
        #expect(model.selectedIDs.isEmpty)
        model.undo()
        model.selectedID = original.id
        #expect(model.beginShapeEdit(handle: .corner(.bottomRight), at: original.end))
        model.continueDrag(to: CGPoint(x: 180, y: 120))
        model.undo()
        model.continueDrag(to: CGPoint(x: 200, y: 150))
        model.endDrag()
        #expect(model.annotations == [original])
        #expect(!model.canUndo)
    }

    @Test func handleTypesAndSingleSelectionAreRequired() {
        let model = makeModel()
        let rectangle = EditorAnnotation(kind: .rectangle, start: .zero, end: CGPoint(x: 100, y: 100))
        let line = EditorAnnotation(kind: .line, start: .zero, end: CGPoint(x: 100, y: 100))
        model.annotations = [rectangle, line]
        model.selectedIDs = [rectangle.id, line.id]
        #expect(!model.beginShapeEdit(handle: .corner(.bottomRight), at: rectangle.end))
        model.selectedID = line.id
        #expect(!model.beginShapeEdit(handle: .corner(.bottomRight), at: line.end))
        model.selectedID = rectangle.id
        #expect(!model.beginShapeEdit(handle: .end, at: rectangle.end))
        #expect(model.annotations == [rectangle, line])
        #expect(!model.canUndo)
    }

    private func makeModel() -> AnnotationEditorModel {
        let context = CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return AnnotationEditorModel(image: NSImage(cgImage: context.makeImage()!, size: CGSize(width: 300, height: 200)), sourceURL: nil)
    }
}
