import Combine
import Foundation
import ServiceManagement

/// Shares login-item state and one-time prompt history across setup, launch, and Settings.
@MainActor
final class LaunchAtLogin: ObservableObject {
    static let promptShownKey = "launchAtLoginPromptShown"

    @Published private(set) var status: SMAppService.Status
    @Published private(set) var error: String?

    private let defaults: UserDefaults
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void

    init(defaults: UserDefaults = .standard,
         readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }) {
        self.defaults = defaults
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        status = readStatus()
    }

    /// A pending registration is already on; macOS still needs the user's approval.
    var isRegistered: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() { status = readStatus() }

    /// Claim before presenting so dismissal, quitting, or reopening setup cannot repeat it.
    func claimPrompt() -> Bool {
        refresh()
        guard !defaults.bool(forKey: Self.promptShownKey) else { return false }
        // Existing registrations also count as handled, even if disabled later.
        defaults.set(true, forKey: Self.promptShownKey)
        return !isRegistered
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(true, forKey: Self.promptShownKey)
        error = nil
        refresh()
        guard enabled != isRegistered else { return }
        do {
            if enabled { try register() }
            else { try unregister() }
            refresh()
            if enabled && !isRegistered {
                error = "macOS hasn’t enabled launch at login. You can try again in Settings → General → Launch at login."
            } else if !enabled && isRegistered {
                error = "macOS hasn’t disabled launch at login. Check TobyShot in System Settings → General → Login Items."
            }
        } catch {
            refresh()
            self.error = error.localizedDescription
        }
    }
}
