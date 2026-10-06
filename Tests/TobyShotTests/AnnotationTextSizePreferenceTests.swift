import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationTextSizePreferenceTests {
    private let preferenceKey = "annotationTextSize"

    @Test
    func unsavedTextSizeKeepsOriginalDefaultAndSelectionDoesNotRememberIt() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(defaults: defaults)
        let existing = text("Existing", at: CGPoint(x: 24, y: 24), size: 37)
        model.annotations = [existing]
        model.selectedID = existing.id

        #expect(model.currentStrokeWidth == 5)
        #expect(defaults.object(forKey: preferenceKey) == nil)
        model.tool = .text
        model.begin(at: CGPoint(x: 300, y: 200))

        let created = try #require(model.annotations.last)
        #expect(model.annotations.count == 2)
        #expect(AnnotationTextLayout.fontSize(for: created) == 25)
        #expect(created.width == 5)
        #expect(model.annotations.first == existing)
        #expect(defaults.object(forKey: preferenceKey) == nil)
    }

    @Test(arguments: [7.0, 401.0])
    func invalidRememberedSizesFallBackToOriginalDefault(size: Double) throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(size, forKey: preferenceKey)
        let model = makeModel(defaults: defaults)
        model.tool = .text

        #expect(model.currentStrokeWidth == 5)
        model.begin(at: CGPoint(x: 300, y: 200))
        let created = try #require(model.annotations.first)
        #expect(AnnotationTextLayout.fontSize(for: created) == 25)
        #expect(created.width == 5)
        #expect(defaults.double(forKey: preferenceKey) == size)
    }

    @Test
    func sizeControlAppliesToNewAndEditedTextAndSurvivesModelReload() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(defaults: defaults)
        let alreadyOpenModel = makeModel(defaults: defaults)
        model.tool = .text
        model.strokeWidth = 8.4
        #expect(defaults.double(forKey: preferenceKey) == 42)
        #expect(model.currentStrokeWidth == 8.4)
        model.begin(at: CGPoint(x: 20, y: 20))
        model.updateText("First label")
        let first = try #require(model.annotations.first)
        #expect(AnnotationTextLayout.fontSize(for: first) == 42)
        #expect(first.width == 8.4)
        model.finishTextEditing()

        model.tool = .text
        model.begin(at: CGPoint(x: 300, y: 200))
        model.updateText("Second label")
        #expect(AnnotationTextLayout.fontSize(for: try #require(model.annotations.last)) == 42)
        model.finishTextEditing()

        #expect(model.beginTextEditing(first.id))
        model.strokeWidth = 12
        #expect(AnnotationTextLayout.fontSize(for: try #require(model.annotations.first)) == 60)
        #expect(AnnotationTextLayout.fontSize(for: try #require(model.annotations.last)) == 42)
        #expect(defaults.double(forKey: preferenceKey) == 60)
        model.finishTextEditing()

        model.selectedID = first.id
        model.strokeWidth = 8
        #expect(AnnotationTextLayout.fontSize(for: try #require(model.annotations.first)) == 40)
        #expect(AnnotationTextLayout.fontSize(for: try #require(model.annotations.last)) == 42)
        #expect(defaults.double(forKey: preferenceKey) == 40)

        alreadyOpenModel.tool = .text
        #expect(alreadyOpenModel.currentStrokeWidth == 8)
        alreadyOpenModel.begin(at: CGPoint(x: 500, y: 350))
        #expect(AnnotationTextLayout.fontSize(for: try #require(alreadyOpenModel.annotations.first)) == 40)
        #expect(try #require(alreadyOpenModel.annotations.first).width == 8)

        let reloaded = makeModel(defaults: UserDefaults(suiteName: suite)!)
        reloaded.tool = .text
        #expect(reloaded.currentStrokeWidth == 8)
        reloaded.begin(at: CGPoint(x: 600, y: 430))
        #expect(AnnotationTextLayout.fontSize(for: try #require(reloaded.annotations.first)) == 40)
        #expect(try #require(reloaded.annotations.first).width == 8)
        #expect(AnnotationTextLayout.fontSize(for: try #require(model.annotations.first)) == 40)
    }

    @Test(arguments: [8.25, 250.5])
    func resizeRemembersFinalFractionalSizeAcrossUndoRedoAndModels(size: CGFloat) throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(defaults: defaults)
        let original = text("Resize", at: CGPoint(x: 50, y: 50), size: 25)
        model.annotations = [original]
        model.selectedID = original.id
        let bounds = model.textSelectionBounds(original)
        let corner = AnnotationResizeCorner.bottomRight
        let handle = corner.point(in: bounds)
        let anchor = corner.opposite.point(in: bounds)
        let factor = size / AnnotationTextLayout.fontSize(for: original)
        let target = CGPoint(x: anchor.x + (handle.x - anchor.x) * factor,
                             y: anchor.y + (handle.y - anchor.y) * factor)

        #expect(model.beginTextResize(corner: corner, at: handle))
        model.continueDrag(to: target)
        model.endDrag()
        let resizedSize = AnnotationTextLayout.fontSize(for: try #require(model.annotations.first))
        #expect(abs(resizedSize - size) < 0.0001)
        #expect(defaults.double(forKey: preferenceKey) == Double(resizedSize))

        model.undo()
        #expect(defaults.double(forKey: preferenceKey) == Double(resizedSize))
        model.redo()
        #expect(defaults.double(forKey: preferenceKey) == Double(resizedSize))

        let anotherEditor = makeModel(defaults: UserDefaults(suiteName: suite)!)
        anotherEditor.tool = .text
        anotherEditor.begin(at: CGPoint(x: 400, y: 250))
        #expect(AnnotationTextLayout.fontSize(for: try #require(anotherEditor.annotations.first)) == resizedSize)
        #expect(try #require(anotherEditor.annotations.first).width == resizedSize / 5)
    }

    @Test
    func shapeSizeAndNoOpTextResizeDoNotReplaceRememberedTextSize() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(defaults: defaults)
        model.tool = .text
        model.strokeWidth = 10
        model.begin(at: CGPoint(x: 30, y: 30))
        model.updateText("Remember this")
        model.finishTextEditing()

        let shape = EditorAnnotation(kind: .rectangle, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 160, y: 150))
        model.annotations.append(shape)
        model.tool = .select
        model.selectedID = shape.id
        model.strokeWidth = 14
        #expect(defaults.double(forKey: preferenceKey) == 50)

        let annotation = text("Keep this size", at: CGPoint(x: 30, y: 180), size: 37)
        model.annotations.append(annotation)
        model.selectedID = annotation.id
        let bounds = model.textSelectionBounds(annotation)
        let corner = AnnotationResizeCorner.bottomRight
        let handle = corner.point(in: bounds)
        #expect(model.beginTextResize(corner: corner, at: handle))
        model.continueDrag(to: handle)
        model.endDrag()
        #expect(defaults.double(forKey: preferenceKey) == 50)
        #expect(model.annotations.last == annotation)

        model.tool = .text
        model.begin(at: CGPoint(x: 350, y: 250))
        #expect(AnnotationTextLayout.fontSize(for: try #require(model.annotations.last)) == 50)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "TobyShot.AnnotationTextSizePreferenceTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func makeModel(defaults: UserDefaults) -> AnnotationEditorModel {
        let size = CGSize(width: 640, height: 480)
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = NSImage(cgImage: context.makeImage()!, size: size)
        return AnnotationEditorModel(image: image, sourceURL: nil, defaults: defaults)
    }

    private func text(_ value: String, at point: CGPoint, size: CGFloat) -> EditorAnnotation {
        var annotation = EditorAnnotation(kind: .text, start: point, end: point, text: value)
        annotation.textSize = size
        return annotation
    }
}
