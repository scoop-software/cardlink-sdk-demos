import Foundation
import ScoopCardlink

// `ScanRecord` is defined ONCE, in the SDK (`ScoopCardlink.ScanRecord`).
// The demo adds only the Swift-app-side conveniences it needs on top of it —
// no parallel record type, no field duplication. Persistence/serialization is
// owned by the SDK (`scanRecordsToJson` / `scanRecordsFromJson`).

extension ScanRecord: Identifiable {}  // SDK already provides `id: String`

extension ScanRecord {
    /// Snapshot the SDK's current performance metrics into a record.
    static func fromPerformanceMetrics() -> ScanRecord {
        ScanRecord(id: UUID().uuidString, metrics: EgkReader.shared.getPerformanceMetricsSnapshot())
    }

    #if DEBUG
    /// Sample records for SwiftUI previews.
    static func sampleRecords(count: Int) -> [ScanRecord] {
        (0..<count).map { i in
            let totalTime = Int64.random(in: 3000...6000)
            let nfcTime = Int64.random(in: 2000...4000)
            let cryptoTime = Int64.random(in: 500...1500)
            let gzipTime = Int64.random(in: 10...100)
            let otherTime = totalTime - nfcTime - cryptoTime - gzipTime
            return ScanRecord(
                id: UUID().uuidString,
                metrics: PerformanceMetricsSnapshot(
                    timestampMs: Int64(Date().addingTimeInterval(Double(i) * -60).timeIntervalSince1970 * 1000),
                    totalTimeMs: totalTime,
                    nfcTimeMs: nfcTime,
                    nfcCallCount: Int32.random(in: 10...20),
                    totalCryptoTimeMs: cryptoTime,
                    aesCbcEncryptTimeMs: 100, aesCbcEncryptCount: 5,
                    aesCbcDecryptTimeMs: 100, aesCbcDecryptCount: 5,
                    aesCmacTimeMs: 50, aesCmacCount: 10,
                    sha1TimeMs: 30, sha1Count: 3,
                    sha256TimeMs: 40, sha256Count: 4,
                    ecKeyGenTimeMs: 20, ecKeyGenCount: 1,
                    ecScalarMultiplyTimeMs: 50, ecScalarMultiplyCount: 2,
                    ecPointAddTimeMs: 10, ecPointAddCount: 2,
                    gzipDecompressTimeMs: gzipTime, gzipDecompressCount: 2,
                    otherTimeMs: otherTime,
                    apduExchanges: [
                        ApduExchangeRecord(command: "00A4040007D276000102010000", response: "9000", durationMs: 45, label: "SELECT DF by AID"),
                        ApduExchangeRecord(command: "00220041", response: "9000", durationMs: 30, label: "MSE:Set AT"),
                        ApduExchangeRecord(command: "10860000", response: "9000", durationMs: 150, label: "GENERAL AUTHENTICATE"),
                        ApduExchangeRecord(command: "0CB00000", response: "9000", durationMs: 80, label: "SM:READ BINARY"),
                    ]
                )
            )
        }
    }
    #endif
}
