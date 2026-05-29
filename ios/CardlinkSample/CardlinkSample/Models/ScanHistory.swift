import Foundation
import SwiftUI
import ScoopCardlink

/// Manages the history of card scans with persistence to JSON file.
@MainActor
class ScanHistory: ObservableObject {
    @Published private(set) var records: [ScanRecord] = []

    private let fileURL: URL

    init() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = documentsDirectory.appendingPathComponent("scan-history.json")
        loadFromDisk()
    }

    /// Adds a new scan record to the history.
    func add(_ record: ScanRecord) {
        records.append(record)
        saveToDisk()
    }

    /// Clears all scan history.
    func clear() {
        records.removeAll()
        saveToDisk()
    }

    /// Loads records from disk.
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            records = try JSONDecoder().decode([ScanRecord].self, from: data)
        } catch {
            print("Failed to load scan history: \(error)")
        }
    }

    /// Saves records to disk.
    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save scan history: \(error)")
        }
    }

    /// Exports records to CSV format using the SDK's CsvExporter.
    func exportCSV() -> String {
        let sdkRecords = records.map { $0.toSdkRecord() }
        let formatter = ISO8601DateFormatter()

        return CsvExporter.shared.export(records: sdkRecords) { timestampMs in
            let date = Date(timeIntervalSince1970: Double(truncating: timestampMs) / 1000.0)
            return formatter.string(from: date)
        }
    }

    // MARK: - Computed Statistics using SDK utilities

    private var sdkRecords: [ScoopCardlink.ScanRecord] {
        records.map { $0.toSdkRecord() }
    }

    private var stats: ScanStats {
        ScanStatistics.shared.calculateStats(records: sdkRecords)
    }

    var totalScans: Int { Int(stats.totalScans) }
    var averageTotalTimeMs: Int64 { stats.averageTotalTimeMs }
    var minTotalTimeMs: Int64 { stats.minTotalTimeMs }
    var maxTotalTimeMs: Int64 { stats.maxTotalTimeMs }
    var averageNfcTimeMs: Int64 { stats.averageNfcTimeMs }
    var averageCryptoTimeMs: Int64 { stats.averageCryptoTimeMs }
}