import AppKit
import SwiftUI

@main
struct TobyShotApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var coordinator: AppCoordinator!
    private var libraryWindow: NSWindow!
    private var settingsWindow: NSWindow?
    private var captureLauncher: CaptureLauncher?
    private var statusItem: NSStatusItem?
    private let hotKeys = HotKeyManager()
    private var preferencesObserver: NSObjectProtocol?
    private var pruneTimer: Timer?
    private var screenshotRetentionDays = 0
    private lazy var menuBarImage: NSImage? = {
        let image = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "tiff")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "TobyShot")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        image?.accessibilityDescription = "TobyShot"
        return image
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.register()
        screenshotRetentionDays = Preferences.int("screenshotRetentionDays")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        coordinator = AppCoordinator(shortcuts: hotKeys)
        hotKeys.onChange = { [weak self] in self?.refreshShortcutMenus() }
        configureMainMenu()
        createLibraryWindow()
        coordinator.showLibrary = { [weak self] in self?.showLibrary() }
        coordinator.hideLibrary = { [weak self] in self?.libraryWindow.orderOut(nil); self?.settingsWindow?.orderOut(nil) }
        coordinator.showSettings = { [weak self] in self?.showSettings() }
        coordinator.recordingChanged = { [weak self] in self?.refreshStatusItem() }
        hotKeys.onAction = { [weak self] id in Task { @MainActor in self?.handleHotKey(id) } }
        hotKeys.register()
        refreshStatusItem()
        preferencesObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshStatusItem()
                let days = Preferences.int("screenshotRetentionDays")
                if days != self.screenshotRetentionDays {
                    self.screenshotRetentionDays = days
                    self.pruneCaptureHistory()
                }
            }
        }
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneCaptureHistory() }
        }
        showLibrary()
        if !hotKeys.issues.isEmpty { coordinator.toast("Some shortcuts are already in use. Customize them in Settings → Shortcuts.") }
        if CommandLine.arguments.contains("--demo") { coordinator.openDemo() }
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if coordinator != nil { hotKeys.register(); pruneCaptureHistory() }
    }

    private func pruneCaptureHistory() {
        do { try coordinator.store.prune() }
        catch { NSLog("TobyShot automatic deletion: %@", error.localizedDescription) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showLibrary(); return true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames { coordinator?.openImage(at: URL(fileURLWithPath: filename)) }
        sender.reply(toOpenOrPrint: .success)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard coordinator.isRecording || coordinator.isBusy else { return coordinator.confirmClosingEditors() ? .terminateNow : .terminateCancel }
        let alert = NSAlert()
        alert.messageText = coordinator.isRecording ? "Finish your recording first" : "A capture is in progress"
        alert.informativeText = coordinator.isRecording ? "Stop the recording and let TobyShot save it before quitting." : "Finish or cancel your capture before quitting."
        alert.addButton(withTitle: coordinator.isRecording ? "Stop recording" : "Return to capture")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn, coordinator.isRecording { coordinator.stopRecording() }
        return .terminateCancel
    }

    private func createLibraryWindow() {
        libraryWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1140, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        libraryWindow.title = "TobyShot"
        libraryWindow.titlebarAppearsTransparent = true
        libraryWindow.titleVisibility = .hidden
        libraryWindow.backgroundColor = NSColor(red: 0.075, green: 0.083, blue: 0.10, alpha: 1)
        libraryWindow.isReleasedWhenClosed = false
        libraryWindow.minSize = CGSize(width: 780, height: 690)
        let view = LibraryView(app: coordinator, store: coordinator.store, shortcuts: hotKeys).padding(.top, 28).background(Color(red: 0.075, green: 0.083, blue: 0.10))
        libraryWindow.contentView = NSHostingView(rootView: view)
        libraryWindow.center(); libraryWindow.setFrameAutosaveName("TobyShotLibrary")
    }

    @objc func showLibrary() { libraryWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); coordinator.refreshPermission() }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 880, height: 840), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "TobyShot Settings"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(shortcuts: hotKeys).preferredColorScheme(.dark))
            window.minSize = CGSize(width: 790, height: 620)
            window.center(); window.setFrameAutosaveName("TobyShotSettings")
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshStatusItem() {
        if Preferences.bool("showMenuBar") || coordinator.isRecording {
            if statusItem == nil {
                statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                let menu = NSMenu(); menu.delegate = self; statusItem?.menu = menu
            }
            statusItem?.button?.image = coordinator.isRecording
                ? NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "TobyShot")
                : menuBarImage
            statusItem?.button?.contentTintColor = coordinator.isRecording ? .systemRed : nil
            statusItem?.button?.title = coordinator.isRecording ? " \(coordinator.recordingTime)" : ""
        } else if let item = statusItem { NSStatusBar.system.removeStatusItem(item); statusItem = nil }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addMenuItem(menu, "TobyShot", #selector(showLibrary))
        menu.addItem(.separator())
        addShortcutItem(menu, "All-in-One", #selector(showAllInOne), shortcut: .allInOne)
        addShortcutItem(menu, "Capture Area", #selector(captureArea), shortcut: .captureArea)
        addShortcutItem(menu, "Capture Full Screen", #selector(captureFull), shortcut: .captureFullScreen)
        addShortcutItem(menu, "Capture Window", #selector(captureWindow), shortcut: .captureWindow)
        addShortcutItem(menu, "Self-Timer", #selector(captureTimer), shortcut: .captureTimer)
        menu.addItem(.separator())
        addShortcutItem(menu, coordinator.isRecording ? "Stop Recording (\(coordinator.recordingTime))" : "Record Area", #selector(recordArea), shortcut: .recordScreen)
        if !coordinator.isRecording { addMenuItem(menu, "Record Full Screen", #selector(recordFull)) }
        menu.addItem(.separator())
        addShortcutItem(menu, "Open Image…", #selector(openImage), shortcut: .openImage)
        addShortcutItem(menu, "Open Capture History", #selector(showLibrary), shortcut: .captureHistory)
        if !coordinator.store.items.isEmpty {
            let recent = NSMenu()
            for item in coordinator.store.items.prefix(5) {
                let entry = NSMenuItem(title: item.title, action: #selector(openRecent(_:)), keyEquivalent: "")
                entry.target = self; entry.representedObject = item.id.uuidString; recent.addItem(entry)
            }
            let parent = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: ""); parent.submenu = recent; menu.addItem(parent)
        }
        menu.addItem(.separator())
        addMenuItem(menu, "Settings…", #selector(showSettings), key: ",")
        addMenuItem(menu, "Quit TobyShot", #selector(quit), key: "q")
    }

    private func configureMainMenu() {
        let main = NSMenu()
        let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem)
        addMenuItem(appMenu, "About TobyShot", #selector(about))
        addMenuItem(appMenu, "Settings…", #selector(showSettings), key: ",")
        appMenu.addItem(.separator())
        addMenuItem(appMenu, "Quit TobyShot", #selector(quit), key: "q")
        let file = NSMenu(title: "File"); let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: ""); fileItem.submenu = file; main.addItem(fileItem)
        addShortcutItem(file, "Open Image…", #selector(openImage), shortcut: .openImage)
        addShortcutItem(file, "All-in-One", #selector(showAllInOne), shortcut: .allInOne)
        addShortcutItem(file, "Capture Area", #selector(captureArea), shortcut: .captureArea)
        addShortcutItem(file, "Capture Full Screen", #selector(captureFull), shortcut: .captureFullScreen)
        addShortcutItem(file, "Capture Window", #selector(captureWindow), shortcut: .captureWindow)
        addShortcutItem(file, "Start / Stop Recording", #selector(recordArea), shortcut: .recordScreen)
        addShortcutItem(file, "Open Capture History", #selector(showLibrary), shortcut: .captureHistory)
        file.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let edit = NSMenu(title: "Edit"); let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; main.addItem(editItem)
        for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Redo", Selector(("redo:")), "Z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        addShortcutItem(edit, "Open From Clipboard", #selector(pasteImage), shortcut: .openClipboard)
        let window = NSMenu(title: "Window"); let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: ""); windowItem.submenu = window; main.addItem(windowItem)
        addMenuItem(window, "Capture Library", #selector(showLibrary))
        window.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        NSApp.mainMenu = main; NSApp.windowsMenu = window
        // Give the library a responder for the familiar image paste shortcut.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.hotKeys.isRecordingShortcut == false, event.charactersIgnoringModifiers == "v", event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               NSApp.keyWindow == self?.libraryWindow, !(NSApp.keyWindow?.firstResponder is NSTextView) {
                self?.coordinator.pasteImage(); return nil
            }
            return event
        }
    }
    private func addMenuItem(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; item.keyEquivalentModifierMask = modifiers; menu.addItem(item)
    }
    private func addShortcutItem(_ menu: NSMenu, _ title: String, _ selector: Selector, shortcut: ShortcutAction) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.tag = 1000 + Int(shortcut.rawValue)
        applyShortcut(to: item, action: shortcut)
        menu.addItem(item)
    }
    private func applyShortcut(to item: NSMenuItem, action: ShortcutAction) {
        let binding = hotKeys.activeBinding(for: action)
        item.keyEquivalent = binding?.menuKey ?? ""
        item.keyEquivalentModifierMask = binding?.appKitModifiers ?? []
    }
    private func refreshShortcutMenus() {
        func update(_ menu: NSMenu?) {
            for item in menu?.items ?? [] {
                if item.tag > 1000, let action = ShortcutAction(rawValue: UInt32(item.tag - 1000)) {
                    applyShortcut(to: item, action: action)
                }
                update(item.submenu)
            }
        }
        update(NSApp.mainMenu)
        update(statusItem?.menu)
    }
    private func handleHotKey(_ id: UInt32) {
        guard !hotKeys.isRecordingShortcut else { return }
        guard let action = ShortcutAction(rawValue: id) else { return }
        switch action {
        case .allInOne: showAllInOne()
        case .captureArea: captureArea()
        case .captureFullScreen: captureFull()
        case .captureWindow: captureWindow()
        case .recordScreen: recordArea()
        case .openImage: openImage()
        case .openClipboard: pasteImage()
        case .captureHistory: showLibrary()
        case .restoreLastCapture: coordinator.restoreLastCapture()
        case .captureTimer: captureTimer()
        case .capturePreviousArea: coordinator.capture(.area, previousArea: true)
        case .captureAreaCopy: coordinator.capture(.area, intent: .copy)
        case .captureAreaSave: coordinator.capture(.area, intent: .save)
        case .captureAreaAnnotate: coordinator.capture(.area, intent: .annotate)
        case .captureAreaPin: coordinator.capture(.area, intent: .pin)
        case .captureText: coordinator.capture(.area, intent: .recognizeText(keepLines: nil))
        case .captureTextWithLines: coordinator.capture(.area, intent: .recognizeText(keepLines: true))
        case .captureTextWithoutLines: coordinator.capture(.area, intent: .recognizeText(keepLines: false))
        case .toggleOverlays: coordinator.toggleOverlays()
        case .saveOverlays: coordinator.saveOverlays()
        case .closeOverlays: coordinator.closeOverlays()
        case .choosePin: coordinator.chooseAndPinImage()
        case .togglePins: coordinator.togglePins()
        case .closePins: coordinator.closePins()
        case .pinLastScreenshot: coordinator.pinLastScreenshot()
        case .annotateLastScreenshot: coordinator.annotateLastScreenshot()
        default: break // Editor actions are dispatched only by the annotation window.
        }
    }
    @objc private func showAllInOne() {
        if coordinator.isBusy { return }
        captureLauncher?.close()
        captureLauncher = CaptureLauncher(app: coordinator)
        captureLauncher?.showWindow(nil)
        captureLauncher?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func captureArea() { coordinator.capture(.area) }
    @objc private func captureFull() { coordinator.capture(.fullscreen) }
    @objc private func captureWindow() { coordinator.capture(.window) }
    @objc private func captureTimer() { coordinator.capture(.fullscreen, delayed: true) }
    @objc private func recordArea() { coordinator.toggleRecording() }
    @objc private func recordFull() { coordinator.toggleRecording(area: false) }
    @objc private func openImage() { coordinator.openImage() }
    @objc private func pasteImage() { coordinator.pasteImage() }
    @objc private func openRecent(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let item = coordinator.store.items.first(where: { $0.id.uuidString == id }) { coordinator.annotate(item) }
    }
    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "TobyShot", .applicationVersion: "0.1.0", .credits: NSAttributedString(string: "Capture. Annotate. Make your point.\nBuilt for macOS. Your captures stay on your Mac.")])
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
