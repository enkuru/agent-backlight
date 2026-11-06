import Observation
import ServiceManagement

/// Whether macOS opens the app when you log in. It is the app's entry in System Settings → General → Login Items,
/// so a change made there shows here the next time the panel opens.
@MainActor @Observable
final class LoginItem {
    private(set) var status = SMAppService.mainApp.status
    private(set) var problem: String?

    /// Registered, though macOS may still be waiting for the user to allow it.
    var isOn: Bool { status == .enabled || status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
        refresh()
    }
}
