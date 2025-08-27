#if USE_MEDIAREMOTE

import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "com.example.ratemate", category: "MediaRemote")

// MediaRemote private framework wrapper
// This is a fallback method for detecting playback changes when OSLog parsing is unavailable
// Note: This uses private APIs and may break in future macOS versions

@objc protocol MRNowPlayingClient {
    @objc optional func handleNowPlayingApplicationDidChange(_ notification: Notification)
    @objc optional func handleNowPlayingInfoDidChange(_ notification: Notification)
    @objc optional func handlePlaybackStateDidChange(_ notification: Notification)
}

class MediaRemoteWatcher: NSObject, ObservableObject {
    @Published var isMonitoring = false
    @Published var lastPlaybackInfo: [String: Any]?
    
    private let rateSubject = PassthroughSubject<Double?, Never>()
    private var notificationObservers: [Any] = []
    
    public var ratePublisher: AnyPublisher<Double?, Never> {
        rateSubject.eraseToAnyPublisher()
    }
    
    // Notification names from MediaRemote framework
    private let kMRMediaRemoteNowPlayingApplicationDidChangeNotification = "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
    private let kMRMediaRemoteNowPlayingInfoDidChangeNotification = "kMRMediaRemoteNowPlayingInfoDidChangeNotification"
    private let kMRMediaRemotePlaybackStateDidChangeNotification = "kMRMediaRemotePlaybackStateDidChangeNotification"
    
    override init() {
        super.init()
        loadMediaRemoteFramework()
    }
    
    deinit {
        stopMonitoring()
    }
    
    private func loadMediaRemoteFramework() {
        // Attempt to load MediaRemote.framework dynamically
        let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(frameworkPath, RTLD_LAZY) else {
            logger.error("Failed to load MediaRemote framework")
            return
        }
        
        // Get function pointers for MediaRemote functions we need
        typealias MRMediaRemoteRegisterForNowPlayingNotifications = @convention(c) (DispatchQueue) -> Void
        typealias MRMediaRemoteGetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
        
        if let registerFunc = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            let register = unsafeBitCast(registerFunc, to: MRMediaRemoteRegisterForNowPlayingNotifications.self)
            register(DispatchQueue.main)
            logger.info("Registered for MediaRemote notifications")
        }
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        
        // Register for notifications
        let nc = NotificationCenter.default
        
        notificationObservers.append(
            nc.addObserver(
                self,
                selector: #selector(handlePlaybackInfoChange(_:)),
                name: NSNotification.Name(kMRMediaRemoteNowPlayingInfoDidChangeNotification),
                object: nil
            )
        )
        
        notificationObservers.append(
            nc.addObserver(
                self,
                selector: #selector(handleApplicationChange(_:)),
                name: NSNotification.Name(kMRMediaRemoteNowPlayingApplicationDidChangeNotification),
                object: nil
            )
        )
        
        logger.info("MediaRemote monitoring started")
    }
    
    func stopMonitoring() {
        isMonitoring = false
        
        let nc = NotificationCenter.default
        notificationObservers.forEach { nc.removeObserver($0) }
        notificationObservers.removeAll()
        
        logger.info("MediaRemote monitoring stopped")
    }
    
    @objc private func handlePlaybackInfoChange(_ notification: Notification) {
        guard let info = notification.userInfo else { return }
        
        lastPlaybackInfo = info
        
        // Try to extract sample rate from the playback info
        // This is speculative as the actual keys may vary
        let possibleKeys = [
            "kMRMediaRemoteNowPlayingInfoSampleRate",
            "sampleRate",
            "audioFormat",
            "format"
        ]
        
        for key in possibleKeys {
            if let value = info[key] {
                logger.debug("Found potential rate info: \(key) = \(String(describing: value))")
                
                if let rateValue = extractRate(from: value) {
                    rateSubject.send(rateValue)
                    logger.info("Detected rate from MediaRemote: \(rateValue) Hz")
                    return
                }
            }
        }
        
        // If we can't find rate directly, send nil to trigger OSLog fallback
        rateSubject.send(nil)
    }
    
    @objc private func handleApplicationChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let bundleId = info["kMRMediaRemoteNowPlayingApplicationBundleIdentifier"] as? String else {
            return
        }
        
        if bundleId == "com.apple.Music" {
            logger.info("Apple Music became active player")
        } else {
            logger.info("Non-Music app became active: \(bundleId)")
            // Could pause monitoring or clear rate when Music isn't active
        }
    }
    
    private func extractRate(from value: Any) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        
        if let string = value as? String {
            // Try to parse rate from string
            let patterns = [
                try! NSRegularExpression(pattern: #"(\d+)"#, options: [])
            ]
            
            for pattern in patterns {
                let matches = pattern.matches(in: string, range: NSRange(string.startIndex..., in: string))
                if let match = matches.first,
                   let range = Range(match.range(at: 1), in: string),
                   let rate = Double(string[range]) {
                    // Validate it's a reasonable sample rate
                    let validRates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000]
                    if validRates.contains(rate) {
                        return rate
                    }
                }
            }
        }
        
        if let dict = value as? [String: Any] {
            // Recursively search dictionary
            for (_, val) in dict {
                if let rate = extractRate(from: val) {
                    return rate
                }
            }
        }
        
        return nil
    }
}

#endif // USE_MEDIAREMOTE