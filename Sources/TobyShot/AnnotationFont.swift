import AppKit
import CoreText

enum AnnotationFont: String, CaseIterable, Identifiable {
    case system
    case excalifont
    case virgil

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .excalifont: "Excalifont"
        case .virgil: "Virgil"
        }
    }

    func font(ofSize size: CGFloat) -> NSFont {
        guard let postScriptName = postScriptName else {
            return NSFont.systemFont(ofSize: size, weight: .bold)
        }

        _ = Self.registerBundledFonts
        return NSFont(name: postScriptName, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: .bold)
    }

    private var postScriptName: String? {
        switch self {
        case .system: nil
        case .excalifont: "Excalifont-Regular"
        case .virgil: "Virgil3YOFF"
        }
    }

    static func resourceBundle(in bundle: Bundle = .main) -> Bundle? {
        guard bundle.bundleURL.pathExtension == "app" else { return .module }
        // Older SwiftPM accessors search beside the executable or in the build
        // directory, but build.sh installs the resources inside the app.
        return bundle.resourceURL
            .map { $0.appendingPathComponent("TobyShot_TobyShot.bundle") }
            .flatMap(Bundle.init(url:))
    }

    private static let registerBundledFonts: Void = {
        guard let bundle = resourceBundle() else {
            NSLog("TobyShot: Missing bundled annotation fonts")
            return
        }
        for fontName in ["Excalifont-Regular", "Virgil"] {
            guard let url = bundle.url(
                forResource: fontName,
                withExtension: "ttf",
                subdirectory: "Fonts"
            ) else {
                NSLog("TobyShot: Missing bundled annotation font: %@.ttf", fontName)
                continue
            }

            var registrationError: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError)
            let error = registrationError?.takeRetainedValue()
            let alreadyRegistered = error.map {
                CFErrorGetDomain($0) as String == kCTFontManagerErrorDomain as String
                    && CFErrorGetCode($0) == CTFontManagerError.alreadyRegistered.rawValue
            } ?? false
            if !registered, !alreadyRegistered {
                let message = error.map { String(describing: $0) } ?? "unknown Core Text error"
                assertionFailure("Could not register \(fontName).ttf: \(message)")
            }
        }
    }()
}
