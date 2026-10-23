import AppKit
import Vision

/// An on-device prototype. Vision proposes contours; full-resolution pixels
/// confirm the outer bounds of bordered or filled surfaces.
enum AreaSuggestionDetector {
    // Contour extraction dominates readiness. Pool thin edges into this smaller
    // proposal image; refine every accepted boundary against the original pixels.
    private static let contourDimension = 640
    // Front to back, in Quartz coordinates. Read before the selection panels exist.
    static func visibleWindowFrames() -> [CGRect] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? Int) != Int(ProcessInfo.processInfo.processIdentifier),
                  (window[kCGWindowLayer as String] as? Int ?? -1) >= 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return rect
        }
    }

    static func detect(in display: CaptureDisplayImage, displayFrame: CGRect, windows: [CGRect]) throws -> [CGRect] {
        try Task.checkCancellation()
        guard let pixels = Pixels(display.image), let edges = pixels.edgeImage() else { return [] }
        let request = VNDetectContoursRequest()
        request.maximumImageDimension = contourDimension
        request.contrastAdjustment = 1
        let handler = VNImageRequestHandler(cgImage: edges)
        var rectangles: [CGRect] = []
        // Detect contrast boundaries rather than absolute luminance, so pale and
        // dark borders receive the same treatment. The edge map is light on dark.
        try Task.checkCancellation()
        request.detectsDarkOnLight = false
        try handler.perform([request])
        guard let observation = request.results?.first else { return [] }
        for index in 0..<observation.contourCount {
            try Task.checkCancellation()
            let contour = try observation.contour(at: index)
            let normalized = contour.normalizedPath.boundingBox
            let proposed = CGRect(x: normalized.minX * CGFloat(pixels.width),
                                  y: (1 - normalized.maxY) * CGFloat(pixels.height),
                                  width: normalized.width * CGFloat(pixels.width),
                                  height: normalized.height * CGFloat(pixels.height))
            // Include short cards, bubbles, and controls while omitting icons
            // and text fragments. Check the final size after pixel refinement.
            guard proposed.width / display.scale >= 60, proposed.height / display.scale >= 20,
                  proposed.width / proposed.height < 20, proposed.height / proposed.width < 5,
                  rectangular(contour, bounds: normalized),
                  let rect = pixels.refine(proposed),
                  rect.width / display.scale >= 64, rect.height / display.scale >= 24,
                  isVisible(rect, imageSize: CGSize(width: pixels.width, height: pixels.height),
                            displayFrame: displayFrame, windows: windows) else { continue }
            if !rectangles.contains(rect) { rectangles.append(rect) }
        }
        // An apparent child sharing an edge with its parent may be clipped by a
        // viewport. Keep the surrounding container, omit the uncertain child.
        rectangles = rectangles.filter { rect in
            !rectangles.contains { parent in
                parent != rect && parent.contains(rect) &&
                (abs(parent.minX - rect.minX) <= 2 || abs(parent.maxX - rect.maxX) <= 2 ||
                 abs(parent.minY - rect.minY) <= 2 || abs(parent.maxY - rect.maxY) <= 2)
            }
        }
        return rectangles.map { globalRect($0, in: display) }
    }

    static func globalRect(_ pixels: CGRect, in display: CaptureDisplayImage) -> CGRect {
        let xScale = CGFloat(display.image.width) / display.frame.width
        let yScale = CGFloat(display.image.height) / display.frame.height
        return CGRect(x: display.frame.minX + pixels.minX / xScale,
                      y: display.frame.maxY - pixels.maxY / yScale,
                      width: pixels.width / xScale, height: pixels.height / yScale)
    }

    static func isVisible(_ rect: CGRect, imageSize: CGSize, displayFrame: CGRect, windows: [CGRect]) -> Bool {
        // A contour touching a display edge has no evidence of a complete boundary.
        guard CGRect(origin: .zero, size: imageSize).insetBy(dx: 1, dy: 1).contains(rect) else { return false }
        let quartzRect = CGRect(x: displayFrame.minX + rect.minX * displayFrame.width / imageSize.width,
                                y: displayFrame.minY + rect.minY * displayFrame.height / imageSize.height,
                                width: rect.width * displayFrame.width / imageSize.width,
                                height: rect.height * displayFrame.height / imageSize.height)
        // The first intersecting window must own the entire rectangle. A front
        // window overlapping even the interior makes a background container unsafe.
        guard let owner = windows.first(where: { !$0.intersection(quartzRect).isEmpty }) else { return false }
        return owner.insetBy(dx: 1, dy: 1).contains(quartzRect)
    }

    private static func rectangular(_ contour: VNContour, bounds: CGRect) -> Bool {
        guard bounds.width > 0, bounds.height > 0 else { return false }
        let points = contour.normalizedPoints
        guard points.count >= 4 else { return false }
        // Allow rounded corners, but not text, open shapes, or irregular silhouettes.
        var twiceArea: CGFloat = 0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            twiceArea += CGFloat(a.x * b.y - b.x * a.y)
        }
        return abs(twiceArea) / 2 / (bounds.width * bounds.height) >= 0.90
    }

    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init?(_ image: CGImage) {
            width = image.width; height = image.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = buffer.withUnsafeMutableBytes { data -> Bool in
                guard let context = CGContext(data: data.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return true
            }
            guard drawn else { return nil }
            bytes = buffer
        }

        func refine(_ rect: CGRect) -> CGRect? {
            let shortestSide = min(rect.width, rect.height)
            let radius = max(4, Int(ceil(CGFloat(max(width, height)) / CGFloat(AreaSuggestionDetector.contourDimension))) * 2)
            guard let left = edge(near: rect.minX, from: rect.minY, to: rect.maxY, vertical: true, lower: true, radius: radius, shortestSide: shortestSide),
                  let right = edge(near: rect.maxX, from: rect.minY, to: rect.maxY, vertical: true, lower: false, radius: radius, shortestSide: shortestSide),
                  let top = edge(near: rect.minY, from: rect.minX, to: rect.maxX, vertical: false, lower: true, radius: radius, shortestSide: shortestSide),
                  let bottom = edge(near: rect.maxY, from: rect.minX, to: rect.maxX, vertical: false, lower: false, radius: radius, shortestSide: shortestSide),
                  right > left, bottom > top else { return nil }
            // Accept either a complete border or a filled silhouette. A border
            // present on only some sides can indicate a cut at a viewport edge.
            let refinedSide = min(right - left, bottom - top)
            let borders = [hasBorder(at: left, from: top, to: bottom, vertical: true, lower: true, depth: radius, shortestSide: refinedSide),
                           hasBorder(at: right, from: top, to: bottom, vertical: true, lower: false, depth: radius, shortestSide: refinedSide),
                           hasBorder(at: top, from: left, to: right, vertical: false, lower: true, depth: radius, shortestSide: refinedSide),
                           hasBorder(at: bottom, from: left, to: right, vertical: false, lower: false, depth: radius, shortestSide: refinedSide)]
            guard borders.allSatisfy({ $0 }) || borders.allSatisfy({ !$0 }) else { return nil }
            return CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }

        private func hasBorder(at edge: Int, from start: Int, to end: Int, vertical: Bool, lower: Bool, depth: Int, shortestSide: Int) -> Bool {
            let direction = lower ? 1 : -1
            let boundary = lower ? edge : edge - 1
            let outside = boundary - direction * 2
            let inside = boundary + direction * (depth + 2)
            let limit = vertical ? width : height
            guard min(outside, inside) >= 0, max(outside, inside) < limit else { return false }
            let inset = min(CGFloat(end - start) * 0.45, CGFloat(shortestSide) / 2)
            var matches = 0
            for sample in 0..<9 {
                let along = start + Int(inset + (CGFloat(end - start) - inset * 2) * CGFloat(sample) / 8)
                func index(_ across: Int) -> Int { (vertical ? along * width + across : across * width + along) * 4 }
                let a = index(outside), b = index(inside)
                var bordered = false
                for offset in 0..<depth {
                    let band = index(boundary + direction * offset)
                    for channel in 0..<3 {
                        let value = Int(bytes[band + channel])
                        let lo = min(Int(bytes[a + channel]), Int(bytes[b + channel]))
                        let hi = max(Int(bytes[a + channel]), Int(bytes[b + channel]))
                        if value < lo - 8 || value > hi + 8 { bordered = true }
                    }
                }
                if bordered { matches += 1 }
            }
            // A divider meeting the outer border can interrupt a few samples.
            return matches >= 7
        }

        func edgeImage() -> CGImage? {
            guard width > 1, height > 1 else { return nil }
            // Pool edges instead of resizing a thin binary line with interpolation,
            // which can erase the one-pixel borders we need on Retina displays.
            // A lower proposal threshold connects faint antialiased corners;
            // native-resolution verification still requires stronger straight edges.
            let factor = max(1, Int(ceil(CGFloat(max(width, height)) / CGFloat(AreaSuggestionDetector.contourDimension))))
            let edgeWidth = (width + factor - 1) / factor
            let edgeHeight = (height + factor - 1) / factor
            var edges = [UInt8](repeating: 0, count: edgeWidth * edgeHeight)
            for y in 1..<height {
                if Task.isCancelled { return nil }
                for x in 1..<width {
                    let index = (y * width + x) * 4
                    for channel in 0..<3 {
                        let value = Int(bytes[index + channel])
                        if abs(value - Int(bytes[index - 4 + channel])) >= 6 ||
                           abs(value - Int(bytes[index - width * 4 + channel])) >= 6 {
                            edges[(y / factor) * edgeWidth + x / factor] = 255
                            break
                        }
                    }
                }
            }
            guard let provider = CGDataProvider(data: Data(edges) as CFData) else { return nil }
            return CGImage(width: edgeWidth, height: edgeHeight, bitsPerComponent: 8, bitsPerPixel: 8,
                           bytesPerRow: edgeWidth, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }

        private func edge(near position: CGFloat, from start: CGFloat, to end: CGFloat,
                          vertical: Bool, lower: Bool, radius: Int, shortestSide: CGFloat) -> Int? {
            // Short pill-shaped surfaces have straight edges only near the
            // center; long sides retain a wider sampling span.
            let inset = min((end - start) * 0.45, shortestSide / 2)
            let positions = (Int(position.rounded()) - radius)...(Int(position.rounded()) + radius)
            // Choose the outer sharp edge of a border, not its inner edge or the
            // gradual shadow beyond it. Allow small antialiasing interruptions.
            for edge in lower ? Array(positions) : Array(positions.reversed()) {
                var matches = 0
                for sample in 0..<33 {
                    let along = Int(start + inset + (end - start - inset * 2) * CGFloat(sample) / 32)
                    let x = vertical ? edge : along, y = vertical ? along : edge
                    let px = vertical ? x - 1 : x, py = vertical ? y : y - 1
                    guard x > 0, y > 0, x < width, y < height, px >= 0, py >= 0 else { continue }
                    let a = (y * width + x) * 4, b = (py * width + px) * 4
                    let contrast = (0..<3).map { abs(Int(bytes[a + $0]) - Int(bytes[b + $0])) }.max() ?? 0
                    if contrast >= 8 { matches += 1 }
                }
                if matches >= 30 { return edge }
            }
            return nil
        }
    }
}
