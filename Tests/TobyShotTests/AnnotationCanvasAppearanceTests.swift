import AppKit
import SwiftUI
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationCanvasAppearanceTests {
    @Test(arguments: [AnnotationTool.select, .rectangle])
    func widthChangeRedrawsSelectedShapeThroughSwiftUI(tool: AnnotationTool) async throws {
        _ = NSApplication.shared
        let context = try #require(CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        let model = AnnotationEditorModel(image: NSImage(cgImage: try #require(context.makeImage()), size: CGSize(width: 300, height: 200)), sourceURL: nil)
        model.zoom = 1
        let shape = EditorAnnotation(kind: .rectangle, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 250, y: 150),
            color: .red, width: 5, shadow: false)
        model.annotations = [shape]
        model.selectedID = shape.id
        model.tool = tool
        let hosting = NSHostingView(rootView: AnnotationCanvasRepresentable(model: model))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(50))
        hosting.layoutSubtreeIfNeeded()
        let canvas = try #require(findCanvas(in: hosting))
        let before = try pixel(in: canvas, at: CGPoint(x: 100, y: 56))
        #expect(before.greenComponent > 0.95)

        model.strokeWidth = 20
        // Let the representable consume the observed model change. No selection change
        // or explicit canvas invalidation should be needed to show the new stroke.
        try await Task.sleep(for: .milliseconds(50))
        hosting.layoutSubtreeIfNeeded()
        #expect(model.selectedID == shape.id)
        #expect(model.tool == tool)
        let selected = try pixel(in: canvas, at: CGPoint(x: 100, y: 56))
        #expect(selected.redComponent > 0.95)
        #expect(selected.greenComponent < 0.3)
        model.clearSelection()
        try await Task.sleep(for: .milliseconds(50))
        hosting.layoutSubtreeIfNeeded()
        let deselected = try pixel(in: canvas, at: CGPoint(x: 100, y: 56))
        #expect(abs(selected.greenComponent - deselected.greenComponent) < 0.01)
    }

    private func findCanvas(in view: NSView) -> AnnotationCanvasView? {
        if let canvas = view as? AnnotationCanvasView { return canvas }
        return view.subviews.lazy.compactMap { findCanvas(in: $0) }.first
    }

    private func pixel(in canvas: AnnotationCanvasView, at point: CGPoint) throws -> NSColor {
        let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        let bounds = canvas.layoutCanvasBounds
        let x = (canvas.bounds.width - bounds.width) / 2 + point.x - bounds.minX
        let y = (canvas.bounds.height - bounds.height) / 2 + point.y - bounds.minY
        let scale = CGFloat(bitmap.pixelsWide) / canvas.bounds.width
        return try #require(bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
    }
}
