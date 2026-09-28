import Testing
import Foundation
import ScreenCaptureKit
@testable import TobyShot

@MainActor
struct ScreenCapturePermissionTests {
    @Test func onlyAuthorizationDenialsOfferPermissionRecovery() {
        let denied = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        #expect(ScreenCaptureService.isPermissionError(denied))

        // Recording failures, cancellations, and errors in other domains need
        // their own diagnostics; sending users to Privacy Settings cannot fix them.
        for code in [SCStreamError.Code.failedToStart, .userStopped, .missingEntitlements, .noDisplayList] {
            #expect(!ScreenCaptureService.isPermissionError(NSError(domain: SCStreamErrorDomain, code: code.rawValue)))
        }
        #expect(!ScreenCaptureService.isPermissionError(NSError(domain: NSCocoaErrorDomain, code: denied.code)))
        #expect(!ScreenCaptureService.isPermissionError(CancellationError()))
    }
}
