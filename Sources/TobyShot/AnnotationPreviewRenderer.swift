import AppKit

/// Draws in top-left view coordinates without flattening the editable canvas into an export bitmap.
@MainActor
final class AnnotationPreviewRenderer {
    private weak var sourceImage: NSImage?
    private var source: CGImage?
    private var backgroundImage: CGImage?
    private var backgroundSize: CGSize = .zero
    private var sourcePixels: [UInt8] = []
    private var pixelations: [UUID: Pixelation] = [:]

    private struct Pixelation {
        let rect: CGRect
        let width: CGFloat
        let image: CGImage
    }

    func draw(image: NSImage, annotations: [EditorAnnotation], canvasBounds: CGRect,
              background: AnnotationBackground, cornerRadius: CGFloat,
              imageOrigin: CGPoint, scale: CGFloat, backingScale: CGFloat,
              shadowScale: CGSize? = nil, in context: CGContext) {
        if sourceImage !== image {
            sourceImage = image
            source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            backgroundImage = nil
            backgroundSize = .zero
            sourcePixels = []
            pixelations.removeAll()
        }
        guard let source, scale > 0 else { return }
        let pixelSize = CGSize(width: source.width, height: source.height)
        let displayImage = cachedBackground(source, scale: min(1, scale * backingScale))

        context.saveGState()
        context.translateBy(x: imageOrigin.x, y: imageOrigin.y)
        context.scaleBy(x: scale, y: scale)
        context.clip(to: canvasBounds)

        // The export's gradient starts at its bottom-left corner.
        context.saveGState()
        context.translateBy(x: canvasBounds.minX, y: canvasBounds.maxY)
        context.scaleBy(x: 1, y: -1)
        AnnotationRenderer.drawBackground(background, in: context, size: canvasBounds.size)
        context.restoreGState()

        context.saveGState()
        if background != .none, cornerRadius > 0 {
            context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: pixelSize),
                                   cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            context.clip()
        }
        drawImage(displayImage, in: CGRect(origin: .zero, size: pixelSize), context: context)
        context.restoreGState()

        let pixelationIDs = Set(annotations.filter { $0.kind == .pixelation }.map(\.id))
        pixelations = pixelations.filter { pixelationIDs.contains($0.key) }
        if pixelationIDs.isEmpty { sourcePixels = [] }
        for annotation in annotations {
            let geometry = AnnotationGeometry(annotation, imageSize: pixelSize)
            if annotation.kind == .pixelation {
                if let patch = cachedPixelation(annotation, geometry: geometry, source: source) {
                    context.saveGState()
                    context.interpolationQuality = .none
                    drawImage(patch.image, in: patch.rect, context: context)
                    context.restoreGState()
                }
            } else {
                // AppKit's default view space is flipped and already includes Retina backing.
                // Raw bitmap callers can supply the corresponding pixel-space shadow scale.
                AnnotationRenderer.draw(annotation, geometry: geometry, in: context, pixelSize: pixelSize,
                                        sourcePixels: [], shadowScale: shadowScale ?? CGSize(width: scale, height: -scale))
            }
        }
        context.restoreGState()
    }

    private func cachedBackground(_ source: CGImage, scale: CGFloat) -> CGImage {
        let size = CGSize(width: max(1, ceil(CGFloat(source.width) * scale)),
                          height: max(1, ceil(CGFloat(source.height) * scale)))
        if size == backgroundSize, let backgroundImage { return backgroundImage }
        backgroundSize = size
        backgroundImage = nil
        if size.width >= CGFloat(source.width), size.height >= CGFloat(source.height) {
            backgroundImage = source
        } else if let bitmap = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                         bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            bitmap.interpolationQuality = .high
            bitmap.draw(source, in: CGRect(origin: .zero, size: size))
            backgroundImage = bitmap.makeImage()
        }
        return backgroundImage ?? source
    }

    private func cachedPixelation(_ annotation: EditorAnnotation, geometry: AnnotationGeometry, source: CGImage) -> Pixelation? {
        let rect = geometry.pixelationRect
        guard !rect.isNull, !rect.isEmpty else { pixelations[annotation.id] = nil; return nil }
        if let patch = pixelations[annotation.id], patch.rect == rect, patch.width == annotation.width { return patch }
        if sourcePixels.isEmpty { sourcePixels = AnnotationRenderer.pixelationSourcePixels(source) }
        guard let bitmap = CGContext(data: nil, width: Int(rect.width), height: Int(rect.height), bitsPerComponent: 8,
                                     bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        bitmap.translateBy(x: -rect.minX, y: rect.maxY)
        bitmap.scaleBy(x: 1, y: -1)
        AnnotationRenderer.draw(annotation, geometry: geometry, in: bitmap,
                                pixelSize: CGSize(width: source.width, height: source.height), sourcePixels: sourcePixels)
        guard let image = bitmap.makeImage() else { return nil }
        let patch = Pixelation(rect: rect, width: annotation.width, image: image)
        pixelations[annotation.id] = patch
        return patch
    }

    private func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}
