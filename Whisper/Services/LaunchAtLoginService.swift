import Foundation
import ServiceManagement

class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()
    
    private init() {}
    
    /// Check if launch at login is enabled
    var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                return UserDefaults.standard.bool(forKey: "launchAtLogin")
            }
        }
    }
    
    /// Enable or disable launch at login
    func setEnabled(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return true
            } catch {
                print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
                return false
            }
        } else {
            // Fallback for older macOS - just store preference
            UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
            return true
        }
    }
}

