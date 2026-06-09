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

        let json = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "[]"
        records = ScanRecordCodec.records(fromJson: json)
    }

    /// Saves records to disk.
    private func saveToDisk() {
        do {
            try Data(ScanRecordCodec.json(for: records).utf8).write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save scan history: \(error)")
        }
    }

    /// Exports records to CSV. Built app-side (reading the SDK's ScanRecord
    /// fields) because the SDK's `CsvExporter.export(records:)` takes the
    /// ScanRecord obj-c type, which doesn't cross the SPM/Xcode-26 boundary.
    func exportCSV() -> String {
        let formatter = ISO8601DateFormatter()
        var out = "timestamp,total_ms,nfc_ms,nfc_calls,crypto_ms,gzip_ms,other_ms\n"
        for r in records {
            let ts = formatter.string(from: Date(timeIntervalSince1970: Double(r.metrics.timestampMs) / 1000.0))
            out += "\(ts),\(r.metrics.totalTimeMs),\(r.metrics.nfcTimeMs),\(r.metrics.nfcCallCount),"
            out += "\(r.metrics.totalCryptoTimeMs),\(r.metrics.gzipDecompressTimeMs),\(r.metrics.otherTimeMs)\n"
        }
        out += "\n# APDU Exchanges\nscan_timestamp,sequence,label,duration_ms,command,response\n"
        for r in records {
            let ts = formatter.string(from: Date(timeIntervalSince1970: Double(r.metrics.timestampMs) / 1000.0))
            for (i, e) in r.metrics.apduExchanges.enumerated() {
                out += "\(ts),\(i + 1),\"\(e.label.replacingOccurrences(of: ",", with: ";"))\",\(e.durationMs),\(e.command),\(e.response)\n"
            }
        }
        return out
    }

    // MARK: - Computed Statistics (app-side; SDK ScanStatistics takes ScanRecord)

    var totalScans: Int { records.count }
    var averageTotalTimeMs: Int64 { records.isEmpty ? 0 : records.map { $0.metrics.totalTimeMs }.reduce(0, +) / Int64(records.count) }
    var minTotalTimeMs: Int64 { records.map { $0.metrics.totalTimeMs }.min() ?? 0 }
    var maxTotalTimeMs: Int64 { records.map { $0.metrics.totalTimeMs }.max() ?? 0 }
    var averageNfcTimeMs: Int64 { records.isEmpty ? 0 : records.map { $0.metrics.nfcTimeMs }.reduce(0, +) / Int64(records.count) }
    var averageCryptoTimeMs: Int64 { records.isEmpty ? 0 : records.map { $0.metrics.totalCryptoTimeMs }.reduce(0, +) / Int64(records.count) }
}