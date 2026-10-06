import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationClipboardTests {
    @Test(arguments: ["Image", "File", "File & Image"])
    func copiesLatestPixelsInTheConfiguredFormatAndSurvivesEditorRelease(mode: String) throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "clipboardMode")
        defer { defaults.set(previous, forKey: "clipboardMode") }
        defaults.set(mode, forKey: "clipboardMode")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var clipboard: AnnotationClipboard? = AnnotationClipboard(pasteboard: board)
        let file = try #require(clipboard?.fileURL)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let model = makeModel()
        clipboard?.copy { model.renderedImage() }
        model.tool = .filledRectangle
        model.begin(at: CGPoint(x: 20, y: 20))
        model.continueDrag(to: CGPoint(x: 80, y: 60))
        model.endDrag()
        let latest = model.renderedImage()
        let expected = try ImageOutput.data(latest, format: "PNG")
        clipboard?.copy { latest }
        clipboard = nil

        #expect(board.types?.contains(.fileURL) == (mode != "Image"))
        #expect(board.types?.contains(.png) == (mode != "File"))
        #expect(board.types?.contains(.tiff) == (mode != "File"))
        if mode != "Image" {
            #expect(board.string(forType: .fileURL) == file.absoluteString)
            #expect(try Data(contentsOf: file) == expected)
        } else {
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
        if mode != "File" { #expect(board.data(forType: .png) == expected) }
    }

    @Test(arguments: [CGSize(width: 120, height: 90), CGSize(width: 6000, height: 4000)])
    func modelPublishesAndReplacesClipboardLazilyAcrossMainTurns(size: CGSize) async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "clipboardMode")
        defer { defaults.set(previous, forKey: "clipboardMode") }
        defaults.set("File & Image", forKey: "clipboardMode")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let clipboard = AnnotationClipboard(pasteboard: board)
        defer { try? FileManager.default.removeItem(at: clipboard.fileURL.deletingLastPathComponent()) }
        let model = makeModel(size: size)
        var renderCount = 0
        model.onImageChange = { render in
            clipboard.copy {
                renderCount += 1
                return render()
            }
        }

        model.tool = .text
        model.begin(at: CGPoint(x: 12, y: 16))
        model.updateText("First publication")
        await drainImageChanges()
        #expect(renderCount == 0)
        for character in " keeps up with typing" {
            model.updateText(model.annotations[0].text + String(character))
            await drainImageChanges()
            #expect(renderCount == 0)
        }
        #expect(board.types?.contains(.png) == true)
        #expect(board.types?.contains(.tiff) == true)
        #expect(board.types?.contains(.fileURL) == true)
        await drainImageChanges()
        #expect(renderCount == 0)

        // A later completed edit replaces the unconsumed provider.
        model.finishTextEditing()
        model.tool = .text
        model.begin(at: CGPoint(x: 12, y: 16))
        model.updateText("Newest publication")
        await drainImageChanges()
        #expect(renderCount == 0)
        let png = try #require(board.data(forType: .png))
        #expect(renderCount == 1)
        #expect(board.data(forType: .tiff) != nil)
        #expect(renderCount == 1)
        #expect(png == (try ImageOutput.data(model.renderedImage(), format: "PNG")))
    }

    @Test
    func replacingUnconsumedClipboardReleasesItsCapturedImage() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "clipboardMode")
        defer { defaults.set(previous, forKey: "clipboardMode") }
        defaults.set("Image", forKey: "clipboardMode")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let clipboard = AnnotationClipboard(pasteboard: board)
        var image: NSImage? = makeModel().image
        let isImageReleased = { [weak image] in image == nil }
        clipboard.copy { [snapshot = try #require(image)] in snapshot }
        image = nil
        #expect(!isImageReleased())

        var renderCount = 0
        clipboard.copy {
            renderCount += 1
            return makeModel().renderedImage()
        }
        #expect(isImageReleased())
        #expect(renderCount == 0)
        #expect(board.data(forType: .png) != nil)
        #expect(renderCount == 1)
    }

    @Test
    func quittingMaterializesEveryPromisedTypeBeforeTermination() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "clipboardMode")
        defer { defaults.set(previous, forKey: "clipboardMode") }
        defaults.set("File & Image", forKey: "clipboardMode")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let clipboard = AnnotationClipboard(pasteboard: board)
        defer { try? FileManager.default.removeItem(at: clipboard.fileURL.deletingLastPathComponent()) }
        let image = makeModel().renderedImage()
        let expected = try ImageOutput.data(image, format: "PNG")
        var renderCount = 0
        clipboard.copy {
            renderCount += 1
            return image
        }
        #expect(renderCount == 0)
        #expect(!FileManager.default.fileExists(atPath: clipboard.fileURL.path))

        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApplication.shared)
        #expect(renderCount == 1)
        #expect(try Data(contentsOf: clipboard.fileURL) == expected)
        #expect(board.string(forType: .fileURL) == clipboard.fileURL.absoluteString)
        #expect(board.data(forType: .png) == expected)
        #expect(board.data(forType: .tiff) != nil)
        #expect(renderCount == 1)
    }

    @Test
    func fileURLMaterializesCurrentPNGOnlyWhenReadAndSharesRenderedPNG() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "clipboardMode")
        defer { defaults.set(previous, forKey: "clipboardMode") }
        defaults.set("File & Image", forKey: "clipboardMode")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let clipboard = AnnotationClipboard(pasteboard: board)
        defer { try? FileManager.default.removeItem(at: clipboard.fileURL.deletingLastPathComponent()) }
        var renderCount = 0
        clipboard.copy {
            renderCount += 1
            return makeModel().renderedImage()
        }

        #expect(renderCount == 0)
        #expect(board.types?.contains(.fileURL) == true)
        #expect(!FileManager.default.fileExists(atPath: clipboard.fileURL.path))
        #expect(board.string(forType: .fileURL) == clipboard.fileURL.absoluteString)
        #expect(renderCount == 1)
        let filePNG = try Data(contentsOf: clipboard.fileURL)
        #expect(board.data(forType: .png) == filePNG)
        #expect(renderCount == 1)
        #expect(try ImageOutput.cgImage(#require(NSImage(data: filePNG))).width == 120)
    }

    @Test
    func deferredPublicationRemainsReadableAfterModelAndClipboardRelease() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "clipboardMode")
        defer { defaults.set(previous, forKey: "clipboardMode") }
        defaults.set("Image", forKey: "clipboardMode")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var model: AnnotationEditorModel? = makeModel()
        var clipboard: AnnotationClipboard? = AnnotationClipboard(pasteboard: board)
        let isModelReleased = { [weak model] in model == nil }
        var renderCount = 0
        model?.onImageChange = { render in
            clipboard?.copy {
                renderCount += 1
                return render()
            }
        }
        model?.tool = .text
        model?.begin(at: CGPoint(x: 12, y: 16))
        model?.updateText("Survives release")
        await drainImageChanges()
        #expect(renderCount == 0)
        model = nil
        clipboard = nil
        #expect(isModelReleased())
        #expect(board.data(forType: .png) != nil)
        #expect(renderCount == 1)
    }

    @Test
    func deferredEditorPublicationFreezesTextBackgroundAndSourceImage() async throws {
        let model = makeModel()
        var publications: [() -> NSImage] = []
        model.onImageChange = { publications.append($0) }
        model.tool = .text
        model.begin(at: CGPoint(x: 12, y: 16))
        model.updateText("Frozen text")
        await drainImageChanges()
        let frozen = try #require(publications.last)
        let expectedFrozen = try ImageOutput.data(model.renderedImage(), format: "PNG")
        model.finishTextEditing()
        model.updateBackground(style: .lavender)
        await drainImageChanges()
        let withBackground = try #require(publications.last)
        let expectedBackground = try ImageOutput.data(model.renderedImage(), format: "PNG")
        #expect(model.beginTextEditing(try #require(model.annotations.first?.id)))
        model.updateText("Newer text")
        model.image = makeModel(size: CGSize(width: 90, height: 60), color: .blue).image

        let deferredPNG = try ImageOutput.data(frozen(), format: "PNG")
        let currentPNG = try ImageOutput.data(model.renderedImage(), format: "PNG")
        #expect(deferredPNG == expectedFrozen)
        #expect(try ImageOutput.data(withBackground(), format: "PNG") == expectedBackground)
        #expect(deferredPNG != currentPNG)
        #expect(publications.count >= 2)
    }

    @Test
    func completedDrawingAndMovingCopyOnceWithFinalPixels() async throws {
        let model = makeModel()
        var copies: [NSImage] = []
        model.onImageChange = { copies.append($0()) }
        model.tool = .filledRectangle
        model.begin(at: CGPoint(x: 20, y: 20))
        model.continueDrag(to: CGPoint(x: 50, y: 40))
        await drainImageChanges()
        #expect(copies.isEmpty)
        model.continueDrag(to: CGPoint(x: 80, y: 60))
        model.endDrag()
        #expect(copies.count == 1)
        #expect(try ImageOutput.data(#require(copies.last), format: "PNG") == ImageOutput.data(model.renderedImage(), format: "PNG"))
        await drainImageChanges()
        #expect(copies.count == 1)

        model.begin(at: CGPoint(x: 40, y: 40))
        model.continueDrag(to: CGPoint(x: 55, y: 55))
        await drainImageChanges()
        #expect(copies.count == 1)
        model.endDrag()
        #expect(copies.count == 2)
        #expect(try ImageOutput.data(#require(copies.last), format: "PNG") == ImageOutput.data(model.renderedImage(), format: "PNG"))
    }

    @Test
    func liveTextAndHistoryCopyTheCurrentFullImage() async throws {
        let model = makeModel()
        var copies: [NSImage] = []
        model.onImageChange = { copies.append($0()) }
        model.tool = .text
        model.begin(at: CGPoint(x: 12, y: 16))
        model.updateText("First")
        await drainImageChanges()
        #expect(copies.count == 1)
        #expect(model.editingTextID != nil)
        let first = try ImageOutput.data(#require(copies.last), format: "PNG")
        #expect(first == (try ImageOutput.data(model.renderedImage(), format: "PNG")))
        model.updateText("Latest")
        await drainImageChanges()
        let latest = try ImageOutput.data(#require(copies.last), format: "PNG")
        #expect(latest != first)
        model.finishTextEditing()
        #expect(copies.count == 2)
        model.undo()
        await drainImageChanges()
        #expect(model.annotations.isEmpty)
        #expect(try ImageOutput.data(#require(copies.last), format: "PNG") == ImageOutput.data(model.renderedImage(), format: "PNG"))
        model.redo()
        await drainImageChanges()
        #expect(try ImageOutput.data(#require(copies.last), format: "PNG") == latest)
    }

    @Test
    func cropAndBackgroundChangesPublishCompleteStates() async throws {
        let model = makeModel()
        var copies: [NSImage] = []
        model.onImageChange = { copies.append($0()) }
        model.tool = .crop
        model.begin(at: CGPoint(x: 20, y: 20))
        model.continueDrag(to: CGPoint(x: 90, y: 70))
        await drainImageChanges()
        #expect(copies.isEmpty)
        model.endDrag()
        #expect(copies.count == 1)
        #expect(copies.last?.size == CGSize(width: 70, height: 50))
        model.updateBackground(style: .lavender)
        await drainImageChanges()
        #expect(copies.count == 2)
        model.setBackgroundEditing(true)
        model.updateBackground(padding: 48, cornerRadius: 24)
        await drainImageChanges()
        #expect(copies.count == 2)
        model.setBackgroundEditing(false)
        #expect(copies.count == 3)
        #expect(try ImageOutput.data(#require(copies.last), format: "PNG") == ImageOutput.data(model.renderedImage(), format: "PNG"))
        model.undo()
        await drainImageChanges()
        #expect(copies.count == 4)
        #expect(try ImageOutput.data(#require(copies.last), format: "PNG") == ImageOutput.data(model.renderedImage(), format: "PNG"))
    }

    @Test
    func selectionZoomToolsAndUnchangedValuesDoNotCopy() async {
        let model = makeModel()
        var copyCount = 0
        model.onImageChange = { _ in copyCount += 1 }
        model.zoom = 2
        model.tool = .arrow
        model.color = .blue
        model.strokeWidth = 10
        model.showBackgroundPanel = true
        model.updateBackground(style: .none)
        model.updateBackground(padding: model.padding, cornerRadius: model.cornerRadius)
        model.annotations = []
        model.image = model.image
        model.tool = .select
        model.begin(at: CGPoint(x: 10, y: 10))
        model.continueDrag(to: CGPoint(x: 90, y: 70))
        model.endDrag()
        model.undo()
        model.redo()
        await drainImageChanges()
        #expect(copyCount == 0)
    }

    @Test
    func leavingAnActiveGestureCopiesItsLastEdit() async throws {
        let model = makeModel()
        var copies: [NSImage] = []
        model.onImageChange = { copies.append($0()) }
        model.tool = .rectangle
        model.begin(at: CGPoint(x: 20, y: 20))
        model.continueDrag(to: CGPoint(x: 70, y: 60))
        await drainImageChanges()
        #expect(copies.isEmpty)
        model.tool = .select
        #expect(copies.count == 1)
        model.begin(at: CGPoint(x: 20, y: 20))
        model.continueDrag(to: CGPoint(x: 30, y: 30))
        await drainImageChanges()
        #expect(copies.count == 1)
        model.clearSelection()
        #expect(copies.count == 2)
        #expect(try ImageOutput.data(#require(copies.last), format: "PNG") == ImageOutput.data(model.renderedImage(), format: "PNG"))
    }

    @Test
    func appearanceDuplicationAndDeletionCopyTheirFinalResult() async throws {
        let model = makeModel()
        let shape = EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 70, y: 60))
        model.annotations = [shape]
        var copies: [NSImage] = []
        model.onImageChange = { copies.append($0()) }
        model.selectedID = shape.id
        model.color = .blue
        model.strokeWidth = 10
        await drainImageChanges()
        #expect(copies.count == 1)
        #expect(try ImageOutput.data(#require(copies.last), format: "PNG") == ImageOutput.data(model.renderedImage(), format: "PNG"))
        #expect(model.duplicateSelection())
        await drainImageChanges()
        #expect(copies.count == 2)
        model.deleteSelection()
        await drainImageChanges()
        #expect(copies.count == 3)
        #expect(try ImageOutput.data(#require(copies.last), format: "PNG") == ImageOutput.data(model.renderedImage(), format: "PNG"))
    }

    private func drainImageChanges() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func makeModel(size: CGSize = CGSize(width: 120, height: 90), color: NSColor = .white) -> AnnotationEditorModel {
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        return AnnotationEditorModel(image: NSImage(cgImage: context.makeImage()!, size: size), sourceURL: nil)
    }
}
