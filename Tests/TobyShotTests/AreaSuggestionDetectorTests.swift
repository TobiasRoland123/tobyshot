import AppKit
import Testing
@testable import TobyShot

struct AreaSuggestionDetectorTests {
    @Test(arguments: [1, 2])
    func detectsNestedBordersAndOmitsControlsAtNativeScale(scale: Int) throws {
        let rectangles = [CGRect(x: 40, y: 40, width: 800, height: 500),
                          CGRect(x: 70, y: 100, width: 730, height: 390),
                          CGRect(x: 100, y: 200, width: 180, height: 220),
                          CGRect(x: 310, y: 200, width: 450, height: 220)]
        let display = try fixture(scale: scale) { context in
            for rect in rectangles { box(rect, context: context) }
            box(CGRect(x: 100, y: 130, width: 100, height: 30), context: context)
            box(CGRect(x: 220, y: 130, width: 180, height: 30), context: context)
            // Unbounded text-like marks cannot become a suggested rectangle.
            context.setFillColor(CGColor(gray: 0.2, alpha: 1))
            for x in stride(from: 450, to: 700, by: 12) {
                context.fill(CGRect(x: x, y: 140, width: 7, height: 12))
            }
        }
        let result = try detect(display)
        let expected = rectangles.map { global($0, display: display) }
        #expect(Set(result) == Set(expected))
        for rect in result {
            let captured = try AreaCaptureComposition.capture(rect: rect, displays: [display])
            #expect(captured.image.size.width == rect.width * CGFloat(scale))
            #expect(captured.image.size.height == rect.height * CGFloat(scale))
        }
    }

    @Test func roundedBorderIsTightAndDoesNotIncludeShadow() throws {
        let rect = CGRect(x: 80, y: 70, width: 380, height: 250)
        let display = try fixture { context in
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 6), blur: 16, color: CGColor(gray: 0, alpha: 0.25))
            box(rect, radius: 16, context: context)
            context.restoreGState()
        }
        #expect(try detect(display) == [global(rect, display: display)])
    }

    @Test func uncertainEdgesAndOpenShapesAreOmitted() throws {
        let display = try fixture { context in
            context.setFillColor(CGColor(gray: 0.94, alpha: 1))
            context.fill(CGRect(x: 40, y: 40, width: 300, height: 200))
            context.setStrokeColor(CGColor(gray: 0.2, alpha: 1))
            context.setLineWidth(2)
            context.move(to: CGPoint(x: 400, y: 50))
            context.addLine(to: CGPoint(x: 700, y: 50))
            context.addLine(to: CGPoint(x: 700, y: 300))
            context.strokePath()
        }
        #expect(try detect(display).isEmpty)
    }

    @Test(arguments: [false, true])
    func subtleLightAndDarkBordersDoNotDependOnAbsoluteBrightness(dark: Bool) throws {
        let rect = CGRect(x: 80, y: 70, width: 380, height: 250)
        let display = try fixture { context in
            context.setFillColor(CGColor(gray: dark ? 0.1 : 0.95, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
            box(rect, radius: 12, border: dark ? 0.45 : 0.65, fill: dark ? 0.16 : 1, context: context)
        }
        #expect(try detect(display) == [global(rect, display: display)])
    }

    @Test func viewportCutIsNotMistakenForACompleteBorder() throws {
        let child = CGRect(x: 140, y: 180, width: 300, height: 180)
        let display = try fixture { context in
            context.saveGState()
            context.clip(to: CGRect(x: 100, y: 100, width: 400, height: 350))
            box(CGRect(x: 60, y: 60, width: 480, height: 360), fill: 0.8, context: context)
            box(child, context: context)
            context.restoreGState()
        }
        #expect(try detect(display) == [global(child, display: display)])
    }

    @Test func obscuredParentIsOmittedButVisibleChildStillQualifies() throws {
        let parent = CGRect(x: 40, y: 40, width: 750, height: 450)
        let child = CGRect(x: 70, y: 100, width: 220, height: 200)
        let display = try fixture { context in
            box(parent, context: context)
            box(child, context: context)
            context.setFillColor(CGColor(gray: 0.3, alpha: 1))
            context.fill(CGRect(x: 500, y: 80, width: 300, height: 300))
        }
        let result = try AreaSuggestionDetector.detect(in: display, displayFrame: CGRect(origin: .zero, size: display.frame.size),
            windows: [CGRect(x: 500, y: 80, width: 300, height: 300), CGRect(origin: .zero, size: display.frame.size)])
        #expect(!result.contains(global(parent, display: display)))
        #expect(result.contains(global(child, display: display)))
    }

    @Test func offscreenContainerIsOmittedButVisibleChildStillQualifies() throws {
        let child = CGRect(x: 650, y: 100, width: 150, height: 200)
        let display = try fixture { context in
            box(CGRect(x: 600, y: 40, width: 500, height: 450), context: context)
            box(child, context: context)
        }
        #expect(try detect(display) == [global(child, display: display)])
    }

    @Test func occlusionChecksInteriorAndDisplayEdgesInQuartzCoordinates() {
        let size = CGSize(width: 1600, height: 1200)
        let frame = CGRect(x: -800, y: -300, width: 800, height: 600)
        let rect = CGRect(x: 100, y: 100, width: 600, height: 400)
        #expect(AreaSuggestionDetector.isVisible(rect, imageSize: size, displayFrame: frame, windows: [frame]))
        let occluder = CGRect(x: -700, y: -200, width: 20, height: 20)
        #expect(!AreaSuggestionDetector.isVisible(rect, imageSize: size, displayFrame: frame, windows: [occluder, frame]))
        #expect(!AreaSuggestionDetector.isVisible(CGRect(x: 0, y: 0, width: 200, height: 200), imageSize: size, displayFrame: frame, windows: [frame]))
    }

    private func fixture(scale: Int = 1, draw: (CGContext) -> Void) throws -> CaptureDisplayImage {
        let width = 900, height = 600
        let context = try #require(CGContext(data: nil, width: width * scale, height: height * scale,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(gray: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(context)
        return CaptureDisplayImage(frame: CGRect(x: -900, y: -200, width: width, height: height), image: try #require(context.makeImage()))
    }

    private func box(_ rect: CGRect, radius: CGFloat = 0, border: CGFloat = 0.25, fill: CGFloat = 1, context: CGContext) {
        context.setFillColor(CGColor(gray: border, alpha: 1))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        context.setFillColor(CGColor(gray: fill, alpha: 1))
        context.addPath(CGPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerWidth: max(0, radius - 2), cornerHeight: max(0, radius - 2), transform: nil))
        context.fillPath()
    }

    private func detect(_ display: CaptureDisplayImage) throws -> [CGRect] {
        let frame = CGRect(origin: .zero, size: display.frame.size)
        return try AreaSuggestionDetector.detect(in: display, displayFrame: frame, windows: [frame])
    }

    private func global(_ rect: CGRect, display: CaptureDisplayImage) -> CGRect {
        CGRect(x: display.frame.minX + rect.minX, y: display.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

struct AreaSuggestionScrollTests {
    @Test func wheelTicksStepOnceAndTrackpadNeedsIntentionalMovement() {
        var wheel = AreaSuggestionScroll()
        #expect(wheel.step(delta: 1, precise: false, timestamp: 0) == true)
        #expect(wheel.step(delta: -12, precise: false, timestamp: 0.1) == false)
        var pad = AreaSuggestionScroll()
        #expect(pad.step(delta: 12, precise: true, timestamp: 0) == nil)
        #expect(pad.step(delta: 12, precise: true, timestamp: 0.01) == true)
        #expect(pad.step(delta: 30, precise: true, timestamp: 0.02) == nil)
        #expect(pad.step(delta: 1, precise: true, timestamp: 0.17) == true)
        #expect(pad.step(delta: -24, precise: true, timestamp: 0.18) == false)
    }

    @Test func idleGestureDoesNotAccumulateOldMotion() {
        var scroll = AreaSuggestionScroll()
        #expect(scroll.step(delta: 20, precise: true, timestamp: 0) == nil)
        #expect(scroll.step(delta: 10, precise: true, timestamp: 1) == nil)
        scroll.reset()
        #expect(scroll.step(delta: 14, precise: true, timestamp: 1.1) == nil)
    }
}
