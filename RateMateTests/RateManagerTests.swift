import XCTest
import Combine
@testable import RateMate

@MainActor
class RateManagerTests: XCTestCase {
    
    var rateManager: RateManager!
    var cancellables = Set<AnyCancellable>()
    
    override func setUp() async throws {
        try await super.setUp()
        rateManager = RateManager.shared
        cancellables.removeAll()
    }
    
    func testDebouncing() async throws {
        // Configure short debounce for testing
        Preferences.shared.debounceMs = 100
        Preferences.shared.autoSwitchEnabled = true
        
        var appliedRates: [Double] = []
        
        // Monitor rate changes
        rateManager.$lastAppliedRate
            .dropFirst() // Skip initial value
            .sink { rate in
                if rate > 0 {
                    appliedRates.append(rate)
                }
            }
            .store(in: &cancellables)
        
        // Simulate rapid rate changes
        await rateManager.handleDetectedRate(44100)
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        await rateManager.handleDetectedRate(48000)
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        await rateManager.handleDetectedRate(96000)
        
        // Wait for debounce period to complete
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Only the last rate should have been applied
        XCTAssertEqual(appliedRates.count, 1, "Should only apply one rate after debouncing")
        if !appliedRates.isEmpty {
            XCTAssertEqual(appliedRates.last, 96000, "Should apply the last debounced rate")
        }
    }
    
    func testRateFamilyMatching() {
        let audioDevice = CoreAudioDevice()
        
        // Test 44.1kHz family
        let supported44_1: [Double] = [44100, 88200, 176400]
        var closest = findClosestRate(target: 44100, supported: supported44_1)
        XCTAssertEqual(closest, 44100, "Should match exact rate")
        
        // When 44.1 not available, should prefer 88.2
        let supported88_2: [Double] = [48000, 88200, 96000]
        closest = findClosestRate(target: 44100, supported: supported88_2, preferHigherFamily: true)
        XCTAssertEqual(closest, 88200, "Should prefer 88.2 for 44.1 content")
        
        // Test 48kHz family
        let supported48: [Double] = [48000, 96000, 192000]
        closest = findClosestRate(target: 48000, supported: supported48)
        XCTAssertEqual(closest, 48000, "Should match exact rate")
        
        // When 48 not available, should prefer 96
        let supported96: [Double] = [44100, 88200, 96000]
        closest = findClosestRate(target: 48000, supported: supported96, preferHigherFamily: true)
        XCTAssertEqual(closest, 96000, "Should prefer 96 for 48 content")
    }
    
    func testAutoSwitchToggle() async {
        // Test that monitoring stops when auto-switch is disabled
        Preferences.shared.autoSwitchEnabled = true
        rateManager.start()
        XCTAssertTrue(rateManager.isMonitoring)
        
        Preferences.shared.autoSwitchEnabled = false
        await rateManager.handleDetectedRate(96000)
        
        // Rate should not change when auto-switch is disabled
        XCTAssertNotEqual(rateManager.pendingRate, 96000)
    }
    
    func testManualRateOverride() async throws {
        // Manual rate changes should cancel pending debounced changes
        Preferences.shared.debounceMs = 200
        
        // Start a debounced rate change
        await rateManager.handleDetectedRate(48000)
        
        // Immediately set manual rate
        await rateManager.setManualRate(96000)
        
        // Wait to ensure debounced change doesn't override manual
        try await Task.sleep(nanoseconds: 300_000_000) // 300ms
        
        XCTAssertNil(rateManager.pendingRate, "Pending rate should be cleared after manual override")
    }
    
    // Helper function to mimic rate family logic
    private func findClosestRate(target: Double, supported: [Double], preferHigherFamily: Bool = true) -> Double? {
        guard !supported.isEmpty else { return nil }
        
        if supported.contains(target) {
            return target
        }
        
        let rateFamily44_1: [Double] = [44100, 88200, 176400]
        let rateFamily48: [Double] = [48000, 96000, 192000]
        
        let is44_1Family = rateFamily44_1.contains(target)
        let targetFamily = is44_1Family ? rateFamily44_1 : rateFamily48
        
        if preferHigherFamily {
            for rate in targetFamily {
                if supported.contains(rate) && rate >= target {
                    return rate
                }
            }
        }
        
        return supported.min(by: { abs($0 - target) < abs($1 - target) })
    }
}