import XCTest
@testable import RateMate

class OSLogParserTests: XCTestCase {
    
    var reader: OSLogMusicReader!
    
    override func setUp() {
        super.setUp()
        reader = OSLogMusicReader()
    }
    
    func testExtractSampleRateFromStandardFormat() {
        let testCases = [
            ("Playing at 44.1 kHz", 44100.0),
            ("Sample rate: 48 kHz", 48000.0),
            ("Format: 96000 Hz", 96000.0),
            ("Hi-Res Lossless 192 kHz", 192000.0),
            ("ALAC 24-bit/96 kHz", 96000.0),
            ("Lossless 88 kHz", 88000.0),
            ("Playing at 44,1 kHz", 44100.0), // Comma decimal
            ("176.4 kHz sample rate", 176400.0),
            ("88.2 kHz", 88200.0)
        ]
        
        for (input, expected) in testCases {
            let result = extractRateFromMessage(input)
            XCTAssertEqual(result, expected, "Failed to extract \(expected) from '\(input)'")
        }
    }
    
    func testInvalidSampleRates() {
        let invalidMessages = [
            "Playing music now",
            "Volume at 50%",
            "Track duration: 3:45",
            "Bitrate: 320 kbps",
            "Sample rate: 999999 Hz" // Invalid rate
        ]
        
        for message in invalidMessages {
            let result = extractRateFromMessage(message)
            XCTAssertNil(result, "Should not extract rate from '\(message)'")
        }
    }
    
    func testComplexLogMessages() {
        let complexMessages = [
            ("2024-01-15 10:30:45.123 Music[1234]: Starting playback of Hi-Res Lossless 96 kHz track", 96000.0),
            ("com.apple.Music: Format changed to ALAC 24-bit/176 kHz for current track", 176000.0),
            ("[DEBUG] Audio engine configured for 48000 Hz sample rate", 48000.0)
        ]
        
        for (input, expected) in complexMessages {
            let result = extractRateFromMessage(input)
            XCTAssertEqual(result, expected, "Failed to extract from complex message")
        }
    }
    
    // Helper method that mimics the private extractSampleRate method
    private func extractRateFromMessage(_ message: String) -> Double? {
        let patterns = [
            try! NSRegularExpression(pattern: #"(\d+)[,.](\d+)\s*kHz"#, options: .caseInsensitive),
            try! NSRegularExpression(pattern: #"(\d+)\s*Hz"#, options: .caseInsensitive),
            try! NSRegularExpression(pattern: #"ALAC\s+\d+-bit/(\d+)\s*kHz"#, options: .caseInsensitive),
            try! NSRegularExpression(pattern: #"Hi-Res Lossless\s+(\d+)\s*kHz"#, options: .caseInsensitive),
            try! NSRegularExpression(pattern: #"Lossless\s+(\d+)\s*kHz"#, options: .caseInsensitive),
            try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*kHz"#, options: .caseInsensitive),
            try! NSRegularExpression(pattern: #"sample rate.*?(\d+)"#, options: .caseInsensitive),
            try! NSRegularExpression(pattern: #"format.*?(\d+)\s*Hz"#, options: .caseInsensitive)
        ]
        
        let lowerMessage = message.lowercased()
        guard lowerMessage.contains("khz") ||
              lowerMessage.contains("hz") ||
              lowerMessage.contains("sample") ||
              lowerMessage.contains("rate") ||
              lowerMessage.contains("lossless") ||
              lowerMessage.contains("alac") ||
              lowerMessage.contains("format") else {
            return nil
        }
        
        for pattern in patterns {
            let matches = pattern.matches(in: message, range: NSRange(message.startIndex..., in: message))
            
            for match in matches {
                if pattern.pattern.contains("[,.]") && match.numberOfRanges > 2 {
                    if let intRange = Range(match.range(at: 1), in: message),
                       let decRange = Range(match.range(at: 2), in: message),
                       let intPart = Double(message[intRange]),
                       let decPart = Double(message[decRange]) {
                        let rate = intPart * 1000 + decPart * 100
                        if isValidSampleRate(rate) {
                            return rate
                        }
                    }
                } else if match.numberOfRanges > 1 {
                    for i in 1..<match.numberOfRanges {
                        if let range = Range(match.range(at: i), in: message),
                           let value = Double(message[range]) {
                            let rate: Double
                            
                            if message[range.upperBound...].lowercased().hasPrefix("khz") ||
                               pattern.pattern.lowercased().contains("khz") {
                                rate = value * 1000
                            } else {
                                rate = value
                            }
                            
                            if isValidSampleRate(rate) {
                                return rate
                            }
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    private func isValidSampleRate(_ rate: Double) -> Bool {
        let validRates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000]
        return validRates.contains(rate)
    }
}