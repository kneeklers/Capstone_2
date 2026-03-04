//
//  CameraView.swift
//  SerialNumberScanner
//
//  Camera preview using AVFoundation with optional YOLO frame processing
//

import SwiftUI
import AVFoundation

struct CameraView: UIViewRepresentable {
    @ObservedObject var viewModel: ScannerViewModel
    var yoloDetector: YOLODetector?
    
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.session = viewModel.session
        view.yoloDetector = yoloDetector
        view.cameraDevice = viewModel.cameraDevice
        view.setupVideoOutput()
        view.setupTapToFocus()
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.yoloDetector = yoloDetector
    }
}

class CameraPreviewView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInteractive)
    
    var yoloDetector: YOLODetector?
    var cameraDevice: AVCaptureDevice?
    
    // Focus indicator view
    private var focusIndicator: UIView?
    
    var session: AVCaptureSession? {
        didSet {
            setupPreviewLayer()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
    
    private func setupPreviewLayer() {
        guard let session = session else { return }
        
        previewLayer?.removeFromSuperlayer()
        
        let newLayer = AVCaptureVideoPreviewLayer(session: session)
        newLayer.videoGravity = .resizeAspectFill
        newLayer.frame = bounds
        
        layer.addSublayer(newLayer)
        previewLayer = newLayer
    }
    
    func setupVideoOutput() {
        guard let session = session else { return }
        
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
    }
    
    // MARK: - Tap to Focus
    func setupTapToFocus() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapToFocus(_:)))
        self.addGestureRecognizer(tapGesture)
        self.isUserInteractionEnabled = true
        
        // Create focus indicator
        let indicator = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        indicator.layer.borderColor = UIColor.yellow.cgColor
        indicator.layer.borderWidth = 2
        indicator.layer.cornerRadius = 8
        indicator.backgroundColor = .clear
        indicator.isHidden = true
        addSubview(indicator)
        focusIndicator = indicator
    }
    
    @objc private func handleTapToFocus(_ gesture: UITapGestureRecognizer) {
        let touchPoint = gesture.location(in: self)
        
        guard let previewLayer = previewLayer else { return }
        
        // Convert touch point to camera coordinates
        let focusPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: touchPoint)
        
        // Show focus indicator
        showFocusIndicator(at: touchPoint)
        
        // Focus the camera
        focusCamera(at: focusPoint)
    }
    
    private func showFocusIndicator(at point: CGPoint) {
        guard let indicator = focusIndicator else { return }
        
        indicator.center = point
        indicator.isHidden = false
        indicator.alpha = 1
        indicator.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        
        UIView.animate(withDuration: 0.3, animations: {
            indicator.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.5, delay: 0.5, options: [], animations: {
                indicator.alpha = 0
            }) { _ in
                indicator.isHidden = true
            }
        }
    }
    
    private func focusCamera(at point: CGPoint) {
        guard let device = cameraDevice else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Set focus point
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            
            // Set exposure point
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            
            device.unlockForConfiguration()
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            
        } catch {
            print("Error focusing camera: \(error)")
        }
    }
}

// MARK: - Video Frame Processing
extension CameraPreviewView: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Process frame with YOLO detector if available
        yoloDetector?.processFrame(sampleBuffer)
    }
}
