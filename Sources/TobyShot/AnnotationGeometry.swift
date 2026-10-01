import AppKit
import CoreText

/// Geometry in the editor's top-left pixel coordinates, shared by drawing and bounds.
struct AnnotationGeometry {
    static func constrainedEndpoint(from start: CGPoint, to point: CGPoint, kind: EditorAnnotation.Kind) -> CGPoint {
        let dx = point.x - start.x
        let dy = point.y - start.y
        switch kind {
        case .line, .arrow:
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            // Exact axis/diagonal directions avoid tiny offsets on horizontal and vertical lines.
            let direction = CGPoint(x: cos(angle).rounded(), y: sin(angle).rounded())
            let distance = hypot(dx, dy) / hypot(direction.x, direction.y)
            return CGPoint(x: start.x + direction.x * distance, y: start.y + direction.y * distance)
        case .rectangle, .filledRectangle, .ellipse:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        default:
            return point
        }
    }

    struct Text {
        let line: CTLine
        let baseline: CGPoint

        var bounds: CGRect {
            let glyphs = CTLineGetImageBounds(line, nil)
            guard !glyphs.isNull else { return .null }
            return CGRect(x: baseline.x + glyphs.minX, y: baseline.y - glyphs.maxY,
                          width: glyphs.width, height: glyphs.height)
        }
    }

    struct Shadow {
        let offset = CGSize(width: 0, height: 2)
        let blur: CGFloat = 3
        let color = NSColor.black.withAlphaComponent(0.55).cgColor

        func bounds(for shape: CGRect) -> CGRect {
            // Quartz offsets shadows in base space; positive Y is up in our bitmaps.
            // Reserve three blur radii for the rasterized shadow's falloff.
            shape.offsetBy(dx: offset.width, dy: -offset.height)
                .insetBy(dx: -blur * 3, dy: -blur * 3)
        }
    }

    let path: CGPath
    let stroked: Bool
    let lineWidth: CGFloat
    let text: Text?
    let textLayout: AnnotationTextLayout?
    let textOrigin: CGPoint
    let shadow: Shadow?
    let pixelationRect: CGRect

    init(_ annotation: EditorAnnotation, imageSize: CGSize? = nil) {
        let a = annotation
        let rect = CGRect(x: min(a.start.x, a.end.x), y: min(a.start.y, a.end.y),
                          width: abs(a.end.x - a.start.x), height: abs(a.end.y - a.start.y))
        let path = CGMutablePath()
        var text: Text?
        var textLayout: AnnotationTextLayout?
        var stroked = false
        var pixelationRect = CGRect.null
        switch a.kind {
        case .redaction:
            path.addRect(rect)
        case .rectangle, .filledRectangle, .ellipse, .line:
            path.addPath(AnnotationShapePath.make(a, in: rect))
            stroked = a.kind != .filledRectangle
        case .arrow:
            path.addPath(AnnotationArrowPath.make(a))
            stroked = true
        case .freehand:
            if let first = a.points.first {
                path.move(to: first)
                if a.points.count == 1 {
                    path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y + 0.1))
                } else {
                    for point in a.points.dropFirst() { path.addLine(to: point) }
                }
            }
            stroked = true
        case .text:
            textLayout = AnnotationTextLayout(a)
        case .step:
            let radius = max(15, a.width * 3.5)
            path.addPath(AnnotationShapePath.make(a, in: CGRect(x: a.start.x - radius, y: a.start.y - radius,
                                                              width: radius * 2, height: radius * 2)))
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: "\(a.step)", attributes: [.font: NSFont.systemFont(ofSize: radius, weight: .bold), .foregroundColor: NSColor.white]))
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            text = Text(line: line, baseline: CGPoint(x: a.start.x - width / 2, y: a.start.y + radius / 3))
        case .pixelation:
            pixelationRect = rect.integral
            if let imageSize { pixelationRect = pixelationRect.intersection(CGRect(origin: .zero, size: imageSize)) }
            if !pixelationRect.isEmpty { path.addRect(pixelationRect) }
        }
        self.path = path
        self.stroked = stroked
        self.lineWidth = a.width
        self.text = text
        self.textLayout = textLayout
        self.textOrigin = a.start
        self.shadow = a.shadow && a.kind != .redaction && a.kind != .pixelation ? Shadow() : nil
        self.pixelationRect = pixelationRect
    }

    var renderedBounds: CGRect {
        let shape = stroked
            ? path.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
            : path
        var bounds = shape.boundingBoxOfPath
        // A step's label is drawn without a shadow; ordinary text casts its own shadow.
        if path.isEmpty, let text { bounds = text.bounds }
        if let textLayout { bounds = textLayout.bounds.offsetBy(dx: textOrigin.x, dy: textOrigin.y) }
        if let shadow, !bounds.isNull { bounds = bounds.union(shadow.bounds(for: bounds)) }
        if let text { bounds = bounds.union(text.bounds) }
        return bounds
    }

    var exportBounds: CGRect {
        // Keep fractional antialiased edge pixels and align the export with the canvas.
        renderedBounds.insetBy(dx: -1, dy: -1).integral
    }
}
