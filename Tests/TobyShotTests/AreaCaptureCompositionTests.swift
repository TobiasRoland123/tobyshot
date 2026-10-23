import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AreaCaptureCompositionTests {
    @Test func composesSideBySideDisplaysAtHighestIntersectingScaleAndKeepsOrientation() throws {
        let left = CaptureDisplayImage(frame: CGRect(x: -2, y: 0, width: 2, height: 2),
            image: raster(width: 2, height: 2, colorsTopDown: [.green, .green, .blue, .blue]))
        let right = CaptureDisplayImage(frame: CGRect(x: 0, y: 0, width: 2, height: 2),
            image: solidRaster(width: 4, height: 4, color: .cyan))
        let rect = CGRect(x: -1, y: 0, width: 3, height: 2)

        let result = try AreaCaptureComposition.capture(rect: rect, displays: [left, right])
        let output = try cgImage(result.image)

        #expect(result.scale == 2)
        #expect(result.isWindow == false)
        #expect(output.width == 6)
        #expect(output.height == 4)
        #expect(rgb(output, x: 0, topY: 0) == [0, 255, 0])
        #expect(rgb(output, x: 0, topY: 3) == [0, 0, 255])
        #expect(rgb(output, x: 2, topY: 0) == [0, 255, 255])
        #expect(rgb(output, x: 5, topY: 3) == [0, 255, 255])
    }

    @Test func placesDisplaysVerticallyAcrossNegativeOrigins() throws {
        let bottom = CaptureDisplayImage(frame: CGRect(x: -1, y: -2, width: 2, height: 2),
            image: solidRaster(width: 2, height: 2, color: .orange))
        let top = CaptureDisplayImage(frame: CGRect(x: -1, y: 0, width: 2, height: 2),
            image: solidRaster(width: 2, height: 2, color: .purple))

        let result = try AreaCaptureComposition.capture(rect: CGRect(x: -1, y: -2, width: 2, height: 4), displays: [bottom, top])
        let output = try cgImage(result.image)

        #expect(output.width == 2)
        #expect(output.height == 4)
        #expect(rgb(output, x: 0, topY: 0) == [128, 0, 128])
        #expect(rgb(output, x: 0, topY: 3) == [255, 128, 0])
    }

    @Test func leavesGapsTransparentAndIgnoresNonintersectingRetinaDisplay() throws {
        let left = CaptureDisplayImage(frame: CGRect(x: 0, y: 0, width: 1, height: 1),
            image: solidRaster(width: 1, height: 1, color: .red))
        let right = CaptureDisplayImage(frame: CGRect(x: 2, y: 0, width: 1, height: 1),
            image: solidRaster(width: 1, height: 1, color: .blue))
        let remoteRetina = CaptureDisplayImage(frame: CGRect(x: 20, y: 0, width: 1, height: 1),
            image: solidRaster(width: 4, height: 4, color: .white))
        let rect = CGRect(x: 0, y: 0, width: 3, height: 1)

        #expect(AreaCaptureComposition.scale(for: rect, displays: [left, right, remoteRetina]) == 1)
        let result = try AreaCaptureComposition.capture(rect: rect, displays: [left, right, remoteRetina])
        let output = try cgImage(result.image)

        #expect(output.width == 3)
        #expect(rgba(output, x: 0, topY: 0).alpha == 255)
        #expect(rgba(output, x: 1, topY: 0).alpha == 0)
        #expect(rgb(output, x: 2, topY: 0) == [0, 0, 255])
    }

    @Test func fractionalSelectionKeepsEveryTouchedEdgePixelAndReportsItsRasterSize() throws {
        let display = CaptureDisplayImage(frame: CGRect(x: -1, y: -1, width: 2, height: 2),
            image: solidRaster(width: 4, height: 4, color: .magenta))
        let rect = CGRect(x: -0.75, y: -0.75, width: 1.25, height: 1.25)

        let result = try AreaCaptureComposition.capture(rect: rect, displays: [display])
        let output = try cgImage(result.image)

        #expect(result.scale == 2)
        #expect(output.width == Int(AreaCaptureComposition.pixelSize(for: rect, displays: [display]).width))
        #expect(output.height == Int(AreaCaptureComposition.pixelSize(for: rect, displays: [display]).height))
        #expect(output.width == 3)
        #expect(output.height == 3)
        #expect(rgb(output, x: 0, topY: 0) == [255, 0, 255])
        #expect(rgb(output, x: 2, topY: 2) == [255, 0, 255])
    }

    @Test func fractionalMultidisplayCropKeepsNativeRetinaPixelsAlignedToGlobalGrid() throws {
        let oneTimes = CaptureDisplayImage(frame: CGRect(x: 0, y: 0, width: 2, height: 2),
            image: solidRaster(width: 2, height: 2, color: .red))
        let twoTimes = CaptureDisplayImage(frame: CGRect(x: 2, y: 0, width: 2, height: 2), image: raster(width: 4, height: 4, colorsTopDown: [
            .red, .green, .blue, .white,
            .yellow, .orange, .purple, .cyan,
            .magenta, .red, .green, .blue,
            .white, .yellow, .orange, .purple
        ]))
        let rect = CGRect(x: 0.2, y: 0.2, width: 3, height: 0.9)

        let result = try AreaCaptureComposition.capture(rect: rect, displays: [oneTimes, twoTimes])
        let output = try cgImage(result.image)
        let size = AreaCaptureComposition.pixelSize(for: rect, displays: [oneTimes, twoTimes])

        #expect(result.scale == 2)
        #expect(size == CGSize(width: 7, height: 3))
        #expect(CGSize(width: output.width, height: output.height) == size)
        #expect(rgb(output, x: 4, topY: 0) == [255, 255, 0])
        #expect(rgb(output, x: 5, topY: 0) == [255, 128, 0])
        #expect(rgb(output, x: 6, topY: 0) == [128, 0, 128])
        #expect(rgb(output, x: 4, topY: 2) == [255, 255, 255])
        #expect(rgb(output, x: 5, topY: 2) == [255, 255, 0])
        #expect(rgb(output, x: 6, topY: 2) == [255, 128, 0])
    }

    @Test func verticallyOffsetDisplaysUseTheirOwnWidthAndHeightRatiosForPartialCrops() throws {
        let upper = CaptureDisplayImage(frame: CGRect(x: 0, y: 1, width: 2, height: 2), image: raster(width: 3, height: 4, colorsTopDown: [
            .red, .red, .red,
            .yellow, .orange, .purple,
            .cyan, .magenta, .white,
            .blue, .yellow, .red
        ]))
        let lower = CaptureDisplayImage(frame: CGRect(x: 0, y: -1, width: 2, height: 2), image: raster(width: 4, height: 3, colorsTopDown: [
            .red, .green, .blue, .white,
            .cyan, .magenta, .purple, .orange,
            .white, .white, .white, .white
        ]))
        let rect = CGRect(x: 0.25, y: -0.75, width: 1.5, height: 3.5)

        let result = try AreaCaptureComposition.capture(rect: rect, displays: [upper, lower])
        let output = try cgImage(result.image)
        let size = AreaCaptureComposition.pixelSize(for: rect, displays: [upper, lower])

        #expect(result.scale == 2)
        #expect(size == CGSize(width: 4, height: 8))
        #expect(CGSize(width: output.width, height: output.height) == size)
        for x in 0..<output.width {
            #expect(rgb(output, x: x, topY: 0) == [255, 0, 0])
            #expect(rgb(output, x: x, topY: output.height - 1) == [255, 255, 255])
        }
    }

    @Test func singleDisplayUsesUnscaledNativePixelCropAndPixelSizeMatches() throws {
        let source = raster(width: 4, height: 4, colorsTopDown: [
            .red, .green, .blue, .white,
            .red, .green, .blue, .white,
            .yellow, .orange, .purple, .cyan,
            .yellow, .orange, .purple, .cyan
        ])
        let display = CaptureDisplayImage(frame: CGRect(x: -2, y: 3, width: 2, height: 2), image: source)
        let rect = CGRect(x: -1.5, y: 3.5, width: 1, height: 1)

        let result = try AreaCaptureComposition.capture(rect: rect, displays: [display])
        let output = try cgImage(result.image)
        let size = AreaCaptureComposition.pixelSize(for: rect, displays: [display])

        #expect(result.scale == 2)
        #expect(output.width == 2)
        #expect(output.height == 2)
        #expect(size == CGSize(width: 2, height: 2))
        #expect(rgb(output, x: 0, topY: 0) == [0, 255, 0])
        #expect(rgb(output, x: 1, topY: 0) == [0, 0, 255])
        #expect(rgb(output, x: 0, topY: 1) == [255, 128, 0])
        #expect(rgb(output, x: 1, topY: 1) == [128, 0, 128])
    }

    @Test func selectionWithoutDisplayIntersectionThrows() {
        let display = CaptureDisplayImage(frame: CGRect(x: 0, y: 0, width: 1, height: 1),
            image: solidRaster(width: 2, height: 2, color: .red))
        #expect(throws: (any Error).self) {
            try AreaCaptureComposition.capture(rect: CGRect(x: 4, y: 4, width: 1, height: 1), displays: [display])
        }
    }

    private enum Color { case red, green, blue, white, yellow, orange, purple, cyan, magenta }

    private func raster(width: Int, height: Int, colorsTopDown: [Color]) -> CGImage {
        precondition(colorsTopDown.count == width * height)
        let bytes = colorsTopDown.flatMap { color -> [UInt8] in
            switch color {
            case .red: [255, 0, 0, 255]
            case .green: [0, 255, 0, 255]
            case .blue: [0, 0, 255, 255]
            case .white: [255, 255, 255, 255]
            case .yellow: [255, 255, 0, 255]
            case .orange: [255, 128, 0, 255]
            case .purple: [128, 0, 128, 255]
            case .cyan: [0, 255, 255, 255]
            case .magenta: [255, 0, 255, 255]
            }
        }
        let data = Data(bytes) as CFData
        let provider = CGDataProvider(data: data)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func solidRaster(width: Int, height: Int, color: Color) -> CGImage {
        raster(width: width, height: height, colorsTopDown: Array(repeating: color, count: width * height))
    }

    private func cgImage(_ image: NSImage) throws -> CGImage {
        var proposed = CGRect(origin: .zero, size: image.size)
        return try #require(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
    }

    private func rgba(_ image: CGImage, x: Int, topY: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let data = image.dataProvider!.data! as Data
        let offset = topY * image.bytesPerRow + x * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    private func rgb(_ image: CGImage, x: Int, topY: Int) -> [UInt8] {
        let pixel = rgba(image, x: x, topY: topY)
        return [pixel.red, pixel.green, pixel.blue]
    }
}
