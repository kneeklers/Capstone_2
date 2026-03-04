//
//  YOLODetector.swift
//  SerialNumberScanner
//
//  Real-time YOLO detection for serial plate localization
//
//  WHAT IT DOES:
//  - Processes camera frames at 10fps looking for serial plates
//  - Provides live feedback (position, size, blur) to guide the user
//  - Crops detected region for better OCR accuracy
//
//  MODEL:
//  - Uses best.mlpackage (CoreML) - add to Xcode project bundle
//  - Trained on industrial serial plates via Roboflow + YOLOv8
//

import Vision
import CoreML
import UIKit
import AVFoundation
import CoreImage

// Detection result for UI feedback
struct DetectionFeedback: Equatable {
    var detected: Bool = false
    var confidence: Float = 0.0
    var boundingBox: CGRect = .zero
    var fillPercent: Int = 0
    var isBlurry: Bool = false
    var blurScore: Double = 0
    var message: String = "🔍 Looking for serial plate..."
    var secondaryMessage: String = ""
    var color: UIColor = .systemYellow
    var quality: DetectionQuality = .searching
    
    enum DetectionQuality: Equatable {
        case searching, adjust, warning, perfect, bad
    }
    
    static func == (lhs: DetectionFeedback, rhs: DetectionFeedback) -> Bool {
        return lhs.message == rhs.message && lhs.quality == rhs.quality
    }
}

class YOLODetector: ObservableObject {
    @Published var feedback = DetectionFeedback()
    @Published var isModelLoaded = false
    
    private var visionModel: VNCoreMLModel?
    private var lastProcessTime = Date()
    private let processInterval: TimeInterval = 0.1  // Process every 100ms for smoother updates
    
    // Smoothing for stable feedback
    private var recentDetections: [CGRect] = []
    private var recentConfidences: [Float] = []
    private let smoothingWindow = 5
    
    // THRESHOLDS - adjust these to tune detection sensitivity
    // Fill % = largest dimension of detected box relative to frame (not area)
    private let minFillRatio: CGFloat = 0.10      // Below 10% = too far, prompt "move closer"
    private let idealMinFill: CGFloat = 0.15      // 15-80% = good range for OCR
    private let idealMaxFill: CGFloat = 0.80
    private let maxFillRatio: CGFloat = 0.95      // Above 95% = too close, may lose focus
    private let centerTolerance: CGFloat = 0.20   // How off-center is acceptable (0.2 = 20%)
    private let minConfidence: Float = 0.25       // Below this = don't show detection
    private let goodConfidence: Float = 0.45      // Green "ready" indicator
    private let greatConfidence: Float = 0.60     // "Perfect" indicator
    private let blurThreshold: Double = 30.0      // Laplacian variance - lower = blurrier
    
    init() {
        loadModel()
    }
    
    // MARK: - Load CoreML Model
    private func loadModel() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .cpuAndNeuralEngine
                
                // Try multiple possible model locations
                var modelURL: URL? = nil
                
                // Check for compiled model first
                if let url = Bundle.main.url(forResource: "best", withExtension: "mlmodelc") {
                    modelURL = url
                }
                // Check for mlpackage
                else if let url = Bundle.main.url(forResource: "best", withExtension: "mlpackage") {
                    modelURL = url
                }
                // Check in app bundle root
                else if let url = Bundle.main.url(forResource: "best", withExtension: nil) {
                    modelURL = url
                }
                
                if let url = modelURL {
                    let model = try MLModel(contentsOf: url, configuration: config)
                    self?.visionModel = try VNCoreMLModel(for: model)
                    
                    DispatchQueue.main.async {
                        self?.isModelLoaded = true
                        print("✅ YOLO model loaded successfully from: \(url.lastPathComponent)")
                    }
                } else {
                    print("⚠️ YOLO model not found. Add best.mlpackage to Xcode project.")
                    DispatchQueue.main.async {
                        self?.isModelLoaded = false
                    }
                }
            } catch {
                print("❌ Failed to load YOLO model: \(error)")
                DispatchQueue.main.async {
                    self?.isModelLoaded = false
                }
            }
        }
    }
    
    // MARK: - Process Camera Frame
    func processFrame(_ sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation = .right) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) >= processInterval else { return }
        lastProcessTime = now
        
        guard let visionModel = visionModel else {
            DispatchQueue.main.async {
                self.feedback = DetectionFeedback(
                    detected: false,
                    message: "⚠️ Loading model...",
                    color: .systemOrange,
                    quality: .warning
                )
            }
            return
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            self?.handleDetectionResults(request: request, error: error, pixelBuffer: pixelBuffer)
        }
        
        request.imageCropAndScaleOption = .scaleFill
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            print("Detection error: \(error)")
        }
    }
    
    // MARK: - Handle Detection Results
    private func handleDetectionResults(request: VNRequest, error: Error?, pixelBuffer: CVPixelBuffer) {
        if let error = error {
            print("Detection error: \(error)")
            return
        }
        
        // Get all observations and find the best one
        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            updateNoDetection()
            return
        }
        
        // Filter by minimum confidence and get best result
        let validResults = results.filter { $0.confidence >= minConfidence }
        guard let topResult = validResults.max(by: { $0.confidence < $1.confidence }) else {
            updateNoDetection()
            return
        }
        
        // Add to smoothing buffer
        recentDetections.append(topResult.boundingBox)
        recentConfidences.append(topResult.confidence)
        
        if recentDetections.count > smoothingWindow {
            recentDetections.removeFirst()
            recentConfidences.removeFirst()
        }
        
        // Use smoothed values for more stable feedback
        let smoothedBox = smoothedBoundingBox()
        let smoothedConfidence = recentConfidences.reduce(0, +) / Float(recentConfidences.count)
        
        // Analyze and provide feedback
        let newFeedback = analyzePlatePosition(
            boundingBox: smoothedBox,
            confidence: smoothedConfidence,
            pixelBuffer: pixelBuffer
        )
        
        DispatchQueue.main.async {
            self.feedback = newFeedback
        }
    }
    
    private func updateNoDetection() {
        // Clear smoothing buffer after no detection
        if recentDetections.count > 0 {
            recentDetections.removeAll()
            recentConfidences.removeAll()
        }
        
        DispatchQueue.main.async {
            self.feedback = DetectionFeedback(
                detected: false,
                message: "🔍 Point camera at serial plate",
                secondaryMessage: "Make sure plate is visible",
                color: .systemRed,
                quality: .bad
            )
        }
    }
    
    private func smoothedBoundingBox() -> CGRect {
        guard !recentDetections.isEmpty else { return .zero }
        
        let avgX = recentDetections.map { $0.origin.x }.reduce(0, +) / CGFloat(recentDetections.count)
        let avgY = recentDetections.map { $0.origin.y }.reduce(0, +) / CGFloat(recentDetections.count)
        let avgW = recentDetections.map { $0.width }.reduce(0, +) / CGFloat(recentDetections.count)
        let avgH = recentDetections.map { $0.height }.reduce(0, +) / CGFloat(recentDetections.count)
        
        return CGRect(x: avgX, y: avgY, width: avgW, height: avgH)
    }
    
    // MARK: - Analyze Plate Position
    private func analyzePlatePosition(boundingBox: CGRect, confidence: Float, pixelBuffer: CVPixelBuffer) -> DetectionFeedback {
        var feedback = DetectionFeedback()
        feedback.detected = true
        feedback.confidence = confidence
        feedback.boundingBox = boundingBox
        
        // Calculate fill ratio using the LARGER dimension (more intuitive for rectangular plates)
        // Serial plates are typically wide and short, so width is more meaningful
        let maxDimension = max(boundingBox.width, boundingBox.height)
        let fillRatio = maxDimension  // Use largest dimension as the "fill"
        feedback.fillPercent = Int(fillRatio * 100)
        
        // Check blur
        let blurScore = calculateBlurScore(pixelBuffer: pixelBuffer, boundingBox: boundingBox)
        feedback.blurScore = blurScore
        feedback.isBlurry = blurScore < blurThreshold
        
        // Center offset (0.5, 0.5 is center)
        let centerX = boundingBox.midX
        let centerY = boundingBox.midY
        let offsetX = centerX - 0.5
        let offsetY = centerY - 0.5
        
        // Collect all issues
        var issues: [(priority: Int, message: String, color: UIColor)] = []
        
        // === BLUR ANALYSIS (Only warn for severe blur) ===
        if feedback.isBlurry && fillRatio > maxFillRatio {
            // Too close AND blurry - need to move back
            issues.append((0, "📷 Too close - move back to focus", .systemOrange))
        } else if feedback.isBlurry && blurScore < blurThreshold * 0.5 {
            // Only warn for very blurry images
            issues.append((3, "📷 Tap to focus", .systemYellow))
        }
        
        // === SIZE ANALYSIS (More lenient) ===
        if fillRatio < minFillRatio {
            issues.append((1, "📏 Move closer", .systemOrange))
        } else if fillRatio > maxFillRatio {
            issues.append((1, "📏 Move back slightly", .systemOrange))
        }
        // Note: Removed warnings for "slightly closer" and "slightly back" - they were too aggressive
        
        // === POSITION ANALYSIS (More lenient) ===
        let totalOffset = sqrt(offsetX * offsetX + offsetY * offsetY)
        
        // Only warn if significantly off-center
        if totalOffset > centerTolerance * 2.5 {
            let direction = getDirectionMessage(offsetX: offsetX, offsetY: offsetY)
            issues.append((2, direction, .systemOrange))
        }
        // Removed yellow warnings for minor offset - too distracting
        
        // === CONFIDENCE ANALYSIS (More lenient) ===
        if confidence < minConfidence {
            issues.append((1, "🔍 Searching...", .systemYellow))
        }
        // Removed "hold steady" message - was too frequent
        
        // === DETERMINE FINAL FEEDBACK ===
        if issues.isEmpty {
            // No issues - ready to capture!
            if confidence >= greatConfidence {
                feedback.message = "✅ Perfect! Tap to capture"
                feedback.secondaryMessage = "Confidence: \(Int(confidence * 100))%"
                feedback.color = .systemGreen
                feedback.quality = .perfect
            } else if confidence >= goodConfidence {
                feedback.message = "👍 Good - tap to capture"
                feedback.secondaryMessage = "Confidence: \(Int(confidence * 100))%"
                feedback.color = .systemGreen
                feedback.quality = .perfect
            } else {
                // Low confidence but still usable
                feedback.message = "📸 Ready - tap to capture"
                feedback.secondaryMessage = "Confidence: \(Int(confidence * 100))%"
                feedback.color = .systemGreen
                feedback.quality = .perfect
            }
        } else {
            // Sort by priority and show the most important issue
            issues.sort { $0.priority < $1.priority }
            let topIssue = issues[0]
            
            feedback.message = topIssue.message
            feedback.color = topIssue.color
            feedback.quality = topIssue.color == .systemRed ? .bad : 
                              topIssue.color == .systemOrange ? .adjust : .warning
            
            // Simplified secondary info
            feedback.secondaryMessage = "Conf: \(Int(confidence * 100))% | Fill: \(feedback.fillPercent)%"
        }
        
        return feedback
    }
    
    // MARK: - Blur Detection (Laplacian Variance)
    private func calculateBlurScore(pixelBuffer: CVPixelBuffer, boundingBox: CGRect) -> Double {
        // Convert pixel buffer to CIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Crop to bounding box region
        let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        
        let cropRect = CGRect(
            x: boundingBox.origin.x * imageWidth,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageHeight,
            width: boundingBox.width * imageWidth,
            height: boundingBox.height * imageHeight
        )
        
        let croppedImage = ciImage.cropped(to: cropRect)
        
        // Apply Laplacian filter for edge detection
        guard let laplacianFilter = CIFilter(name: "CIConvolution3X3") else {
            return 200 // Default to "not blurry" if filter unavailable
        }
        
        // Laplacian kernel for edge detection
        let laplacianKernel = CIVector(values: [0, 1, 0, 1, -4, 1, 0, 1, 0], count: 9)
        laplacianFilter.setValue(croppedImage, forKey: kCIInputImageKey)
        laplacianFilter.setValue(laplacianKernel, forKey: "inputWeights")
        laplacianFilter.setValue(0, forKey: "inputBias")
        
        guard let outputImage = laplacianFilter.outputImage else {
            return 200
        }
        
        // Calculate variance (higher = sharper)
        let context = CIContext()
        var bitmap = [UInt8](repeating: 0, count: 4)
        
        // Sample center of the cropped region
        let sampleRect = CGRect(x: outputImage.extent.midX - 1, y: outputImage.extent.midY - 1, width: 2, height: 2)
        
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 8, bounds: sampleRect, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        
        // Simple variance calculation from sampled pixels
        let intensity = Double(bitmap[0]) + Double(bitmap[1]) + Double(bitmap[2])
        
        // Scale to useful range (higher = sharper)
        return intensity
    }
    
    private func getDirectionMessage(offsetX: CGFloat, offsetY: CGFloat) -> String {
        // Determine primary direction to move
        let absX = abs(offsetX)
        let absY = abs(offsetY)
        
        if absX > absY {
            // Horizontal adjustment needed
            if offsetX > 0 {
                return "⬅️ Move camera LEFT"
            } else {
                return "➡️ Move camera RIGHT"
            }
        } else {
            // Vertical adjustment needed
            if offsetY > 0 {
                return "⬇️ Move camera DOWN"
            } else {
                return "⬆️ Move camera UP"
            }
        }
    }
    
    // MARK: - Get Current Bounding Box for Cropping
    /// Returns the current detected bounding box (normalized 0-1 coordinates)
    /// Use this to crop the image before OCR for better accuracy
    func getCurrentBoundingBox() -> CGRect? {
        guard feedback.detected, feedback.boundingBox != .zero else {
            return nil
        }
        return feedback.boundingBox
    }
    
    /// Crop image using the detected bounding box with adjustable expansion
    /// - Parameters:
    ///   - image: The original UIImage to crop
    ///   - horizontalExpansion: Expand width (0.05 = 5% on each side). Can be negative to crop tighter.
    ///   - verticalExpansion: Expand height (can be negative to crop tighter, e.g., -0.15 removes 15% from top/bottom)
    /// - Returns: Cropped UIImage or nil if no detection
    func cropImageToDetection(_ image: UIImage, horizontalExpansion: CGFloat = 0.05, verticalExpansion: CGFloat = -0.10) -> UIImage? {
        guard let boundingBox = getCurrentBoundingBox() else {
            return nil
        }
        
        guard let cgImage = image.cgImage else {
            return nil
        }
        
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        // Convert normalized coordinates to pixel coordinates
        // Note: Vision uses bottom-left origin, UIKit uses top-left
        // Horizontal: slight expansion to ensure text isn't cut off
        // Vertical: negative expansion to crop out metal housing above/below text
        let adjustedWidth = boundingBox.width * (1 + horizontalExpansion * 2)
        let adjustedHeight = boundingBox.height * (1 + verticalExpansion * 2)
        let adjustedX = max(0, boundingBox.origin.x - boundingBox.width * horizontalExpansion)
        let adjustedY = max(0, boundingBox.origin.y - boundingBox.height * verticalExpansion)
        
        // Ensure dimensions are positive
        let finalWidth = max(0.1, adjustedWidth)
        let finalHeight = max(0.1, adjustedHeight)
        
        // Convert to pixel coordinates (flip Y for UIKit)
        let cropRect = CGRect(
            x: adjustedX * imageWidth,
            y: (1 - adjustedY - finalHeight) * imageHeight,
            width: min(finalWidth * imageWidth, imageWidth - adjustedX * imageWidth),
            height: min(finalHeight * imageHeight, imageHeight)
        )
        
        // Ensure crop rect is valid
        let validRect = cropRect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        
        guard validRect.width > 0 && validRect.height > 0 else {
            return nil
        }
        
        // Perform the crop
        guard let croppedCGImage = cgImage.cropping(to: validRect) else {
            return nil
        }
        
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
