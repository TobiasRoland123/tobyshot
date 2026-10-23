import Foundation
import ServiceManagement
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct LaunchAtLoginTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "TobyShot.LaunchAtLoginTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func makeModel(defaults: UserDefaults, backend: FakeLaunchAtLoginBackend) -> LaunchAtLogin {
        LaunchAtLogin(defaults: defaults, readStatus: { backend.status },
                      register: { try backend.register() }, unregister: { try backend.unregister() })
    }

    @Test func promptCanBeClaimedOnlyOnceAndDisabledOrMissingItemsAreEligible() {
        for initialStatus in [SMAppService.Status.notRegistered, .notFound] {
            let (defaults, name) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: name) }
            let backend = FakeLaunchAtLoginBackend(status: initialStatus)
            let launchAtLogin = makeModel(defaults: defaults, backend: backend)

            #expect(launchAtLogin.claimPrompt())
            #expect(defaults.bool(forKey: LaunchAtLogin.promptShownKey))
            #expect(!launchAtLogin.claimPrompt())
            #expect(backend.registerCalls == 0)
        }
    }

    @Test func promptHistoryIsSeparateFromSetupCompletionAndSkipping() {
        for setupState in [SetupAssistant.completedKey, SetupAssistant.skippedKey] {
            let (defaults, name) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set(true, forKey: setupState)
            let backend = FakeLaunchAtLoginBackend(status: .notRegistered)
            let launchAtLogin = makeModel(defaults: defaults, backend: backend)

            #expect(launchAtLogin.claimPrompt())
            #expect(defaults.bool(forKey: setupState))
            #expect(defaults.bool(forKey: LaunchAtLogin.promptShownKey))
            #expect(defaults.bool(forKey: SetupAssistant.completedKey) == (setupState == SetupAssistant.completedKey))
            #expect(defaults.bool(forKey: SetupAssistant.skippedKey) == (setupState == SetupAssistant.skippedKey))
        }
    }

    @Test func promptClaimSurvivesFreshModelAndDefaultsInstance() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = FakeLaunchAtLoginBackend(status: .notRegistered)
        #expect(makeModel(defaults: defaults, backend: backend).claimPrompt())

        let relaunchedDefaults = UserDefaults(suiteName: name)!
        let relaunchedModel = makeModel(defaults: relaunchedDefaults, backend: backend)
        #expect(!relaunchedModel.claimPrompt())
    }

    @Test func promptKeyRemainsStableAcrossVersions() {
        #expect(LaunchAtLogin.promptShownKey == "launchAtLoginPromptShown")
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "launchAtLoginPromptShown")
        let backend = FakeLaunchAtLoginBackend(status: .notRegistered)

        #expect(!makeModel(defaults: defaults, backend: backend).claimPrompt())
        #expect(defaults.bool(forKey: "launchAtLoginPromptShown"))
    }

    @Test func registeredAndPendingItemsSuppressPromptAndStaySuppressedAfterExternalDisable() {
        for initialStatus in [SMAppService.Status.enabled, .requiresApproval] {
            let (defaults, name) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: name) }
            let backend = FakeLaunchAtLoginBackend(status: initialStatus)
            let launchAtLogin = makeModel(defaults: defaults, backend: backend)

            #expect(!launchAtLogin.claimPrompt())
            #expect(defaults.bool(forKey: LaunchAtLogin.promptShownKey))
            launchAtLogin.setEnabled(true)
            #expect(backend.registerCalls == 0)
            backend.status = .notRegistered
            #expect(!launchAtLogin.claimPrompt())
        }
    }

    @Test func setEnabledUsesFreshStatusBeforeChangingLoginItem() {
        for currentStatus in [SMAppService.Status.enabled, .requiresApproval] {
            let (defaults, name) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: name) }
            let backend = FakeLaunchAtLoginBackend(status: .notRegistered)
            let launchAtLogin = makeModel(defaults: defaults, backend: backend)
            backend.status = currentStatus

            launchAtLogin.setEnabled(true)

            #expect(backend.registerCalls == 0)
            #expect(backend.unregisterCalls == 0)
            #expect(launchAtLogin.isRegistered)
            #expect(launchAtLogin.requiresApproval == (currentStatus == .requiresApproval))
            #expect(launchAtLogin.error == nil)
        }
    }

    @Test func promptChecksCurrentStatusBeforePresenting() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = FakeLaunchAtLoginBackend(status: .notRegistered)
        let launchAtLogin = makeModel(defaults: defaults, backend: backend)
        backend.status = .enabled

        #expect(!launchAtLogin.claimPrompt())
        #expect(backend.registerCalls == 0)
        #expect(launchAtLogin.isRegistered)
    }

    @Test func registrationSuccessAndPendingApprovalReflectMacOSStatus() {
        for resultStatus in [SMAppService.Status.enabled, .requiresApproval] {
            let (defaults, name) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: name) }
            let backend = FakeLaunchAtLoginBackend(status: .notRegistered)
            backend.statusAfterRegister = resultStatus
            let launchAtLogin = makeModel(defaults: defaults, backend: backend)

            launchAtLogin.setEnabled(true)

            #expect(backend.registerCalls == 1)
            #expect(launchAtLogin.status == resultStatus)
            #expect(launchAtLogin.isRegistered)
            #expect(launchAtLogin.requiresApproval == (resultStatus == .requiresApproval))
            #expect(launchAtLogin.error == nil)
            #expect(defaults.bool(forKey: LaunchAtLogin.promptShownKey))
        }
    }

    @Test func registrationFailureKeepsAccurateStatusAndMarksPromptHandled() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = FakeLaunchAtLoginBackend(status: .notRegistered)
        backend.registrationError = NSError(domain: "LaunchAtLoginTests", code: 17,
                                            userInfo: [NSLocalizedDescriptionKey: "Registration failed"])
        let launchAtLogin = makeModel(defaults: defaults, backend: backend)

        launchAtLogin.setEnabled(true)

        #expect(backend.registerCalls == 1)
        #expect(launchAtLogin.status == .notRegistered)
        #expect(!launchAtLogin.isRegistered)
        #expect(launchAtLogin.error == "Registration failed")
        #expect(defaults.bool(forKey: LaunchAtLogin.promptShownKey))
        #expect(!launchAtLogin.claimPrompt())
    }

    @Test func settingsCanDisableAndReenableLoginItem() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = FakeLaunchAtLoginBackend(status: .enabled)
        let launchAtLogin = makeModel(defaults: defaults, backend: backend)

        launchAtLogin.setEnabled(false)
        #expect(backend.unregisterCalls == 1)
        #expect(!launchAtLogin.isRegistered)
        #expect(launchAtLogin.error == nil)

        launchAtLogin.setEnabled(true)
        #expect(backend.registerCalls == 1)
        #expect(launchAtLogin.isRegistered)
        #expect(launchAtLogin.error == nil)
        #expect(!makeModel(defaults: defaults, backend: backend).claimPrompt())
    }

    @Test func registrationErrorStillRefreshesPendingApproval() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var status = SMAppService.Status.notRegistered
        let launchAtLogin = LaunchAtLogin(defaults: defaults, readStatus: { status }, register: {
            status = .requiresApproval
            throw NSError(domain: "LaunchAtLoginTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Approval required"])
        }, unregister: {})

        launchAtLogin.setEnabled(true)

        #expect(launchAtLogin.requiresApproval)
        #expect(launchAtLogin.error == "Approval required")
        #expect(!launchAtLogin.claimPrompt())
    }

    @Test func failedUnregistrationKeepsToggleOnAndAllowsRetry() {
        for initialStatus in [SMAppService.Status.enabled, .requiresApproval] {
            let (defaults, name) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: name) }
            let backend = FakeLaunchAtLoginBackend(status: initialStatus)
            backend.unregistrationError = NSError(domain: "LaunchAtLoginTests", code: 2,
                                                  userInfo: [NSLocalizedDescriptionKey: "Unregistration failed"])
            let launchAtLogin = makeModel(defaults: defaults, backend: backend)

            launchAtLogin.setEnabled(false)
            #expect(launchAtLogin.isRegistered)
            #expect(launchAtLogin.error == "Unregistration failed")

            backend.unregistrationError = nil
            launchAtLogin.setEnabled(false)
            #expect(backend.unregisterCalls == 2)
            #expect(!launchAtLogin.isRegistered)
            #expect(launchAtLogin.error == nil)
            #expect(!makeModel(defaults: defaults, backend: backend).claimPrompt())
        }
    }

    @Test func successfulRegistrationThatLeavesStatusDisabledDoesNotClaimEnabled() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = FakeLaunchAtLoginBackend(status: .notRegistered)
        backend.statusAfterRegister = .notRegistered
        let launchAtLogin = makeModel(defaults: defaults, backend: backend)

        launchAtLogin.setEnabled(true)

        #expect(backend.registerCalls == 1)
        #expect(launchAtLogin.status == .notRegistered)
        #expect(!launchAtLogin.isRegistered)
        #expect(launchAtLogin.error != nil)
    }
}

@MainActor
private final class FakeLaunchAtLoginBackend {
    var status: SMAppService.Status
    var statusAfterRegister: SMAppService.Status = .enabled
    var registrationError: Error?
    var unregistrationError: Error?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCalls += 1
        if let registrationError { throw registrationError }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregistrationError { throw unregistrationError }
        status = .notRegistered
    }
}
