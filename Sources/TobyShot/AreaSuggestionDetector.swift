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
            guard proposed.width / display.scale >= 60, proposed.height / display.scale >= 10,
                  proposed.height / proposed.width < 5,
                  rectangular(contour, bounds: normalized),
                  let rect = pixels.refine(proposed),
                  rect.width / display.scale >= 64, rect.height / display.scale >= 14,
                  isVisible(rect, imageSize: CGSize(width: pixels.width, height: pixels.height),
                            displayFrame: displayFrame, windows: windows) else { continue }
            if !rectangles.contains(rect) { rectangles.append(rect) }
        }
        // Window geometry supplies the outer edges of panes that have only a
        // horizontal/vertical separator, even when no closed contour survives.
        let windowRects = windows.filter { window in
            windows.first(where: { !$0.intersection(window).isEmpty }) == window
        }.map { window in
            CGRect(x: (window.minX - displayFrame.minX) * CGFloat(pixels.width) / displayFrame.width,
                   y: (window.minY - displayFrame.minY) * CGFloat(pixels.height) / displayFrame.height,
                   width: window.width * CGFloat(pixels.width) / displayFrame.width,
                   height: window.height * CGFloat(pixels.height) / displayFrame.height).integral
        }.filter {
            isVisible($0, imageSize: CGSize(width: pixels.width, height: pixels.height),
                      displayFrame: displayFrame, windows: windows, allowWindowEdges: true)
        }
        // A long separator can define a pane even when text merges with its
        // outline in the reduced contour image. Keep the enclosing area too.
        for parent in Set(rectangles + windowRects) {
            for rect in pixels.subdivisions(in: parent, scale: display.scale) where
                isVisible(rect, imageSize: CGSize(width: pixels.width, height: pixels.height),
                          displayFrame: displayFrame, windows: windows, allowWindowEdges: true) {
                if !rectangles.contains(rect) { rectangles.append(rect) }
            }
        }
        // Vision can propose both sides of a faint border. Remove only near-
        // identical outlines, not legitimate sections sharing their parent's edge.
        let tolerance = max(2, display.scale * 2)
        rectangles = rectangles.filter { rect in
            !rectangles.contains { parent in
                parent != rect && parent.contains(rect) &&
                abs(parent.minX - rect.minX) <= tolerance && abs(parent.maxX - rect.maxX) <= tolerance &&
                abs(parent.minY - rect.minY) <= tolerance && abs(parent.maxY - rect.maxY) <= tolerance
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

    static func isVisible(_ rect: CGRect, imageSize: CGSize, displayFrame: CGRect, windows: [CGRect],
                          allowWindowEdges: Bool = false) -> Bool {
        // Pixel contours need visible margins. Separator-based panes can instead
        // use the verified bounds of an entirely visible window at the screen edge.
        let margin: CGFloat = allowWindowEdges ? 0 : 1
        guard CGRect(origin: .zero, size: imageSize).insetBy(dx: margin, dy: margin).contains(rect) else { return false }
        let quartzRect = CGRect(x: displayFrame.minX + rect.minX * displayFrame.width / imageSize.width,
                                y: displayFrame.minY + rect.minY * displayFrame.height / imageSize.height,
                                width: rect.width * displayFrame.width / imageSize.width,
                                height: rect.height * displayFrame.height / imageSize.height)
        // The first intersecting window must own the entire rectangle. A front
        // window overlapping even the interior makes a background container unsafe.
        guard let owner = windows.first(where: { !$0.intersection(quartzRect).isEmpty }) else { return false }
        return owner.contains(quartzRect)
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

        func subdivisions(in rect: CGRect, scale: CGFloat) -> [CGRect] {
            guard rect.width / scale >= 160, rect.height / scale >= 48 else { return [] }
            var result: [CGRect] = []
            for vertical in [false, true] {
                let start = Int(vertical ? rect.minX : rect.minY)
                let end = Int(vertical ? rect.maxX : rect.maxY)
                let alongStart = Int(vertical ? rect.minY : rect.minX) + max(1, Int(scale * 2))
                let alongEnd = Int(vertical ? rect.maxY : rect.maxX) - max(1, Int(scale * 2)) - 1
                // Include both ends: grid lines and underlines that stop inside
                // the content must not split the surrounding container.
                let samples = (0..<33).map { alongStart + (alongEnd - alongStart) * $0 / 32 }
                func contrast(_ a: Int, _ b: Int, along: Int) -> Int {
                    let first = (vertical ? along * width + a : a * width + along) * 4
                    let second = (vertical ? along * width + b : b * width + along) * 4
                    return (0..<3).map { abs(Int(bytes[first + $0]) - Int(bytes[second + $0])) }.max() ?? 0
                }
                func continuous(_ a: Int, _ b: Int) -> Bool {
                    contrast(a, b, along: alongStart) >= 6 && contrast(a, b, along: alongEnd) >= 6 &&
                    samples.filter { contrast(a, b, along: $0) >= 6 }.count >= 30
                }
                var bands: [(start: Int, end: Int, transition: Bool)] = []
                var edge = start + max(2, Int(scale * 2))
                while edge < end - max(2, Int(scale * 2)) {
                    if Task.isCancelled { return [] }
                    guard continuous(edge - 1, edge) else { edge += 1; continue }
                    let first = edge
                    let bandWidth = max(2, Int(scale * 3))
                    var next = edge + 1
                    // The two edges of a one-point divider are separated by
                    // multiple pixels on Retina displays; treat them as one rule.
                    while next < end && next - edge <= bandWidth {
                        if continuous(next - 1, next) { edge = next }
                        next += 1
                    }
                    // Broad gradients are not sharp separators.
                    if edge - first <= bandWidth {
                        bands.append((first, edge, continuous(first - 1, edge)))
                    }
                    edge += 1
                }
                func parts(from lower: Int, to upper: Int, cuts: [(start: Int, end: Int, transition: Bool)]) -> [CGRect] {
                    guard !cuts.isEmpty else { return [] }
                    let beginnings = [lower] + cuts.map(\.end)
                    let endings = cuts.map(\.start) + [upper]
                    return zip(beginnings, endings).compactMap { low, high in
                        let part = vertical ? CGRect(x: low, y: Int(rect.minY), width: high - low, height: Int(rect.height)) :
                            CGRect(x: Int(rect.minX), y: low, width: Int(rect.width), height: high - low)
                        return part.width / scale >= 64 && part.height / scale >= 14 ? part : nil
                    }
                }
                // Background changes separate panes. Thin rules divide content
                // within each pane without discarding the pane's full bounds.
                let panes = parts(from: start, to: end, cuts: bands.filter(\.transition))
                result += panes
                for pane in panes.isEmpty ? [rect] : panes {
                    let low = Int(vertical ? pane.minX : pane.minY), high = Int(vertical ? pane.maxX : pane.maxY)
                    result += parts(from: low, to: high, cuts: bands.filter { !$0.transition && $0.start > low && $0.end < high })
                }
            }
            return result
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
