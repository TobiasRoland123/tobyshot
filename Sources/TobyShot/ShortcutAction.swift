import AppKit
import Carbon

enum ShortcutScope { case global, editor }

enum ShortcutGroup: String, CaseIterable, Identifiable {
    case general = "General", screenshots = "Screenshots", recording = "Screen Recording"
    case ocr = "OCR", overlay = "Quick Access Overlay", pin = "Pin"
    case annotate = "Annotate", tools = "Annotate Tools"
    var id: String { rawValue }
    var actions: [ShortcutAction] {
        if self == .screenshots {
            return [.captureArea, .capturePreviousArea, .captureFullScreen, .captureWindow, .captureTimer,
                    .captureAreaCopy, .captureAreaSave, .captureAreaAnnotate, .captureAreaPin]
        }
        return ShortcutAction.allCases.filter { $0.group == self }
    }
}

enum ShortcutAction: UInt32, CaseIterable, Identifiable {
    // Keep the original identifiers stable so existing customizations survive upgrades.
    case captureArea = 1, captureFullScreen, captureWindow, recordScreen, openImage
    case allInOne, captureHistory, restoreLastCapture, captureTimer
    case captureAreaCopy, captureAreaSave, captureAreaAnnotate, captureAreaPin
    case captureText, captureTextWithLines, captureTextWithoutLines
    case toggleOverlays, saveOverlays, closeOverlays
    case choosePin, togglePins, closePins, pinLastScreenshot, openClipboard, annotateLastScreenshot, capturePreviousArea
    case editorCopyObject = 100, editorDuplicate, editorSave, editorSaveAs, editorCopyScreenshot, editorPrint, editorPin
    case increaseToolSize = 200, decreaseToolSize, backgroundTool, moveTool, cropTool, drawTool
    case lineTool, textTool, arrowTool, counterTool, ellipseTool, redactionTool, rectangleTool, filledRectangleTool, pixelateTool

    var id: UInt32 { rawValue }
    var scope: ShortcutScope { rawValue >= 100 ? .editor : .global }
    var title: String {
        switch self {
        case .allInOne: return "All-in-One"
        case .captureHistory: return "Open Capture History"
        case .restoreLastCapture: return "Restore Last Capture"
        case .captureArea: return "Capture Area"
        case .capturePreviousArea: return "Capture Previous Area"
        case .captureFullScreen: return "Capture Fullscreen"
        case .captureWindow: return "Capture Window"
        case .captureTimer: return "Self-Timer"
        case .captureAreaCopy: return "Capture Area & Copy to Clipboard"
        case .captureAreaSave: return "Capture Area & Save"
        case .captureAreaAnnotate: return "Capture Area & Annotate"
        case .captureAreaPin: return "Capture Area & Pin to the Screen"
        case .recordScreen: return "Record Screen / Stop Recording"
        case .captureText: return "Capture Text"
        case .captureTextWithLines: return "Capture Text With Line Breaks"
        case .captureTextWithoutLines: return "Capture Text Without Line Breaks"
        case .toggleOverlays: return "Hide/Show Overlays"
        case .saveOverlays: return "Save All Overlays"
        case .closeOverlays: return "Close All Overlays"
        case .choosePin: return "Choose and Pin an Image"
        case .togglePins: return "Toggle Pins Visibility"
        case .closePins: return "Close All Pins"
        case .pinLastScreenshot: return "Pin Last Screenshot"
        case .openImage: return "Open File"
        case .openClipboard: return "Open From Clipboard"
        case .annotateLastScreenshot: return "Annotate Last Screenshot"
        case .editorCopyObject: return "Copy Object to Clipboard"
        case .editorDuplicate: return "Duplicate Object"
        case .editorSave: return "Save"
        case .editorSaveAs: return "Save as"
        case .editorCopyScreenshot: return "Copy Screenshot to Clipboard"
        case .editorPrint: return "Print"
        case .editorPin: return "Pin to the Screen"
        case .increaseToolSize: return "Increase Tool Size"
        case .decreaseToolSize: return "Decrease Tool Size"
        case .backgroundTool: return "Background Tool"
        case .moveTool: return "Move Tool"
        case .cropTool: return "Crop Tool"
        case .drawTool: return "Draw Tool"
        case .lineTool: return "Line Tool"
        case .textTool: return "Text Tool"
        case .arrowTool: return "Arrow Tool"
        case .counterTool: return "Counter Tool"
        case .ellipseTool: return "Ellipse Tool"
        case .redactionTool: return "Redaction Tool"
        case .rectangleTool: return "Rectangle Tool"
        case .filledRectangleTool: return "Filled Rectangle Tool"
        case .pixelateTool: return "Pixelate Tool"
        }
    }

    var group: ShortcutGroup {
        switch self {
        case .allInOne, .captureHistory, .restoreLastCapture: return .general
        case .captureArea, .captureFullScreen, .captureWindow, .capturePreviousArea, .captureTimer,
             .captureAreaCopy, .captureAreaSave, .captureAreaAnnotate, .captureAreaPin: return .screenshots
        case .recordScreen: return .recording
        case .captureText, .captureTextWithLines, .captureTextWithoutLines: return .ocr
        case .toggleOverlays, .saveOverlays, .closeOverlays: return .overlay
        case .choosePin, .togglePins, .closePins, .pinLastScreenshot: return .pin
        default: return rawValue >= 200 ? .tools : .annotate
        }
    }

    var defaultBinding: ShortcutBinding? {
        let key: Int
        var modifiers = UInt32(0)
        switch self {
        case .captureArea: key = kVK_ANSI_4; modifiers = UInt32(cmdKey | shiftKey)
        case .captureFullScreen: key = kVK_ANSI_3; modifiers = UInt32(cmdKey | shiftKey)
        case .allInOne: key = kVK_ANSI_5; modifiers = UInt32(cmdKey | shiftKey)
        // Preserve the user's earlier preference for Command-based app shortcuts.
        case .openClipboard: key = kVK_ANSI_V; modifiers = UInt32(cmdKey | shiftKey)
        case .editorCopyObject: key = kVK_ANSI_C; modifiers = UInt32(cmdKey)
        case .editorDuplicate: key = kVK_ANSI_D; modifiers = UInt32(cmdKey)
        case .editorSave: key = kVK_ANSI_S; modifiers = UInt32(cmdKey)
        case .editorSaveAs: key = kVK_ANSI_S; modifiers = UInt32(cmdKey | shiftKey)
        case .editorCopyScreenshot: key = kVK_ANSI_C; modifiers = UInt32(cmdKey | shiftKey)
        case .editorPrint: key = kVK_ANSI_P; modifiers = UInt32(cmdKey)
        case .increaseToolSize: return .forCharacter("'", fallback: kVK_ANSI_Quote)
        case .decreaseToolSize: return .forCharacter("+", fallback: kVK_ANSI_Equal)
        case .backgroundTool: key = kVK_ANSI_B
        case .moveTool: key = kVK_ANSI_V
        case .cropTool: key = kVK_ANSI_K
        case .drawTool: key = kVK_ANSI_D
        case .lineTool: key = kVK_ANSI_L
        case .textTool: key = kVK_ANSI_T
        case .arrowTool: key = kVK_ANSI_A
        case .counterTool: key = kVK_ANSI_C
        case .ellipseTool: key = kVK_ANSI_E
        case .redactionTool: key = kVK_ANSI_P
        case .rectangleTool: key = kVK_ANSI_R
        case .filledRectangleTool: key = kVK_ANSI_F
        case .pixelateTool: key = kVK_ANSI_X
        default: return nil
        }
        return ShortcutBinding(keyCode: UInt32(key), modifiers: modifiers)
    }

    var preferenceKey: String { "shortcut.\(rawValue)" }
}
