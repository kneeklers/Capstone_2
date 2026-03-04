# Serial Number OCR System

**Mobile applications for scanning and extracting serial numbers from industrial nameplates**

This project provides two mobile app implementations for serial number recognition using OCR technology.

---

## Mobile Applications

### 1. iOS Native App (`ios_native_app/`)

A native iOS app built with **SwiftUI** using **Apple Vision framework** for on-device OCR.

**Features:**
- Native iOS performance with SwiftUI
- On-device OCR using `VNRecognizeTextRequest`
- Works offline (no internet required)
- Live camera preview with guide overlay
- Editable results before saving

**Requirements:**
- iOS 16.0+
- Xcode 15.0+
- Physical iPhone/iPad

**Quick Start:**
```bash
cd ios_native_app/SerialNumberScanner
open SerialNumberScanner.xcodeproj
```

See [`ios_native_app/README.md`](ios_native_app/README.md) for detailed setup instructions.

---

### 2. Expo Go App (`mobile_app_expo/`)

A cross-platform mobile app built with **React Native** and **Expo**. Uses a Python backend for YOLO (live bounding box) and EasyOCR (text extraction); same serial/part pattern matching as the iOS app.

**Features:**
- Cross-platform (iOS & Android)
- Live YOLO bounding box + static guide overlay
- Capture & extract serial/part numbers (EasyOCR + same regex as iOS)
- Run in Expo Go via QR code

**Requirements:**
- Node.js, Expo Go app on your device
- Backend running (`expo_backend/`) — see below
- Phone and computer on same Wi‑Fi

**Quick Start:**
1. **Terminal 1:** Start the backend and wait for "Models ready":
   ```bash
   cd expo_backend && source venv/bin/activate && pip install -r requirements.txt && python app.py
   ```
2. **Terminal 2:** Start Expo and open on device:
   ```bash
   cd mobile_app_expo && npm install && npx expo start
   ```
3. Set `BACKEND_URL` in `mobile_app_expo/App.tsx` to your computer's IP (e.g. `http://192.168.1.100:5000`).
4. Scan the QR code with Expo Go.

See **[mobile_app_expo/README.md](mobile_app_expo/README.md)** for full setup, BACKEND_URL, and troubleshooting.

---

## Project Structure

```
Capstone_2/
├── ios_native_app/              # Native iOS application (SwiftUI)
│   ├── README.md                # iOS app documentation
│   └── SerialNumberScanner/     # Xcode project
│
├── mobile_app_expo/             # Expo/React Native application
│   ├── README.md                # How to run with Expo Go (backend, BACKEND_URL, npx expo start)
│   ├── App.tsx                  # Main app (camera, bbox, capture, BACKEND_URL)
│   ├── utils/patternMatching.ts # Serial/part extraction (same as iOS)
│   └── package.json
├── expo_backend/                # Python backend (YOLO + EasyOCR) for Expo app
│   ├── README.md
│   ├── app.py
│   └── requirements.txt
│
├── best.pt                      # YOLO model weights (6MB)
├── best.mlpackage/              # CoreML model for iOS
│
├── images/                      # Sample/test images
│
├── Documentation/
│   ├── README.md                # This file
│   ├── CAPSTONE_FINAL_REPORT.md # Final project report
│   ├── CAPSTONE_PROGRESS_REPORT.md
│   ├── PRESENTATION_MATERIALS.md
│   ├── USAGE_GUIDE.md
│   ├── STREAMLIT_GUIDE.md
│   ├── SERIAL_PLATE_TRAINING_GUIDE.md
│   ├── BATCH_EXPORT_GUIDE.md
│   ├── LLM_TESTING_GUIDE.md
│   ├── MANUAL_CROP_GUIDE.md
│   ├── ROTATION_DETECTION.md
│   ├── PATENT_FIX.md
│   └── EXAMPLE_LLM_OUTPUT.md
│
└── requirements.txt             # Python dependencies (for model training)
```

---

## ML Models

| File | Description |
|------|-------------|
| `best.pt` | YOLO v8 model weights for serial plate detection |
| `best.mlpackage/` | CoreML model package for iOS integration |

These models are trained to detect serial number plates on industrial equipment.

---

## Documentation

| Document | Description |
|----------|-------------|
| [`CAPSTONE_FINAL_REPORT.md`](CAPSTONE_FINAL_REPORT.md) | Comprehensive final project report |
| [`CAPSTONE_PROGRESS_REPORT.md`](CAPSTONE_PROGRESS_REPORT.md) | Development progress documentation |
| [`USAGE_GUIDE.md`](USAGE_GUIDE.md) | How to use the OCR system |
| [`SERIAL_PLATE_TRAINING_GUIDE.md`](SERIAL_PLATE_TRAINING_GUIDE.md) | Guide for training YOLO models |
| [`ROTATION_DETECTION.md`](ROTATION_DETECTION.md) | Rotation detection implementation |

---

## Getting Started

### For iOS Development

1. Open the Xcode project:
   ```bash
   cd ios_native_app/SerialNumberScanner
   open SerialNumberScanner.xcodeproj
   ```

2. Configure signing in Xcode (Signing & Capabilities)

3. Connect your iPhone and run (⌘+R)

### For Expo Development

1. Install dependencies:
   ```bash
   cd mobile_app_expo
   npm install
   ```

2. Start the development server:
   ```bash
   npm start
   ```

3. Scan QR code with Expo Go app

---

## License

MIT License

---

**Capstone Project - Serial Number Recognition System**
