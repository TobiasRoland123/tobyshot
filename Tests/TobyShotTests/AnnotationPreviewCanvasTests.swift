import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationPreviewCanvasTests {
    @Test(arguments: [CGFloat(0.5), 1, 2])
    func nativeCanvasKeepsSourceOrientationAndVectorPositions(zoom: CGFloat) throws {
        _ = NSApplication.shared
        let source = DemoImage.make()
        let model = AnnotationEditorModel(image: source, sourceURL: nil)
        model.zoom = zoom
        // This checks orientation and placement. Comparing a vector shadow to a
        // downsampled export depends on display density; shadow parity is covered
        // separately by AnnotationPreviewTests.
        let annotation = EditorAnnotation(kind: .filledRectangle, start: CGPoint(x: 140, y: 160),
                                          end: CGPoint(x: 220, y: 220), color: .systemRed, shadow: false)
        model.annotations = [annotation]
        let canvas = AnnotationCanvasView(frame: CGRect(x: 0, y: 0, width: 2400, height: 1600))
        canvas.model = model
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        defer { window.close() }
        let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        let referenceView = PreviewReferenceView(frame: canvas.frame, image: model.renderedImage(), zoom: zoom)
        canvas.window?.contentView?.addSubview(referenceView)
        let reference = try #require(referenceView.bitmapImageRepForCachingDisplay(in: referenceView.bounds))
        referenceView.cacheDisplay(in: referenceView.bounds, to: reference)
        referenceView.removeFromSuperview()
        let factor = CGFloat(bitmap.pixelsWide) / canvas.bounds.width
        let origin = CGPoint(x: (canvas.bounds.width - model.canvasBounds.width * zoom) / 2,
                             y: (canvas.bounds.height - model.canvasBounds.height * zoom) / 2)
        func pixel(at point: CGPoint) throws -> NSColor {
            let x = Int((origin.x + point.x * zoom) * factor)
            let y = Int((origin.y + point.y * zoom) * factor)
            return try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        }
        let red = try pixel(at: CGPoint(x: 180, y: 190))
        func expected(at point: CGPoint) throws -> NSColor {
            let x = Int((origin.x + point.x * zoom) * CGFloat(reference.pixelsWide) / referenceView.bounds.width)
            let y = Int((origin.y + point.y * zoom) * CGFloat(reference.pixelsHigh) / referenceView.bounds.height)
            return try #require(reference.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        }
        let expectedRed = try expected(at: CGPoint(x: 180, y: 190))
        #expect(abs(red.redComponent - expectedRed.redComponent) < 0.03)
        #expect(abs(red.greenComponent - expectedRed.greenComponent) < 0.03)
        for point in [CGPoint(x: 200, y: 120), CGPoint(x: 200, y: 500),
                      CGPoint(x: 137, y: 190), CGPoint(x: 180, y: 157)] {
            let actual = try pixel(at: point)
            let expected = try expected(at: point)
            #expect(abs(actual.redComponent - expected.redComponent) < 0.03, "Red at \(point), zoom \(zoom)")
            #expect(abs(actual.greenComponent - expected.greenComponent) < 0.03, "Green at \(point), zoom \(zoom)")
            #expect(abs(actual.blueComponent - expected.blueComponent) < 0.03, "Blue at \(point), zoom \(zoom)")
        }
    }
}

@MainActor
private final class PreviewReferenceView: NSView {
    let image: NSImage
    let zoom: CGFloat
    override var isFlipped: Bool { true }
    init(frame: CGRect, image: NSImage, zoom: CGFloat) {
        self.image = image
        self.zoom = zoom
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) {
        let rect = CGRect(x: (bounds.width - image.size.width * zoom) / 2,
                          y: (bounds.height - image.size.height * zoom) / 2,
                          width: image.size.width * zoom, height: image.size.height * zoom)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
}
