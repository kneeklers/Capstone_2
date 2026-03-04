import { useState, useEffect, useRef } from 'react';
import {
  StyleSheet,
  Text,
  View,
  TouchableOpacity,
  Dimensions,
  ActivityIndicator,
  Modal,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { CameraView, useCameraPermissions } from 'expo-camera';
import axios from 'axios';
import { extractSerialAndPartNumber } from './utils/patternMatching';

// Set your machine's IP when testing on device (same WiFi). Example: http://192.168.1.100:5000
const BACKEND_URL = 'http://172.20.10.2:5000';
const LIVE_DETECT_INTERVAL_MS = 1200;

type BBox = [number, number, number, number]; // cx, cy, w, h normalized 0-1

export default function App() {
  const [permission, requestPermission] = useCameraPermissions();
  const [bbox, setBbox] = useState<BBox | null>(null);
  const [processing, setProcessing] = useState(false);
  const [result, setResult] = useState<{ serialNumber: string | null; partNumber: string | null } | null>(null);
  const [ocrLinesCount, setOcrLinesCount] = useState<number | null>(null);
  const [showResult, setShowResult] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [cameraReady, setCameraReady] = useState(false);
  const cameraRef = useRef<CameraView>(null);
  const liveIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Start live detection once camera is ready (or after 2s fallback)
  useEffect(() => {
    if (!permission?.granted) return;
    const t = setTimeout(() => setCameraReady(true), 2000);
    return () => clearTimeout(t);
  }, [permission?.granted]);

  // Warm up backend (load EasyOCR) when camera screen is ready so first capture is faster
  useEffect(() => {
    if (!permission?.granted) return;
    axios.get(`${BACKEND_URL}/warmup`, { timeout: 90000 }).catch(() => {});
  }, [permission?.granted]);

  // Live YOLO detection: periodically take a frame and get bbox
  useEffect(() => {
    if (!permission?.granted || !cameraReady || processing) return;

    const runDetect = async () => {
      try {
        const photo = await cameraRef.current?.takePictureAsync({
          quality: 0.4,
          base64: false,
        });
        if (!photo?.uri) return;

        const formData = new FormData();
        formData.append('image', {
          uri: photo.uri,
          name: 'frame.jpg',
          type: 'image/jpeg',
        } as any);

        const { data } = await axios.post<{ bbox: BBox | null; detected: boolean }>(
          `${BACKEND_URL}/detect`,
          formData,
          { headers: { 'Content-Type': 'multipart/form-data' }, timeout: 5000 }
        );
        if (data.detected && data.bbox) setBbox(data.bbox);
        else setBbox(null);
      } catch {
        setBbox(null);
      }
    };

    liveIntervalRef.current = setInterval(runDetect, LIVE_DETECT_INTERVAL_MS);
    runDetect();
    return () => {
      if (liveIntervalRef.current) clearInterval(liveIntervalRef.current);
    };
  }, [permission?.granted, cameraReady, processing]);

  const handleCapture = async () => {
    if (!cameraRef.current || processing) return;
    setProcessing(true);
    setError(null);
    try {
      const photo = await cameraRef.current.takePictureAsync({
        quality: 0.85,
        base64: false,
      });
      if (!photo?.uri) {
        setError('Failed to take photo');
        setProcessing(false);
        return;
      }

      const formData = new FormData();
      formData.append('image', {
        uri: photo.uri,
        name: 'capture.jpg',
        type: 'image/jpeg',
      } as any);

      const { data } = await axios.post<{ lines: string[]; linesCount?: number }>(`${BACKEND_URL}/ocr`, formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
        timeout: 60000,
      });

      const lines = data.lines || [];
      setOcrLinesCount(data.linesCount ?? lines.length);
      const extracted = extractSerialAndPartNumber(lines);
      setResult(extracted);
      setShowResult(true);
    } catch (err: any) {
      const msg = err.code === 'ECONNABORTED'
        ? 'Request timed out. EasyOCR is slow on first run—try again in 30s or run backend with GPU.'
        : (err.message || 'Backend error. Is the server running at ' + BACKEND_URL + '?');
      setError(msg);
    } finally {
      setProcessing(false);
    }
  };

  if (!permission) {
    return (
      <View style={styles.center}>
        <Text style={styles.message}>Checking camera permission…</Text>
        <StatusBar style="auto" />
      </View>
    );
  }

  if (!permission.granted) {
    return (
      <View style={styles.center}>
        <Text style={styles.message}>Camera access is needed to scan serial plates.</Text>
        <TouchableOpacity style={styles.button} onPress={requestPermission}>
          <Text style={styles.buttonText}>Allow camera</Text>
        </TouchableOpacity>
        <StatusBar style="auto" />
      </View>
    );
  }

  const { width: screenWidth, height: screenHeight } = Dimensions.get('window');

  // Guide box: centered, ~70% width, 50% height (always visible)
  const guideMarginW = screenWidth * 0.15;
  const guideMarginH = screenHeight * 0.25;
  const guideWidth = screenWidth - guideMarginW * 2;
  const guideHeight = screenHeight - guideMarginH * 2;

  return (
    <View style={styles.container}>
      <View style={styles.cameraWrapper}>
        <CameraView
          ref={cameraRef}
          style={styles.camera}
          onCameraReady={() => setCameraReady(true)}
        />
      </View>

      {/* Overlay layer on top of camera - so box is never clipped */}
      <View style={[styles.overlayLayer, { width: screenWidth, height: screenHeight }]} pointerEvents="none">
        {/* Static guide box - always visible */}
        <View
          style={[
            styles.guideBox,
            {
              left: guideMarginW,
              top: guideMarginH,
              width: guideWidth,
              height: guideHeight,
            },
          ]}
        />
        {/* Live YOLO bounding box - when backend returns one */}
        {bbox && (
          <View
            style={[
              styles.bboxOverlay,
              {
                left: (bbox[0] - bbox[2] / 2) * screenWidth,
                top: (bbox[1] - bbox[3] / 2) * screenHeight,
                width: bbox[2] * screenWidth,
                height: bbox[3] * screenHeight,
              },
            ]}
          />
        )}
      </View>

      {/* Bottom controls - need pointer events */}
      <View style={styles.overlay}>
        <Text style={styles.hint}>
          {bbox ? 'Serial plate detected' : 'Point camera at serial plate'}
        </Text>
        {error && <Text style={styles.errorText}>{error}</Text>}
        {processing ? (
            <>
              <ActivityIndicator size="large" color="#fff" style={{ marginVertical: 16 }} />
              <Text style={styles.loadingHint}>Extracting text…</Text>
            </>
          ) : (
          <TouchableOpacity style={styles.captureButton} onPress={handleCapture} activeOpacity={0.8}>
            <Text style={styles.captureButtonText}>Capture & extract</Text>
          </TouchableOpacity>
        )}
      </View>

      <Modal visible={showResult} transparent animationType="slide">
        <View style={styles.modalBackdrop}>
          <View style={styles.resultCard}>
            <Text style={styles.resultTitle}>Extracted</Text>
            <View style={styles.resultRow}>
              <Text style={styles.resultLabel}>Serial number</Text>
              <Text style={styles.resultValue}>{result?.serialNumber ?? '—'}</Text>
            </View>
            <View style={styles.resultRow}>
              <Text style={styles.resultLabel}>Part number</Text>
              <Text style={styles.resultValue}>{result?.partNumber ?? '—'}</Text>
            </View>
            {((result?.serialNumber == null && result?.partNumber == null) && ocrLinesCount != null) && (
              <Text style={styles.ocrHint}>
                {ocrLinesCount === 0
                  ? 'OCR found no text. Hold the camera steady and ensure the plate is in focus and well lit.'
                  : `OCR found ${ocrLinesCount} line(s) but no serial/part matched. Try framing the plate clearly.`}
              </Text>
            )}
            <TouchableOpacity
              style={styles.closeButton}
              onPress={() => {
                setShowResult(false);
                setResult(null);
                setOcrLinesCount(null);
              }}
            >
              <Text style={styles.closeButtonText}>Done</Text>
            </TouchableOpacity>
          </View>
        </View>
      </Modal>

      <StatusBar style="light" />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  center: {
    flex: 1,
    backgroundColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  message: {
    fontSize: 16,
    textAlign: 'center',
    marginBottom: 16,
  },
  button: {
    backgroundColor: '#007AFF',
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 8,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  cameraWrapper: {
    flex: 1,
    overflow: 'hidden',
  },
  camera: {
    flex: 1,
    width: '100%',
    height: '100%',
  },
  overlayLayer: {
    position: 'absolute',
    top: 0,
    left: 0,
  },
  guideBox: {
    position: 'absolute',
    borderWidth: 2,
    borderColor: 'rgba(0, 255, 0, 0.5)',
    borderRadius: 12,
  },
  bboxOverlay: {
    position: 'absolute',
    borderWidth: 4,
    borderColor: '#00FF00',
    borderRadius: 8,
  },
  overlay: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: 'transparent',
    alignItems: 'center',
    paddingBottom: 48,
  },
  hint: {
    color: '#fff',
    fontSize: 16,
    marginBottom: 12,
    textShadowColor: 'rgba(0,0,0,0.8)',
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 4,
  },
  errorText: {
    color: '#ff6b6b',
    fontSize: 12,
    marginBottom: 8,
    textAlign: 'center',
  },
  loadingHint: {
    color: 'rgba(255,255,255,0.9)',
    fontSize: 12,
    textAlign: 'center',
  },
  captureButton: {
    backgroundColor: '#fff',
    paddingHorizontal: 32,
    paddingVertical: 16,
    borderRadius: 30,
  },
  captureButtonText: {
    color: '#000',
    fontSize: 18,
    fontWeight: 'bold',
  },
  modalBackdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'flex-end',
  },
  resultCard: {
    backgroundColor: '#fff',
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    padding: 24,
    paddingBottom: 40,
  },
  resultTitle: {
    fontSize: 22,
    fontWeight: 'bold',
    marginBottom: 20,
    textAlign: 'center',
  },
  resultRow: {
    marginBottom: 16,
  },
  resultLabel: {
    fontSize: 12,
    color: '#666',
    marginBottom: 4,
  },
  resultValue: {
    fontSize: 18,
    fontWeight: '600',
  },
  ocrHint: {
    fontSize: 12,
    color: '#666',
    textAlign: 'center',
    marginTop: 8,
    paddingHorizontal: 8,
  },
  closeButton: {
    backgroundColor: '#007AFF',
    paddingVertical: 14,
    borderRadius: 10,
    marginTop: 16,
    alignItems: 'center',
  },
  closeButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
});
