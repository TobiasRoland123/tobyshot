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
}
