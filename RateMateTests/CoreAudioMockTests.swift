import XCTest
@testable import RateMate

class CoreAudioMockTests: XCTestCase {
    
    func testSupportedRatesExtraction() {
        // Test that we correctly extract discrete rates from AudioValueRange
        let mockRanges = [
            AudioValueRange(mMinimum: 44100, mMaximum: 44100),
            AudioValueRange(mMinimum: 48000, mMaximum: 48000),
            AudioValueRange(mMinimum: 88200, mMaximum: 192000) // Range covering multiple rates
        ]
        
        let expectedRates: Set<Double> = [44100, 48000, 88200, 96000, 176400, 192000]
        let extractedRates = extractRatesFromRanges(mockRanges)
        
        XCTAssertEqual(Set(extractedRates), expectedRates, "Should extract all valid rates from ranges")
    }
    
    func testRateValidation() {
        let validRates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000]
        let invalidRates: [Double] = [22050, 32000, 64000, 128000, 384000]
        
        for rate in validRates {
            XCTAssertTrue(isStandardSampleRate(rate), "\(rate) should be valid")
        }
        
        for rate in invalidRates {
            XCTAssertFalse(isStandardSampleRate(rate), "\(rate) should be invalid")
        }
    }
    
    func testDeviceNameFormatting() {
        let testNames = [
            ("Built-in Output", "Built-in Output"),
            ("External Headphones", "External Headphones"),
            ("", "Unknown Device"),
            ("USB Audio Device", "USB Audio Device")
        ]
        
        for (input, expected) in testNames {
            let formatted = formatDeviceName(input)
            XCTAssertEqual(formatted, expected)
        }
    }
    
    func testRateFormatting() {
        let testCases: [(Double, String)] = [
            (44100, "44.1"),
            (48000, "48"),
            (88200, "88.2"),
            (96000, "96"),
            (176400, "176.4"),
            (192000, "192")
        ]
        
        for (rate, expected) in testCases {
            let formatted = formatRateForDisplay(rate)
            XCTAssertEqual(formatted, expected, "Rate \(rate) should format as \(expected)")
        }
    }
    
    func testClosestRateSelection() {
        let supported: [Double] = [44100, 48000, 96000, 192000]
        
        let testCases: [(Double, Double)] = [
            (44100, 44100),  // Exact match
            (88200, 44100),  // 44.1 family, no 88.2 available
            (176400, 192000), // Closest available
            (48000, 48000),  // Exact match
            (96000, 96000),  // Exact match
            (50000, 48000),  // Closest by distance
        ]
        
        for (target, expected) in testCases {
            let closest = findClosestRate(target: target, supported: supported)
            XCTAssertEqual(closest, expected, "For target \(target), should select \(expected)")
        }
    }
    
    // Helper functions
    private func extractRatesFromRanges(_ ranges: [AudioValueRange]) -> [Double] {
        var rates = Set<Double>()
        
        for range in ranges {
            if range.mMinimum == range.mMaximum {
                rates.insert(range.mMinimum)
            } else {
                let commonRates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000]
                for rate in commonRates {
                    if rate >= range.mMinimum && rate <= range.mMaximum {
                        rates.insert(rate)
                    }
                }
            }
        }
        
        return rates.sorted()
    }
    
    private func isStandardSampleRate(_ rate: Double) -> Bool {
        let standardRates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000]
        return standardRates.contains(rate)
    }
    
    private func formatDeviceName(_ name: String) -> String {
        return name.isEmpty ? "Unknown Device" : name
    }
    
    private func formatRateForDisplay(_ rate: Double) -> String {
        let kHz = rate / 1000.0
        if kHz == floor(kHz) {
            return "\(Int(kHz))"
        } else {
            return String(format: "%.1f", kHz)
        }
    }
    
    private func findClosestRate(target: Double, supported: [Double]) -> Double? {
        guard !supported.isEmpty else { return nil }
        
        if supported.contains(target) {
            return target
        }
        
        return supported.min(by: { abs($0 - target) < abs($1 - target) })
    }
}

// Mock AudioValueRange for testing (since we can't import CoreAudio in tests)
struct AudioValueRange {
    let mMinimum: Double
    let mMaximum: Double
}