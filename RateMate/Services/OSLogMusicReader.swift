import Foundation
import OSLog
import Combine

private let logger = Logger(subsystem: "com.example.ratemate", category: "OSLogReader")

public struct MusicRateEvent {
    let sampleRate: Double
    let timestamp: Date
    let source: String
    let logMessage: String?
}

public class OSLogMusicReader: ObservableObject {
    @Published var lastDetectedRate: MusicRateEvent?
    @Published var isMonitoring = false
    @Published var hasAccess = false
    @Published var statusMessage = "Not monitoring"
    @Published var lastCheckTime: Date?
    @Published var detectionAttempts = 0
    
    private var logStore: OSLogStore?
    private var lastPosition: OSLogPosition?
    private var monitorTask: Task<Void, Never>?
    private let rateSubject = PassthroughSubject<MusicRateEvent, Never>()
    
    public var ratePublisher: AnyPublisher<MusicRateEvent, Never> {
        rateSubject.eraseToAnyPublisher()
    }
    
    private let patterns = [
        try! NSRegularExpression(pattern: #"(\d+)[,.](\d+)\s*kHz"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"(\d+)\s*Hz"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"ALAC\s+\d+-bit/(\d+)\s*kHz"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"Hi-Res Lossless\s+(\d+)\s*kHz"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"Lossless\s+(\d+)\s*kHz"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*kHz"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"sample rate.*?(\d+)"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"format.*?(\d+)\s*Hz"#, options: .caseInsensitive)
    ]
    
    init() {
        checkAccess()
    }
    
    func checkAccess() {
        do {
            logStore = try OSLogStore(scope: .system)
            hasAccess = true
            logger.info("OSLog access granted")
        } catch {
            hasAccess = false
            logger.warning("No OSLog access: \(error.localizedDescription)")
        }
    }
    
    func startMonitoring() {
        guard hasAccess else {
            logger.warning("Cannot start monitoring without OSLog access")
            statusMessage = "⚠️ Full Disk Access required"
            return
        }
        
        stopMonitoring()
        isMonitoring = true
        statusMessage = "🔍 Monitoring logs..."
        
        monitorTask = Task {
            await monitorLogs()
        }
    }
    
    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        isMonitoring = false
        statusMessage = "Monitoring stopped"
    }
    
    private func monitorLogs() async {
        guard let store = logStore else { return }
        
        do {
            lastPosition = store.position(timeIntervalSinceLatestBoot: -5)
            
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 500_000_000) // 500ms for faster updates
                
                guard let position = lastPosition else { continue }
                
                let predicate = NSPredicate(format: """
                    subsystem == 'com.apple.Music' OR 
                    subsystem == 'com.apple.amp.mediaplaybackcore' OR
                    subsystem == 'com.apple.MediaPlayer' OR
                    category == 'Music'
                """)
                
                let entries = try store.getEntries(at: position, matching: predicate)
                
                await MainActor.run {
                    self.lastCheckTime = Date()
                    self.detectionAttempts += 1
                }
                
                var foundRate = false
                for entry in entries {
                    guard let logEntry = entry as? OSLogEntryLog else { continue }
                    
                    let message = logEntry.composedMessage
                    
                    if let rate = extractSampleRate(from: message) {
                        foundRate = true
                        let event = MusicRateEvent(
                            sampleRate: rate,
                            timestamp: logEntry.date,
                            source: "Music @ \(formatTime(logEntry.date))",
                            logMessage: message
                        )
                        
                        await MainActor.run {
                            self.lastDetectedRate = event
                            self.statusMessage = "✅ Detected: \(Int(rate/1000))kHz"
                            MusicNowPlaying.shared.updateFromLog(message, sampleRate: rate, timestamp: logEntry.date)
                        }
                        
                        rateSubject.send(event)
                        logger.info("Detected sample rate: \(rate) Hz from: \(message)")
                    }
                }
                
                if !foundRate && detectionAttempts % 10 == 0 {
                    await MainActor.run {
                        self.statusMessage = "🔍 Scanning... (checked \(detectionAttempts) times)"
                    }
                }
                
                lastPosition = store.position(date: Date())
            }
        } catch {
            logger.error("Log monitoring error: \(error.localizedDescription)")
            await MainActor.run {
                self.isMonitoring = false
                self.statusMessage = "❌ Error: \(error.localizedDescription)"
            }
        }
    }
    
    private func extractSampleRate(from message: String) -> Double? {
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
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}