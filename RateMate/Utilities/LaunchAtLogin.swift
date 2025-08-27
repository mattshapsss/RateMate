import Foundation
import ServiceManagement
import OSLog

private let logger = Logger(subsystem: "com.example.ratemate", category: "LaunchAtLogin")

@available(macOS 13.0, *)
class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()
    
    @Published var isEnabled = false
    @Published var lastError: String?
    
    private let appService = SMAppService.mainApp
    
    private init() {
        updateStatus()
    }
    
    func updateStatus() {
        isEnabled = (appService.status == .enabled)
        logger.info("Launch at login status: \(self.isEnabled ? "enabled" : "disabled")")
    }
    
    func enable() async -> Bool {
        do {
            try appService.register()
            await MainActor.run {
                self.isEnabled = true
                self.lastError = nil
            }
            logger.info("Successfully enabled launch at login")
            return true
        } catch {
            let errorMsg = "Failed to enable launch at login: \(error.localizedDescription)"
            logger.error("\(errorMsg)")
            await MainActor.run {
                self.lastError = errorMsg
                self.updateStatus()
            }
            return false
        }
    }
    
    func disable() async -> Bool {
        do {
            try appService.unregister()
            await MainActor.run {
                self.isEnabled = false
                self.lastError = nil
            }
            logger.info("Successfully disabled launch at login")
            return true
        } catch {
            let errorMsg = "Failed to disable launch at login: \(error.localizedDescription)"
            logger.error("\(errorMsg)")
            await MainActor.run {
                self.lastError = errorMsg
                self.updateStatus()
            }
            return false
        }
    }
    
    func toggle() async -> Bool {
        if isEnabled {
            return await disable()
        } else {
            return await enable()
        }
    }
}

// Legacy support for macOS < 13.0
class LaunchAtLoginLegacy {
    static func isEnabled() -> Bool {
        let launcherBundleId = "com.example.ratemate.launcher"
        
        if let jobs = SMCopyAllJobDictionaries(kSMDomainUserLaunchd).takeRetainedValue() as? [[String: Any]] {
            return jobs.contains { $0["Label"] as? String == launcherBundleId }
        }
        
        return false
    }
    
    static func setEnabled(_ enabled: Bool) -> Bool {
        let launcherBundleId = "com.example.ratemate.launcher"
        
        if enabled {
            return SMLoginItemSetEnabled(launcherBundleId as CFString, true)
        } else {
            return SMLoginItemSetEnabled(launcherBundleId as CFString, false)
        }
    }
}