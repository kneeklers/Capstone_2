"""
Backend for Expo Serial Number Scanner.
- POST /detect: image -> YOLO bbox (normalized 0-1) for live overlay.
- POST /ocr: image -> preprocess for OCR -> EasyOCR -> text lines for pattern matching.
- Models load in background at startup so first capture is fast (like last time).
"""
import io
import os
import threading
from pathlib import Path

from flask import Flask, request, jsonify
from flask_cors import CORS
from PIL import Image, ImageOps
import numpy as np
import cv2

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
    img = Image.open(io.BytesIO(raw))
    try:
        img = ImageOps.exif_transpose(img)
    except Exception:
        pass
    img = img.convert("RGB")
    return np.array(img)


def preprocess_for_ocr(img: np.ndarray) -> np.ndarray:
    """
    Light preprocessing only (resize + contrast). Skip heavy sharpen/denoise so text is not lost.
    """
    if img is None or img.size == 0:
        return img
    h, w = img.shape[:2]
    max_side = 2000
    if max(h, w) > max_side:
        scale = max_side / max(h, w)
        new_w, new_h = int(w * scale), int(h * scale)
        img = cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_AREA)
    if len(img.shape) == 3:
        gray = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
    else:
        gray = img.copy()
    try:
        clahe = cv2.createCLAHE(clipLimit=1.5, tileGridSize=(8, 8))
        gray = clahe.apply(gray)
    except Exception:
        gray = cv2.normalize(gray, None, 0, 255, cv2.NORM_MINMAX)
    return cv2.cvtColor(gray, cv2.COLOR_GRAY2RGB)


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
        cx, cy, nw, nh = best["bbox"]
        # Fix skinny/flat boxes: enforce minimum aspect so the overlay is usable (serial plates are ~wide rectangles)
        min_ratio = 0.45
        if nw > 0 and nh > 0:
            if nw / nh < min_ratio:
                nw = min(0.92, nh * 0.85)
            if nh / nw < min_ratio:
                nh = min(0.92, nw * 0.85)
            # Clamp center so box stays in [0, 1]
            cx = max(nw / 2, min(1 - nw / 2, cx))
            cy = max(nh / 2, min(1 - nh / 2, cy))
        bbox = [float(cx), float(cy), float(nw), float(nh)]
        return jsonify({
            "bbox": bbox,
            "confidence": best["confidence"],
            "detected": True,
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/ocr", methods=["POST"])
def ocr():
    """Run EasyOCR on image (with light preprocessing). Return text lines for pattern matching."""
    img = image_from_request()
    if img is None:
        return jsonify({"error": "No image"}), 400
    try:
        reader = get_ocr()
        # Run on original first to get maximum text (avoid losing text to heavy preprocessing)
        results = reader.readtext(img)
        lines_orig = [item[1].strip() for item in results if item[1].strip()]
        if len(lines_orig) >= 3:
            lines = lines_orig
        else:
            # If very few lines, try with light preprocessing
            img_prep = preprocess_for_ocr(img)
            results_prep = reader.readtext(img_prep)
            lines_prep = [item[1].strip() for item in results_prep if item[1].strip()]
            lines = list(dict.fromkeys(lines_orig + lines_prep))
        return jsonify({"lines": lines, "linesCount": len(lines)})
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
