# Serial Number Scanner – Expo Go App

Cross-platform app (iOS & Android) that uses the camera to scan serial plates, shows a live YOLO bounding box, and extracts serial/part numbers with the same pattern matching as the iOS app. OCR runs on a Python backend (EasyOCR); the app sends images and displays results.

---

## Prerequisites

- **Node.js** (v18+ recommended)
- **Expo Go** installed on your phone ([iOS](https://apps.apple.com/app/expo-go/id982107779) / [Android](https://play.google.com/store/apps/details?id=host.exp.exponent))
- **Same Wi‑Fi** for phone and computer (so the app can reach the backend)
- **Backend** running (see [expo_backend](../expo_backend/README.md)) — YOLO + EasyOCR

---

## 1. Start the backend (Terminal 1)

In a **separate terminal**, set up and run the backend: install dependencies from `requirements.txt`, then run `app.py`. The app needs this for live detection and OCR.

```bash
cd expo_backend
python3 -m venv venv
source venv/bin/activate          # Windows: venv\Scripts\activate
pip install -r requirements.txt  # install dependencies from requirements.txt
python app.py                     # run the backend server
```

Wait until you see **"Models ready. You can take a photo now."** in that terminal. Leave it running.

---

## 2. Set the backend URL in the app

The app must call your computer’s IP (not `localhost`), so the phone can reach it.

1. Find your computer’s local IP:
   - **Mac:** System Settings → Network, or run `ipconfig getifaddr en0` in Terminal
   - **Windows:** `ipconfig` → look for IPv4 (e.g. `192.168.1.100`)

2. In **`mobile_app_expo/App.tsx`**, set `BACKEND_URL` near the top (around line 16):

   ```ts
   const BACKEND_URL = 'http://YOUR_IP:5000';   // e.g. http://192.168.1.100:5000
   ```

   Replace `YOUR_IP` with your actual IP. Port `5000` must match the backend.

---

## 3. Install dependencies and start Expo (Terminal 2)

In **another terminal** (keep the backend running in the first):

```bash
cd mobile_app_expo
npm install
npx expo start
```

A QR code and menu will appear in this terminal.

---

## 4. Open the app in Expo Go

- **iPhone:** Open the **Camera** app, point at the QR code, tap the banner to open in Expo Go.
- **Android:** Open the **Expo Go** app and tap **Scan QR code**, then scan the code from the terminal.

Grant camera permission when prompted. You should see the camera with a green guide box; when the backend detects a plate, a live bounding box appears. Tap **Capture & extract** to run OCR and see serial/part numbers (same pattern matching as the iOS app).

---

## Quick reference: two terminals

Use **one terminal** for the backend (install from `requirements.txt`, run `app.py`) and **another terminal** for Expo:

| Terminal 1 (backend)           | Terminal 2 (Expo)        |
|-------------------------------|--------------------------|
| `cd expo_backend`             | `cd mobile_app_expo`     |
| `source venv/bin/activate`   | `npm install`            |
| `pip install -r requirements.txt` | `npx expo start`     |
| `python app.py`               | Scan QR code with Expo Go |
| Wait for "Models ready", leave running | |

---

## Option: run everything in one terminal

You can start the backend in the **background** in the same terminal, then start Expo. The backend still has to be running; it just doesn’t need its own window.

From the **project root** (e.g. `Capstone_2/`):

```bash
cd expo_backend && source venv/bin/activate && python app.py &
cd ../mobile_app_expo && npm install && npx expo start
```

- The `&` runs `python app.py` in the background.
- Wait a minute for "Models ready" (check the same terminal or the backend log), then scan the QR code with Expo Go.
- To stop the backend later: `pkill -f "python app.py"` or close the terminal.

---

## Troubleshooting

| Issue | What to do |
|-------|------------|
| **"Request timed out" / no results** | Backend not ready or wrong IP. Wait for "Models ready", then set `BACKEND_URL` in `App.tsx` to your computer’s IP (same Wi‑Fi as phone). |
| **No live bounding box** | Backend may still be loading, or no plate in view. You’ll always see the static green guide box; the bright green live box appears when YOLO detects a plate. |
| **Can’t connect to backend** | Phone and computer must be on the same Wi‑Fi. Disable VPN on either. Ensure nothing is blocking port 5000. |
| **Expo Go won’t open project** | Ensure `npm install` and `npx expo start` were run from `mobile_app_expo`. Try `npx expo start --clear`. |

---

## Project layout

- **`App.tsx`** – Camera, live bbox overlay, capture, results modal, `BACKEND_URL`.
- **`utils/patternMatching.ts`** – Serial/part extraction (same logic as iOS `ScannerViewModel`).
- **`expo_backend/`** (sibling folder) – Python server: `/detect` (YOLO), `/ocr` (EasyOCR).
