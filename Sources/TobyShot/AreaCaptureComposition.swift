import AppKit
import CoreGraphics

struct CaptureDisplayImage {
    let frame: CGRect
    let image: CGImage
    var scale: CGFloat { CGFloat(image.width) / frame.width }
}

enum AreaCaptureComposition {
    static func scale(for rect: CGRect, displays: [CaptureDisplayImage]) -> CGFloat {
        displays
            .filter { intersects(rect, $0.frame) }
            .map(\.scale)
            .filter { $0.isFinite && $0 > 0 }
            .max() ?? 1
    }

    static func pixelSize(for rect: CGRect, displays: [CaptureDisplayImage]) -> CGSize {
        let intersecting = displays.filter { intersects(rect, $0.frame) }
        if intersecting.count == 1, intersecting[0].frame.contains(rect),
           let crop = sourceCrop(rect, display: intersecting[0]) {
            return CGSize(width: crop.width, height: crop.height)
        }

        let scale = scale(for: rect, displays: displays)
        let bounds = outputPixelBounds(for: rect, scale: scale)
        return CGSize(width: bounds.width, height: bounds.height)
    }

    static func capture(rect: CGRect, displays: [CaptureDisplayImage]) throws -> CaptureResult {
        let intersecting = displays.filter { intersects(rect, $0.frame) }
        guard !intersecting.isEmpty else {
            throw TobyError.message("The selected area does not intersect a display.")
        }

        let scale = intersecting.map(\.scale).filter { $0.isFinite && $0 > 0 }.max() ?? 1
        if intersecting.count == 1, intersecting[0].frame.contains(rect),
           let crop = sourceCrop(rect, display: intersecting[0]),
           let image = intersecting[0].image.cropping(to: crop) {
            return result(image, scale: intersecting[0].scale)
        }

        let pixelBounds = outputPixelBounds(for: rect, scale: scale)
        let width = Int(pixelBounds.width)
        let height = Int(pixelBounds.height)
        let outputRect = CGRect(x: pixelBounds.minX / scale, y: pixelBounds.minY / scale,
                                width: pixelBounds.width / scale, height: pixelBounds.height / scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw TobyError.message("The selected area could not be captured.")
        }

        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -outputRect.minX, y: -outputRect.minY)
        for display in intersecting {
            let overlap = outputRect.intersection(display.frame)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }

            // Clip in global point coordinates, then draw the complete source image
            // into its display frame. The image's top row stays at the display's top.
            context.saveGState()
            context.clip(to: overlap)
            context.draw(display.image, in: display.frame)
            context.restoreGState()
        }

        guard let image = context.makeImage() else {
            throw TobyError.message("The selected area could not be captured.")
        }
        return result(image, scale: scale)
    }

    private static func intersects(_ rect: CGRect, _ frame: CGRect) -> Bool {
        guard rect.width > 0, rect.height > 0, frame.width > 0, frame.height > 0 else { return false }
        let overlap = rect.intersection(frame)
        return !overlap.isNull && overlap.width > 0 && overlap.height > 0
    }

    private static func outputPixelBounds(for rect: CGRect, scale: CGFloat) -> CGRect {
        let minX = floor(rect.minX * scale)
        let minY = floor(rect.minY * scale)
        let maxX = ceil(rect.maxX * scale)
        let maxY = ceil(rect.maxY * scale)
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    private static func sourceCrop(_ rect: CGRect, display: CaptureDisplayImage) -> CGRect? {
        let image = display.image
        let xScale = CGFloat(image.width) / display.frame.width
        let yScale = CGFloat(image.height) / display.frame.height
        let left = floor((rect.minX - display.frame.minX) * xScale)
        let right = ceil((rect.maxX - display.frame.minX) * xScale)
        let top = floor((display.frame.maxY - rect.maxY) * yScale)
        let bottom = ceil((display.frame.maxY - rect.minY) * yScale)
        let crop = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return crop.isNull || crop.isEmpty ? nil : crop
    }

    private static func result(_ image: CGImage, scale: CGFloat) -> CaptureResult {
        CaptureResult(image: NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)),
                      scale: scale, isWindow: false)
    }
}
