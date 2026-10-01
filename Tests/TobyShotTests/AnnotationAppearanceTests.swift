import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationAppearanceTests {
    @Test func newAnnotationsReadSavedStylesAndKeepThemThroughHistoryAndDuplication() throws {
        let defaults = UserDefaults.standard
        let keys = ["annotationFont", "annotationArrowStyle", "annotationArrowStroke"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) } }
        defaults.set("excalifont", forKey: keys[0])
        defaults.set("handDrawn", forKey: keys[1])
        defaults.set("dashed", forKey: keys[2])
        let model = AnnotationEditorModel(image: sourceImage(), sourceURL: nil)
        model.tool = .arrow
        model.begin(at: CGPoint(x: 20, y: 80))
        model.continueDrag(to: CGPoint(x: 200, y: 30))
        model.endDrag()
        let arrow = try #require(model.annotations.first)
        #expect(arrow.arrowStyle == .handDrawn)
        #expect(arrow.arrowStroke == .dashed)
        let before = try #require(model.renderedSelection())

        defaults.set("clean", forKey: keys[1])
        defaults.set("solid", forKey: keys[2])
        #expect(model.annotations == [arrow])
        model.undo()
        #expect(model.annotations.isEmpty)
        model.redo()
        #expect(model.annotations == [arrow])
        model.selectedID = arrow.id
        #expect(model.duplicateSelection())
        let copy = try #require(model.annotations.last)
        #expect(copy.id != arrow.id)
        #expect(copy.arrowSeed == arrow.arrowSeed)
        #expect(copy.arrowStyle == arrow.arrowStyle)
        #expect(copy.arrowStroke == arrow.arrowStroke)
        #expect(try ImageOutput.data(#require(model.renderedSelection()), format: "PNG") == ImageOutput.data(before, format: "PNG"))

        // The same open editor picks up new settings without restyling existing objects.
        model.tool = .arrow
        model.begin(at: CGPoint(x: 30, y: 100))
        model.continueDrag(to: CGPoint(x: 210, y: 50))
        model.endDrag()
        #expect(model.annotations.last?.arrowStyle == .clean)
        #expect(model.annotations.last?.arrowStroke == .solid)
        model.tool = .text
        model.begin(at: CGPoint(x: 20, y: 20))
        model.updateText("Æblegrød")
        model.finishTextEditing()
        let text = try #require(model.annotations.last)
        #expect(text.font == .excalifont)
        defaults.set("virgil", forKey: keys[0])
        model.beginTextEditing(text.id)
        model.updateText("Æblegrød!")
        model.finishTextEditing()
        #expect(model.annotations.last?.font == .excalifont)
        model.undo()
        #expect(model.annotations.last == text)
    }

    @Test func unknownPreferencesFallBackToOriginalAppearance() throws {
        let defaults = UserDefaults.standard
        let keys = ["annotationFont", "annotationArrowStyle", "annotationArrowStroke"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) } }
        for key in keys { defaults.set("unknown-future-style", forKey: key) }
        let model = AnnotationEditorModel(image: sourceImage(), sourceURL: nil)
        model.tool = .arrow
        model.begin(at: CGPoint(x: 20, y: 80))
        model.continueDrag(to: CGPoint(x: 200, y: 30))
        model.endDrag()
        let arrow = try #require(model.annotations.first)
        #expect(arrow.font == .system)
        #expect(arrow.arrowStyle == .clean)
        #expect(arrow.arrowStroke == .solid)
    }

    @Test(arguments: [AnnotationTool.rectangle, .filledRectangle, .ellipse, .line, .step])
    func shapesUseExistingStyleDefaultsAndPreserveThemThroughEdits(tool: AnnotationTool) throws {
        let defaults = UserDefaults.standard
        let keys = ["annotationArrowStyle", "annotationArrowStroke"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) } }
        defaults.set("handDrawn", forKey: keys[0])
        defaults.set("dashed", forKey: keys[1])
        let model = AnnotationEditorModel(image: sourceImage(), sourceURL: nil)
        model.tool = tool
        model.begin(at: CGPoint(x: 40, y: 50))
        if tool != .step { model.continueDrag(to: CGPoint(x: 180, y: 110)) }
        model.endDrag()
        let original = try #require(model.annotations.first)
        #expect(original.arrowStyle == .handDrawn)
        #expect(original.arrowStroke == .dashed)
        var clean = original
        clean.arrowStyle = .clean
        #expect(AnnotationGeometry(original).path != AnnotationGeometry(clean).path)
        model.selectedID = original.id
        let before = try ImageOutput.data(#require(model.renderedSelection()), format: "PNG")

        defaults.set("clean", forKey: keys[0])
        defaults.set("solid", forKey: keys[1])
        model.tool = .select
        model.begin(at: original.start)
        model.continueDrag(to: CGPoint(x: original.start.x + 20, y: original.start.y + 12))
        model.endDrag()
        let moved = try #require(model.annotations.first)
        #expect(moved.arrowSeed == original.arrowSeed)
        #expect(try ImageOutput.data(#require(model.renderedSelection()), format: "PNG") == before)
        #expect(model.duplicateSelection())
        let copy = try #require(model.annotations.last)
        #expect(copy.id != original.id)
        #expect(copy.arrowStyle == .handDrawn)
        #expect(copy.arrowStroke == .dashed)
        #expect(copy.arrowSeed == original.arrowSeed)
        #expect(try ImageOutput.data(#require(model.renderedSelection()), format: "PNG") == before)
        model.undo()
        #expect(model.annotations == [moved])
        model.undo()
        #expect(model.annotations == [original])
        model.redo()
        #expect(model.annotations == [moved])

        // The open editor takes the new defaults only when placing another shape.
        model.tool = tool
        model.begin(at: CGPoint(x: 50, y: 60))
        if tool != .step { model.continueDrag(to: CGPoint(x: 190, y: 120)) }
        model.endDrag()
        #expect(model.annotations.last?.arrowStyle == .clean)
        #expect(model.annotations.last?.arrowStroke == .solid)
        #expect(model.annotations.first == moved)
    }

    private func sourceImage() -> NSImage {
        let context = CGContext(data: nil, width: 260, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return NSImage(cgImage: context.makeImage()!, size: CGSize(width: 260, height: 160))
    }
}
