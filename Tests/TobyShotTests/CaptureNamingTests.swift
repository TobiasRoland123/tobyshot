import Foundation
import Testing
@testable import TobyShot

struct CaptureNamingTests {
    @Test(arguments: ["a", "æ", "📸", "👍🏽", "e\u{301}"])
    func limitsUTF8BytesWithoutSplittingCharacters(character: String) {
        let template = String(repeating: character, count: 200)
        let expected = String(repeating: character, count: 180 / character.utf8.count)

        #expect(CaptureNaming.filename(template: template) == expected)
        #expect(CaptureNaming.filename(template: template, retina: true) == expected + "@2x")
    }

    @Test
    func fallsBackWhenTheFirstCharacterExceedsTheByteLimit() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let template = "e" + String(repeating: "\u{301}", count: 200)
        #expect(template.count == 1)
        #expect(CaptureNaming.filename(template: template, date: date, retina: true)
                == CaptureNaming.filename(template: "", date: date, retina: true))
    }

    @Test(arguments: ["png", "jpg", "tiff", "mp4"])
    func longUnicodeNamesCanBeWrittenAndCollisionSuffixesRemainUsable(ext: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = CaptureNaming.filename(template: String(repeating: "📸", count: 200), retina: true)
        let first = CaptureNaming.uniqueURL(directory: directory, name: name, ext: ext)
        try Data([1]).write(to: first, options: .atomic)
        let second = CaptureNaming.uniqueURL(directory: directory, name: name, ext: ext)
        try Data([2]).write(to: second, options: .atomic)

        #expect(first != second)
        #expect(second.lastPathComponent == name + " 2." + ext)
        #expect(try Data(contentsOf: first) == Data([1]))
        #expect(try Data(contentsOf: second) == Data([2]))
    }
}
