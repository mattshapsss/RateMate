import Foundation
import Combine

class Preferences: ObservableObject {
    static let shared = Preferences()
    
    @Published var autoSwitchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoSwitchEnabled, forKey: "autoSwitchEnabled")
        }
    }
    
    @Published var debounceMs: Double {
        didSet {
            UserDefaults.standard.set(debounceMs, forKey: "debounceMs")
        }
    }
    
    @Published var preferHigherFamily: Bool {
        didSet {
            UserDefaults.standard.set(preferHigherFamily, forKey: "preferHigherFamily")
        }
    }
    
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
        }
    }
    
    @Published var showDebugInfo: Bool {
        didSet {
            UserDefaults.standard.set(showDebugInfo, forKey: "showDebugInfo")
        }
    }
    
    @Published var preferFixedFamilyRates: Bool {
        didSet {
            UserDefaults.standard.set(preferFixedFamilyRates, forKey: "preferFixedFamilyRates")
        }
    }
    
    @Published var fixed44_1FamilyRate: Double {
        didSet {
            UserDefaults.standard.set(fixed44_1FamilyRate, forKey: "fixed44_1FamilyRate")
        }
    }
    
    @Published var fixed48FamilyRate: Double {
        didSet {
            UserDefaults.standard.set(fixed48FamilyRate, forKey: "fixed48FamilyRate")
        }
    }
    
    private init() {
        self.autoSwitchEnabled = UserDefaults.standard.object(forKey: "autoSwitchEnabled") as? Bool ?? true
        self.debounceMs = UserDefaults.standard.object(forKey: "debounceMs") as? Double ?? 300
        self.preferHigherFamily = UserDefaults.standard.object(forKey: "preferHigherFamily") as? Bool ?? true
        self.launchAtLogin = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? false
        self.showDebugInfo = UserDefaults.standard.object(forKey: "showDebugInfo") as? Bool ?? false
        self.preferFixedFamilyRates = UserDefaults.standard.object(forKey: "preferFixedFamilyRates") as? Bool ?? false
        self.fixed44_1FamilyRate = UserDefaults.standard.object(forKey: "fixed44_1FamilyRate") as? Double ?? 88200
        self.fixed48FamilyRate = UserDefaults.standard.object(forKey: "fixed48FamilyRate") as? Double ?? 96000
    }
    
    func resetToDefaults() {
        autoSwitchEnabled = true
        debounceMs = 300
        preferHigherFamily = true
        launchAtLogin = false
        showDebugInfo = false
        preferFixedFamilyRates = false
        fixed44_1FamilyRate = 88200
        fixed48FamilyRate = 96000
    }
}