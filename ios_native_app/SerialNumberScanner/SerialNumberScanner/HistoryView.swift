//
//  HistoryView.swift
//  SerialNumberScanner
//
//  View showing all saved scan results with export options
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyManager: ScanHistoryManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showExportSheet = false
    @State private var showPDFExport = false
    @State private var showClearConfirmation = false
    @State private var exportText = ""
    @State private var exportFileType = "csv"
    @State private var searchText = ""
    @State private var pdfURL: URL?
    
    var filteredRecords: [ScanRecord] {
        if searchText.isEmpty {
            return historyManager.records
        }
        return historyManager.records.filter { record in
            (record.serialNumber?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (record.partNumber?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (record.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Statistics Header
                if !historyManager.records.isEmpty {
                    statsHeader
                }
                
                // Records List
                if historyManager.records.isEmpty {
                    emptyState
                } else {
                    recordsList
                }
            }
            .navigationTitle("📋 Scan History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Section("With Images") {
                            Button(action: exportPDF) {
                                Label("Export PDF Report", systemImage: "doc.richtext")
                            }
                        }
                        
                        Section("Data Only") {
                            Button(action: exportCSV) {
                                Label("Export CSV", systemImage: "doc.text")
                            }
                            
                            Button(action: exportJSON) {
                                Label("Export JSON", systemImage: "doc.badge.gearshape")
                            }
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: { showClearConfirmation = true }) {
                            Label("Clear All", systemImage: "trash")
                        }
                        .disabled(historyManager.records.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search serial or part number")
            .alert("Clear All Records?", isPresented: $showClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    historyManager.clearAll()
                }
            } message: {
                Text("This will permanently delete all \(historyManager.totalScans) scan records.")
            }
            .sheet(isPresented: $showExportSheet) {
                ExportSheet(exportText: exportText, fileExtension: exportFileType)
            }
            .sheet(isPresented: $showPDFExport) {
                if let url = pdfURL {
                    PDFExportSheet(pdfURL: url)
                }
            }
        }
    }
    
    // MARK: - Stats Header
    private var statsHeader: some View {
        HStack(spacing: 20) {
            StatBox(title: "Total", value: "\(historyManager.totalScans)", color: .blue)
            StatBox(title: "Today", value: "\(historyManager.todayScans)", color: .green)
            if let avg = historyManager.averageConfidence {
                StatBox(title: "Avg Conf", value: "\(Int(avg * 100))%", color: .orange)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Scans Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Scan a serial plate and tap Save\nto add it to your history")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Records List
    private var recordsList: some View {
        VStack(spacing: 0) {
            List {
                ForEach(filteredRecords) { record in
                    RecordRow(record: record, historyManager: historyManager)
                }
                .onDelete { offsets in
                    // Map filtered offsets to actual indices
                    let recordsToDelete = offsets.map { filteredRecords[$0] }
                    for record in recordsToDelete {
                        historyManager.deleteRecord(record)
                    }
                }
            }
            .listStyle(.plain)
            
            // Clear All Button at bottom
            if !historyManager.records.isEmpty {
                Button(action: { showClearConfirmation = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear All History")
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .background(Color(.systemGray6))
            }
        }
    }
    
    // MARK: - Export Functions
    private func exportCSV() {
        exportText = historyManager.exportToCSV()
        exportFileType = "csv"
        showExportSheet = true
    }
    
    private func exportJSON() {
        exportText = historyManager.exportToJSON() ?? "Export failed"
        exportFileType = "json"
        showExportSheet = true
    }
    
    private func exportPDF() {
        // Generate PDF with images
        pdfURL = generatePDFReport()
        if pdfURL != nil {
            showPDFExport = true
        }
    }
    
    // Generate PDF report with images
    private func generatePDFReport() -> URL? {
        let pageWidth: CGFloat = 612  // US Letter width in points
        let pageHeight: CGFloat = 792 // US Letter height in points
        let margin: CGFloat = 40
        let contentWidth = pageWidth - (margin * 2)
        
        let pdfMetaData = [
            kCGPDFContextCreator: "Serial Number Scanner",
            kCGPDFContextAuthor: "Scan History Export",
            kCGPDFContextTitle: "Scan History Report"
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            format: format
        )
        
        let data = renderer.pdfData { context in
            var yPosition: CGFloat = margin
            var isFirstPage = true
            
            func startNewPageIfNeeded(neededHeight: CGFloat) {
                if yPosition + neededHeight > pageHeight - margin || isFirstPage {
                    context.beginPage()
                    yPosition = margin
                    
                    if isFirstPage {
                        // Draw title on first page
                        let titleAttributes: [NSAttributedString.Key: Any] = [
                            .font: UIFont.boldSystemFont(ofSize: 24),
                            .foregroundColor: UIColor.black
                        ]
                        let title = "Scan History Report"
                        title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
                        yPosition += 35
                        
                        // Date
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateStyle = .long
                        dateFormatter.timeStyle = .short
                        let dateStr = "Generated: \(dateFormatter.string(from: Date()))"
                        let dateAttributes: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 12),
                            .foregroundColor: UIColor.gray
                        ]
                        dateStr.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: dateAttributes)
                        yPosition += 25
                        
                        // Summary
                        let summary = "Total Scans: \(historyManager.totalScans)"
                        summary.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: dateAttributes)
                        yPosition += 40
                        
                        isFirstPage = false
                    }
                }
            }
            
            for (index, record) in historyManager.records.enumerated() {
                let recordHeight: CGFloat = 180 // Approximate height per record
                startNewPageIfNeeded(neededHeight: recordHeight)
                
                // Record number
                let headerAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: UIColor.darkGray
                ]
                let header = "Scan #\(index + 1) - \(record.formattedDate)"
                header.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: headerAttributes)
                yPosition += 20
                
                // Draw separator line
                let linePath = UIBezierPath()
                linePath.move(to: CGPoint(x: margin, y: yPosition))
                linePath.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
                UIColor.lightGray.setStroke()
                linePath.lineWidth = 0.5
                linePath.stroke()
                yPosition += 10
                
                // Image and details side by side
                let imageSize: CGFloat = 100
                var textX = margin
                
                // Draw image if available
                if let image = historyManager.getImage(for: record) {
                    let imageRect = CGRect(x: margin, y: yPosition, width: imageSize, height: imageSize)
                    image.draw(in: imageRect)
                    textX = margin + imageSize + 15
                }
                
                // Details
                let labelAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: UIColor.gray
                ]
                let valueAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: UIColor.black
                ]
                
                var detailY = yPosition
                
                // Serial Number
                "Serial Number:".draw(at: CGPoint(x: textX, y: detailY), withAttributes: labelAttributes)
                detailY += 14
                (record.serialNumber ?? "Not found").draw(at: CGPoint(x: textX, y: detailY), withAttributes: valueAttributes)
                detailY += 20
                
                // Part Number
                "Part Number:".draw(at: CGPoint(x: textX, y: detailY), withAttributes: labelAttributes)
                detailY += 14
                (record.partNumber ?? "Not found").draw(at: CGPoint(x: textX, y: detailY), withAttributes: valueAttributes)
                detailY += 20
                
                // Confidence
                if let conf = record.confidence {
                    "Confidence:".draw(at: CGPoint(x: textX, y: detailY), withAttributes: labelAttributes)
                    detailY += 14
                    "\(Int(conf * 100))%".draw(at: CGPoint(x: textX, y: detailY), withAttributes: valueAttributes)
                    detailY += 20
                }
                
                // Notes
                if let notes = record.notes, !notes.isEmpty {
                    "Notes:".draw(at: CGPoint(x: textX, y: detailY), withAttributes: labelAttributes)
                    detailY += 14
                    let notesAttr: [NSAttributedString.Key: Any] = [
                        .font: UIFont.italicSystemFont(ofSize: 11),
                        .foregroundColor: UIColor.darkGray
                    ]
                    notes.draw(at: CGPoint(x: textX, y: detailY), withAttributes: notesAttr)
                }
                
                yPosition += max(imageSize, 100) + 20
            }
        }
        
        // Save to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let fileName = "scan_report_\(dateFormatter.string(from: Date())).pdf"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Error saving PDF: \(error)")
            return nil
        }
    }
}

// MARK: - Stat Box
struct StatBox: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(10)
    }
}

// MARK: - Record Row
struct RecordRow: View {
    let record: ScanRecord
    let historyManager: ScanHistoryManager
    @State private var showDetail = false
    
    var body: some View {
        Button(action: { showDetail = true }) {
            HStack(spacing: 12) {
                // Thumbnail image
                if let image = historyManager.getImage(for: record) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                        .clipped()
                } else {
                    // Placeholder
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                }
                
                // Record info
                VStack(alignment: .leading, spacing: 4) {
                    // Date and confidence
                    HStack {
                        Text(record.formattedDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if record.wasEdited {
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        
                        if let conf = record.confidence {
                            Text("\(Int(conf * 100))%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(conf > 0.8 ? .green : conf > 0.5 ? .orange : .red)
                        }
                    }
                    
                    // Serial Number
                    HStack(spacing: 4) {
                        Text("S/N:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(record.serialNumber ?? "—")
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    
                    // Part Number
                    HStack(spacing: 4) {
                        Text("P/N:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(record.partNumber ?? "—")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            RecordDetailView(record: record, historyManager: historyManager)
        }
    }
}

// MARK: - Record Detail View
struct RecordDetailView: View {
    let record: ScanRecord
    let historyManager: ScanHistoryManager
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Image
                    if let image = historyManager.getImage(for: record) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray5))
                            .frame(height: 200)
                            .overlay(
                                VStack {
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundColor(.gray)
                                    Text("No image saved")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            )
                    }
                    
                    // Details card
                    VStack(alignment: .leading, spacing: 16) {
                        // Date
                        DetailRow(label: "Date", value: record.formattedDate, icon: "calendar")
                        
                        Divider()
                        
                        // Serial Number
                        DetailRow(label: "Serial Number", value: record.serialNumber ?? "Not found", icon: "number", copyable: record.serialNumber)
                        
                        Divider()
                        
                        // Part Number
                        DetailRow(label: "Part Number", value: record.partNumber ?? "Not found", icon: "shippingbox", copyable: record.partNumber)
                        
                        Divider()
                        
                        // Confidence
                        if let conf = record.confidence {
                            DetailRow(label: "Confidence", value: "\(Int(conf * 100))%", icon: "checkmark.seal")
                        }
                        
                        // Notes
                        if let notes = record.notes, !notes.isEmpty {
                            Divider()
                            DetailRow(label: "Notes", value: notes, icon: "note.text")
                        }
                        
                        // Edited badge
                        if record.wasEdited {
                            Divider()
                            HStack {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundColor(.orange)
                                Text("Values were manually edited")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Share button
                    if let image = historyManager.getImage(for: record) {
                        Button(action: { showShareSheet = true }) {
                            Label("Share Image & Details", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .sheet(isPresented: $showShareSheet) {
                            let text = """
                            Serial Number: \(record.serialNumber ?? "N/A")
                            Part Number: \(record.partNumber ?? "N/A")
                            Date: \(record.formattedDate)
                            """
                            ShareSheetView(items: [image, text])
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Scan Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let label: String
    let value: String
    let icon: String
    var copyable: String? = nil
    
    @State private var showCopied = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(.body, design: .monospaced))
            }
            
            Spacer()
            
            if let copyValue = copyable {
                Button(action: {
                    UIPasteboard.general.string = copyValue
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                }) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .foregroundColor(showCopied ? .green : .blue)
                }
            }
        }
    }
}

// MARK: - Share Sheet (UIKit wrapper)
struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - PDF Export Sheet
struct PDFExportSheet: View {
    let pdfURL: URL
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // PDF Icon and info
                VStack(spacing: 12) {
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    
                    Text(pdfURL.lastPathComponent)
                        .font(.headline)
                    
                    Text("PDF Report with Images")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                // Preview hint
                VStack(spacing: 8) {
                    Image(systemName: "eye")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text("The PDF includes all scan images and details")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
                
                // Actions
                VStack(spacing: 12) {
                    // Share button
                    ShareLink(item: pdfURL) {
                        Label("Share / Save PDF", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    // Quick actions
                    HStack(spacing: 12) {
                        // Preview in Quick Look would require QLPreviewController
                        // For simplicity, just provide share
                        
                        Button(action: {
                            // Open in Files app
                            if let filesURL = URL(string: "shareddocuments://\(pdfURL.path)") {
                                UIApplication.shared.open(filesURL)
                            }
                        }) {
                            Label("Open", systemImage: "doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            UIPasteboard.general.url = pdfURL
                        }) {
                            Label("Copy Link", systemImage: "link")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Text("Tap 'Share' → 'Save to Files' to save the PDF")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("PDF Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Export Sheet
struct ExportSheet: View {
    let exportText: String
    let fileExtension: String  // "csv" or "json"
    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedToast = false
    @State private var showSavedToast = false
    @State private var showShareSheet = false
    
    var fileName: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        return "scan_history_\(dateString).\(fileExtension)"
    }
    
    // Create file URL
    var fileURL: URL {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent(fileName)
        try? exportText.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // File info
                HStack {
                    Image(systemName: fileExtension == "csv" ? "tablecells" : "doc.badge.gearshape")
                        .font(.title)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading) {
                        Text(fileName)
                            .font(.headline)
                        Text(fileExtension.uppercased() + " file • \(exportText.count) characters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()
                
                // Preview
                ScrollView {
                    Text(exportText)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .frame(maxHeight: 300)
                
                Spacer()
                
                // Actions
                VStack(spacing: 12) {
                    // Share/Save button - this opens iOS share sheet where user can "Save to Files"
                    ShareLink(item: fileURL) {
                        Label("Share / Save to Files", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    // Copy button
                    Button(action: copyToClipboard) {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    // Instructions
                    Text("Tap 'Share' then choose 'Save to Files' to save the \(fileExtension.uppercased()) file")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle("Export \(fileExtension.uppercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .overlay(toastOverlay)
        }
    }
    
    // Toast overlay
    private var toastOverlay: some View {
        VStack {
            Spacer()
            
            if showCopiedToast {
                Text("✓ Copied to clipboard")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(20)
                    .padding(.bottom, 50)
            }
        }
        .animation(.easeInOut, value: showCopiedToast)
    }
    
    // Copy to clipboard
    private func copyToClipboard() {
        UIPasteboard.general.string = exportText
        showCopiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedToast = false
        }
    }
}

#Preview {
    HistoryView(historyManager: {
        let manager = ScanHistoryManager()
        manager.addRecord(serialNumber: "HJ023764-F", partNumber: "45731-1423", confidence: 0.95, image: nil)
        manager.addRecord(serialNumber: "GRT61846", partNumber: "2496M44P04", confidence: 0.88, wasEdited: true, image: nil)
        manager.addRecord(serialNumber: "1P002106", partNumber: "362-001-242-0H-S", confidence: 0.92, image: nil)
        return manager
    }())
}
