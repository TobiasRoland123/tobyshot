import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var shortcuts: HotKeyManager
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("hideDesktopIcons") private var hideDesktopIcons = true
    @AppStorage("playSounds") private var playSounds = true
    @AppStorage("shutterSound") private var shutterSound = "Tink"
    @AppStorage("exportPath") private var exportPath = "~/Pictures/TobyShot"

    @AppStorage("afterScreenshotOverlay") private var afterScreenshotOverlay = true
    @AppStorage("afterScreenshotCopy") private var afterScreenshotCopy = true
    @AppStorage("afterScreenshotSave") private var afterScreenshotSave = true
    @AppStorage("afterScreenshotAnnotate") private var afterScreenshotAnnotate = false
    @AppStorage("afterScreenshotPin") private var afterScreenshotPin = false
    @AppStorage("afterRecordingOverlay") private var afterRecordingOverlay = true
    @AppStorage("afterRecordingCopy") private var afterRecordingCopy = true
    @AppStorage("afterRecordingSave") private var afterRecordingSave = true
    @AppStorage("afterRecordingOpen") private var afterRecordingOpen = false

    @AppStorage("overlayPosition") private var overlayPosition = "Right"
    @AppStorage("overlayActiveScreen") private var overlayActiveScreen = true
    @AppStorage("overlaySize") private var overlaySize = 280.0
    @AppStorage("overlayAutoClose") private var overlayAutoClose = true
    @AppStorage("overlayInterval") private var overlayInterval = 8.0
    @AppStorage("overlayCloseAfterDrag") private var overlayCloseAfterDrag = true
    @AppStorage("saveBehavior") private var saveBehavior = "Export location"

    @AppStorage("imageFormat") private var imageFormat = "PNG"
    @AppStorage("convertSRGB") private var convertSRGB = true
    @AppStorage("retinaOneX") private var retinaOneX = false
    @AppStorage("imageBorder") private var imageBorder = false
    @AppStorage("backgroundPreset") private var backgroundPreset = "None"
    @AppStorage("selfTimer") private var selfTimer = 5
    @AppStorage("screenshotCursor") private var screenshotCursor = false
    @AppStorage("windowBackground") private var windowBackground = "Transparent"
    @AppStorage("windowPadding") private var windowPadding = 32.0
    @AppStorage("windowShadow") private var windowShadow = true

    @AppStorage("recordingControls") private var recordingControls = true
    @AppStorage("recordingCountdown") private var recordingCountdown = true
    @AppStorage("recordingCursor") private var recordingCursor = true
    @AppStorage("recordingFPS") private var recordingFPS = 30
    @AppStorage("recordingResolution") private var recordingResolution = "Original"
    @AppStorage("recordingOneX") private var recordingOneX = false
    @AppStorage("recordingSystemAudio") private var recordingSystemAudio = false
    @AppStorage("recordingMicrophone") private var recordingMicrophone = false

    @AppStorage("inverseArrow") private var inverseArrow = false
    @AppStorage("annotationFont") private var annotationFont: AnnotationFont = .system
    @AppStorage("annotationArrowStyle") private var annotationArrowStyle: AnnotationArrowStyle = .clean
    @AppStorage("annotationArrowStroke") private var annotationArrowStroke: AnnotationArrowStroke = .solid
    @AppStorage("smoothDrawing") private var smoothDrawing = true
    @AppStorage("annotationShadow") private var annotationShadow = true
    @AppStorage("editorAlwaysOnTop") private var editorAlwaysOnTop = false
    @AppStorage("showColorNames") private var showColorNames = false

    @AppStorage("filenameTemplate") private var filenameTemplate = "TobyShot {date} at {time}"
    @AppStorage("askFilename") private var askFilename = false
    @AppStorage("retinaSuffix") private var retinaSuffix = false
    @AppStorage("clipboardMode") private var clipboardMode = "File & Image"
    @AppStorage("historyDays") private var historyDays = 7
    @AppStorage("ocrLineBreaks") private var ocrLineBreaks = true
    @AppStorage("ocrLanguage") private var ocrLanguage = "Automatic"
    @AppStorage("pinnedRounded") private var pinnedRounded = true
    @AppStorage("pinnedShadow") private var pinnedShadow = true
    @AppStorage("pinnedBorder") private var pinnedBorder = true

    @AppStorage("wallpaperStyle") private var wallpaperStyle = "Midnight"

    @State private var selection: SettingsSection = .general
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private let accent = Color(red: 0.26, green: 0.62, blue: 1.0)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
            page
        }
        .frame(minWidth: 860, idealWidth: 860, minHeight: 720, idealHeight: 850)
        .background(Color(white: 0.10))
        .preferredColorScheme(.dark)
        .tint(accent)
        .onAppear(perform: refreshLoginStatus)
        .alert("Couldn’t update Login Items", isPresented: Binding(
            get: { loginError != nil },
            set: { if !$0 { loginError = nil } }
        )) {
            Button("OK", role: .cancel) { loginError = nil }
        } message: {
            Text(loginError ?? "Please try again.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 30, weight: .medium))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text("TobyShot").font(.system(size: 15, weight: .semibold))
                    Text("Local first").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 25)
            .padding(.bottom, 27)

            VStack(spacing: 3) {
                ForEach(SettingsSection.primary) { section in
                    sidebarButton(section)
                }
            }
            Spacer(minLength: 12)
            sidebarButton(.about)
                .padding(.bottom, 18)
        }
        .frame(width: 210)
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.12))
    }

    private func sidebarButton(_ section: SettingsSection) -> some View {
        Button { selection = section } label: {
            HStack(spacing: 11) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(section.color)
                    .frame(width: 25, height: 25)
                    .background(section.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
                Text(section.title)
                    .font(.system(size: 13, weight: selection == section ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selection == section ? Color.white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == section ? .isSelected : [])
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                Text(selection.title)
                    .font(.system(size: 20, weight: .bold))
                    .padding(.bottom, 1)
                pageContent
            }
            .padding(.horizontal, 29)
            .padding(.top, 27)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var pageContent: some View {
        switch selection {
        case .general: generalPage
        case .shortcuts: shortcutsPage
        case .quickAccess: quickAccessPage
        case .wallpaper: wallpaperPage
        case .screenshots: screenshotsPage
        case .recording: recordingPage
        case .annotate: annotatePage
        case .cloud: cloudPage
        case .advanced: advancedPage
        case .about: aboutPage
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            group("App") {
                ToggleRow("Launch at login", isOn: $loginEnabled, detail: "Starts TobyShot when you sign in.")
                    .onChange(of: loginEnabled) { _, enabled in updateLoginItem(enabled) }
                ToggleRow("Show menu bar icon", isOn: $showMenuBar)
            }
            group("Capture") {
                ToggleRow("Hide desktop icons while capturing", isOn: $hideDesktopIcons,
                          detail: "Excludes desktop icons from captures without changing your desktop.")
            }
            group("Sounds") {
                ToggleRow("Play sounds", isOn: $playSounds)
                PickerRow("Shutter sound", selection: $shutterSound, options: ["Tink", "Pop", "Glass", "None"])
            }
            group("Export") {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Export location").font(.system(size: 13))
                        Text(expandedExportPath).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button("Choose…", action: chooseExportFolder)
                        .controlSize(.small)
                }
                .padding(.vertical, 3)
                Text("Used when you save a capture from TobyShot.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.top, 3)
            }
            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("After capture")
                Text("Choose which local actions TobyShot runs after each capture.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    HStack {
                        Text("Action").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Screenshot").frame(width: 86)
                        Text("Recording").frame(width: 86)
                    }.font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.vertical, 12)
                    afterCaptureRow("Show Quick Access", screenshot: $afterScreenshotOverlay, recording: $afterRecordingOverlay)
                    afterCaptureRow("Copy to clipboard", screenshot: $afterScreenshotCopy, recording: $afterRecordingCopy)
                    afterCaptureRow("Save", screenshot: $afterScreenshotSave, recording: $afterRecordingSave)
                    afterCaptureRow("Open Annotate", screenshot: $afterScreenshotAnnotate, recording: nil)
                    afterCaptureRow("Pin to screen", screenshot: $afterScreenshotPin, recording: nil)
                    afterCaptureRow("Open recording", screenshot: nil, recording: $afterRecordingOpen)
                }.padding(.horizontal, 12).padding(.bottom, 5)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                ComingNext(items: ["Cloud upload and share links", "Open video editor"])
            }
        }
    }

    private func afterCaptureRow(_ title: String, screenshot: Binding<Bool>?, recording: Binding<Bool>?) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if let screenshot { Toggle(title + " for screenshots", isOn: screenshot).labelsHidden().toggleStyle(.checkbox) }
                else { Text("—").foregroundStyle(.tertiary) }
            }.frame(width: 86)
            Group {
                if let recording { Toggle(title + " for recordings", isOn: recording).labelsHidden().toggleStyle(.checkbox) }
                else { Text("—").foregroundStyle(.tertiary) }
            }.frame(width: 86)
        }.frame(height: 33).overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.065)).frame(height: 1) }
    }

    private var shortcutsPage: some View {
        ShortcutSettingsView(shortcuts: shortcuts)
    }

    private var quickAccessPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            group("Appearance") {
                PickerRow("Position on screen", selection: $overlayPosition, options: ["Left", "Right"])
                ToggleRow("Move to active screen", isOn: $overlayActiveScreen,
                          detail: "Follows the screen where your pointer is located.")
                SliderRow("Overlay size", value: $overlaySize, range: 220...400, valueText: "\(Int(overlaySize)) px")
            }
            group("Behavior") {
                ToggleRow("Auto-close", isOn: $overlayAutoClose)
                PickerRow("Close after", selection: $overlayInterval, options: [5.0, 8.0, 15.0, 30.0], titleForValue: { "\(Int($0)) seconds" })
                ToggleRow("Close after dragging", isOn: $overlayCloseAfterDrag)
                PickerRow("Save button behavior", selection: $saveBehavior, options: ["Export location", "Ask every time"])
            }
        }
    }

    private var wallpaperPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose the look used by TobyShot’s capture backgrounds.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            group("Wallpaper") {
                PickerRow("Background style", selection: $wallpaperStyle, options: ["Midnight", "Lavender", "Peach"])
            }
            HStack(spacing: 10) {
                ForEach([
                    WallpaperSwatch(name: "Midnight", color: Color(red: 0.12, green: 0.14, blue: 0.22)),
                    WallpaperSwatch(name: "Lavender", color: Color(red: 0.47, green: 0.38, blue: 0.62)),
                    WallpaperSwatch(name: "Peach", color: Color(red: 0.80, green: 0.47, blue: 0.37))
                ]) { item in
                    Button { wallpaperStyle = item.name } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 9).fill(item.color.gradient).frame(height: 92)
                                .overlay(alignment: .bottomTrailing) {
                                    if wallpaperStyle == item.name { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white).padding(8) }
                                }
                            Text(item.name).font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.name)
                    .accessibilityAddTraits(wallpaperStyle == item.name ? .isSelected : [])
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            Text("Wallpaper styles are stored on this Mac and can be used as screenshot backgrounds.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var screenshotsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            group("Output") {
                PickerRow("File format", selection: $imageFormat, options: ["PNG", "JPEG", "TIFF"])
                ToggleRow("Convert to sRGB profile", isOn: $convertSRGB)
                ToggleRow("Scale Retina screenshots to 1×", isOn: $retinaOneX)
                ToggleRow("Add 1 px border", isOn: $imageBorder)
                PickerRow("Background preset", selection: $backgroundPreset, options: ["None", "Midnight", "Lavender", "Peach"])
            }
            group("Capture") {
                PickerRow("Self-timer", selection: $selfTimer, options: [3, 5, 10], titleForValue: { "\($0) seconds" })
                ToggleRow("Show cursor in screenshots", isOn: $screenshotCursor, detail: "Applies to full-screen and self-timer captures.")
            }
            group("Window screenshots") {
                PickerRow("Background", selection: $windowBackground, options: ["Transparent", "Wallpaper"])
                SliderRow("Padding", value: $windowPadding, range: 0...100, valueText: "\(Int(windowPadding)) px")
                ToggleRow("Capture window shadow", isOn: $windowShadow)
            }
        }
    }

    private var recordingPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            group("General") {
                ToggleRow("Show controls while recording", isOn: $recordingControls)
                ToggleRow("Show countdown", isOn: $recordingCountdown)
            }
            group("Cursor") {
                ToggleRow("Show cursor", isOn: $recordingCursor)
            }
            group("Video") {
                PickerRow("Frame rate", selection: $recordingFPS, options: [15, 30, 60], titleForValue: { "\($0) fps" })
                PickerRow("Maximum resolution", selection: $recordingResolution, options: ["Original", "1080p", "720p"])
                Text("Original preserves display resolution up to 4096 pixels on the longest edge.").font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 5)
                ToggleRow("Scale Retina recordings to 1×", isOn: $recordingOneX)
            }
            group("Audio") {
                ToggleRow("Record system audio", isOn: $recordingSystemAudio)
                ToggleRow("Record microphone", isOn: $recordingMicrophone)
            }
            ComingNext(items: ["GIF export", "Keystroke overlay", "Click highlights", "Do Not Disturb while recording"])
        }
    }

    private var annotatePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            group("Appearance") {
                PickerRow("Text font", selection: $annotationFont, options: AnnotationFont.allCases, titleForValue: { $0.title })
                PickerRow("Arrow style", selection: $annotationArrowStyle, options: AnnotationArrowStyle.allCases, titleForValue: { $0.title })
                PickerRow("Arrow stroke", selection: $annotationArrowStroke, options: AnnotationArrowStroke.allCases, titleForValue: { $0.title })
                Text("Choose Excalifont or Virgil with hand-drawn arrows for an Excalidraw feel. Changes apply to new annotations.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                annotationPreview
            }
            group("Tools") {
                ToggleRow("Inverse arrow direction", isOn: $inverseArrow)
                ToggleRow("Smooth drawing", isOn: $smoothDrawing)
                ToggleRow("Draw shadow on objects", isOn: $annotationShadow)
            }
            group("Window") {
                ToggleRow("Always on top", isOn: $editorAlwaysOnTop)
            }
            group("Accessibility") {
                ToggleRow("Show color names", isOn: $showColorNames)
            }
        }
    }

    private var annotationPreview: some View {
        // Render at Retina resolution so the resized settings preview stays sharp.
        let size = CGSize(width: 1000, height: 280)
        let source = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        let annotations = [
            EditorAnnotation(kind: .text, start: CGPoint(x: 48, y: 40), end: .zero,
                             color: .black, width: 12, text: "Make it your own", shadow: annotationShadow, font: annotationFont),
            EditorAnnotation(kind: .arrow, start: CGPoint(x: 56, y: 214), end: CGPoint(x: 932, y: 182),
                             color: NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.85, alpha: 1), width: 6,
                             shadow: annotationShadow, reversed: inverseArrow,
                             arrowStyle: annotationArrowStyle, arrowStroke: annotationArrowStroke, arrowSeed: 42)
        ]
        return Image(nsImage: AnnotationRenderer.render(image: source, annotations: annotations))
            .resizable().aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 9)
            .accessibilityLabel("Preview: \(annotationFont.title) text and \(annotationArrowStyle.title.lowercased()) \(annotationArrowStroke.title.lowercased()) arrow")
    }

    private var cloudPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("Cloud") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "icloud").font(.system(size: 20)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cloud features are coming later").font(.system(size: 13, weight: .semibold))
                        Text("TobyShot currently keeps captures on this Mac. Cloud upload, account sync, and share links are not available yet.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.vertical, 3)
            }
            Label("Your captures stay on this Mac.", systemImage: "lock.fill")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var advancedPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            group("File name") {
                ToggleRow("Ask for a name after every capture", isOn: $askFilename)
                VStack(alignment: .leading, spacing: 7) {
                    Text("File name format").font(.system(size: 13))
                    TextField("TobyShot {date} at {time}", text: $filenameTemplate)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12))
                    Text("Use {date} and {time} in the name.").font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
                ToggleRow("Add @2x suffix to Retina screenshots", isOn: $retinaSuffix)
            }
            group("Clipboard") {
                PickerRow("Copy format", selection: $clipboardMode, options: ["File & Image", "Image", "File"])
            }
            group("Capture history") {
                PickerRow("Keep history", selection: $historyDays, options: [1, 3, 7, 30, 0], titleForValue: { $0 == 0 ? "Forever" : "\($0) days" })
            }
            group("Text recognition") {
                PickerRow("Language", selection: $ocrLanguage, options: ["Automatic", "English", "Danish"])
                ToggleRow("Keep line breaks", isOn: $ocrLineBreaks)
            }
            group("Pinned screenshots") {
                ToggleRow("Rounded corners", isOn: $pinnedRounded)
                ToggleRow("Shadow", isOn: $pinnedShadow)
                ToggleRow("Border", isOn: $pinnedBorder)
            }
            ComingNext(items: ["URL scheme API"])
        }
    }

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 42)).symbolRenderingMode(.palette).foregroundStyle(.white, accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("TobyShot").font(.system(size: 18, weight: .bold))
                    Text("A local-first capture tool for macOS").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 5)
            group("About TobyShot") {
                InfoRow("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development")
                InfoRow("Storage", value: "On this Mac")
                InfoRow("Cloud services", value: "Coming later")
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading(title)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.leading, 3)
    }

    private var expandedExportPath: String {
        (exportPath as NSString).expandingTildeInPath
    }

    private func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Location"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: expandedExportPath, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        exportPath = url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
    }

    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
    }

    private func updateLoginItem(_ enabled: Bool) {
        let status = SMAppService.mainApp.status
        if enabled == (status == .enabled || status == .requiresApproval) { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginStatus()
        } catch {
            refreshLoginStatus()
            loginError = error.localizedDescription
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, shortcuts, quickAccess, wallpaper, screenshots, recording, annotate, cloud, advanced, about

    static let primary: [SettingsSection] = [.general, .shortcuts, .quickAccess, .wallpaper, .screenshots, .recording, .annotate, .cloud, .advanced]
    var id: Self { self }
    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .quickAccess: "Quick Access"
        case .wallpaper: "Wallpaper"
        case .screenshots: "Screenshots"
        case .recording: "Screen Recording"
        case .annotate: "Annotate"
        case .cloud: "Cloud"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .shortcuts: "command"
        case .quickAccess: "rectangle.stack.fill"
        case .wallpaper: "rectangle.inset.filled"
        case .screenshots: "camera.fill"
        case .recording: "record.circle.fill"
        case .annotate: "pencil.tip.crop.circle.fill"
        case .cloud: "icloud.fill"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .general: .gray
        case .shortcuts: .gray.opacity(0.9)
        case .quickAccess: .green
        case .wallpaper: .cyan
        case .screenshots: .blue
        case .recording: .pink
        case .annotate: .orange
        case .cloud: .cyan
        case .advanced: .purple
        case .about: .gray
        }
    }
}

private struct WallpaperSwatch: Identifiable {
    let name: String
    let color: Color
    var id: String { name }
}

private struct ToggleRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>, detail: String? = nil) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13))
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.065)).frame(height: 1).padding(.leading, 0) }
    }
}

private struct PickerRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let titleForValue: (Value) -> String

    init(_ title: String, selection: Binding<Value>, options: [Value], titleForValue: @escaping (Value) -> String = { String(describing: $0) }) {
        self.title = title
        self._selection = selection
        self.options = options
        self.titleForValue = titleForValue
    }

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(titleForValue(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .font(.system(size: 12))
        }
        .padding(.vertical, 4)
        .frame(minHeight: 34)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.065)).frame(height: 1) }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, valueText: String) {
        self.title = title
        self._value = value
        self.range = range
        self.valueText = valueText
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            Text(valueText).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
            Slider(value: $value, in: range).frame(width: 140)
        }
        .padding(.vertical, 5)
    }
}

private struct InfoRow: View {
    let title: String
    let value: String
    init(_ title: String, value: String) { self.title = title; self.value = value }
    var body: some View {
        HStack { Text(title).font(.system(size: 13)); Spacer(); Text(value).font(.system(size: 12)).foregroundStyle(.secondary) }
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.065)).frame(height: 1) }
    }
}

private struct ComingNext: View {
    let items: [String]
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 7) {
                        Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(item).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }.padding(.top, 5).padding(.bottom, 3)
        } label: {
            Label("Coming next", systemImage: "sparkles")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
}
