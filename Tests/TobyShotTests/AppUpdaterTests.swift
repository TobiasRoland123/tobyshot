import Foundation
import Testing
@testable import TobyShot

@MainActor
struct AppUpdaterTests {
    @Test func captureDefersUpdateChecks() throws {
        let updater = AppUpdater()
        #expect(updater.responds(to: NSSelectorFromString("updater:mayPerformUpdateCheck:error:")))
        var capturing = true
        updater.captureInProgress = { capturing }
        do {
            try updater.validateUpdateCheck()
            Issue.record("Update checks must wait until the capture or recording finishes")
        } catch let error as NSError {
            #expect(error.domain == "app.tobyshot.updates")
            #expect(error.localizedDescription.contains("capture or recording"))
        }
        capturing = false
        try updater.validateUpdateCheck()
    }
}
