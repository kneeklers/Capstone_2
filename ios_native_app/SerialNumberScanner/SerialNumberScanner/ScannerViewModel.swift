//
//  ScannerViewModel.swift
//  SerialNumberScanner
//
//  Main view model - handles camera, OCR, and serial extraction
//
//  DATA FLOW:
//  1. Camera captures photo
//  2. YOLO crops to serial plate region (if enabled)
//  3. Preprocessing enhances image contrast/sharpness (if enabled)
//  4. Apple Vision OCR extracts all text
//  5. Pattern matching finds serial/part numbers
//
//  KEY SETTINGS (in Settings screen):
//  - useYOLOCropping: Crop to detected plate before OCR (improves accuracy)
//  - usePreprocessing: Apply contrast/sharpening filters
//  - useOnDeviceOCR: Use Apple Vision (offline) vs backend API
//

import SwiftUI
import AVFoundation
import Vision
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins

class ScannerViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isProcessing = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var capturedImage: UIImage?      // Displayed image (cropped if YOLO enabled)
    @Published var originalImage: UIImage?       // Original full image (backup)
    @Published var croppedImage: UIImage?        // Cropped region for OCR
    @Published var wasYOLOCropped: Bool = false  // Track if cropping was applied
    
    // Results
    @Published var serialNumber: String?
    @Published var partNumber: String?
    @Published var confidence: Double?
    @Published var allRecognizedText: [String] = []
    
    // Settings
    @Published var useOnDeviceOCR = true
    @Published var useYOLOCropping = true      // Use YOLO to crop before OCR
    @Published var usePreprocessing = true     // Apply image preprocessing before OCR
    @Published var backendURL = "http://192.168.1.100:8000" // Update this
    
    // Core Image context for preprocessing (reusable for performance)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // Camera
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var photoCompletion: ((Bool) -> Void)?
    var cameraDevice: AVCaptureDevice?  // Exposed for tap-to-focus
    
    // YOLO Detector reference for cropping
    weak var yoloDetector: YOLODetector?
    
    // Macro mode
    @Published var isMacroMode: Bool = false
    @Published var macroAvailable: Bool = false
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupCamera()
    }
    
    // MARK: - Camera Setup
    private func setupCamera() {
        session.sessionPreset = .photo
        
        // Try to get the best camera with automatic switching (like native Camera app)
        // Priority: Triple > Dual Wide > Dual > Wide
        let camera = getBestAvailableCamera()
        
        guard let camera = camera else {
            showError(message: "Camera not available")
            return
        }
        
        // Store reference for tap-to-focus
        self.cameraDevice = camera
        
        do {
            // Configure camera for optimal close-up focusing
            try camera.lockForConfiguration()
            
            // Enable continuous autofocus
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            
            // Enable auto exposure
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            
            // Enable subject area change monitoring for better auto-switching
            camera.isSubjectAreaChangeMonitoringEnabled = true
            
            // For devices with macro capability, ensure it's enabled
            // This allows automatic switching to ultra-wide for close-ups
            if #available(iOS 15.0, *) {
                // Check if this is a device that supports automatic macro switching
                if camera.deviceType == .builtInTripleCamera || 
                   camera.deviceType == .builtInDualWideCamera {
                    // The multi-camera system handles macro automatically
                    print("✅ Multi-camera with macro support enabled")
                }
            }
            
            camera.unlockForConfiguration()
            
            let input = try AVCaptureDeviceInput(device: camera)
            
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
            
            // Start session on background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
            
            print("📷 Using camera: \(camera.localizedName) (\(camera.deviceType.rawValue))")
            
        } catch {
            showError(message: "Camera setup failed: \(error.localizedDescription)")
        }
    }
    
    // Get the best available camera that supports automatic macro/close-up focusing
    private func getBestAvailableCamera() -> AVCaptureDevice? {
        // Try cameras in order of preference for close-up photography
        
        // 1. Triple camera (iPhone Pro models) - has automatic macro switching
        if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
            print("📷 Found: Triple Camera (best for macro)")
            macroAvailable = true
            return triple
        }
        
        // 2. Dual Wide camera (iPhone 13+) - has automatic macro switching
        if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            print("📷 Found: Dual Wide Camera (good for macro)")
            macroAvailable = true
            return dualWide
        }
        
        // 3. Dual camera - automatic switching between wide and telephoto
        if let dual = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            print("📷 Found: Dual Camera")
            // Check if ultra-wide is available for manual macro
            macroAvailable = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil
            return dual
        }
        
        // 4. Check if ultra-wide is available - better minimum focus distance
        if AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil {
            macroAvailable = true
        }
        
        // 5. Standard wide camera - fallback
        if let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            print("📷 Found: Wide Camera (standard)")
            return wide
        }
        
        return nil
    }
    
    // MARK: - Toggle Macro Mode
    func toggleMacroMode() {
        guard macroAvailable else { return }
        
        isMacroMode.toggle()
        
        // Switch camera
        session.beginConfiguration()
        
        // Remove current input
        if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
            session.removeInput(currentInput)
        }
        
        // Get appropriate camera
        let newCamera: AVCaptureDevice?
        if isMacroMode {
            // Use ultra-wide for macro (best close-up focus)
            newCamera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
            print("📷 Switched to: Ultra Wide (Macro Mode)")
        } else {
            // Use the best multi-camera system
            newCamera = getBestAvailableCamera()
        }
        
        guard let camera = newCamera else {
            session.commitConfiguration()
            return
        }
        
        do {
            // Configure new camera
            try camera.lockForConfiguration()
            
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            camera.isSubjectAreaChangeMonitoringEnabled = true
            
            camera.unlockForConfiguration()
            
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            self.cameraDevice = camera
            
        } catch {
            print("Error switching camera: \(error)")
        }
        
        session.commitConfiguration()
    }
    
    // MARK: - Photo Capture
    func capturePhoto(completion: @escaping (Bool) -> Void) {
        guard !isProcessing else { return }
        
        isProcessing = true
        photoCompletion = completion
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    // MARK: - OCR Processing
    private func processImage(_ image: UIImage) {
        // Store original image
        self.originalImage = image
        
        // Try to crop using YOLO detection for better accuracy
        var imageToProcess = image
        
        if useYOLOCropping, let detector = yoloDetector {
            // Crop with padding to ensure text isn't cut off
            // - 15% horizontal expansion (left/right)
            // - 10% vertical expansion (top/bottom)
            if let cropped = detector.cropImageToDetection(image, horizontalExpansion: 0.15, verticalExpansion: 0.10) {
                imageToProcess = cropped
                self.croppedImage = cropped
                // Use cropped image as the main captured image for display and history
                self.capturedImage = cropped
                self.wasYOLOCropped = true
                print("✅ Using YOLO-cropped image (\(Int(cropped.size.width))x\(Int(cropped.size.height)))")
            } else {
                print("⚠️ YOLO cropping unavailable, using full image")
                self.croppedImage = nil
                self.wasYOLOCropped = false
            }
        } else {
            self.croppedImage = nil
            self.wasYOLOCropped = false
        }
        
        if useOnDeviceOCR {
            // Apply preprocessing if enabled (improves OCR accuracy)
            if usePreprocessing {
                if let preprocessed = preprocessImageForOCR(imageToProcess) {
                    print("✅ Preprocessing applied")
                    performVisionOCR(preprocessed)
                } else {
                    print("⚠️ Preprocessing failed, using original")
                    performVisionOCR(imageToProcess)
                }
            } else {
                performVisionOCR(imageToProcess)
            }
        } else {
            performBackendOCR(imageToProcess)
        }
    }
    
    // MARK: - Image Preprocessing for Better OCR
    // 4-step pipeline: grayscale → contrast boost → sharpen → shadow/highlight adjust
    // Helps with faded text, uneven lighting, and low-contrast plates
    private func preprocessImageForOCR(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        var ciImage = CIImage(cgImage: cgImage)
        
        // 1. Convert to grayscale for better text recognition
        if let grayscaleFilter = CIFilter(name: "CIPhotoEffectMono") {
            grayscaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
            if let output = grayscaleFilter.outputImage {
                ciImage = output
            }
        }
        
        // 2. Enhance contrast (similar to CLAHE)
        // Using CIColorControls for contrast boost
        if let contrastFilter = CIFilter(name: "CIColorControls") {
            contrastFilter.setValue(ciImage, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.3, forKey: kCIInputContrastKey)      // Boost contrast by 30%
            contrastFilter.setValue(0.05, forKey: kCIInputBrightnessKey)   // Slight brightness increase
            contrastFilter.setValue(1.0, forKey: kCIInputSaturationKey)
            if let output = contrastFilter.outputImage {
                ciImage = output
            }
        }
        
        // 3. Apply unsharp mask for sharpening (enhances text edges)
        if let sharpenFilter = CIFilter(name: "CIUnsharpMask") {
            sharpenFilter.setValue(ciImage, forKey: kCIInputImageKey)
            sharpenFilter.setValue(1.5, forKey: kCIInputRadiusKey)         // Sharpening radius
            sharpenFilter.setValue(0.8, forKey: kCIInputIntensityKey)      // Sharpening intensity
            if let output = sharpenFilter.outputImage {
                ciImage = output
            }
        }
        
        // 4. Local contrast enhancement (helps with uneven lighting)
        if let highlightFilter = CIFilter(name: "CIHighlightShadowAdjust") {
            highlightFilter.setValue(ciImage, forKey: kCIInputImageKey)
            highlightFilter.setValue(0.3, forKey: "inputShadowAmount")     // Brighten shadows
            highlightFilter.setValue(-0.2, forKey: "inputHighlightAmount") // Reduce highlights
            if let output = highlightFilter.outputImage {
                ciImage = output
            }
        }
        
        // Render the processed image
        guard let outputCGImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: outputCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    // MARK: - Apple Vision OCR
    private func performVisionOCR(_ image: UIImage) {
        guard let cgImage = image.cgImage else {
            finishProcessing(success: false, message: "Invalid image")
            return
        }
        
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.finishProcessing(success: false, message: error.localizedDescription)
                }
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async {
                    self.finishProcessing(success: false, message: "No text found")
                }
                return
            }
            
            DispatchQueue.main.async {
                self.parseOCRResults(observations)
            }
        }
        
        // Configure for best accuracy
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false // Disable for serial numbers
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.finishProcessing(success: false, message: error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Parse OCR Results
    private func parseOCRResults(_ observations: [VNRecognizedTextObservation]) {
        var allText: [String] = []
        var maxConfidence: Double = 0
        
        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            
            allText.append(topCandidate.string)
            maxConfidence = max(maxConfidence, Double(topCandidate.confidence))
        }
        
        allRecognizedText = allText
        confidence = maxConfidence
        
        // Extract serial number and part number using patterns
        extractSerialAndPartNumber(from: allText)
        
        let success = serialNumber != nil || partNumber != nil
        finishProcessing(success: success, message: success ? nil : "Could not identify serial/part number")
    }
    
    // MARK: - Serial/Part Number Extraction
    // Extraction priority:
    // 1. Lines ending with "P/N" → treat as part numbers
    // 2. Labeled values on same line (SER:, S/N:, SERIAL:, etc.)
    // 3. Label on one line, value on next (multi-line format)
    // 4. Fallback: score-based detection for unlabeled alphanumeric codes
    private func extractSerialAndPartNumber(from textLines: [String]) {
        serialNumber = nil
        partNumber = nil
        
        // Clean and normalize lines (normalize different dash characters)
        let cleanedLines = textLines.map { line -> String in
            var cleaned = line.trimmingCharacters(in: .whitespaces).uppercased()
            // Normalize different dash characters to standard hyphen
            cleaned = cleaned
                .replacingOccurrences(of: "−", with: "-")  // en-dash  
                .replacingOccurrences(of: "–", with: "-")  // em-dash
                .replacingOccurrences(of: "—", with: "-")  // long dash
                .replacingOccurrences(of: "―", with: "-")  // horizontal bar
            return cleaned
        }
        
        // === STEP 1: Find lines ending with "P/N" - these are PART NUMBERS ===
        for line in cleanedLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Lines ending with "P/N" are part numbers
            if partNumber == nil && trimmed.hasSuffix("P/N") {
                // Extract the code before "P/N"
                let codepart = trimmed.replacingOccurrences(of: "P/N", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "/S-M", with: "") // Clean up variants
                    .trimmingCharacters(in: .whitespaces)
                
                if codepart.count >= 5 && isAlphanumericCode(codepart.replacingOccurrences(of: " ", with: "")) {
                    partNumber = codepart
                }
            }
        }
        
        // === STEP 2: Same-line detection for labeled values ===
        for line in cleanedLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.count < 5 || isNoiseLine(trimmed) {
                continue
            }
            
            // Skip lines that end with P/N (already handled as part numbers)
            if trimmed.hasSuffix("P/N") {
                continue
            }
            
            // Serial number patterns
            if serialNumber == nil {
                // Handle "(S) Serial No." pattern (common on Apple product labels)
                if let match = extractSerialWithOptionalPrefix(line: trimmed) {
                    serialNumber = match
                }
                else if let match = extractWithWordBoundary(line: trimmed, prefix: "SERIAL NO") {
                    serialNumber = match
                }
                else if let match = extractWithWordBoundary(line: trimmed, prefix: "SERIAL NUMBER") {
                    serialNumber = match
                }
                else if let match = extractWithWordBoundary(line: trimmed, prefix: "SERIAL") {
                    serialNumber = match
                }
                else if let match = extractWithWordBoundary(line: trimmed, prefix: "SER") {
                    serialNumber = match
                }
                else if let match = extractWithWordBoundary(line: trimmed, prefix: "S/N") {
                    serialNumber = match
                }
                else if let match = extractWithWordBoundary(line: trimmed, prefix: "SN") {
                    serialNumber = match
                }
            }
            
            // Part number patterns (if not found via P/N suffix)
            if partNumber == nil {
                if let match = extractWithWordBoundary(line: trimmed, prefix: "PNR") {
                    partNumber = match
                }
                else if let match = extractWithWordBoundary(line: trimmed, prefix: "P/N") {
                    partNumber = match
                }
                else if let match = extractWithWordBoundary(line: trimmed, prefix: "PN") {
                    partNumber = match
                }
                else if let match = extractWithWordBoundary(line: trimmed, prefix: "PART") {
                    partNumber = match
                }
            }
        }
        
        // === STEP 3: Multi-line detection (label on one line, value on next) ===
        for (index, line) in cleanedLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Serial number labels (including French notation)
            if serialNumber == nil {
                let serialLabels = [
                    "SER", "S/N", "SN", "SERIAL", "SERIAL NO", "SERIAL NUMBER",
                    "SERIAL N°", "SERIAL N", "N°MATRICULE", "MATRICULE"  // French
                ]
                
                if serialLabels.contains(trimmed) {
                    // Get next line as value
                    if index + 1 < cleanedLines.count {
                        let nextLine = cleanedLines[index + 1].trimmingCharacters(in: .whitespaces)
                        // Make sure it's not another label and looks like a code
                        if !nextLine.isEmpty && 
                           nextLine.count >= 4 && 
                           !isLabelLine(nextLine) &&
                           isAlphanumericCode(nextLine) {
                            serialNumber = nextLine
                        }
                    }
                }
            }
            
            // Part number labels
            if partNumber == nil {
                let partLabels = ["PNR", "P/N", "PN", "PART", "PART NO", "PART NUMBER"]
                
                if partLabels.contains(trimmed) {
                    if index + 1 < cleanedLines.count {
                        let nextLine = cleanedLines[index + 1].trimmingCharacters(in: .whitespaces)
                        if !nextLine.isEmpty && nextLine.count >= 4 && !isLabelLine(nextLine) {
                            // Extract just the first code (before ISSUE, spaces, etc.)
                            let extractedCode = extractFirstCode(from: nextLine)
                            if extractedCode.count >= 4 && isAlphanumericCode(extractedCode) {
                                partNumber = extractedCode
                            }
                        }
                    }
                }
            }
        }
        
        // === STEP 4: Fallback - score-based detection ===
        if serialNumber == nil {
            var candidates: [(String, Int)] = []
            
            for line in cleanedLines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                
                // Skip noise, labels, and lines with P/N
                if isNoiseLine(trimmed) { continue }
                if isLabelLine(trimmed) { continue }
                if trimmed.contains("P/N") { continue }
                if let pn = partNumber, trimmed.contains(pn) { continue }
                
                let score = serialNumberScore(trimmed)
                if score > 0 {
                    candidates.append((trimmed, score))
                }
            }
            
            candidates.sort { $0.1 > $1.1 }
            if let best = candidates.first {
                serialNumber = best.0
            }
        }
    }
    
    // Check if a line is just a label (not a value)
    private func isLabelLine(_ text: String) -> Bool {
        let labels = [
            "SER", "SERIAL", "SERIAL N°", "SERIAL NO", "SERIAL NUMBER",
            "PNR", "P/N", "PN", "PART", "PART NO", "PART NUMBER",
            "MFR", "MODEL", "MDL", "REF", "DATE", "DOM",
            "N°MATRICULE", "MATRICULE", "CONTROLE", "INSPECTION",
            "SUPPORT", "ACCESSORY", "GEARBOX"
        ]
        return labels.contains(text.uppercased())
    }
    
    // Extract serial number with optional prefix like "(S) Serial No. F4GZ9JGEN735"
    private func extractSerialWithOptionalPrefix(line: String) -> String? {
        // Pattern: optional (S) or (s) prefix, then "Serial No" or "Serial No.", then the value
        let pattern = #"^\(?\s*[Ss]\s*\)?\s*[Ss]erial\s*[Nn]o\.?\s*[:\s]*([A-Z0-9]+(?:[-/][A-Z0-9]+)?)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let range = NSRange(line.startIndex..., in: line)
        if let match = regex.firstMatch(in: line, options: [], range: range),
           match.numberOfRanges > 1,
           let captureRange = Range(match.range(at: 1), in: line) {
            let value = String(line[captureRange]).trimmingCharacters(in: .whitespaces)
            if value.count >= 4 && isAlphanumericCode(value) {
                return value
            }
        }
        return nil
    }
    
    // Extract value after a prefix with proper word boundary
    // e.g., "SER : HJ023764-F" -> "HJ023764-F"
    // but NOT "SERCK AVIATION" -> should not match
    private func extractWithWordBoundary(line: String, prefix: String) -> String? {
        // Check if line starts with the prefix followed by separator
        let pattern = "^" + NSRegularExpression.escapedPattern(for: prefix) + "[\\s:]+(.+)$"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let range = NSRange(line.startIndex..., in: line)
        if let match = regex.firstMatch(in: line, options: [], range: range),
           match.numberOfRanges > 1,
           let captureRange = Range(match.range(at: 1), in: line) {
            let value = String(line[captureRange]).trimmingCharacters(in: .whitespaces)
            
            // Clean up: take only the first "word" (alphanumeric with dashes)
            let cleanValue = extractFirstCode(from: value)
            
            // Validate it looks like a code
            if cleanValue.count >= 4 && isAlphanumericCode(cleanValue) {
                return cleanValue
            }
        }
        return nil
    }
    
    // Extract first alphanumeric code from a string
    // e.g., "HJ023764-F ISSUE:D" -> "HJ023764-F"
    // e.g., "45731-1423 ISSUE: [" -> "45731-1423"
    private func extractFirstCode(from text: String) -> String {
        // First, normalize different dash characters to standard hyphen
        let normalized = text
            .replacingOccurrences(of: "−", with: "-")  // en-dash
            .replacingOccurrences(of: "–", with: "-")  // em-dash
            .replacingOccurrences(of: "—", with: "-")  // long dash
            .replacingOccurrences(of: "―", with: "-")  // horizontal bar
        
        // Match alphanumeric code (letters, numbers, dashes, dots)
        // Stop at spaces, colons, or other separators
        let pattern = "^([A-Z0-9][A-Z0-9\\-\\.]*[A-Z0-9])"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            // Fallback: split by space and take first part
            let firstPart = normalized.split(separator: " ").first.map(String.init) ?? normalized
            return firstPart
        }
        
        let range = NSRange(normalized.startIndex..., in: normalized)
        if let match = regex.firstMatch(in: normalized, options: [], range: range),
           let captureRange = Range(match.range(at: 1), in: normalized) {
            return String(normalized[captureRange])
        }
        
        // Fallback: split by space and take first part
        let firstPart = normalized.split(separator: " ").first.map(String.init) ?? normalized
        return firstPart
    }
    
    // Check if line is noise (UI elements, common words, file names)
    private func isNoiseLine(_ text: String) -> Bool {
        let noisePatterns = [
            "PREVIEW", "FILE", "EDIT", "VIEW", "GO", "TOOLS", "WINDOW", "HELP",
            ".JPG", ".PNG", ".PDF", "TV", "Q Q", "0,",
            "MFR ", "BIRMINGHAM", "ENGLAND", "USA", "INC.", "LTD",
            "MAIN HEAT", "EXCHANGER", "AVIATION", "INSP",
            "EID ", "IMEI", "MEID", "IMEI2", "IMEI/MEID"  // Device identifiers (not serial numbers)
        ]
        
        let upper = text.uppercased()
        
        // Check for exact short matches
        if text.count <= 3 {
            return true
        }
        
        // Check for noise patterns
        for noise in noisePatterns {
            if upper == noise || upper.hasPrefix(noise + " ") || upper.hasSuffix(" " + noise) {
                return true
            }
        }
        
        // Check if it's just a filename
        if upper.hasSuffix(".JPG") || upper.hasSuffix(".PNG") || upper.contains("...") {
            return true
        }
        
        return false
    }
    
    // Check if string looks like an alphanumeric code (serial/part number)
    private func isAlphanumericCode(_ text: String) -> Bool {
        let hasLetter = text.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasNumber = text.range(of: "[0-9]", options: .regularExpression) != nil
        let isClean = text.range(of: "^[A-Z0-9\\-\\.]+$", options: .regularExpression) != nil
        return (hasLetter || hasNumber) && isClean
    }
    
    // Score how likely a string is to be a serial number
    private func serialNumberScore(_ text: String) -> Int {
        var score = 0
        let length = text.count
        
        // Length check (6-25 chars is typical)
        guard length >= 5 && length <= 30 else { return 0 }
        
        // Must be mostly alphanumeric
        let alphanumericCount = text.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }.count
        guard Double(alphanumericCount) / Double(length) > 0.8 else { return 0 }
        
        // Has letters
        if text.range(of: "[A-Z]", options: .regularExpression) != nil {
            score += 2
        }
        
        // Has numbers
        if text.range(of: "[0-9]", options: .regularExpression) != nil {
            score += 2
        }
        
        // Has mix of letters and numbers (very likely serial)
        let hasLetter = text.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasNumber = text.range(of: "[0-9]", options: .regularExpression) != nil
        if hasLetter && hasNumber {
            score += 5
        }
        
        // Longer strings score higher (up to a point)
        if length >= 8 && length <= 20 {
            score += 3
        }
        
        // Contains dash (common in serial numbers)
        if text.contains("-") {
            score += 2
        }
        
        // Penalize if it looks like a common word
        let commonWords = ["MODEL", "SERIAL", "PART", "NUMBER", "TYPE", "MADE", "DATE"]
        for word in commonWords {
            if text == word {
                return 0
            }
        }
        
        // Penalize device identifiers (EID, IMEI are NOT serial numbers)
        let deviceIdentifiers = ["EID", "IMEI", "MEID", "IMEI2", "IMEI/MEID"]
        for identifier in deviceIdentifiers {
            if text.uppercased().hasPrefix(identifier) {
                return 0  // Not a serial number
            }
        }
        
        // Penalize very long numbers (EID is 32 digits, likely not a serial)
        let digitCount = text.filter { $0.isNumber }.count
        if digitCount > 20 {
            return 0  // Too many digits, likely EID or similar
        }
        
        return score
    }
    
    private func extractMatch(pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           match.numberOfRanges > 1,
           let captureRange = Range(match.range(at: 1), in: text) {
            return String(text[captureRange]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
    
    
    // MARK: - Backend OCR
    private func performBackendOCR(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            finishProcessing(success: false, message: "Failed to encode image")
            return
        }
        
        guard let url = URL(string: "\(backendURL)/extract") else {
            finishProcessing(success: false, message: "Invalid backend URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add image
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add method
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"method\"\r\n\r\n".data(using: .utf8)!)
        body.append("minimal".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.finishProcessing(success: false, message: "Network error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    self?.finishProcessing(success: false, message: "No response from server")
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let success = json["success"] as? Bool ?? false
                        self?.serialNumber = json["serial"] as? String
                        self?.partNumber = json["part_number"] as? String
                        self?.confidence = json["confidence"] as? Double
                        
                        if success {
                            self?.finishProcessing(success: true)
                        } else {
                            let errorMsg = json["error"] as? String ?? "Extraction failed"
                            self?.finishProcessing(success: false, message: errorMsg)
                        }
                    }
                } catch {
                    self?.finishProcessing(success: false, message: "Failed to parse response")
                }
            }
        }.resume()
    }
    
    // MARK: - Helpers
    private func finishProcessing(success: Bool, message: String? = nil) {
        isProcessing = false
        
        if !success && message != nil {
            showError(message: message!)
        }
        
        photoCompletion?(success)
        photoCompletion = nil
    }
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
    
    func reset() {
        serialNumber = nil
        partNumber = nil
        confidence = nil
        allRecognizedText = []
        capturedImage = nil
        originalImage = nil
        croppedImage = nil
        wasYOLOCropped = false
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension ScannerViewModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            DispatchQueue.main.async { [weak self] in
                self?.finishProcessing(success: false, message: error.localizedDescription)
            }
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            DispatchQueue.main.async { [weak self] in
                self?.finishProcessing(success: false, message: "Failed to capture image")
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.capturedImage = image
            self?.processImage(image)
        }
    }
}
