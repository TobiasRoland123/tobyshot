import Foundation
import Vision

/// On-device text recognition shared by "Copy text from image" and library search.
enum TextRecognition {
    static func recognize(_ handler: VNImageRequestHandler, language: String, keepLines: Bool) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = language == "Automatic"
        if language == "English" { request.recognitionLanguages = ["en-US"] }
        if language == "Danish" { request.recognitionLanguages = ["da-DK"] }
        try handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: keepLines ? "\n" : " ")
    }

    /// Reads a saved screenshot for search. Lines are joined with spaces so a phrase can match across a line break.
    static func searchableText(in url: URL) async throws -> String {
        let language = Preferences.string("ocrLanguage")
        return try await Task.detached(priority: .utility) {
            try recognize(VNImageRequestHandler(url: url), language: language, keepLines: false)
        }.value
    }
}
