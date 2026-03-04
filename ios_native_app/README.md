# Serial Number Scanner - Native iOS App

A native iOS app built with SwiftUI that uses **Apple's Vision framework** for on-device OCR to scan and extract serial numbers from equipment plates.

## Features

- 📱 **Native iOS app** - Built with SwiftUI for optimal performance
- 🔍 **Apple Vision OCR** - Uses `VNRecognizeTextRequest` for accurate text recognition
- 🌐 **Offline capable** - On-device OCR works without internet
- 📷 **Live camera preview** - Real-time camera view with guideline overlay
- ✏️ **Editable results** - Review and edit extracted text before saving
- 🔄 **Dual OCR modes** - Switch between on-device and backend API

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Physical iPhone/iPad (camera required)

## Getting Started

### Option 1: Open in Xcode

1. Navigate to the project folder:
   ```bash
   cd ios_native_app/SerialNumberScanner
   ```

2. Open the Xcode project:
   ```bash
   open SerialNumberScanner.xcodeproj
   ```

3. Select your development team in **Signing & Capabilities**

4. Connect your iPhone and select it as the run destination

5. Press **⌘+R** to build and run

### Option 2: Create Project via Xcode (Alternative)

If you prefer to create a fresh project in Xcode:

1. Open Xcode → **File** → **New** → **Project**
2. Select **iOS** → **App**
3. Configure:
   - Product Name: `SerialNumberScanner`
   - Interface: **SwiftUI**
   - Language: **Swift**
4. Copy the Swift files from `SerialNumberScanner/` into your project
5. Add camera permission to `Info.plist`

## Project Structure

```
ios_native_app/
└── SerialNumberScanner/
    ├── SerialNumberScanner.xcodeproj/
    │   └── project.pbxproj
    └── SerialNumberScanner/
        ├── SerialNumberScannerApp.swift    # App entry point
        ├── ContentView.swift               # Main UI container
        ├── CameraView.swift                # AVFoundation camera
        ├── ScannerViewModel.swift          # Business logic & OCR
        ├── GuidelineOverlay.swift          # Green guide box UI
        ├── ResultsView.swift               # Results display/edit
        ├── SettingsView.swift              # Settings screen
        ├── Info.plist                      # App configuration
        └── Assets.xcassets/                # App icons & colors
```

## How It Works

### Apple Vision OCR

The app uses Apple's Vision framework (`VNRecognizeTextRequest`) for text recognition:

```swift
let request = VNRecognizeTextRequest { request, error in
    guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
    
    for observation in observations {
        let text = observation.topCandidates(1).first?.string
        // Process recognized text...
    }
}

request.recognitionLevel = .accurate    // Use accurate mode
request.usesLanguageCorrection = false  // Disabled for serial numbers
```

### Serial Number Pattern Matching

The app looks for common patterns:
- `S/N:` or `SN:` followed by alphanumeric text
- `SERIAL:` followed by alphanumeric text
- `P/N:` or `PN:` for part numbers
- Alphanumeric strings 6-25 characters with mixed letters/numbers

## Settings

### OCR Mode Toggle

- **On-Device OCR** (Default)
  - Uses Apple Vision framework
  - Works offline
  - Fast processing
  - Privacy-focused (no data leaves device)

- **Backend API**
  - Uses your Python YOLO server
  - Requires network connection
  - Uses your trained model for detection

### Backend Configuration

If using the backend API:

1. Start your Python server:
   ```bash
   python api_server.py
   ```

2. Find your Mac's IP address:
   - System Settings → Network → Wi-Fi → Details → IP Address

3. Enter the URL in Settings (e.g., `http://192.168.1.100:8000`)

## Camera Permissions

The app requires camera access. This is configured in `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to scan serial numbers.</string>
```

## Tips for Best Results

1. **Good Lighting** - Ensure even lighting without harsh shadows
2. **Fill the Frame** - Position the serial plate to fill ~70% of the guide box
3. **Keep Steady** - Hold the phone steady while capturing
4. **Avoid Glare** - Tilt to reduce reflections on metal plates
5. **Straight Angle** - Capture straight-on, not at an angle

## Customization

### Adjusting Pattern Matching

Edit `ScannerViewModel.swift` to customize serial number patterns:

```swift
let serialPatterns = [
    "S/?N[:\\s]*([A-Z0-9\\-]+)",   // S/N: or SN:
    "SERIAL[:\\s]*([A-Z0-9\\-]+)", // SERIAL:
    // Add your custom patterns here
]
```

### Changing the Guide Box Size

Edit `GuidelineOverlay.swift`:

```swift
private let widthRatio: CGFloat = 0.7   // 70% of screen width
private let heightRatio: CGFloat = 0.6  // 60% of screen height
```

### Changing the Accent Color

Edit `Assets.xcassets/AccentColor.colorset/Contents.json` to change the app's green accent color.

## Comparison: On-Device vs Backend OCR

| Feature | On-Device (Vision) | Backend (YOLO) |
|---------|-------------------|----------------|
| Speed | Fast | Medium |
| Offline | ✅ Yes | ❌ No |
| Privacy | ✅ On-device | ⚠️ Sends images |
| Accuracy | Good for clear text | Better for worn plates |
| Detection | Text only | Finds serial plate first |

## Troubleshooting

### Camera Not Working
- Ensure you're running on a physical device (not simulator)
- Check camera permission in iOS Settings

### OCR Not Finding Text
- Improve lighting conditions
- Make sure text is in focus
- Try moving closer or further from the plate
- Use the backend API for difficult images

### Build Errors
- Check that deployment target is iOS 16.0+
- Verify all Swift files are added to the target
- Clean build folder: **Product** → **Clean Build Folder**

## License

This project is part of the Capstone project for serial number recognition.
