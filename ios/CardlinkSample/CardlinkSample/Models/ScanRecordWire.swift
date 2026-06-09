import Foundation
import ScoopCardlink

// JSON wire format for on-disk persistence of the SDK's `ScanRecord` type.
// This is NOT a second record type — it carries no behavior, only the field
// layout used to encode/decode scan history. `ScanRecord` is a Kotlin/obj-c
// class (not Swift `Codable`), so the app owns its own persistence format here.
private struct ScanRecordWire: Codable {
    let id: String
    let timestampMs: Int64
    let totalTimeMs: Int64
    let nfcTimeMs: Int64
    let nfcCallCount: Int32
    let totalCryptoTimeMs: Int64
    let aesCbcEncryptTimeMs: Int64
    let aesCbcEncryptCount: Int32
    let aesCbcDecryptTimeMs: Int64
    let aesCbcDecryptCount: Int32
    let aesCmacTimeMs: Int64
    let aesCmacCount: Int32
    let sha1TimeMs: Int64
    let sha1Count: Int32
    let sha256TimeMs: Int64
    let sha256Count: Int32
    let ecKeyGenTimeMs: Int64
    let ecKeyGenCount: Int32
    let ecScalarMultiplyTimeMs: Int64
    let ecScalarMultiplyCount: Int32
    let ecPointAddTimeMs: Int64
    let ecPointAddCount: Int32
    let gzipDecompressTimeMs: Int64
    let gzipDecompressCount: Int32
    let otherTimeMs: Int64
    let apduExchanges: [ApduWire]

    struct ApduWire: Codable {
        let command: String
        let response: String
        let durationMs: Int64
        let label: String
    }

    init(_ r: ScanRecord) {
        let m = r.metrics
        id = r.id
        timestampMs = m.timestampMs
        totalTimeMs = m.totalTimeMs
        nfcTimeMs = m.nfcTimeMs
        nfcCallCount = m.nfcCallCount
        totalCryptoTimeMs = m.totalCryptoTimeMs
        aesCbcEncryptTimeMs = m.aesCbcEncryptTimeMs
        aesCbcEncryptCount = m.aesCbcEncryptCount
        aesCbcDecryptTimeMs = m.aesCbcDecryptTimeMs
        aesCbcDecryptCount = m.aesCbcDecryptCount
        aesCmacTimeMs = m.aesCmacTimeMs
        aesCmacCount = m.aesCmacCount
        sha1TimeMs = m.sha1TimeMs
        sha1Count = m.sha1Count
        sha256TimeMs = m.sha256TimeMs
        sha256Count = m.sha256Count
        ecKeyGenTimeMs = m.ecKeyGenTimeMs
        ecKeyGenCount = m.ecKeyGenCount
        ecScalarMultiplyTimeMs = m.ecScalarMultiplyTimeMs
        ecScalarMultiplyCount = m.ecScalarMultiplyCount
        ecPointAddTimeMs = m.ecPointAddTimeMs
        ecPointAddCount = m.ecPointAddCount
        gzipDecompressTimeMs = m.gzipDecompressTimeMs
        gzipDecompressCount = m.gzipDecompressCount
        otherTimeMs = m.otherTimeMs
        apduExchanges = m.apduExchanges.map {
            ApduWire(command: $0.command, response: $0.response, durationMs: $0.durationMs, label: $0.label)
        }
    }

    func toRecord() -> ScanRecord {
        ScanRecord(id: id, metrics: PerformanceMetricsSnapshot(
            timestampMs: timestampMs,
            totalTimeMs: totalTimeMs,
            nfcTimeMs: nfcTimeMs,
            nfcCallCount: nfcCallCount,
            totalCryptoTimeMs: totalCryptoTimeMs,
            aesCbcEncryptTimeMs: aesCbcEncryptTimeMs,
            aesCbcEncryptCount: aesCbcEncryptCount,
            aesCbcDecryptTimeMs: aesCbcDecryptTimeMs,
            aesCbcDecryptCount: aesCbcDecryptCount,
            aesCmacTimeMs: aesCmacTimeMs,
            aesCmacCount: aesCmacCount,
            sha1TimeMs: sha1TimeMs,
            sha1Count: sha1Count,
            sha256TimeMs: sha256TimeMs,
            sha256Count: sha256Count,
            ecKeyGenTimeMs: ecKeyGenTimeMs,
            ecKeyGenCount: ecKeyGenCount,
            ecScalarMultiplyTimeMs: ecScalarMultiplyTimeMs,
            ecScalarMultiplyCount: ecScalarMultiplyCount,
            ecPointAddTimeMs: ecPointAddTimeMs,
            ecPointAddCount: ecPointAddCount,
            gzipDecompressTimeMs: gzipDecompressTimeMs,
            gzipDecompressCount: gzipDecompressCount,
            otherTimeMs: otherTimeMs,
            apduExchanges: apduExchanges.map {
                ApduExchangeRecord(command: $0.command, response: $0.response, durationMs: $0.durationMs, label: $0.label)
            }
        ))
    }
}

enum ScanRecordCodec {
    /// Many scans → JSON array string (for on-disk persistence).
    static func json(for records: [ScanRecord]) -> String {
        (try? String(data: JSONEncoder().encode(records.map(ScanRecordWire.init)), encoding: .utf8)) ?? "[]"
    }

    /// JSON array string → scans.
    static func records(fromJson json: String) -> [ScanRecord] {
        guard let data = json.data(using: .utf8),
              let wires = try? JSONDecoder().decode([ScanRecordWire].self, from: data) else { return [] }
        return wires.map { $0.toRecord() }
    }
}
