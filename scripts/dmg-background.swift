// Draws the DMG window background at 1x and 2x.
// Usage: swift scripts/dmg-background.swift <output-directory>
// Writes background.png and background@2x.png. Keep the canvas size and icon
// centers in sync with scripts/dmg-settings.py, which positions the icons.
//
// Finder draws icon labels in black on custom backgrounds in both light and
// dark appearance, so the canvas stays light. Rendering fails if any text or
// label area falls below WCAG AA contrast.
import AppKit

let canvas = CGSize(width: 660, height: 400)
let appIconCenter = CGPoint(x: 170, y: 186)
let applicationsCenter = CGPoint(x: 490, y: 186)
let iconSize: CGFloat = 128

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let navy = color(0x0F1B36)
let slate = color(0x3D4B68)
let skyBlue = color(0x1F86F5)
let captureRed = color(0xEE2D36)
let finderLabel = color(0x000000)

struct Caption {
    let text: String
    let font: NSFont
    let color: NSColor
    let top: CGFloat

    var string: NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }

    var frame: CGRect {
        let size = string.size()
        return CGRect(x: ((canvas.width - size.width) / 2).rounded(), y: top, width: size.width, height: size.height)
    }
}

let title = Caption(
    text: "Drag TobyShot to Applications",
    font: .systemFont(ofSize: 27, weight: .bold), color: navy, top: 34
)
let hint = Caption(
    text: "Then eject this disk and open TobyShot from Applications.",
    font: .systemFont(ofSize: 14, weight: .medium), color: slate, top: 346
)

/// The area where Finder draws an item's name below its icon.
func labelFrame(below center: CGPoint) -> CGRect {
    CGRect(x: center.x - 64, y: center.y + iconSize / 2 + 6, width: 128, height: 24)
}

/// Frames the icon and its label, leaving the label clear of the corners.
func itemFrame(around center: CGPoint) -> CGRect {
    CGRect(x: center.x - 88, y: center.y - 86, width: 176, height: 208)
}

func drawBackground(in context: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let base = CGGradient(
        colorsSpace: space,
        colors: [color(0xFBFCFE).cgColor, color(0xF1F5FB).cgColor, color(0xE6ECF6).cgColor] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.drawLinearGradient(base, start: .zero, end: CGPoint(x: 0, y: canvas.height), options: [])

    // A soft blue light behind the icon row, echoing the app icon's glass.
    let glow = CGGradient(
        colorsSpace: space,
        colors: [color(0x5DB8FF, 0.20).cgColor, color(0x5DB8FF, 0).cgColor] as CFArray,
        locations: [0, 1]
    )!
    let glowCenter = CGPoint(x: canvas.width / 2, y: appIconCenter.y)
    context.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: 320, options: [])

    // A faint dot grid, like an empty annotation canvas.
    context.setFillColor(navy.withAlphaComponent(0.07).cgColor)
    for y in stride(from: CGFloat(10), to: canvas.height, by: 20) {
        for x in stride(from: CGFloat(10), to: canvas.width, by: 20) {
            context.fillEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
        }
    }
}

func drawCaptureBrackets(in context: CGContext, around frame: CGRect) {
    let arm: CGFloat = 26
    let corners: [(CGPoint, CGFloat, CGFloat, NSColor)] = [
        (CGPoint(x: frame.minX, y: frame.minY), 1, 1, skyBlue),
        (CGPoint(x: frame.maxX, y: frame.minY), -1, 1, navy),
        (CGPoint(x: frame.minX, y: frame.maxY), 1, -1, navy),
        (CGPoint(x: frame.maxX, y: frame.maxY), -1, -1, navy),
    ]
    for (corner, dx, dy, strokeColor) in corners {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        path.addArc(tangent1End: corner, tangent2End: CGPoint(x: corner.x + dx * arm, y: corner.y), radius: 8)
        path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        context.saveGState()
        if strokeColor == skyBlue {
            context.setShadow(offset: .zero, blur: 8, color: skyBlue.withAlphaComponent(0.55).cgColor)
        }
        context.setLineWidth(5)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(strokeColor.cgColor)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }
}

func drawDropZone(in context: CGContext, around frame: CGRect) {
    let path = CGPath(roundedRect: frame, cornerWidth: 26, cornerHeight: 26, transform: nil)
    context.saveGState()
    context.setFillColor(color(0xFFFFFF, 0.6).cgColor)
    context.addPath(path)
    context.fillPath()
    context.setStrokeColor(navy.withAlphaComponent(0.32).cgColor)
    context.setLineWidth(2)
    context.setLineDash(phase: 0, lengths: [8, 7])
    context.addPath(path)
    context.strokePath()
    context.restoreGState()
}

func drawArrow(in context: CGContext, from start: CGPoint, to end: CGPoint, lift: CGFloat) {
    let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - lift)
    let angle = atan2(end.y - control.y, end.x - control.x)
    let headLength: CGFloat = 22
    let headSpread: CGFloat = .pi / 6
    // End the shaft inside the head, so its round cap stays hidden.
    let shaftEnd = CGPoint(x: end.x - cos(angle) * headLength * 0.6, y: end.y - sin(angle) * headLength * 0.6)

    context.saveGState()
    // Shadow the arrow as one shape, so the shaft doesn't shade the head.
    context.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: captureRed.withAlphaComponent(0.35).cgColor)
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setStrokeColor(captureRed.cgColor)
    context.setFillColor(captureRed.cgColor)
    context.setLineWidth(7)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    let shaft = CGMutablePath()
    shaft.move(to: start)
    shaft.addQuadCurve(to: shaftEnd, control: control)
    context.addPath(shaft)
    context.strokePath()

    let head = CGMutablePath()
    head.move(to: end)
    head.addLine(to: CGPoint(x: end.x - cos(angle - headSpread) * headLength, y: end.y - sin(angle - headSpread) * headLength))
    head.addLine(to: CGPoint(x: end.x - cos(angle + headSpread) * headLength, y: end.y - sin(angle + headSpread) * headLength))
    head.closeSubpath()
    context.addPath(head)
    context.drawPath(using: .fillStroke)
    context.endTransparencyLayer()
    context.restoreGState()
}

func relativeLuminance(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGFloat {
    func linear(_ channel: CGFloat) -> CGFloat {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
}

/// The lowest WCAG contrast ratio between a text color and the pixels behind it.
func minimumContrast(of text: NSColor, over rect: CGRect, in bitmap: NSBitmapImageRep, scale: CGFloat) -> CGFloat {
    let textColor = text.usingColorSpace(.sRGB)!
    let textLuminance = relativeLuminance(textColor.redComponent, textColor.greenComponent, textColor.blueComponent)
    var minimum = CGFloat.infinity
    for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
        for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
            guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            let background = relativeLuminance(pixel.redComponent, pixel.greenComponent, pixel.blueComponent)
            let ratio = (max(textLuminance, background) + 0.05) / (min(textLuminance, background) + 0.05)
            minimum = min(minimum, ratio)
        }
    }
    return minimum
}

func render(scale: CGFloat, to url: URL) throws {
    let pixelsWide = Int(canvas.width * scale), pixelsHigh = Int(canvas.height * scale)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )?.retagging(with: .sRGB), let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else {
        throw CocoaError(.fileWriteUnknown)
    }
    // Draw in points with a top-left origin, matching Finder's icon coordinates.
    context.translateBy(x: 0, y: CGFloat(pixelsHigh))
    context.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

    drawBackground(in: context)
    drawCaptureBrackets(in: context, around: itemFrame(around: appIconCenter))
    drawDropZone(in: context, around: itemFrame(around: applicationsCenter))
    drawArrow(
        in: context,
        from: CGPoint(x: appIconCenter.x + iconSize / 2 + 36, y: appIconCenter.y + 4),
        to: CGPoint(x: applicationsCenter.x - iconSize / 2 - 32, y: appIconCenter.y + 4),
        lift: 44
    )
    context.flush()

    let checks = [
        ("title", title.color, title.frame),
        ("hint", hint.color, hint.frame),
        ("TobyShot label", finderLabel, labelFrame(below: appIconCenter)),
        ("Applications label", finderLabel, labelFrame(below: applicationsCenter)),
    ]
    for (name, textColor, rect) in checks {
        let contrast = minimumContrast(of: textColor, over: rect, in: bitmap, scale: scale)
        guard contrast >= 4.5 else {
            throw NSError(domain: "dmg-background", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The \(name) contrast is \(String(format: "%.1f", contrast)):1; it must be at least 4.5:1.",
            ])
        }
        if scale == 1 { print("\(name) contrast: \(String(format: "%.1f", contrast)):1") }
    }

    title.string.draw(at: title.frame.origin)
    hint.string.draw(at: hint.frame.origin)

    NSGraphicsContext.current = nil
    bitmap.size = canvas
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift scripts/dmg-background.swift <output-directory>\n".utf8))
    exit(2)
}
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try render(scale: 1, to: outputDirectory.appendingPathComponent("background.png"))
    try render(scale: 2, to: outputDirectory.appendingPathComponent("background@2x.png"))
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
