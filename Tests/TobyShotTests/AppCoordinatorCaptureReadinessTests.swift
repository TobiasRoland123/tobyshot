import AppKit
import Foundation
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct AppCoordinatorCaptureReadinessTests {
    @Test(arguments: [CaptureMode.area, .fullscreen, .window], [false, true])
    func blockedHistoryRejectsScreenshotsBeforeCaptureSideEffects(mode: CaptureMode, delayed: Bool) throws {
        try expectBlockedCapture { app in app.capture(mode, delayed: delayed) }
    }

    @Test func blockedHistoryRejectsPreviousAreaCapture() throws {
        try expectBlockedCapture { app in app.capture(.area, previousArea: true) }
    }

    @Test(arguments: [false, true])
    func blockedHistoryRejectsRecordingBeforeCaptureSideEffects(area: Bool) throws {
        try expectBlockedCapture { app in app.toggleRecording(area: area) }
    }

    @Test(arguments: [false, true])
    func blockedHistoryStillAllowsAnActiveRecordingToStop(area: Bool) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try blockedStore(in: directory)
        let app = AppCoordinator(shortcuts: HotKeyManager(), store: store)
        var shown = 0
        var hidden = 0
        app.showLibrary = { shown += 1 }
        app.hideLibrary = { hidden += 1 }
        app.isRecording = true
        app.isBusy = true
        app.isCheckingPermission = true
        app.notice = "Existing notice"

        // No recorder session is needed: entering stopRecording changes isStopping
        // synchronously, and the idle recorder's stop performs no recording APIs.
        app.toggleRecording(area: area)

        #expect(app.isStopping)
        #expect(app.isRecording)
        #expect(app.isBusy)
        #expect(app.isCheckingPermission)
        #expect(app.countdown == nil)
        #expect(app.notice == "Existing notice")
        #expect(shown == 0)
        #expect(hidden == 0)
        #expect(store.historyLoadError != nil)
    }

    private func expectBlockedCapture(_ request: (AppCoordinator) -> Void) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try blockedStore(in: directory)
        let app = AppCoordinator(shortcuts: HotKeyManager(), store: store)
        defer { app.cancelCountdown() }
        let permission = app.screenPermission
        let history = directory.appendingPathComponent("history.json")
        let originalHistory = try Data(contentsOf: history)
        let originalFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        var shown = 0
        var hidden = 0
        var recordingChanges = 0
        app.showLibrary = { shown += 1 }
        app.hideLibrary = { hidden += 1 }
        app.recordingChanged = { recordingChanges += 1 }

        request(app)

        #expect(!app.isBusy)
        #expect(!app.isRecording)
        #expect(!app.isStopping)
        #expect(!app.isCheckingPermission)
        #expect(app.countdown == nil)
        #expect(app.screenPermission == permission)
        #expect(shown == 1)
        #expect(hidden == 0)
        #expect(recordingChanges == 0)
        let notice = try #require(app.notice)
        #expect(notice.contains("recovery"))
        #expect(notice.contains("Retry"))
        #expect(store.items.isEmpty)
        #expect(store.historyLoadError != nil)
        #expect(try Data(contentsOf: history) == originalHistory)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == originalFiles)
    }

    private func blockedStore(in directory: URL) throws -> CaptureStore {
        _ = NSApplication.shared
        Preferences.register()
        try Data("invalid history".utf8).write(to: directory.appendingPathComponent("history.json"))
        let store = CaptureStore(directory: directory)
        #expect(store.historyLoadError != nil)
        return store
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TobyShot-CaptureReadinessTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
