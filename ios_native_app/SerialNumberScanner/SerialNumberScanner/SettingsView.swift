//
//  SettingsView.swift
//  SerialNumberScanner
//
//  Settings for OCR mode and backend configuration
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ScannerViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // OCR Mode Section
                Section(header: Text("OCR Mode")) {
                    Toggle(isOn: $viewModel.useOnDeviceOCR) {
                        HStack {
                            Image(systemName: viewModel.useOnDeviceOCR ? "iphone" : "cloud.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(viewModel.useOnDeviceOCR ? "On-Device OCR" : "Backend API")
                                    .font(.body)
                                Text(viewModel.useOnDeviceOCR ? "Apple Vision Framework" : "Python YOLO Server")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if viewModel.useOnDeviceOCR {
                        onDeviceInfoView
                    } else {
                        backendConfigView
                    }
                }
                
                // YOLO Cropping Section
                Section(header: Text("Accuracy Enhancement")) {
                    Toggle(isOn: $viewModel.useYOLOCropping) {
                        HStack {
                            Image(systemName: "crop")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text("YOLO Smart Cropping")
                                    .font(.body)
                                Text("Crop to detected plate before OCR")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if viewModel.useYOLOCropping {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Reduces background noise", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            Label("Improves OCR accuracy ~10-15%", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Image Preprocessing Toggle
                    Toggle(isOn: $viewModel.usePreprocessing) {
                        HStack {
                            Image(systemName: "wand.and.stars")
                                .foregroundColor(.purple)
                            VStack(alignment: .leading) {
                                Text("Image Preprocessing")
                                    .font(.body)
                                Text("Enhance contrast & sharpness")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if viewModel.usePreprocessing {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Grayscale conversion", systemImage: "circle.lefthalf.filled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Label("Contrast enhancement (+30%)", systemImage: "sun.max")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Label("Edge sharpening", systemImage: "lines.measurement.horizontal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Label("Shadow/highlight adjustment", systemImage: "circle.righthalf.filled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("⚠️ Raw image sent to OCR (may struggle with low contrast)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                // About Section
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("OCR Engine")
                        Spacer()
                        Text(viewModel.useOnDeviceOCR ? "Apple Vision" : "Python Backend")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Tips Section
                Section(header: Text("Tips for Best Results")) {
                    TipRow(icon: "sun.max", text: "Ensure good lighting conditions")
                    TipRow(icon: "viewfinder", text: "Fill 70% of the frame with the plate")
                    TipRow(icon: "hand.raised", text: "Hold the camera steady")
                    TipRow(icon: "photo", text: "Avoid glare and reflections")
                    TipRow(icon: "angle", text: "Capture straight-on, not at an angle")
                }
                
            }
            .navigationTitle("⚙️ Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - On-Device Info View
    private var onDeviceInfoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Works offline", systemImage: "wifi.slash")
                .font(.caption)
                .foregroundColor(.green)
            
            Label("Fast processing", systemImage: "bolt.fill")
                .font(.caption)
                .foregroundColor(.green)
            
            Label("Privacy-focused", systemImage: "lock.fill")
                .font(.caption)
                .foregroundColor(.green)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Backend Config View
    private var backendConfigView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backend URL")
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextField("http://192.168.1.100:8000", text: $viewModel.backendURL)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.URL)
            
            Text("💡 Run 'python api_server.py' on your Mac and enter its IP address")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(action: testConnection) {
                HStack {
                    Image(systemName: "network")
                    Text("Test Connection")
                }
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Test Connection
    private func testConnection() {
        guard let url = URL(string: "\(viewModel.backendURL)/health") else {
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    // Show success
                    print("Connection successful!")
                } else {
                    // Show error
                    print("Connection failed: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }.resume()
    }
}

// MARK: - Tip Row
struct TipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    SettingsView(viewModel: ScannerViewModel())
}
