import Foundation
import OSLog
import ServiceManagement

/// Login-item registration via SMAppService. The SYSTEM is the single source of
/// truth — no UserDefaults mirror: the user can flip the same switch in System
/// Settings → General → Login Items, and the in-app toggle must reflect that.
public enum LaunchAtLogin {
    private static let log = Logger(subsystem: "com.kslff.ember", category: "launch")

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// macOS can defer a registration until the user approves it in System
    /// Settings (e.g. after the item was disabled there) — surface that state
    /// instead of silently showing the toggle off.
    public static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Registers/unregisters and returns the ACTUAL state afterwards — the caller
    /// re-reads the toggle from it, so a failed or approval-gated attempt never
    /// leaves the UI lying.
    @discardableResult
    public static func setEnabled(_ on: Bool) -> Bool {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("launch-at-login \(on ? "register" : "unregister", privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
        return isEnabled
    }

    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
