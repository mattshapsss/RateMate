import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "com.example.ratemate", category: "RateManager")

@MainActor
class RateManager: ObservableObject {
    static let shared = RateManager()
    
    @Published var isMonitoring = false
    @Published var lastAppliedRate: Double = 0
    @Published var pendingRate: Double?
    
    let audioDevice = CoreAudioDevice()
    let logReader = OSLogMusicReader()
    private let statusBarController = StatusBarController.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var debounceTask: Task<Void, Never>?
    private var lastRateChangeTime = Date()
    private var trackMonitorTask: Task<Void, Never>?
    private var rateSyncTask: Task<Void, Never>?
    
    private init() {
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        logReader.ratePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { [weak self] in
                    await self?.handleDetectedRate(event.sampleRate)
                }
            }
            .store(in: &cancellables)
        
        audioDevice.$currentDevice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                guard let device = device else { return }
                self?.statusBarController.updateRate(device.currentRate)
                logger.info("Device updated: \(device.name) at \(device.currentRate) Hz")
            }
            .store(in: &cancellables)
    }
    
    func start() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        
        // Always start track monitoring for display
        startTrackMonitoring()
        
        // Only start rate monitoring if we have Full Disk Access
        if PermissionManager.shared.hasFullDiskAccess {
            logReader.startMonitoring()
            startRateSyncMonitoring()
            logger.info("Full rate monitoring started with FDA")
        } else {
            logger.warning("Starting without Full Disk Access - rate detection disabled")
            logReader.statusMessage = "⚠️ Full Disk Access required for rate detection"
        }
        
        logger.info("Monitoring started")
    }
    
    func stop() {
        isMonitoring = false
        logReader.stopMonitoring()
        debounceTask?.cancel()
        trackMonitorTask?.cancel()
        rateSyncTask?.cancel()
        logger.info("Rate monitoring stopped")
    }
    
    func handleDetectedRate(_ detectedRate: Double) async {
        guard Preferences.shared.autoSwitchEnabled else {
            logger.info("Auto-switch disabled, ignoring rate: \(detectedRate)")
            return
        }
        
        guard let device = audioDevice.currentDevice else {
            logger.warning("No audio device available")
            return
        }
        
        // Try to get better track info from AppleScript
        Task {
            await AppleMusicHelper.shared.updateNowPlayingWithAppleScript()
        }
        
        // Apply family coalescing if enabled
        let effectiveRate = determineEffectiveRate(detectedRate)
        
        if device.currentRate == effectiveRate {
            logger.info("Rate already matches: \(effectiveRate) Hz")
            return
        }
        
        let targetRate: Double
        if device.supportedRates.contains(effectiveRate) {
            targetRate = effectiveRate
        } else if let closest = audioDevice.findClosestSupportedRate(
            targetHz: effectiveRate,
            forDevice: device.id
        ) {
            targetRate = closest
            logger.info("Using closest supported rate: \(targetRate) Hz for effective: \(effectiveRate) Hz")
        } else {
            logger.warning("No suitable rate found for: \(effectiveRate) Hz")
            return
        }
        
        pendingRate = targetRate
        statusBarController.updateRate(device.currentRate, isTransitioning: true, targetRate: targetRate)
        
        debounceTask?.cancel()
        
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(Preferences.shared.debounceMs * 1_000_000))
                
                guard !Task.isCancelled else { return }
                
                await self?.applyRate(targetRate)
            } catch {
                logger.error("Debounce task error: \(error)")
            }
        }
    }
    
    func setManualRate(_ rate: Double) async {
        guard let device = audioDevice.currentDevice else { return }
        
        debounceTask?.cancel()
        pendingRate = nil
        
        statusBarController.updateRate(device.currentRate, isTransitioning: true, targetRate: rate)
        
        await applyRate(rate)
    }
    
    private func determineEffectiveRate(_ detectedRate: Double) -> Double {
        // If fixed family rates are preferred, coalesce to fixed rates
        if Preferences.shared.preferFixedFamilyRates {
            let rateFamily44_1: [Double] = [44100, 88200, 176400]
            let rateFamily48: [Double] = [48000, 96000, 192000]
            
            if rateFamily44_1.contains(detectedRate) {
                let fixedRate = Preferences.shared.fixed44_1FamilyRate
                logger.info("Coalescing \(detectedRate) Hz to fixed 44.1 family rate: \(fixedRate) Hz")
                return fixedRate
            } else if rateFamily48.contains(detectedRate) {
                let fixedRate = Preferences.shared.fixed48FamilyRate
                logger.info("Coalescing \(detectedRate) Hz to fixed 48 family rate: \(fixedRate) Hz")
                return fixedRate
            }
        }
        
        // Otherwise return the detected rate as-is
        return detectedRate
    }
    
    private func applyRate(_ rate: Double) async {
        guard let device = audioDevice.currentDevice else { return }
        
        logger.info("Applying rate: \(rate) Hz to device: \(device.name)")
        
        let success = await audioDevice.setNominalRate(device.id, rateHz: rate)
        
        if success {
            lastAppliedRate = rate
            pendingRate = nil
            
            // Update UI with actual accepted rate if available
            if let actualRate = audioDevice.actualAcceptedRate {
                statusBarController.updateRate(actualRate)
                if audioDevice.rateDiscrepancy {
                    statusBarController.showError()
                }
                logger.info("Device accepted rate: \(actualRate) Hz")
            } else {
                statusBarController.updateRate(rate)
                logger.info("Successfully requested rate: \(rate) Hz")
            }
        } else {
            statusBarController.showError()
            logger.error("Failed to apply rate: \(rate) Hz")
        }
    }
    
    // MARK: - Periodic Monitoring
    
    private func startTrackMonitoring() {
        trackMonitorTask?.cancel()
        
        trackMonitorTask = Task { [weak self] in
            // Initial check immediately
            await self?.updateCurrentTrack()
            
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { break }
                    
                    await self?.updateCurrentTrack()
                } catch {
                    break
                }
            }
        }
    }
    
    private func startRateSyncMonitoring() {
        rateSyncTask?.cancel()
        
        rateSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { break }
                    
                    await self?.checkAndSyncRate()
                } catch {
                    break
                }
            }
        }
    }
    
    func updateCurrentTrack() async {
        let trackInfo = await AppleMusicHelper.shared.getCurrentTrack()
        
        if trackInfo.isPlaying, let title = trackInfo.title {
            await MainActor.run {
                // Use current device rate if we don't have a detected rate
                let currentRate = audioDevice.currentDevice?.currentRate ?? 44100
                
                // Update or create track info
                if MusicNowPlaying.shared.currentTrack == nil {
                    MusicNowPlaying.shared.currentTrack = MusicTrackInfo(
                        title: title,
                        artist: trackInfo.artist,
                        album: trackInfo.album,
                        sampleRate: currentRate,
                        timestamp: Date(),
                        source: "Music"
                    )
                } else {
                    // Update existing track info
                    MusicNowPlaying.shared.currentTrack = MusicTrackInfo(
                        title: title,
                        artist: trackInfo.artist,
                        album: trackInfo.album,
                        sampleRate: MusicNowPlaying.shared.currentTrack?.sampleRate ?? currentRate,
                        timestamp: Date(),
                        source: MusicNowPlaying.shared.currentTrack?.source ?? "Music"
                    )
                }
                
                MusicNowPlaying.shared.isPlaying = true
            }
        } else {
            await MainActor.run {
                MusicNowPlaying.shared.isPlaying = trackInfo.isPlaying
                if !trackInfo.isPlaying {
                    // Clear track after a delay when stopped
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        if !MusicNowPlaying.shared.isPlaying {
                            MusicNowPlaying.shared.currentTrack = nil
                        }
                    }
                }
            }
        }
    }
    
    private func checkAndSyncRate() async {
        // Update device info to get current actual rate
        await MainActor.run {
            audioDevice.updateCurrentDevice()
        }
        
        // Only sync if auto-switch is enabled and music is playing
        guard Preferences.shared.autoSwitchEnabled,
              MusicNowPlaying.shared.isPlaying,
              let currentTrack = MusicNowPlaying.shared.currentTrack,
              let device = audioDevice.currentDevice else {
            return
        }
        
        // Check if we should be at a different rate
        let targetRate = determineEffectiveRate(currentTrack.sampleRate)
        
        if abs(device.currentRate - targetRate) > 1 {
            logger.info("Rate sync: Current \(device.currentRate) Hz, should be \(targetRate) Hz")
            await handleDetectedRate(targetRate)
        }
    }
}