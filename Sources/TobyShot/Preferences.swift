import AppKit

enum Preferences {
    static let defaults = UserDefaults.standard
    static func register() {
        defaults.register(defaults: [
            "showMenuBar": true, "hideDesktopIcons": true, "playSounds": true, "shutterSound": "Tink",
            "exportPath": FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/TobyShot").path,
            "afterScreenshotOverlay": true, "afterScreenshotCopy": true, "afterScreenshotSave": true,
            "afterScreenshotAnnotate": false, "afterScreenshotPin": false,
            "afterRecordingOverlay": true, "afterRecordingCopy": true, "afterRecordingSave": true, "afterRecordingOpen": false,
            "overlayPosition": "Right", "overlayActiveScreen": true, "overlaySize": 280.0,
            "overlayAutoClose": true, "overlayInterval": 8.0, "overlayCloseAfterDrag": true,
            "saveBehavior": "Export location", "imageFormat": "PNG", "convertSRGB": true,
            "retinaOneX": false, "imageBorder": false, "backgroundPreset": "None", "selfTimer": 5,
            "screenshotCursor": false, "windowBackground": "Transparent", "windowPadding": 32.0,
            "windowShadow": true, "recordingControls": true, "recordingCountdown": true,
            "recordingCursor": true, "recordingFPS": 30, "recordingResolution": "Original",
            "recordingOneX": false, "recordingSystemAudio": false, "recordingMicrophone": false,
            "inverseArrow": false, "smoothDrawing": true, "annotationShadow": true,
            "editorAlwaysOnTop": false, "showColorNames": false,
            "filenameTemplate": "TobyShot {date} at {time}", "askFilename": false, "retinaSuffix": false,
            "clipboardMode": "File & Image", "historyDays": 7, "ocrLineBreaks": true, "ocrLanguage": "Automatic",
            "pinnedRounded": true, "pinnedShadow": true, "pinnedBorder": true, "wallpaperStyle": "Midnight"
        ])
    }
    static func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }
    static func string(_ key: String) -> String { defaults.string(forKey: key) ?? "" }
    static func int(_ key: String) -> Int { defaults.integer(forKey: key) }
    static func double(_ key: String) -> Double { defaults.double(forKey: key) }
    static var exportDirectory: URL { URL(fileURLWithPath: (string("exportPath") as NSString).expandingTildeInPath, isDirectory: true) }
}

enum CaptureNaming {
    static func filename(template: String, date: Date = Date(), retina: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = "HH.mm.ss"
        let time = formatter.string(from: date)
        let result = template.replacingOccurrences(of: "{date}", with: day)
            .replacingOccurrences(of: "{time}", with: time)
            .components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String((result.isEmpty ? "TobyShot \(day) at \(time)" : result).prefix(180))
        return name + (retina ? "@2x" : "")
    }

    static func uniqueURL(directory: URL, name: String, ext: String) -> URL {
        var url = directory.appendingPathComponent(name).appendingPathExtension(ext)
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(name) \(index)").appendingPathExtension(ext)
            index += 1
        }
        return url
    }
}
