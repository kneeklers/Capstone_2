//
//  ScanHistory.swift
//  SerialNumberScanner
//
//  Data model and storage for scan history
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Scan Record Model
struct ScanRecord: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    var serialNumber: String?
    var partNumber: String?
    var confidence: Double?
    var notes: String?
    var wasEdited: Bool
    var imageFileName: String?  // Stored image file name
    
    init(serialNumber: String?, partNumber: String?, confidence: Double?, notes: String? = nil, wasEdited: Bool = false, imageFileName: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.serialNumber = serialNumber
        self.partNumber = partNumber
        self.confidence = confidence
        self.notes = notes
        self.wasEdited = wasEdited
        self.imageFileName = imageFileName
    }
    
    // Formatted timestamp
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    // CSV row
    var csvRow: String {
        let serial = serialNumber ?? ""
        let part = partNumber ?? ""
        let conf = confidence.map { String(format: "%.1f", $0 * 100) } ?? ""
        let note = notes ?? ""
        let edited = wasEdited ? "Yes" : "No"
        
        // Escape quotes in fields
        let escapedNote = note.replacingOccurrences(of: "\"", with: "\"\"")
        
        return "\"\(serial)\",\"\(part)\",\"\(conf)\",\"\(formattedDate)\",\"\(edited)\",\"\(escapedNote)\""
    }
}

// MARK: - Scan History Manager
class ScanHistoryManager: ObservableObject {
    @Published var records: [ScanRecord] = []
    
    private let saveKey = "ScanHistory"
    private let userDefaults = UserDefaults.standard
    
    // Image storage directory
    private var imagesDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagesPath = documentsPath.appendingPathComponent("ScanImages", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: imagesPath.path) {
            try? FileManager.default.createDirectory(at: imagesPath, withIntermediateDirectories: true)
        }
        
        return imagesPath
    }
    
    init() {
        loadRecords()
    }
    
    // MARK: - CRUD Operations
    
    func addRecord(_ record: ScanRecord) {
        records.insert(record, at: 0)  // Add to beginning (newest first)
        saveRecords()
    }
    
    func addRecord(serialNumber: String?, partNumber: String?, confidence: Double?, notes: String? = nil, wasEdited: Bool = false, image: UIImage? = nil) {
        var imageFileName: String? = nil
        
        // Save image if provided
        if let image = image {
            imageFileName = saveImage(image)
        }
        
        let record = ScanRecord(
            serialNumber: serialNumber,
            partNumber: partNumber,
            confidence: confidence,
            notes: notes,
            wasEdited: wasEdited,
            imageFileName: imageFileName
        )
        addRecord(record)
    }
    
    func deleteRecord(_ record: ScanRecord) {
        // Delete associated image
        if let fileName = record.imageFileName {
            deleteImage(fileName: fileName)
        }
        records.removeAll { $0.id == record.id }
        saveRecords()
    }
    
    func deleteRecords(at offsets: IndexSet) {
        // Delete associated images
        for index in offsets {
            if let fileName = records[index].imageFileName {
                deleteImage(fileName: fileName)
            }
        }
        records.remove(atOffsets: offsets)
        saveRecords()
    }
    
    func clearAll() {
        // Delete all images
        for record in records {
            if let fileName = record.imageFileName {
                deleteImage(fileName: fileName)
            }
        }
        records.removeAll()
        saveRecords()
    }
    
    func updateRecord(_ record: ScanRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
            saveRecords()
        }
    }
    
    // MARK: - Image Management
    
    func saveImage(_ image: UIImage) -> String? {
        let fileName = UUID().uuidString + ".jpg"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        
        // Compress and save
        if let data = image.jpegData(compressionQuality: 0.7) {
            do {
                try data.write(to: fileURL)
                return fileName
            } catch {
                print("Error saving image: \(error)")
            }
        }
        return nil
    }
    
    func loadImage(fileName: String) -> UIImage? {
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: fileURL) {
            return UIImage(data: data)
        }
        return nil
    }
    
    func getImage(for record: ScanRecord) -> UIImage? {
        guard let fileName = record.imageFileName else { return nil }
        return loadImage(fileName: fileName)
    }
    
    func deleteImage(fileName: String) {
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - Persistence
    
    private func saveRecords() {
        if let encoded = try? JSONEncoder().encode(records) {
            userDefaults.set(encoded, forKey: saveKey)
        }
    }
    
    private func loadRecords() {
        if let data = userDefaults.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([ScanRecord].self, from: data) {
            records = decoded
        }
    }
    
    // MARK: - Export
    
    func exportToCSV() -> String {
        var csv = "Serial Number,Part Number,Confidence (%),Date,Edited,Notes\n"
        for record in records {
            csv += record.csvRow + "\n"
        }
        return csv
    }
    
    func exportToJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        if let data = try? encoder.encode(records) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    // MARK: - Statistics
    
    var totalScans: Int {
        records.count
    }
    
    var todayScans: Int {
        let calendar = Calendar.current
        return records.filter { calendar.isDateInToday($0.timestamp) }.count
    }
    
    var averageConfidence: Double? {
        let confidences = records.compactMap { $0.confidence }
        guard !confidences.isEmpty else { return nil }
        return confidences.reduce(0, +) / Double(confidences.count)
    }
}
