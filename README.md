# RateMate 🎵

Automatically adjust your Mac's audio output sample rate to match currently playing Apple Music tracks for the highest fidelity playback.

## Features

- 🎵 **Automatic Sample Rate Switching** - Detects Apple Music playback and adjusts your DAC/audio interface to match
- 📊 **Supports All Common Rates** - 44.1, 48, 88.2, 96, 176.4, and 192 kHz
- 🎯 **Smart DAC Handling** - Works with DACs that quantize to nearest supported rate
- ⚡ **Debounced Switching** - Prevents rapid changes when skipping tracks (configurable 100-1000ms)
- 🎼 **Track Display** - Shows currently playing track with scrolling for long names
- 🔢 **Rate Family Coalescing** - Option to use fixed rates per family (e.g., always 88.2kHz for 44.1 family)
- 🚀 **Launch at Login** - Built-in support via SMAppService (macOS 13+)
- 🐛 **Advanced Debug Menu** - Test rates, check permissions, view detection status

## Requirements

- macOS 14.0 or later
- Apple Music app (or Music app)
- **Full Disk Access** permission (for rate detection from logs)
- **Music Control** permission (for track names)

## Installation

### Easy Install (No Terminal Required!)

1. **Build and Install to Applications:**
   ```bash
   ./build_and_install.sh
   ```
   
2. **Find RateMate in your Applications folder**

3. **Double-click to run** (or drag to Dock for easy access)

4. **Grant permissions when prompted:**
   - **Full Disk Access**: For rate detection (System Settings > Privacy & Security)
   - **Music Control**: For track names (automatic prompt)

That's it! RateMate now works like any regular Mac app.

### Manual Build with Xcode

1. Open `RateMate.xcodeproj` in Xcode
2. Press ⌘B to build
3. Find the app in DerivedData and copy to Applications

### Build from Source

```bash
# Clone the repository
git clone https://github.com/mattshapsss/RateMate.git
cd RateMate

# One-command install
./build_and_install.sh
```

## Usage

### Menu Bar Interface

- **🎧 44.1 kHz** - Shows current sample rate
- **🎧 44.1 → 96** - Transitioning between rates (with animation)
- Click icon to open control panel

### Main Controls

Click the menu bar icon to access:
- **Device Info**: Current audio device and rate
- **Rate Buttons**: Click any rate to manually switch
- **Currently Playing**: Shows track name, artist, and detected rate
- **Auto-switch Toggle**: Enable/disable automatic switching
- **Launch at Login**: Start with macOS
- **Debounce Slider**: Adjust switching delay (100-1000ms)
- **Family Rate Options**: Lock to consistent rates within families

### Settings Explained

- **Auto-switch**: Automatically changes rate when track changes
- **Debounce**: Prevents rapid switching when skipping (100-1000ms delay)
- **Lock to fixed family rates**: 
  - 44.1/88.2/176.4 → Always use your preferred rate (e.g., 88.2)
  - 48/96/192 → Always use your preferred rate (e.g., 96)
  - Reduces DAC switching for mixed-rate playlists
- **Launch at login**: Starts RateMate automatically

### Debug Menu

Advanced features in three tabs:
- **Rates**: Force rates, simulate detection
- **Status**: View permissions, detection status
- **Test**: Run diagnostic tests

## What is Debounce?

Debounce prevents your DAC from rapidly switching when you skip through songs:
- Without: Track changes → Instant switch → Click/pop sounds
- With 300ms debounce: Track changes → Wait 300ms → Switch once
- Adjustable from 100ms (responsive) to 1000ms (stable)

## How It Works

1. **Log Monitoring**: Reads Apple Music playback logs via OSLogStore
2. **Rate Detection**: Parses log entries for sample rate information
3. **CoreAudio Control**: Uses `kAudioDevicePropertyNominalSampleRate` to set device rate
4. **Smart Matching**: Finds closest supported rate if exact match unavailable

### Detection Patterns

RateMate detects rates from Music app logs containing:
- "44.1 kHz", "48 kHz", "96 kHz" etc.
- "Hi-Res Lossless 192 kHz"
- "ALAC 24-bit/96 kHz"
- "sample rate: 48000"

## Development

### Project Structure

```
RateMate/
├── RateMateApp.swift           # App entry point
├── Views/
│   ├── StatusBarController.swift
│   └── RateView.swift
├── Services/
│   ├── CoreAudioDevice.swift   # Audio device control
│   ├── OSLogMusicReader.swift  # Log parsing
│   └── MediaRemoteWatcher.swift # Optional fallback
├── Controllers/
│   ├── RateManager.swift       # Rate switching logic
│   └── PermissionManager.swift # FDA handling
└── Models/
    └── Preferences.swift        # User settings
```

### Building with Xcode

1. Open `RateMate.xcodeproj`
2. Select "RateMate" scheme
3. Product → Build (⌘B)
4. Product → Run (⌘R)

### Running Tests

```bash
# Unit tests
xcodebuild test -project RateMate.xcodeproj -scheme RateMate

# Acceptance tests (requires app running)
swift test --filter AcceptanceTests
```

### Debug Mode

Access debug menu from the popover to:
- Simulate rate detections (44.1k, 48k, 88.2k, 96k, 176.4k, 192k)
- View monitoring status
- Check error states
- Test without Apple Music

## Troubleshooting

### "No music detected"
1. Ensure Apple Music is playing (not paused)
2. Grant Full Disk Access (System Settings > Privacy & Security)
3. Check Debug > Status tab for permission status
4. Restart RateMate after granting permissions

### Rate not switching
1. Enable "Auto-switch on track change" toggle
2. Check if your DAC supports the target rate
3. Try manually clicking a rate button to test
4. Check Debug > Status for detection messages

### Track names not showing
1. Grant Music control when prompted on first launch
2. If missed: Debug > Status > Request Music Control
3. Restart Music app if needed

### Two menu bar icons appear
- Quit both instances and restart RateMate
- Only one instance should run at a time

### DAC makes clicking sounds
- Increase debounce delay to 500-1000ms
- Enable "Lock to fixed family rates" to reduce switching

## Security & Privacy

- **No Network Access**: RateMate works entirely offline
- **No Data Collection**: No telemetry or analytics
- **Log Reading Only**: Only reads Music app logs, no system modifications
- **Unsandboxed**: Required for OSLogStore access (documented requirement)

## Acceptance Tests

The app includes automated acceptance tests:

1. **44.1 kHz Detection**: Switches to 44.1 within 1 second
2. **96 kHz Hi-Res**: Handles Hi-Res Lossless content
3. **48 kHz Family**: Applies family preference policy
4. **Auto-Switch Toggle**: Respects on/off setting
5. **Full Integration**: Complete workflow test
6. **Debounce Performance**: Efficient rate coalescing

Run tests with: `swift test --filter AcceptanceTests`

## Performance Impact

RateMate is extremely lightweight:
- **CPU Usage**: < 1% typical, 2-3% peak when switching
- **Memory**: ~20-30MB footprint
- **Polling**: Track check every 2s, rate sync every 3s
- **Log Scanning**: Every 500ms when music playing

## Supported DACs

Tested with:
- Noble FoKus Rex5 (16/44.1kHz quantization)
- Most USB DACs with multiple rate support
- Built-in Mac audio
- Thunderbolt audio interfaces

## Technical Details

- **Architecture**: Unsandboxed (required for OSLog access)
- **Rate Detection**: OSLogStore parsing of Music app logs
- **Audio Control**: CoreAudio `kAudioDevicePropertyNominalSampleRate`
- **Track Info**: AppleScript for Music app integration
- **UI**: SwiftUI with AppKit menu bar integration
- **Bit Depth**: Not modified (macOS/DAC negotiate optimal bit depth automatically)

## Known Limitations

- Requires Full Disk Access (Apple's OSLog security model)
- Cannot be sandboxed (OSLogStore requirement)
- Apple Music only (Spotify/Tidal not supported yet)
- Some DACs may have audible switching delays

## FAQ

**Q: Does RateMate affect bit depth?**  
A: No, only sample rate. Your DAC automatically uses its highest bit depth (usually 24-bit).

**Q: Why does my DAC show a different rate?**  
A: Some DACs quantize to nearest supported rate. RateMate detects this and shows both requested and actual rates.

**Q: Can I use this with AirPods?**  
A: AirPods have fixed sample rates. RateMate works best with external DACs.

**Q: How do I share with friends?**  
A: Run `./build_and_install.sh`, then zip `/Applications/RateMate.app` and share. They'll need to right-click > Open on first launch.

## Contributing

Pull requests welcome! Please test with your DAC and report compatibility.

## License

MIT License - See LICENSE file for details

## Acknowledgments

Built with Swift, SwiftUI, CoreAudio, and OSLog frameworks.

---

**Version**: 1.0  
**Requires**: macOS 14.0+  
**Author**: Matt Shapiro