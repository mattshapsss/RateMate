import Foundation

public struct MusicTrackInfo: Equatable {
    let title: String
    let artist: String?
    let album: String?
    let sampleRate: Double
    let timestamp: Date
    let source: String
    
    var displayName: String {
        if let artist = artist, !artist.isEmpty {
            return "\(title) - \(artist)"
        }
        return title
    }
    
    var rateDisplay: String {
        let kHz = sampleRate / 1000.0
        if kHz == floor(kHz) {
            return "\(Int(kHz)) kHz"
        } else {
            return String(format: "%.1f kHz", kHz)
        }
    }
}

public class MusicNowPlaying: ObservableObject {
    @Published var currentTrack: MusicTrackInfo?
    @Published var isPlaying = false
    
    static let shared = MusicNowPlaying()
    
    private init() {}
    
    func updateFromLog(_ message: String, sampleRate: Double, timestamp: Date) {
        // Try to extract track info from log message
        let trackInfo = parseTrackInfo(from: message)
        
        currentTrack = MusicTrackInfo(
            title: trackInfo.title ?? "Unknown Track",
            artist: trackInfo.artist,
            album: trackInfo.album,
            sampleRate: sampleRate,
            timestamp: timestamp,
            source: formatTime(timestamp)
        )
        
        isPlaying = true
    }
    
    private func parseTrackInfo(from message: String) -> (title: String?, artist: String?, album: String?) {
        // Common patterns in Music.app logs
        // "Playing track: Title by Artist"
        // "Now playing: Title - Artist"
        // "Track: Title, Artist: Artist, Album: Album"
        
        var title: String?
        var artist: String?
        var album: String?
        
        // Pattern 1: "Playing track: Title by Artist"
        if message.contains("Playing track:") {
            let parts = message.components(separatedBy: "Playing track:").last?.trimmingCharacters(in: .whitespaces)
            if let parts = parts {
                let byParts = parts.components(separatedBy: " by ")
                title = byParts.first?.trimmingCharacters(in: .whitespaces)
                artist = byParts.count > 1 ? byParts[1].trimmingCharacters(in: .whitespaces) : nil
            }
        }
        
        // Pattern 2: "Now playing: Title - Artist"
        else if message.contains("Now playing:") {
            let parts = message.components(separatedBy: "Now playing:").last?.trimmingCharacters(in: .whitespaces)
            if let parts = parts {
                let dashParts = parts.components(separatedBy: " - ")
                title = dashParts.first?.trimmingCharacters(in: .whitespaces)
                artist = dashParts.count > 1 ? dashParts[1].trimmingCharacters(in: .whitespaces) : nil
            }
        }
        
        // Pattern 3: Look for quoted strings (often titles/artists)
        let quotedPattern = try? NSRegularExpression(pattern: #""([^"]+)""#, options: [])
        if let matches = quotedPattern?.matches(in: message, range: NSRange(message.startIndex..., in: message)) {
            let strings = matches.compactMap { match -> String? in
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: message) else { return nil }
                return String(message[range])
            }
            
            if !strings.isEmpty {
                title = strings.first
                artist = strings.count > 1 ? strings[1] : nil
                album = strings.count > 2 ? strings[2] : nil
            }
        }
        
        // If we couldn't parse, use a portion of the message as title
        if title == nil && (message.contains("track") || message.contains("playing")) {
            title = message
                .replacingOccurrences(of: #"[\d,.]+ kHz"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
                .prefix(50)
                .trimmingCharacters(in: .whitespaces) + (message.count > 50 ? "..." : "")
        }
        
        return (title, artist, album)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "Music @ \(formatter.string(from: date))"
    }
}