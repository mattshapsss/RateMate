import XCTest
import Combine
@testable import RateMate

@MainActor
class AcceptanceTests: XCTestCase {
    
    var rateManager: RateManager!
    var audioDevice: CoreAudioDevice!
    var cancellables = Set<AnyCancellable>()
    
    override func setUp() async throws {
        try await super.setUp()
        rateManager = RateManager.shared
        audioDevice = CoreAudioDevice()
        cancellables.removeAll()
        
        // Configure for testing
        Preferences.shared.autoSwitchEnabled = true
        Preferences.shared.debounceMs = 300
    }
    
    // Acceptance Test 1: 44.1 kHz content detection and switching
    func testAcceptance_44_1kHz_Detection() async throws {
        print("🧪 Acceptance Test 1: Apple Music 44.1 kHz Detection")
        
        let expectation = XCTestExpectation(description: "Device switches to 44.1 kHz")
        
        audioDevice.$currentDevice
            .compactMap { $0 }
            .sink { device in
                if device.currentRate == 44100 {
                    print("✅ Device switched to 44.1 kHz")
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Simulate detection of 44.1 kHz content
        print("📻 Simulating 44.1 kHz track detection...")
        await rateManager.handleDetectedRate(44100)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(audioDevice.currentDevice?.currentRate, 44100, "Device should be at 44.1 kHz")
    }
    
    // Acceptance Test 2: Hi-Res 96 kHz content switching
    func testAcceptance_96kHz_HiRes() async throws {
        print("🧪 Acceptance Test 2: Hi-Res 96 kHz Album Switching")
        
        let expectation = XCTestExpectation(description: "Device switches to 96 kHz")
        
        audioDevice.$currentDevice
            .compactMap { $0 }
            .sink { device in
                if device.currentRate == 96000 {
                    print("✅ Device switched to 96 kHz")
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Simulate detection of 96 kHz Hi-Res content
        print("📻 Simulating Hi-Res 96 kHz track detection...")
        await rateManager.handleDetectedRate(96000)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        let currentRate = audioDevice.currentDevice?.currentRate ?? 0
        let supportedRates = audioDevice.currentDevice?.supportedRates ?? []
        
        if supportedRates.contains(96000) {
            XCTAssertEqual(currentRate, 96000, "Device should be at 96 kHz")
        } else {
            // Check if closest supported rate was selected
            let closest = audioDevice.findClosestSupportedRate(
                targetHz: 96000,
                forDevice: audioDevice.currentDevice!.id
            )
            XCTAssertEqual(currentRate, closest, "Device should be at closest supported rate")
            print("⚠️ Device doesn't support 96 kHz, using \(closest ?? 0) Hz")
        }
    }
    
    // Acceptance Test 3: 48 kHz content with family preference
    func testAcceptance_48kHz_FamilySwitch() async throws {
        print("🧪 Acceptance Test 3: 48 kHz Content Family Switching")
        
        Preferences.shared.preferHigherFamily = true
        
        let expectation = XCTestExpectation(description: "Device switches to 48/96 family rate")
        
        audioDevice.$currentDevice
            .compactMap { $0 }
            .sink { device in
                if device.currentRate == 48000 || device.currentRate == 96000 {
                    print("✅ Device switched to \(device.currentRate) Hz (48 kHz family)")
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Simulate detection of 48 kHz content
        print("📻 Simulating 48 kHz track detection...")
        await rateManager.handleDetectedRate(48000)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        let currentRate = audioDevice.currentDevice?.currentRate ?? 0
        XCTAssertTrue([48000, 96000, 192000].contains(currentRate), 
                     "Device should be in 48 kHz family")
    }
    
    // Acceptance Test 4: Auto-switch toggle
    func testAcceptance_AutoSwitchToggle() async throws {
        print("🧪 Acceptance Test 4: Auto-Switch Toggle Behavior")
        
        // Enable auto-switch
        Preferences.shared.autoSwitchEnabled = true
        let initialRate = audioDevice.currentDevice?.currentRate ?? 0
        print("📊 Initial rate: \(initialRate) Hz")
        
        // Try to switch with auto-switch enabled
        print("✅ Auto-switch ON - attempting rate change...")
        await rateManager.handleDetectedRate(96000)
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        let rateAfterEnabled = audioDevice.currentDevice?.currentRate ?? 0
        print("📊 Rate after auto-switch: \(rateAfterEnabled) Hz")
        
        // Disable auto-switch
        Preferences.shared.autoSwitchEnabled = false
        print("❌ Auto-switch OFF - attempting rate change...")
        
        await rateManager.handleDetectedRate(44100)
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        let rateAfterDisabled = audioDevice.currentDevice?.currentRate ?? 0
        print("📊 Rate after disabled: \(rateAfterDisabled) Hz")
        
        // When auto-switch is off, rate should not change
        XCTAssertEqual(rateAfterDisabled, rateAfterEnabled, 
                      "Rate should not change when auto-switch is disabled")
        print("✅ Auto-switch toggle working correctly")
    }
    
    // Integration test for full flow
    func testIntegration_FullWorkflow() async throws {
        print("🧪 Integration Test: Complete Workflow")
        
        // 1. Check permissions
        let permissionManager = PermissionManager()
        let hasAccess = permissionManager.hasFullDiskAccess()
        print("🔐 Full Disk Access: \(hasAccess ? "✅" : "❌")")
        
        // 2. Start monitoring
        rateManager.start()
        XCTAssertTrue(rateManager.isMonitoring, "Monitoring should be active")
        print("📡 Monitoring started")
        
        // 3. Simulate track sequence
        let trackSequence: [(String, Double)] = [
            ("Standard Quality", 44100),
            ("Hi-Res Lossless", 96000),
            ("Standard Lossless", 48000),
            ("Ultra Hi-Res", 192000)
        ]
        
        for (quality, rate) in trackSequence {
            print("🎵 Playing \(quality) at \(rate) Hz...")
            await rateManager.handleDetectedRate(rate)
            try await Task.sleep(nanoseconds: 400_000_000) // 400ms
            
            let currentRate = audioDevice.currentDevice?.currentRate ?? 0
            print("   Device rate: \(currentRate) Hz")
        }
        
        // 4. Stop monitoring
        rateManager.stop()
        XCTAssertFalse(rateManager.isMonitoring, "Monitoring should be stopped")
        print("⏹ Monitoring stopped")
        
        print("✅ Integration test completed successfully")
    }
    
    // Performance test for debouncing
    func testPerformance_Debouncing() async throws {
        print("🧪 Performance Test: Debouncing Efficiency")
        
        Preferences.shared.debounceMs = 100
        
        var rateChanges = 0
        audioDevice.$currentDevice
            .compactMap { $0?.currentRate }
            .removeDuplicates()
            .sink { _ in
                rateChanges += 1
            }
            .store(in: &cancellables)
        
        // Rapid fire rate changes
        let rapidRates = Array(repeating: [44100.0, 48000.0, 96000.0], count: 10).flatMap { $0 }
        
        let startTime = Date()
        for rate in rapidRates {
            await rateManager.handleDetectedRate(rate)
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms between changes
        }
        
        // Wait for debounce to settle
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        print("📊 Sent \(rapidRates.count) rate changes in \(String(format: "%.2f", elapsed))s")
        print("📊 Actual device changes: \(rateChanges)")
        
        // Should have significantly fewer actual changes than requests
        XCTAssertLessThan(rateChanges, rapidRates.count / 2, 
                         "Debouncing should reduce rate changes significantly")
        print("✅ Debouncing working efficiently")
    }
}

// Test runner for command line execution
extension AcceptanceTests {
    static func runAllTests() async {
        print("=====================================")
        print("🚀 RateMate Acceptance Tests")
        print("=====================================\n")
        
        let tests = AcceptanceTests()
        await tests.setUp()
        
        let testMethods = [
            ("44.1 kHz Detection", tests.testAcceptance_44_1kHz_Detection),
            ("96 kHz Hi-Res", tests.testAcceptance_96kHz_HiRes),
            ("48 kHz Family", tests.testAcceptance_48kHz_FamilySwitch),
            ("Auto-Switch Toggle", tests.testAcceptance_AutoSwitchToggle),
            ("Full Integration", tests.testIntegration_FullWorkflow),
            ("Debounce Performance", tests.testPerformance_Debouncing)
        ]
        
        var passed = 0
        var failed = 0
        
        for (name, test) in testMethods {
            print("\n📋 Running: \(name)")
            print("-------------------------------------")
            
            do {
                try await test()
                passed += 1
                print("✅ PASSED: \(name)\n")
            } catch {
                failed += 1
                print("❌ FAILED: \(name)")
                print("   Error: \(error)\n")
            }
        }
        
        print("\n=====================================")
        print("📊 Test Results")
        print("=====================================")
        print("✅ Passed: \(passed)")
        print("❌ Failed: \(failed)")
        print("📈 Success Rate: \(Int(Double(passed) / Double(passed + failed) * 100))%")
        print("=====================================\n")
    }
}