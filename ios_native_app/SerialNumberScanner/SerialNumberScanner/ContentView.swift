//
//  ContentView.swift
//  SerialNumberScanner
//
//  Main screen with camera preview and capture controls
//
//  UI STRUCTURE:
//  - CameraView: Live camera feed (full screen background)
//  - BoundingBoxOverlay: Shows YOLO-detected plate region
//  - TopBarView: Settings, history, macro toggle
//  - LiveGuidanceView: Real-time feedback ("move closer", "ready", etc.)
//  - BottomControlsView: Capture button, confidence/quality indicators
//
//  SHEETS:
//  - ResultsView: Shows extracted serial/part numbers after capture
//  - SettingsView: OCR mode, preprocessing toggles
//  - HistoryView: Past scans stored on device
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ScannerViewModel()
    @StateObject private var yoloDetector = YOLODetector()
    @StateObject private var historyManager = ScanHistoryManager()
    @State private var showGuide = true
    @State private var showBoundingBox = true
    @State private var showResults = false
    @State private var showSettings = false
    @State private var showHistory = false
    
    var body: some View {
        ZStack {
            // Camera View with YOLO processing
            CameraView(viewModel: viewModel, yoloDetector: yoloDetector)
                .ignoresSafeArea()
            
            // YOLO Bounding Box Overlay (pass detector so overlay observes feedback for live updates)
            if showBoundingBox && yoloDetector.isModelLoaded && !viewModel.isProcessing && !showResults {
                BoundingBoxOverlay(detector: yoloDetector, showBox: true)
                    .ignoresSafeArea()
            }
            
            // Static Guideline Overlay (when YOLO not loaded)
            if showGuide && !yoloDetector.isModelLoaded && !viewModel.isProcessing && !showResults {
                GuidelineOverlay()
            }
            
            // UI Overlay
            VStack {
                // Top Bar
                TopBarView(
                    showGuide: $showGuide,
                    showBoundingBox: $showBoundingBox,
                    showSettings: $showSettings,
                    showHistory: $showHistory,
                    viewModel: viewModel,
                    isYoloLoaded: yoloDetector.isModelLoaded,
                    scanCount: historyManager.totalScans
                )
                
                // Live Guidance Feedback (YOLO)
                if yoloDetector.isModelLoaded && !viewModel.isProcessing && !showResults {
                    LiveGuidanceView(feedback: yoloDetector.feedback)
                } else if showGuide && !viewModel.isProcessing && !showResults {
                    // Fallback to static instructions
                    InstructionsView()
                }
                
                Spacer()
                
                // Bottom Controls
                BottomControlsView(
                    viewModel: viewModel,
                    showResults: $showResults,
                    feedback: yoloDetector.feedback,
                    isYoloLoaded: yoloDetector.isModelLoaded
                )
            }
            
            // Processing Overlay
            if viewModel.isProcessing {
                ProcessingOverlay()
            }
        }
        .sheet(isPresented: $showResults) {
            ResultsView(
                viewModel: viewModel,
                historyManager: historyManager,
                isPresented: $showResults
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(historyManager: historyManager)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .onAppear {
            // Connect YOLO detector to view model for cropping
            viewModel.yoloDetector = yoloDetector
        }
    }
}

// MARK: - Live Guidance View (YOLO Feedback)
struct LiveGuidanceView: View {
    let feedback: DetectionFeedback
    
    var body: some View {
        VStack(spacing: 6) {
            // Main message
            Text(feedback.message)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            // Secondary message (additional info)
            if !feedback.secondaryMessage.isEmpty {
                Text(feedback.secondaryMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(feedback.color).opacity(0.9))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        )
        .padding(.top, 10)
        .animation(.easeInOut(duration: 0.15), value: feedback.message)
    }
}

// MARK: - Top Bar View
struct TopBarView: View {
    @Binding var showGuide: Bool
    @Binding var showBoundingBox: Bool
    @Binding var showSettings: Bool
    @Binding var showHistory: Bool
    @ObservedObject var viewModel: ScannerViewModel
    var isYoloLoaded: Bool
    var scanCount: Int
    
    var body: some View {
        HStack {
            Text("🔍 Serial Scanner")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            // History Button with badge
            Button(action: { showHistory = true }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.white)
                        .font(.system(size: 18))
                        .padding(6)
                    
                    if scanCount > 0 {
                        Text("\(min(scanCount, 99))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 6, y: -4)
                    }
                }
            }
            
            // Macro Mode Toggle (for close-up focus)
            if viewModel.macroAvailable {
                Button(action: { viewModel.toggleMacroMode() }) {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.isMacroMode ? "camera.macro" : "camera")
                            .font(.system(size: 14))
                        Text(viewModel.isMacroMode ? "Macro" : "Auto")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(viewModel.isMacroMode ? Color.orange.opacity(0.8) : Color.gray.opacity(0.6))
                    .cornerRadius(6)
                }
            }
            
            // Bounding Box Toggle (only show if YOLO is loaded)
            if isYoloLoaded {
                Button(action: { showBoundingBox.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: showBoundingBox ? "square.dashed" : "square")
                            .font(.system(size: 14))
                        Text("Box")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(showBoundingBox ? Color.blue.opacity(0.8) : Color.gray.opacity(0.6))
                    .cornerRadius(6)
                }
            } else {
                // Guide Toggle (when YOLO not loaded)
                Button(action: { showGuide.toggle() }) {
                    Text(showGuide ? "👁️ Hide" : "👁️ Show")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.8))
                        .cornerRadius(6)
                }
            }
            
            // Settings
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 20))
                    .padding(8)
            }
        }
        .padding()
        .background(Color.black.opacity(0.6))
    }
}

// MARK: - Instructions View
struct InstructionsView: View {
    var body: some View {
        Text("Position the serial plate inside the green box")
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.7))
            .cornerRadius(8)
            .padding(.top, 10)
    }
}

// MARK: - Bottom Controls View
struct BottomControlsView: View {
    @ObservedObject var viewModel: ScannerViewModel
    @Binding var showResults: Bool
    var feedback: DetectionFeedback
    var isYoloLoaded: Bool
    
    // Determine capture button color based on YOLO feedback
    private var captureButtonColor: Color {
        if !isYoloLoaded {
            return .green
        }
        switch feedback.quality {
        case .perfect:
            return .green
        case .adjust, .warning:
            return .orange
        case .bad, .searching:
            return .gray
        }
    }
    
    // Quality text for display
    private var qualityText: String {
        switch feedback.quality {
        case .perfect: return "Perfect"
        case .adjust: return "Adjust"
        case .warning: return "Wait..."
        case .bad: return "Poor"
        case .searching: return "Searching"
        }
    }
    
    // Quality color
    private var qualityColor: Color {
        switch feedback.quality {
        case .perfect: return .green
        case .adjust: return .orange
        case .warning: return .yellow
        case .bad, .searching: return .red
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Tips or YOLO detection info
            if isYoloLoaded && feedback.detected {
                HStack(spacing: 16) {
                    // Confidence indicator (updated thresholds: 45% good, 60% great)
                    VStack(spacing: 2) {
                        Text("Confidence")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                        Text("\(Int(feedback.confidence * 100))%")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(feedback.confidence > 0.60 ? .green : feedback.confidence > 0.45 ? .yellow : .orange)
                    }
                    
                    // Fill indicator (uses largest dimension: 15-80% is ideal)
                    VStack(spacing: 2) {
                        Text("Size")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                        Text("\(feedback.fillPercent)%")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(feedback.fillPercent >= 15 && feedback.fillPercent <= 80 ? .green : .orange)
                    }
                    
                    // Focus indicator
                    VStack(spacing: 2) {
                        Text("Focus")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                        Text(feedback.isBlurry ? "Blurry" : "Sharp")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(feedback.isBlurry ? .red : .green)
                    }
                    
                    // Quality indicator
                    VStack(spacing: 2) {
                        Text("Quality")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                        Text(qualityText)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(qualityColor)
                    }
                }
            } else if isYoloLoaded {
                Text("🔍 Point camera at serial plate")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            } else {
                Text("💡 Fill 70% | Good lighting | Keep steady")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }
            
            // Capture Button
            Button(action: {
                viewModel.capturePhoto { success in
                    if success {
                        showResults = true
                    }
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .fill(captureButtonColor)
                        .frame(width: 64, height: 64)
                    
                    // Pulsing animation when perfect
                    if isYoloLoaded && feedback.quality == .perfect {
                        Circle()
                            .stroke(Color.green, lineWidth: 3)
                            .frame(width: 90, height: 90)
                            .scaleEffect(1.1)
                            .opacity(0.5)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: feedback.quality)
                    }
                }
            }
            .disabled(viewModel.isProcessing)
            
            // OCR Mode Indicator
            HStack(spacing: 16) {
                HStack {
                    Image(systemName: viewModel.useOnDeviceOCR ? "iphone" : "cloud.fill")
                        .foregroundColor(.white)
                    Text(viewModel.useOnDeviceOCR ? "On-Device OCR" : "Backend API")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
                
                if isYoloLoaded {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("YOLO Active")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding(.bottom, 40)
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.6))
    }
}

// MARK: - Processing Overlay
struct ProcessingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text("Processing...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(Color.black.opacity(0.8))
            .cornerRadius(16)
        }
    }
}

#Preview {
    ContentView()
}
