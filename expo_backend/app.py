"""
Backend for Expo Serial Number Scanner.
- POST /detect: image -> YOLO bbox (normalized 0-1) for live overlay.
- POST /ocr: image -> EasyOCR text lines for pattern matching in app.
- Models load in background at startup so first capture is fast (like last time).
"""
import io
import os
import threading
from pathlib import Path

from flask import Flask, request, jsonify
from flask_cors import CORS
from PIL import Image
import numpy as np

app = Flask(__name__)
CORS(app)

# Path to YOLO model (repo root)
ROOT = Path(__file__).resolve().parent.parent
YOLO_PT = ROOT / "best.pt"

# Lazy-load YOLO and EasyOCR
_yolo_model = None
_ocr_reader = None


def get_yolo():
    global _yolo_model
    if _yolo_model is None:
        from ultralytics import YOLO
        if not YOLO_PT.exists():
            raise FileNotFoundError(f"YOLO model not found: {YOLO_PT}")
        _yolo_model = YOLO(str(YOLO_PT))
    return _yolo_model


def get_ocr():
    global _ocr_reader
    if _ocr_reader is None:
        import easyocr
        _ocr_reader = easyocr.Reader(["en"], gpu=False)
    return _ocr_reader


def image_from_request():
    if "image" not in request.files and not request.data:
        return None
    if request.files.get("image"):
        raw = request.files["image"].read()
    else:
        raw = request.data
    img = Image.open(io.BytesIO(raw)).convert("RGB")
    return np.array(img)


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"})


@app.route("/warmup", methods=["GET", "POST"])
def warmup():
    """Load YOLO and EasyOCR so first /detect and /ocr are fast."""
    try:
        get_yolo()
        get_ocr()
        return jsonify({"status": "ok", "message": "Models loaded"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route("/detect", methods=["POST"])
def detect():
    """Run YOLO on image, return best bbox as normalized [x_center, y_center, width, height] 0-1."""
    img = image_from_request()
    if img is None:
        return jsonify({"error": "No image"}), 400
    try:
        model = get_yolo()
        results = model(img, verbose=False)
        boxes = []
        for r in results:
            if r.boxes is not None and len(r.boxes) > 0:
                # xyxy in pixels
                xyxy = r.boxes.xyxy.cpu().numpy()
                conf = r.boxes.conf.cpu().numpy()
                # Take best by confidence
                idx = conf.argmax()
                x1, y1, x2, y2 = xyxy[idx]
                h, w = img.shape[:2]
                # Normalize to 0-1: center x, center y, width, height (YOLO style for overlay)
                cx = ((x1 + x2) / 2) / w
                cy = ((y1 + y2) / 2) / h
                nw = (x2 - x1) / w
                nh = (y2 - y1) / h
                boxes.append({
                    "bbox": [float(cx), float(cy), float(nw), float(nh)],
                    "confidence": float(conf[idx]),
                })
        # Return single best bbox for overlay (first/best)
        if not boxes:
            return jsonify({"bbox": None, "detected": False})
        best = max(boxes, key=lambda b: b["confidence"])
        return jsonify({
            "bbox": best["bbox"],
            "confidence": best["confidence"],
            "detected": True,
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/ocr", methods=["POST"])
def ocr():
    """Run EasyOCR, return text lines for pattern matching in app."""
    img = image_from_request()
    if img is None:
        return jsonify({"error": "No image"}), 400
    try:
        reader = get_ocr()
        results = reader.readtext(img)
        lines = [item[1].strip() for item in results if item[1].strip()]
        return jsonify({"lines": lines})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


def _load_models_in_background():
    """Load YOLO and EasyOCR at startup so first /detect and /ocr are fast."""
    print("Loading YOLO and EasyOCR in background... (wait for 'Models ready' before first capture)")
    try:
        get_yolo()
        get_ocr()
        print("Models ready. You can take a photo now.")
    except Exception as e:
        print("Model load failed:", e)


if __name__ == "__main__":
    t = threading.Thread(target=_load_models_in_background, daemon=True)
    t.start()
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
