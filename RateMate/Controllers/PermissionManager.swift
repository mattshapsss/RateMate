import Foundation
import OSLog
import AppKit

private let logger = Logger(subsystem: "com.example.ratemate", category: "Permissions")

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    // Separate tracking for each permission
    @Published var hasFullDiskAccess = false
    @Published var hasMusicControl = false
    @Published var hasCheckedFDA = false
    @Published var hasCheckedMusic = false
    
    // Legacy compatibility
    var hasAccess: Bool { hasFullDiskAccess }
    var hasCheckedAccess: Bool { hasCheckedFDA }
    
    private init() {
        // Don't check during init to avoid SwiftUI update cycles
    }
    
    func checkAllPermissions() async {
        await checkFullDiskAccessAsync()
        await checkMusicControlAsync()
    }
    
    func checkAccessAsync() async {
        await checkFullDiskAccessAsync()
    }
    
    func checkFullDiskAccessAsync() async {
        await MainActor.run {
            _ = checkFullDiskAccess()
        }
    }
    
    func checkMusicControlAsync() async {
        await MainActor.run {
            _ = checkMusicControl()
        }
    }
    
    @discardableResult
    func checkAccess() -> Bool {
        return checkFullDiskAccess()
    }
    
    @discardableResult
    func checkFullDiskAccess() -> Bool {
        // Avoid multiple simultaneous checks
        guard !hasCheckedFDA else { return hasFullDiskAccess }
        
        do {
            _ = try OSLogStore(scope: .system)
            Task { @MainActor in
                self.hasFullDiskAccess = true
                self.hasCheckedFDA = true
            }
            logger.info("Full Disk Access granted")
            return true
        } catch {
            Task { @MainActor in
                self.hasFullDiskAccess = false
                self.hasCheckedFDA = true
            }
            logger.warning("Full Disk Access denied: \(error.localizedDescription)")
            return false
        }
    }
    
    @discardableResult
    func checkMusicControl() -> Bool {
        // Check if we can access Music app via AppleScript
        guard !hasCheckedMusic else { return hasMusicControl }
        
        let script = """
        tell application "System Events"
            return exists application process "Music"
        end tell
        """
        
        do {
            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            _ = appleScript?.executeAndReturnError(&error)
            
            if let error = error {
                let errorCode = error["NSAppleScriptErrorNumber"] as? Int ?? -1
                if errorCode == -1743 {
                    // Permission denied
                    Task { @MainActor in
                        self.hasMusicControl = false
                        self.hasCheckedMusic = true
                    }
                    logger.warning("Music control permission denied")
                    return false
                }
            }
            
            // Permission granted or not needed yet
            Task { @MainActor in
                self.hasMusicControl = true
                self.hasCheckedMusic = true
            }
            logger.info("Music control permission available")
            return true
        } catch {
            Task { @MainActor in
                self.hasMusicControl = false
                self.hasCheckedMusic = true
            }
            logger.warning("Failed to check Music control: \(error)")
            return false
        }
    }
    
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
        logger.info("Opening System Settings for Full Disk Access")
    }
    
    func showPermissionRequest() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Check what's missing
            let needsFDA = !self.hasFullDiskAccess
            let needsMusic = !self.hasMusicControl
            
            if !needsFDA && !needsMusic {
                logger.info("All permissions granted")
                return
            }
            
            let alert = NSAlert()
            alert.messageText = "Permissions Required"
            
            var infoText = "RateMate needs the following permissions:\n\n"
            
            if needsMusic {
                infoText += "✗ Music Control - To display track names\n"
            } else {
                infoText += "✓ Music Control - Granted\n"
            }
            
            if needsFDA {
                infoText += "✗ Full Disk Access - To detect sample rates from logs\n"
            } else {
                infoText += "✓ Full Disk Access - Granted\n"
            }
            
            if needsFDA {
                infoText += """
                
                To grant Full Disk Access:
                1. Click "Open System Settings"
                2. Find RateMate in the list
                3. Enable the toggle
                4. Restart RateMate
                """
            }
            
            if needsMusic {
                infoText += """
                
                Music Control permission will be requested automatically when needed.
                """
            }
            
            alert.informativeText = infoText
            alert.alertStyle = .informational
            
            if needsFDA {
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Later")
            } else {
                alert.addButton(withTitle: "OK")
            }
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn && needsFDA {
                self.openSystemSettings()
            }
        }
    }
}