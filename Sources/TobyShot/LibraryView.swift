import SwiftUI
import AppKit

private let studioBackground = Color(red: 0.075, green: 0.083, blue: 0.10)
private let studioAccent = Color(red: 0.40, green: 0.69, blue: 1)

struct LibraryView: View {
    @ObservedObject var app: AppCoordinator
    @ObservedObject var store: CaptureStore
    @ObservedObject var shortcuts: HotKeyManager
    @State private var filter = "All captures"
    @State private var search = ""

    private var filtered: [CaptureItem] {
        store.items.filter { item in
            (filter == "All captures" || (filter == "Screenshots" ? item.kind == .image : item.kind == .video)) &&
            (search.isEmpty || item.title.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
            VStack(spacing: 0) {
                topbar
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if store.items.isEmpty { welcome }
                        captureActions
                        library
                    }.padding(30)
                }
                footer
            }
        }
        .background(studioBackground)
        .preferredColorScheme(.dark)
        .frame(minWidth: 760, minHeight: 650)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in app.refreshPermission() }
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in app.openImage(at: url) } }
                }
                return true
            }
            return false
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().scaledToFit()
                    .frame(width: 38, height: 38).accessibilityLabel("TobyShot")
                VStack(alignment: .leading, spacing: 3) {
                    Text("TobyShot").font(.system(size: 17, weight: .semibold))
                    Text("Your screen. Your story.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 36)
            Text("WORKSPACE").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(.tertiary).padding(.horizontal, 23).padding(.bottom, 12)
            ForEach([("All captures", "square.grid.2x2"), ("Screenshots", "photo"), ("Recordings", "video")], id: \.0) { name, icon in
                Button { filter = name } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon).font(.system(size: 14)).frame(width: 18)
                        Text(name).font(.system(size: 12, weight: filter == name ? .semibold : .regular))
                        Spacer()
                        if name == "All captures", !store.items.isEmpty {
                            Text("\(store.items.count)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        }
                    }.foregroundStyle(filter == name ? Color.white : Color.secondary)
                        .padding(.horizontal, 12).frame(height: 37)
                        .background(filter == name ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 3)
            }
            Divider().overlay(Color.white.opacity(0.03)).padding(.horizontal, 22).padding(.vertical, 20)
            sidebarAction("Open image…", icon: "folder", action: app.openImage)
            sidebarAction("Paste image", icon: "doc.on.clipboard", action: app.pasteImage)
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) { Image(systemName: "internaldrive").font(.system(size: 11)); Text("Made for your Mac").font(.system(size: 11, weight: .medium)) }
                Text("Your captures stay on this device.").font(.system(size: 10)).foregroundStyle(.secondary)
            }.foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10)).padding(14)
            sidebarAction("Settings", icon: "gearshape") { app.showSettings?() }
                .padding(.bottom, 20)
        }.frame(width: 205).background(Color.white.opacity(0.018))
    }

    private func sidebarAction(_ name: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(name, systemImage: icon).font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 23).frame(height: 35)
        }.buttonStyle(.plain)
    }

    private var topbar: some View {
        HStack {
            Text(filter).font(.system(size: 14, weight: .semibold))
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a capture", text: $search).textFieldStyle(.plain).font(.system(size: 11))
            }.padding(8).frame(width: 184).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            Button(action: app.openImage) { Image(systemName: "plus").frame(width: 20, height: 20) }.buttonStyle(.borderless).help("Open an image")
        }.padding(.horizontal, 30).frame(height: 62)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
    }

    private var welcome: some View {
        HStack(spacing: 25) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 6) {
                    Circle().fill(studioAccent).frame(width: 5, height: 5)
                    Text("A CLEARER WAY TO CAPTURE").font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(studioAccent)
                }
                Text("Good things deserve\na screenshot.").font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-0.8).lineSpacing(1)
                Text("Capture a moment. Make your point.\nKeep everything right here.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                Button { app.openDemo() } label: {
                    HStack(spacing: 7) { Text("Try the annotation tools"); Image(systemName: "arrow.up.right") }
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(studioAccent)
                }.buttonStyle(.plain).padding(.top, 5)
            }.frame(maxWidth: .infinity, alignment: .leading)
            WelcomeIllustration().frame(width: 160, height: 186).scaleEffect(0.8)
        }.padding(26)
            .background(LinearGradient(colors: [Color(red: 0.11, green: 0.14, blue: 0.20), Color(red: 0.10, green: 0.11, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.055)))
    }

    private var captureActions: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Make a capture").font(.system(size: 14, weight: .semibold))
                Spacer()
                Menu {
                    Button("Capture with \(Preferences.int("selfTimer"))-second timer") { app.capture(.fullscreen, delayed: true) }
                    Button("Record full screen") { app.toggleRecording(area: false) }
                } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary) }.menuStyle(.borderlessButton).frame(width: 24)
            }
            HStack(spacing: 11) {
                captureButton("Capture area", subtitle: "Just the part you need", icon: "viewfinder", shortcut: shortcuts.label(for: .captureArea), color: studioAccent) { app.capture(.area) }
                captureButton("Full screen", subtitle: "The whole picture", icon: "display", shortcut: shortcuts.label(for: .captureFullScreen), color: Color(red: 0.60, green: 0.56, blue: 0.96)) { app.capture(.fullscreen) }
                captureButton("Window", subtitle: "A perfect window shot", icon: "macwindow", shortcut: shortcuts.label(for: .captureWindow), color: Color(red: 0.46, green: 0.78, blue: 0.66)) { app.capture(.window) }
                captureButton(app.isRecording ? "Stop recording" : "Record screen", subtitle: app.isRecording ? app.recordingTime : "Show it in motion", icon: app.isRecording ? "stop.circle.fill" : "record.circle", shortcut: shortcuts.label(for: .recordScreen), color: Color(red: 0.99, green: 0.53, blue: 0.55)) { app.toggleRecording() }
            }
            if !app.screenPermission {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(studioAccent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Screen access needs checking.").font(.system(size: 11, weight: .medium))
                        Text("Try a capture, or check access if you’ve already enabled TobyShot.").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(app.isCheckingPermission ? "Checking…" : "Check access", action: app.requestPermission)
                        .font(.system(size: 11, weight: .medium)).buttonStyle(.bordered)
                        .disabled(app.isCheckingPermission || app.isBusy || app.isRecording)
                }.padding(13).background(studioAccent.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(studioAccent.opacity(0.12)))
            }
        }
    }

    private func captureButton(_ title: String, subtitle: String, icon: String, shortcut: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack { Image(systemName: icon).font(.system(size: 20, weight: .regular)).foregroundStyle(color); Spacer(); Text(shortcut).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary) }.frame(height: 28)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary).padding(.top, 15)
                Text(subtitle).font(.system(size: 9)).foregroundStyle(.secondary).padding(.top, 5).lineLimit(1)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.065)))
        }.buttonStyle(CaptureCardStyle()).disabled(app.isBusy || (app.isRecording && title != "Stop recording"))
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent captures").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(store.items.isEmpty ? "A home for your good finds" : "\(filtered.count) \(filtered.count == 1 ? "capture" : "captures")")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            if filtered.isEmpty {
                VStack(spacing: 11) {
                    Image(systemName: search.isEmpty ? "photo.on.rectangle.angled" : "magnifyingglass").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(.tertiary)
                    Text(search.isEmpty ? "Your next great capture starts here" : "No matching captures").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Text(search.isEmpty ? "Take a screenshot, drop an image, or paste with ⌘V." : "Try a different search or capture type.").font(.system(size: 10)).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity).frame(height: 145)
                    .background(Color.white.opacity(0.012), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.065), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 18) {
                    ForEach(filtered) { item in captureTile(item) }
                }
            }
        }
    }

    private func captureTile(_ item: CaptureItem) -> some View {
        Button { app.annotate(item) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Color.white.opacity(0.025)
                    if let image = store.thumbnail(for: item) {
                        Image(nsImage: image).resizable().scaledToFit().padding(10)
                    } else {
                        VStack(spacing: 10) { Image(systemName: "play.circle.fill").font(.system(size: 34)).foregroundStyle(studioAccent); Text("Screen recording").font(.system(size: 11)).foregroundStyle(.secondary) }
                    }
                }.frame(height: 145).clipped()
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    HStack { Text(item.date, style: .relative); Spacer(); Text(item.dimensions) }.font(.system(size: 9)).foregroundStyle(.tertiary)
                }.padding(12)
            }.background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06)))
        }.buttonStyle(.plain)
            .contextMenu {
                Button(item.kind == .image ? "Annotate" : "Play recording") { app.annotate(item) }
                Button("Copy") { app.copy(item) }
                Button("Save") { app.save(item) }
                Button("Save as…") { app.save(item, ask: true) }
                if item.kind == .image {
                    Button("Copy text from image") { app.recognizeText(item) }
                    Button("Pin to screen") { if let image = store.image(for: item) { app.pin(image) } }
                }
                Button("Show in Finder") { app.reveal(item) }
                Divider()
                Button("Remove from history", role: .destructive) { app.remove(item) }
            }
            .onDrag { NSItemProvider(contentsOf: store.url(for: item)) ?? NSItemProvider() }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(app.isRecording ? Color.red : Color.green.opacity(0.7)).frame(width: 5, height: 5)
            Text(app.notice ?? (app.isRecording ? "Recording · \(app.recordingTime)" : "\(store.items.count) captures · Stored on this Mac"))
                .font(.system(size: 10)).foregroundStyle(app.notice == nil ? Color.secondary : studioAccent)
            Spacer()
            Text("TobyShot 0.1").font(.system(size: 9)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 30).frame(height: 35)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
    }
}

private struct CaptureCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.opacity(configuration.isPressed ? 0.65 : 1) }
}

private struct WelcomeIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(studioAccent.opacity(0.025)).frame(width: 204, height: 158).rotationEffect(.degrees(-9)).offset(x: -3, y: 5)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(studioAccent.opacity(0.12)).frame(width: 204, height: 158).rotationEffect(.degrees(-9)).offset(x: -3, y: 5))
            VStack(spacing: 0) {
                HStack(spacing: 4) { ForEach(0..<3) { _ in Circle().fill(Color.white.opacity(0.18)).frame(width: 4, height: 4) }; Spacer(); Image(systemName: "sparkle").font(.system(size: 8)).foregroundStyle(studioAccent) }.padding(11)
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                HStack(alignment: .top, spacing: 13) {
                    RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [Color(red: 0.31, green: 0.51, blue: 0.67), Color(red: 0.20, green: 0.26, blue: 0.39)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 61, height: 71)
                        .overlay(Image(systemName: "mountain.2").font(.system(size: 25, weight: .ultraLight)).foregroundStyle(Color.white.opacity(0.6)))
                    VStack(alignment: .leading, spacing: 9) {
                        Capsule().fill(Color.white.opacity(0.55)).frame(width: 65, height: 5)
                        Capsule().fill(Color.white.opacity(0.17)).frame(width: 70, height: 4)
                        Capsule().fill(Color.white.opacity(0.17)).frame(width: 53, height: 4)
                        Capsule().fill(studioAccent.opacity(0.3)).frame(width: 44, height: 15).padding(.top, 9)
                    }.padding(.top, 8)
                }.padding(16)
            }.frame(width: 205).background(Color(red: 0.12, green: 0.15, blue: 0.20), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.15)))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 12)
                .rotationEffect(.degrees(4))
            Image(systemName: "arrow.up.left").font(.system(size: 40, weight: .light)).foregroundStyle(Color(red: 1, green: 0.69, blue: 0.45)).rotationEffect(.degrees(10)).offset(x: 96, y: 56)
            HStack(spacing: 5) { Image(systemName: "checkmark.circle.fill"); Text("A point, well made.") }.font(.system(size: 9, weight: .medium)).foregroundStyle(studioAccent)
                .padding(.horizontal, 10).padding(.vertical, 7).background(Color(red: 0.12, green: 0.17, blue: 0.23), in: Capsule()).overlay(Capsule().stroke(studioAccent.opacity(0.22))).offset(x: -18, y: 79)
        }
    }
}

enum DemoImage {
    static func make() -> NSImage {
        let size = CGSize(width: 1120, height: 720)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1120, pixelsHigh: 720, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGradient(colors: [NSColor(red: 0.16, green: 0.24, blue: 0.33, alpha: 1), NSColor(red: 0.07, green: 0.11, blue: 0.18, alpha: 1)])?.draw(in: CGRect(origin: .zero, size: size), angle: -40)
        NSColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: 100, y: 92, width: 920, height: 536), xRadius: 18, yRadius: 18).fill()
        func label(_ string: String, _ x: CGFloat, _ y: CGFloat, _ font: NSFont, _ color: NSColor) {
            (string as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
        }
        let ink = NSColor(red: 0.12, green: 0.19, blue: 0.20, alpha: 1)
        label("FIELDNOTES", 146, 571, .systemFont(ofSize: 15, weight: .bold), ink)
        label("Stories     Places     About", 751, 571, .systemFont(ofSize: 12), ink.withAlphaComponent(0.6))
        label("COLLECTION NO. 08", 146, 495, .systemFont(ofSize: 11, weight: .semibold), ink.withAlphaComponent(0.5))
        label("Take the", 142, 418, .systemFont(ofSize: 54, weight: .semibold), ink)
        label("scenic route.", 142, 352, .systemFont(ofSize: 54, weight: .semibold), ink)
        label("Small escapes. Quiet moments.", 146, 302, .systemFont(ofSize: 15), ink.withAlphaComponent(0.65))
        label("A few things worth slowing down for.", 146, 277, .systemFont(ofSize: 15), ink.withAlphaComponent(0.65))
        ink.setFill(); NSBezierPath(roundedRect: CGRect(x: 146, y: 202, width: 174, height: 43), xRadius: 7, yRadius: 7).fill()
        label("Explore the collection  →", 161, 217, .systemFont(ofSize: 12, weight: .medium), .white)
        let landscape = CGRect(x: 622, y: 170, width: 348, height: 353)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: landscape, xRadius: 10, yRadius: 10).addClip()
        NSGradient(colors: [NSColor(red: 0.72, green: 0.82, blue: 0.80, alpha: 1), NSColor(red: 0.91, green: 0.83, blue: 0.66, alpha: 1)])?.draw(in: landscape, angle: 90)
        NSColor(red: 0.97, green: 0.90, blue: 0.70, alpha: 1).setFill(); NSBezierPath(ovalIn: CGRect(x: 842, y: 416, width: 65, height: 65)).fill()
        for (offset, color) in [(CGFloat(0), NSColor(red: 0.40, green: 0.57, blue: 0.54, alpha: 1)), (CGFloat(70), NSColor(red: 0.22, green: 0.40, blue: 0.37, alpha: 1)), (CGFloat(145), NSColor(red: 0.12, green: 0.29, blue: 0.27, alpha: 1))] {
            color.setFill(); let p = NSBezierPath(); p.move(to: CGPoint(x: 600, y: 130)); p.line(to: CGPoint(x: 600, y: 300 - offset)); p.curve(to: CGPoint(x: 990, y: 355 - offset), controlPoint1: CGPoint(x: 740, y: 500 - offset), controlPoint2: CGPoint(x: 860, y: 235 - offset)); p.line(to: CGPoint(x: 990, y: 130)); p.close(); p.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        label("A sample canvas for your first TobyShot annotation", 146, 125, .systemFont(ofSize: 10), ink.withAlphaComponent(0.4))
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: size); result.addRepresentation(bitmap); return result
    }
}
