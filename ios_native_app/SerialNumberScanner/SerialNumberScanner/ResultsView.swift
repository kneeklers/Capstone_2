//
//  ResultsView.swift
//  SerialNumberScanner
//
//  Results sheet showing extracted serial number and part number
//

import SwiftUI

struct ResultsView: View {
    @ObservedObject var viewModel: ScannerViewModel
    @ObservedObject var historyManager: ScanHistoryManager
    @Binding var isPresented: Bool
    
    @State private var editedSerial: String = ""
    @State private var editedPartNumber: String = ""
    @State private var notes: String = ""
    @State private var isEdited = false
    @State private var showCopiedToast = false
    @State private var showSavedToast = false
    @State private var showOriginalImage = false  // Toggle to view original vs cropped
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerView
                    
                    // Captured Image Preview
                    if let image = viewModel.capturedImage {
                        imagePreview(image)
                    }
                    
                    // Serial Number Section
                    resultSection(
                        icon: "🔢",
                        title: "Serial Number",
                        value: $editedSerial,
                        original: viewModel.serialNumber
                    )
                    
                    // Part Number Section
                    resultSection(
                        icon: "📦",
                        title: "Part Number",
                        value: $editedPartNumber,
                        original: viewModel.partNumber
                    )
                    
                    // Confidence Metrics
                    if let confidence = viewModel.confidence {
                        confidenceView(confidence: confidence)
                    }
                    
                    // Notes field
                    notesSection
                    
                    // All Recognized Text (expandable)
                    if !viewModel.allRecognizedText.isEmpty {
                        allTextView
                    }
                    
                    // Action Buttons
                    actionButtons
                    
                    // Scan count indicator
                    Text("📊 \(historyManager.totalScans) scans saved")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("✅ Extraction Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.title2)
                    }
                }
            }
        }
        .onAppear {
            editedSerial = viewModel.serialNumber ?? ""
            editedPartNumber = viewModel.partNumber ?? ""
            notes = ""
        }
        .overlay(toastOverlay)
        .overlay(savedToastOverlay)
    }
    
    // MARK: - Header
    private var headerView: some View {
        VStack(spacing: 8) {
            if viewModel.serialNumber != nil || viewModel.partNumber != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                
                Text("Text Successfully Recognized")
                    .font(.headline)
                    .foregroundColor(.green)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("No Serial/Part Number Found")
                    .font(.headline)
                    .foregroundColor(.orange)
            }
        }
        .padding()
    }
    
    // MARK: - Image Preview
    private func imagePreview(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with toggle if YOLO cropping was used
            HStack {
                if viewModel.wasYOLOCropped {
                    Text(showOriginalImage ? "📷 Original Image" : "✂️ Cropped Plate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Toggle button to switch views
                    Button(action: { showOriginalImage.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: showOriginalImage ? "crop" : "photo")
                                .font(.system(size: 12))
                            Text(showOriginalImage ? "Show Cropped" : "Show Original")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                } else {
                    Text("📷 Captured Image")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            // Show appropriate image
            let displayImage = (showOriginalImage && viewModel.originalImage != nil) 
                ? viewModel.originalImage! 
                : image
            
            Image(uiImage: displayImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(viewModel.wasYOLOCropped && !showOriginalImage ? Color.green : Color.gray.opacity(0.3), lineWidth: viewModel.wasYOLOCropped && !showOriginalImage ? 2 : 1)
                )
            
            // YOLO cropping indicator
            if viewModel.wasYOLOCropped && !showOriginalImage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text("YOLO Smart Crop applied")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
        }
    }
    
    // MARK: - Result Section
    private func resultSection(icon: String, title: String, value: Binding<String>, original: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(icon) \(title)")
                    .font(.system(size: 16, weight: .semibold))
                
                Spacer()
                
                if let orig = original, !orig.isEmpty {
                    Button(action: {
                        UIPasteboard.general.string = value.wrappedValue
                        showCopiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showCopiedToast = false
                        }
                    }) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.blue)
                    }
                }
            }
            
            if original != nil && !original!.isEmpty {
                TextField("Enter \(title.lowercased())", text: value)
                    .textFieldStyle(ResultTextFieldStyle())
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundColor(.black)
                    .accentColor(.green)
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                    .onChange(of: value.wrappedValue) { _ in
                        isEdited = true
                    }
                
                if isEdited && value.wrappedValue != original {
                    Text("⚠️ Modified from: \(original ?? "")")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else {
                Text("❌ Not found")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Confidence View
    private func confidenceView(confidence: Double) -> some View {
        HStack(spacing: 20) {
            VStack {
                Text("OCR Confidence")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(Int(confidence * 100))%")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(confidenceColor(confidence))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }
    
    // MARK: - Notes Section
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📝 Notes (optional)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            TextField("Add notes about this scan...", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - All Text View
    private var allTextView: some View {
        DisclosureGroup("📝 All Recognized Text (\(viewModel.allRecognizedText.count) lines)") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.allRecognizedText, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Action Buttons
    private var actionButtons: some View {
        HStack(spacing: 16) {
            // Retake Button
            Button(action: {
                viewModel.reset()
                isPresented = false
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Retake")
                }
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .cornerRadius(12)
            }
            
            // Save Button
            Button(action: {
                saveResults()
            }) {
                HStack {
                    Image(systemName: "checkmark")
                    Text("Save")
                }
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding(.top)
    }
    
    // MARK: - Toast Overlay
    private var toastOverlay: some View {
        Group {
            if showCopiedToast {
                VStack {
                    Spacer()
                    
                    Text("✓ Copied to clipboard")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(25)
                        .padding(.bottom, 50)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeInOut, value: showCopiedToast)
            }
        }
    }
    
    // MARK: - Save Results
    private func saveResults() {
        // Determine if values were edited
        let wasEdited = (editedSerial != (viewModel.serialNumber ?? "")) ||
                        (editedPartNumber != (viewModel.partNumber ?? ""))
        
        // Save to history with image
        historyManager.addRecord(
            serialNumber: editedSerial.isEmpty ? nil : editedSerial,
            partNumber: editedPartNumber.isEmpty ? nil : editedPartNumber,
            confidence: viewModel.confidence,
            notes: notes.isEmpty ? nil : notes,
            wasEdited: wasEdited,
            image: viewModel.capturedImage  // Save the captured image
        )
        
        print("✅ Saved to history:")
        print("  Serial: \(editedSerial)")
        print("  Part Number: \(editedPartNumber)")
        print("  Image saved: \(viewModel.capturedImage != nil)")
        print("  Total records: \(historyManager.totalScans)")
        
        // Show saved toast then dismiss
        showSavedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isPresented = false
        }
    }
}

// MARK: - Saved Toast Extension
extension ResultsView {
    var savedToastOverlay: some View {
        Group {
            if showSavedToast {
                VStack {
                    Spacer()
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved to history!")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(25)
                    .padding(.bottom, 100)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeInOut, value: showSavedToast)
            }
        }
    }
}

// MARK: - Custom Text Field Style
struct ResultTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .foregroundColor(.black)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green, lineWidth: 2)
            )
    }
}

#Preview {
    ResultsView(
        viewModel: {
            let vm = ScannerViewModel()
            vm.serialNumber = "ABC123456789"
            vm.partNumber = "PN-2024-001"
            vm.confidence = 0.95
            vm.allRecognizedText = ["S/N: ABC123456789", "P/N: PN-2024-001", "Made in USA"]
            return vm
        }(),
        historyManager: ScanHistoryManager(),
        isPresented: .constant(true)
    )
}
