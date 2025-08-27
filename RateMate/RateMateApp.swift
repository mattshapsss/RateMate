import SwiftUI
import AppKit

@main
struct RateMateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var rateManager: RateManager?
    var permissionManager: PermissionManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure single instance
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.example.ratemate")
        if runningApps.count > 1 {
            NSApp.terminate(nil)
            return
        }
        
        NSApplication.shared.setActivationPolicy(.accessory)
        
        Task { @MainActor in
            statusBarController = StatusBarController.shared
            rateManager = RateManager.shared
            permissionManager = PermissionManager.shared
            
            // Defer permission check to avoid SwiftUI update cycles
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                
                // Check both permissions
                await permissionManager!.checkAllPermissions()
                
                // Show permission dialog if EITHER is missing
                if !permissionManager!.hasFullDiskAccess || !permissionManager!.hasMusicControl {
                    permissionManager!.showPermissionRequest()
                }
                
                // Always start monitoring (for track display)
                rateManager!.start()
                
                // Check for current track immediately (may trigger Music permission)
                await rateManager!.updateCurrentTrack()
                
                // If no FDA, show warning in log reader status
                if !permissionManager!.hasFullDiskAccess {
                    rateManager!.logReader.statusMessage = "⚠️ Full Disk Access required"
                }
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            rateManager?.stop()
        }
    }
}