import SwiftUI
import ServiceManagement
import OSLog

struct RateView: View {
    @EnvironmentObject var statusBarController: StatusBarController
    @StateObject private var audioDevice = CoreAudioDevice()
    @StateObject private var preferences = Preferences.shared
    @StateObject private var rateManager = RateManager.shared
    @StateObject private var permissionManager = PermissionManager.shared
    @StateObject private var nowPlaying = MusicNowPlaying.shared
    
    @State private var showingDebugMenu = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            
            Divider()
            
            deviceInfoSection
            ratesSection
            currentlyPlayingSection
            
            Divider()
            
            settingsSection
            
            Divider()
            
            footerSection
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            Task {
                await permissionManager.checkAllPermissions()
            }
        }
    }
    
    private var headerSection: some View {
        HStack {
            Text("RateMate")
                .font(.headline)
            
            Spacer()
            
            if rateManager.isMonitoring {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "pause.circle")
                    .foregroundColor(.gray)
            }
        }
    }
    
    private var deviceInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(audioDevice.currentDevice?.name ?? "No Device")
                    .fontWeight(.medium)
            } icon: {
                Image(systemName: "hifispeaker")
            }
            
            HStack {
                Text("Current Rate:")
                    .foregroundColor(.secondary)
                Text(formatRateHz(audioDevice.currentDevice?.currentRate ?? 0))
                    .fontWeight(.semibold)
                
                if audioDevice.rateDiscrepancy {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .imageScale(.small)
                        .help("DAC quantized to nearest supported rate")
                }
                
                if audioDevice.isChangingRate {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .font(.system(.body, design: .monospaced))
            
            if let actualRate = audioDevice.actualAcceptedRate,
               audioDevice.rateDiscrepancy {
                Text("(DAC accepted: \(formatRateHz(actualRate)))")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
    
    private var ratesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Supported Rates")
                .font(.caption)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(audioDevice.currentDevice?.supportedRates ?? [], id: \.self) { rate in
                    RateButton(
                        rate: rate,
                        isActive: rate == audioDevice.currentDevice?.currentRate,
                        action: {
                            Task {
                                await rateManager.setManualRate(rate)
                            }
                        }
                    )
                }
            }
        }
    }
    
    private var currentlyPlayingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Currently Playing")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let track = nowPlaying.currentTrack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "music.note")
                            .foregroundColor(.blue)
                            .frame(width: 16)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            // Scrolling track name
                            MarqueeText(text: track.displayName)
                                .frame(height: 16)
                            
                            HStack(spacing: 6) {
                                Text(track.rateDisplay)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                                
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(track.source)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            } else if let event = rateManager.logReader.lastDetectedRate {
                // Fallback to old display if no track info
                HStack {
                    Image(systemName: "music.note")
                        .foregroundColor(.blue)
                    Text(formatRateHz(event.sampleRate))
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(event.source)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            } else {
                Text("No music detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Auto-switch on track change", isOn: $preferences.autoSwitchEnabled)
                .onChange(of: preferences.autoSwitchEnabled) { newValue in
                    Task {
                        if newValue {
                            rateManager.start()
                        } else {
                            rateManager.stop()
                        }
                    }
                }
            
            Toggle("Launch at login", isOn: $preferences.launchAtLogin)
                .onChange(of: preferences.launchAtLogin) { newValue in
                    Task {
                        toggleLaunchAtLogin(newValue)
                    }
                }
            
            HStack {
                Text("Debounce:")
                Slider(value: $preferences.debounceMs, in: 100...1000, step: 100)
                    .frame(width: 100)
                Text("\(Int(preferences.debounceMs))ms")
                    .font(.caption)
                    .frame(width: 50)
            }
            
            Divider()
                .padding(.vertical, 4)
            
            Toggle("Lock to fixed family rates", isOn: $preferences.preferFixedFamilyRates)
                .help("Always use 88.2 kHz for 44.1 family, 96 kHz for 48 family")
            
            if preferences.preferFixedFamilyRates {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.blue)
                            .imageScale(.small)
                        Text("44.1/88.2/176.4 → \(Int(preferences.fixed44_1FamilyRate/1000)) kHz")
                            .font(.caption)
                    }
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.green)
                            .imageScale(.small)
                        Text("48/96/192 → \(Int(preferences.fixed48FamilyRate/1000)) kHz")
                            .font(.caption)
                    }
                }
                .padding(.leading, 20)
                .foregroundColor(.secondary)
            } else {
                Toggle("Prefer higher family rates", isOn: $preferences.preferHigherFamily)
                    .help("When exact rate unavailable, use 88.2 for 44.1 content, 96 for 48")
            }
        }
    }
    
    private var footerSection: some View {
        HStack {
            Button("Debug") {
                showingDebugMenu.toggle()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.caption)
            
            Spacer()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
        .sheet(isPresented: $showingDebugMenu) {
            DebugView()
        }
    }
    
    private func formatRateHz(_ hz: Double) -> String {
        let kHz = hz / 1000.0
        if kHz == floor(kHz) {
            return "\(Int(kHz)) kHz"
        } else {
            return String(format: "%.1f kHz", kHz)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func toggleLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enable {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                print("Failed to toggle launch at login: \(error)")
            }
        }
    }
}

struct RateButton: View {
    let rate: Double
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(formatRate(rate))
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(isActive ? Color.accentColor : Color.gray.opacity(0.2))
                .foregroundColor(isActive ? .white : .primary)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    private func formatRate(_ hz: Double) -> String {
        let kHz = Int(hz / 1000)
        return "\(kHz)k"
    }
}

struct DebugView: View {
    @StateObject private var rateManager = RateManager.shared
    @StateObject private var permissionManager = PermissionManager.shared
    @Environment(\.dismiss) var dismiss
    
    let testRates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000]
    @State private var logMessages: [String] = []
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Debug Menu")
                .font(.headline)
            
            // Tab selector
            Picker("", selection: $selectedTab) {
                Text("Rates").tag(0)
                Text("Status").tag(1)
                Text("Test").tag(2)
            }
            .pickerStyle(.segmented)
            
            Divider()
            
            // Tab content
            if selectedTab == 0 {
                // Rates tab
                VStack(alignment: .leading, spacing: 10) {
                    // Direct rate forcing
                    Text("Force Rate (Bypass Checks)")
                        .font(.subheadline)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(testRates, id: \.self) { rate in
                            Button("\(Int(rate/1000))k") {
                                Task {
                                    guard let device = rateManager.audioDevice.currentDevice else { return }
                                    logMessages.append("Force setting \(Int(rate/1000))kHz...")
                                    let success = await rateManager.audioDevice.setNominalRate(device.id, rateHz: rate)
                                    logMessages.append(success ? "✅ Success" : "❌ Failed")
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    Divider()
                    
                    // Simulate detection
                    Text("Simulate Detection (Uses Auto-Switch)")
                        .font(.subheadline)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(testRates, id: \.self) { rate in
                            Button("\(Int(rate/1000))k") {
                                Task {
                                    logMessages.append("Simulating \(Int(rate/1000))kHz detection...")
                                    await rateManager.handleDetectedRate(rate)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!Preferences.shared.autoSwitchEnabled)
                        }
                    }
                    if !Preferences.shared.autoSwitchEnabled {
                        Text("Enable Auto-Switch to use")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            } else if selectedTab == 1 {
                // System Status tab
                VStack(alignment: .leading, spacing: 10) {
                    // Permissions
                    Text("Permissions")
                        .font(.subheadline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: permissionManager.hasMusicControl ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(permissionManager.hasMusicControl ? .green : .red)
                                .imageScale(.small)
                            Text("Music Control (track names)")
                                .font(.caption)
                            Spacer()
                            if !permissionManager.hasMusicControl {
                                Button("Request") {
                                    Task {
                                        _ = await AppleMusicHelper.shared.getCurrentTrack()
                                        await permissionManager.checkMusicControlAsync()
                                    }
                                }
                                .font(.caption2)
                                .buttonStyle(.plain)
                                .foregroundColor(.blue)
                            }
                        }
                        
                        HStack {
                            Image(systemName: permissionManager.hasFullDiskAccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(permissionManager.hasFullDiskAccess ? .green : .red)
                                .imageScale(.small)
                            Text("Full Disk Access (rate detection)")
                                .font(.caption)
                            Spacer()
                            if !permissionManager.hasFullDiskAccess {
                                Button("Settings") {
                                    permissionManager.openSystemSettings()
                                }
                                .font(.caption2)
                                .buttonStyle(.plain)
                                .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                    
                    Button("Recheck Permissions") {
                        Task {
                            await permissionManager.checkAllPermissions()
                            if permissionManager.hasFullDiskAccess {
                                rateManager.logReader.checkAccess()
                                if rateManager.isMonitoring {
                                    rateManager.stop()
                                    rateManager.start()
                                }
                            }
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    
                    Divider()
                    
                    // Detection Status
                    Text("Detection Status")
                        .font(.subheadline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(rateManager.logReader.statusMessage)
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                            if rateManager.logReader.isMonitoring {
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                        }
                        
                        if let lastCheck = rateManager.logReader.lastCheckTime {
                            Text("Last check: \(formatTime(lastCheck))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Attempts: \(rateManager.logReader.detectionAttempts)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // System info
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Monitoring: \(rateManager.isMonitoring ? "Active" : "Inactive")")
                        Text("Auto-Switch: \(Preferences.shared.autoSwitchEnabled ? "On" : "Off")")
                        Text("Device: \(rateManager.audioDevice.currentDevice?.name ?? "None")")
                        Text("Current Rate: \(Int((rateManager.audioDevice.currentDevice?.currentRate ?? 0)/1000))kHz")
                    }
                    .font(.caption)
                }
            } else {
                // Test tab
                VStack(alignment: .leading, spacing: 10) {
                    Text("Diagnostics")
                        .font(.subheadline)
                    
                    HStack(spacing: 8) {
                        Button("Test FDA") {
                            logMessages.append("Testing Full Disk Access...")
                            do {
                                _ = try OSLogStore(scope: .system)
                                logMessages.append("✅ FDA granted")
                            } catch {
                                logMessages.append("❌ FDA denied: \(error)")
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Test Music") {
                            Task {
                                logMessages.append("Testing Music control...")
                                let track = await AppleMusicHelper.shared.getCurrentTrack()
                                if let title = track.title {
                                    logMessages.append("✅ Got track: \(title)")
                                } else {
                                    logMessages.append("❌ No track info")
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Clear") {
                            logMessages.removeAll()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            // Log messages
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(logMessages.enumerated()), id: \.offset) { _, msg in
                        Text(msg)
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                }
            }
            .frame(maxHeight: 100)
            .padding(4)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(4)
            
            Spacer()
            
            Button("Close") {
                dismiss()
            }
        }
        .padding()
        .frame(width: 350, height: 500)
    }
}