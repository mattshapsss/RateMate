import Foundation
import CoreAudio
import AudioToolbox
import OSLog

private let logger = Logger(subsystem: "com.example.ratemate", category: "CoreAudio")

public struct AudioDeviceInfo {
    let id: AudioObjectID
    let name: String
    let currentRate: Double
    let supportedRates: [Double]
}

public class CoreAudioDevice: ObservableObject {
    @Published var currentDevice: AudioDeviceInfo?
    @Published var isChangingRate = false
    @Published var lastError: String?
    @Published var actualAcceptedRate: Double?
    @Published var rateDiscrepancy: Bool = false
    
    private var deviceChangeListener: AudioObjectPropertyListenerProc?
    private var rateChangeListener: AudioObjectPropertyListenerProc?
    private var listenerRefCon: UnsafeMutableRawPointer?
    private var rateListenerRefCon: UnsafeMutableRawPointer?
    
    init() {
        updateCurrentDevice()
        setupDeviceChangeListener()
        setupRateChangeListener()
    }
    
    deinit {
        removeDeviceChangeListener()
        removeRateChangeListener()
    }
    
    func getCurrentDefaultOutputDevice() -> AudioObjectID? {
        var deviceID = AudioObjectID()
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size,
            &deviceID
        )
        
        guard result == noErr else {
            logger.error("Failed to get default output device: \(result)")
            return nil
        }
        
        return deviceID
    }
    
    func getDeviceName(_ deviceID: AudioObjectID) -> String {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let result = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0, nil,
            &size,
            &name
        )
        
        if result == noErr {
            return name as String
        } else {
            return "Unknown Device"
        }
    }
    
    func getCurrentNominalRate(_ deviceID: AudioObjectID) -> Double? {
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let result = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0, nil,
            &size,
            &rate
        )
        
        guard result == noErr else {
            logger.error("Failed to get nominal sample rate: \(result)")
            return nil
        }
        
        return rate
    }
    
    func getSupportedNominalRates(_ deviceID: AudioObjectID) -> [Double] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0, nil,
            &size
        )
        
        guard result == noErr else {
            logger.error("Failed to get property size: \(result)")
            return []
        }
        
        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        guard count > 0 else { return [] }
        
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        
        result = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0, nil,
            &size,
            &ranges
        )
        
        guard result == noErr else {
            logger.error("Failed to get available sample rates: \(result)")
            return []
        }
        
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
    
    func setNominalRate(_ deviceID: AudioObjectID, rateHz: Double) async -> Bool {
        isChangingRate = true
        defer { 
            Task { @MainActor in
                self.isChangingRate = false
            }
        }
        
        let supportedRates = getSupportedNominalRates(deviceID)
        guard supportedRates.contains(rateHz) else {
            let errorMsg = "Rate \(rateHz) Hz not supported by device. Supported: \(supportedRates)"
            logger.warning("\(errorMsg)")
            await MainActor.run {
                self.lastError = errorMsg
            }
            return false
        }
        
        var rate = Float64(rateHz)
        let size = UInt32(MemoryLayout<Float64>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let result = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0, nil,
            size,
            &rate
        )
        
        if result == noErr {
            logger.info("Requested sample rate: \(rateHz) Hz")
            
            // Wait a moment for DAC to accept/quantize the rate
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            // Read back actual accepted rate
            if let actualRate = getCurrentNominalRate(deviceID) {
                await MainActor.run {
                    self.actualAcceptedRate = actualRate
                    self.rateDiscrepancy = abs(actualRate - rateHz) > 1
                    
                    if self.rateDiscrepancy {
                        logger.warning("DAC quantized rate: requested \(rateHz) Hz, accepted \(actualRate) Hz")
                    } else {
                        logger.info("DAC accepted rate: \(actualRate) Hz")
                    }
                    
                    self.updateCurrentDevice()
                    self.lastError = nil
                }
            }
            return true
        } else {
            let errorMsg = "Failed to set sample rate: OSStatus \(result)"
            logger.error("\(errorMsg)")
            await MainActor.run {
                self.lastError = errorMsg
            }
            return false
        }
    }
    
    func updateCurrentDevice() {
        guard let deviceID = getCurrentDefaultOutputDevice() else { return }
        
        let name = getDeviceName(deviceID)
        let rate = getCurrentNominalRate(deviceID) ?? 0
        let supportedRates = getSupportedNominalRates(deviceID)
        
        currentDevice = AudioDeviceInfo(
            id: deviceID,
            name: name,
            currentRate: rate,
            supportedRates: supportedRates
        )
    }
    
    private func setupDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let listener: AudioObjectPropertyListenerProc = { _, _, _, refCon in
            guard let refCon = refCon else { return noErr }
            let device = Unmanaged<CoreAudioDevice>.fromOpaque(refCon).takeUnretainedValue()
            
            DispatchQueue.main.async {
                device.updateCurrentDevice()
                logger.info("Default output device changed")
            }
            
            return noErr
        }
        
        listenerRefCon = Unmanaged.passUnretained(self).toOpaque()
        
        let result = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listener,
            listenerRefCon
        )
        
        if result != noErr {
            logger.error("Failed to add device change listener: \(result)")
        }
        
        deviceChangeListener = listener
    }
    
    private func setupRateChangeListener() {
        guard let deviceID = getCurrentDefaultOutputDevice() else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let listener: AudioObjectPropertyListenerProc = { _, _, _, refCon in
            guard let refCon = refCon else { return noErr }
            let device = Unmanaged<CoreAudioDevice>.fromOpaque(refCon).takeUnretainedValue()
            
            DispatchQueue.main.async {
                device.handleActualRateChange()
            }
            
            return noErr
        }
        
        rateListenerRefCon = Unmanaged.passUnretained(self).toOpaque()
        
        let result = AudioObjectAddPropertyListener(
            deviceID,
            &address,
            listener,
            rateListenerRefCon
        )
        
        if result != noErr {
            logger.error("Failed to add rate change listener: \(result)")
        } else {
            logger.info("Rate change listener installed")
        }
        
        rateChangeListener = listener
    }
    
    private func removeRateChangeListener() {
        guard let listener = rateChangeListener, 
              let refCon = rateListenerRefCon,
              let deviceID = getCurrentDefaultOutputDevice() else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListener(
            deviceID,
            &address,
            listener,
            refCon
        )
    }
    
    private func handleActualRateChange() {
        guard let deviceID = getCurrentDefaultOutputDevice() else { return }
        
        if let actualRate = getCurrentNominalRate(deviceID) {
            actualAcceptedRate = actualRate
            
            // Update device info with actual rate
            if var device = currentDevice {
                currentDevice = AudioDeviceInfo(
                    id: device.id,
                    name: device.name,
                    currentRate: actualRate,
                    supportedRates: device.supportedRates
                )
                logger.info("Rate change detected: \(actualRate) Hz")
            }
        }
    }
    
    private func removeDeviceChangeListener() {
        guard let listener = deviceChangeListener, let refCon = listenerRefCon else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listener,
            refCon
        )
    }
    
    func findClosestSupportedRate(targetHz: Double, forDevice deviceID: AudioObjectID) -> Double? {
        let supportedRates = getSupportedNominalRates(deviceID)
        guard !supportedRates.isEmpty else { return nil }
        
        if supportedRates.contains(targetHz) {
            return targetHz
        }
        
        let rateFamily44_1: [Double] = [44100, 88200, 176400]
        let rateFamily48: [Double] = [48000, 96000, 192000]
        
        let is44_1Family = rateFamily44_1.contains(targetHz)
        let targetFamily = is44_1Family ? rateFamily44_1 : rateFamily48
        
        for rate in targetFamily {
            if supportedRates.contains(rate) && rate >= targetHz {
                return rate
            }
        }
        
        return supportedRates.min(by: { abs($0 - targetHz) < abs($1 - targetHz) })
    }
}