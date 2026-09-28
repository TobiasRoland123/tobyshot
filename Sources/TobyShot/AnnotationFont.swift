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

    private static let registerBundledFonts: Void = {
        for fontName in ["Excalifont-Regular", "Virgil"] {
            guard let url = Bundle.module.url(
                forResource: fontName,
                withExtension: "ttf",
                subdirectory: "Fonts"
            ) else {
                assertionFailure("Missing bundled annotation font: \(fontName).ttf")
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
