# Expo Serial Scanner Backend

Runs YOLO (plate detection) and EasyOCR for the Expo app. The app sends camera frames for live bounding box and captured images for text extraction.

**Full run instructions (backend + Expo Go):** see [mobile_app_expo/README.md](../mobile_app_expo/README.md).

## Setup

1. From repo root, create a venv and install deps:

```bash
cd expo_backend
python3 -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

2. Ensure the YOLO model exists at repo root: `../best.pt` (same `best.pt` used for the iOS app).

## Run

```bash
python app.py
```

Server runs at `http://0.0.0.0:5000`. On your phone (Expo Go), set `BACKEND_URL` in `mobile_app_expo/App.tsx` to your computer’s LAN IP, e.g. `http://192.168.1.100:5000`, Then run the Expo app: see [mobile_app_expo/README.md](../mobile_app_expo/README.md).

## Endpoints

- **GET /health** – Check server is up.
- **POST /detect** – Body: `multipart/form-data` with `image` file. Returns `{ bbox: [cx, cy, w, h], detected }` (normalized 0–1).
- **POST /ocr** – Body: `multipart/form-data` with `image` file. Returns `{ lines: string[] }` from EasyOCR for pattern matching in the app.
