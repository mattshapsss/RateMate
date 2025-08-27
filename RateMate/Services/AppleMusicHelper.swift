import Foundation
import OSLog

private let logger = Logger(subsystem: "com.example.ratemate", category: "AppleMusic")

public class AppleMusicHelper {
    static let shared = AppleMusicHelper()
    
    private init() {}
    
    func getCurrentTrack() async -> (title: String?, artist: String?, album: String?, isPlaying: Bool) {
        // Skip the System Events check - just try to get track directly
        // This will trigger permission dialog if needed
        
        // Now get track info if Music is running
        let script = """
        tell application "Music"
            if player state is playing then
                try
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    return trackName & "|" & trackArtist & "|" & trackAlbum & "|playing"
                on error
                    return "|||not_playing"
                end try
            else if player state is paused then
                try
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    return trackName & "|" & trackArtist & "|" & trackAlbum & "|paused"
                on error
                    return "|||paused"
                end try
            else
                return "|||stopped"
            end if
        end tell
        """
        
        do {
            let result = try await MainActor.run {
                try runAppleScript(script)
            }
            let parts = result.components(separatedBy: "|")
            
            let isPlaying = parts.count > 3 && parts[3] == "playing"
            
            logger.info("Got track info: \(parts.count > 0 ? parts[0] : "no title"), playing: \(isPlaying)")
            
            return (
                title: parts.count > 0 && !parts[0].isEmpty ? parts[0] : nil,
                artist: parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil,
                album: parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil,
                isPlaying: isPlaying
            )
        } catch {
            let nsError = error as NSError
            if nsError.code == -1743 {
                logger.warning("Music automation permission needed. User should grant in System Settings.")
            } else {
                logger.error("Failed to get track info: \(error)")
            }
            return (nil, nil, nil, false)
        }
    }
    
    func updateNowPlayingWithAppleScript() async {
        let trackInfo = await getCurrentTrack()
        
        if trackInfo.isPlaying, let title = trackInfo.title {
            await MainActor.run {
                // Update with AppleScript data if we have it
                if let currentTrack = MusicNowPlaying.shared.currentTrack {
                    // Merge AppleScript info with existing rate info
                    MusicNowPlaying.shared.currentTrack = MusicTrackInfo(
                        title: title,
                        artist: trackInfo.artist,
                        album: trackInfo.album,
                        sampleRate: currentTrack.sampleRate,
                        timestamp: Date(),
                        source: currentTrack.source
                    )
                }
            }
        }
    }
    
    @MainActor
    private func runAppleScript(_ script: String) throws -> String {
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        
        if let result = appleScript?.executeAndReturnError(&error) {
            return result.stringValue ?? ""
        } else if let error = error {
            let errorCode = error["NSAppleScriptErrorNumber"] as? Int ?? -1
            let errorMsg = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
            
            // -1743 = User hasn't granted permission for automation
            if errorCode == -1743 {
                logger.warning("Music control permission needed - error code: \(errorCode)")
                logger.warning("Please grant permission in System Settings > Privacy & Security > Automation")
            }
            
            logger.error("AppleScript error \(errorCode): \(errorMsg)")
            throw NSError(domain: "AppleScript", code: errorCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        } else {
            return ""
        }
    }
}