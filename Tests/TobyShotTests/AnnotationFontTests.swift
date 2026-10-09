import AppKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AnnotationFontTests {
    @Test(arguments: [
        (AnnotationFont.excalifont, "Excalifont-Regular"),
        (AnnotationFont.virgil, "Virgil3YOFF")
    ])
    func bundledFontsRegisterWithTheirPostScriptNames(
        font: AnnotationFont,
        postScriptName: String
    ) {
        let renderedFont = font.font(ofSize: 23)
        #expect(renderedFont.fontName == postScriptName)
        #expect(renderedFont.pointSize == 23)
        #expect(["TobyShot", "Æblegrød", "Øresund", "Århus"].allSatisfy { text in
            text.unicodeScalars.allSatisfy { renderedFont.coveredCharacterSet.contains($0) }
        })
    }

    @Test func systemFontRemainsBoldAndSized() {
        let renderedFont = AnnotationFont.system.font(ofSize: 19)
        #expect(renderedFont.pointSize == 19)
        #expect(renderedFont.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test(arguments: [false, true])
    func relocatedAppFindsFontsInItsResources(macOSBundle: Bool) throws {
        let (directory, app) = try makeAppBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resourceURL = try #require(app.resourceURL)
        let bundleURL = resourceURL.appendingPathComponent("TobyShot_TobyShot.bundle")
        let fontDirectory = bundleURL.appendingPathComponent(macOSBundle ? "Contents/Resources/Fonts" : "Fonts")
        try FileManager.default.createDirectory(at: fontDirectory, withIntermediateDirectories: true)
        if macOSBundle {
            try PropertyListSerialization.data(fromPropertyList: [:], format: .xml, options: 0)
                .write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
        }
        for name in ["Excalifont-Regular", "Virgil"] {
            let source = try #require(Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts"))
            try FileManager.default.copyItem(at: source, to: fontDirectory.appendingPathComponent("\(name).ttf"))
        }

        let resources = try #require(AnnotationFont.resourceBundle(in: app))
        #expect(resources.bundleURL.path == bundleURL.path)
        for name in ["Excalifont-Regular", "Virgil"] {
            let fontURL = try #require(resources.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts"))
            #expect(fontURL.path == fontDirectory.appendingPathComponent("\(name).ttf").path)
        }
    }

    @Test func appWithMissingResourcesDoesNotUseTheBuildDirectory() throws {
        let (directory, app) = try makeAppBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(AnnotationFont.resourceBundle(in: app) == nil)
    }

    private func makeAppBundle() throws -> (URL, Bundle) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TobyShot-Fonts-\(UUID().uuidString)")
        let appURL = directory.appendingPathComponent("TobyShot.app")
        try FileManager.default.createDirectory(at: appURL.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "app.tobyshot.font-test", "CFBundlePackageType": "APPL"],
            format: .xml, options: 0)
            .write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        return (directory, try #require(Bundle(url: appURL)))
    }
}
