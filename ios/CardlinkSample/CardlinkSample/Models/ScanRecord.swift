import Foundation
import ScoopCardlink

/// Wraps PerformanceMetricsSnapshot with Identifiable conformance and computed properties for charts.
struct ScanRecord: Identifiable {
    let id: UUID
    let metrics: PerformanceMetricsSnapshot

    /// Creates a ScanRecord from the SDK's current PerformanceMetrics.
    static func fromPerformanceMetrics() -> ScanRecord {
        ScanRecord(
            id: UUID(),
            metrics: EgkReader.shared.getPerformanceMetricsSnapshot()
        )
    }

    // MARK: - Delegated Properties

    var timestamp: Date {
        Date(timeIntervalSince1970: Double(metrics.timestampMs) / 1000.0)
    }

    var totalTimeMs: Int64 { metrics.totalTimeMs }
    var nfcTimeMs: Int64 { metrics.nfcTimeMs }
    var nfcCallCount: Int { Int(metrics.nfcCallCount) }
    var cryptoTimeMs: Int64 { metrics.totalCryptoTimeMs }
    var gzipTimeMs: Int64 { metrics.gzipDecompressTimeMs }
    var otherTimeMs: Int64 { metrics.otherTimeMs }

    var aesCbcEncryptTimeMs: Int64 { metrics.aesCbcEncryptTimeMs }
    var aesCbcEncryptCount: Int { Int(metrics.aesCbcEncryptCount) }
    var aesCbcDecryptTimeMs: Int64 { metrics.aesCbcDecryptTimeMs }
    var aesCbcDecryptCount: Int { Int(metrics.aesCbcDecryptCount) }
    var aesCmacTimeMs: Int64 { metrics.aesCmacTimeMs }
    var aesCmacCount: Int { Int(metrics.aesCmacCount) }
    var sha1TimeMs: Int64 { metrics.sha1TimeMs }
    var sha1Count: Int { Int(metrics.sha1Count) }
    var sha256TimeMs: Int64 { metrics.sha256TimeMs }
    var sha256Count: Int { Int(metrics.sha256Count) }
    var ecKeyGenTimeMs: Int64 { metrics.ecKeyGenTimeMs }
    var ecKeyGenCount: Int { Int(metrics.ecKeyGenCount) }
    var ecScalarMultiplyTimeMs: Int64 { metrics.ecScalarMultiplyTimeMs }
    var ecScalarMultiplyCount: Int { Int(metrics.ecScalarMultiplyCount) }
    var ecPointAddTimeMs: Int64 { metrics.ecPointAddTimeMs }
    var ecPointAddCount: Int { Int(metrics.ecPointAddCount) }
    var gzipDecompressCount: Int { Int(metrics.gzipDecompressCount) }
    var apduExchanges: [ApduExchangeRecord] { Array(metrics.apduExchanges) }

    // MARK: - Computed Properties for Charts

    var nfcPercentage: Double {
        guard totalTimeMs > 0 else { return 0 }
        return Double(nfcTimeMs) / Double(totalTimeMs) * 100
    }

    var cryptoPercentage: Double {
        guard totalTimeMs > 0 else { return 0 }
        return Double(cryptoTimeMs) / Double(totalTimeMs) * 100
    }

    var gzipPercentage: Double {
        guard totalTimeMs > 0 else { return 0 }
        return Double(gzipTimeMs) / Double(totalTimeMs) * 100
    }

    var otherPercentage: Double {
        guard totalTimeMs > 0 else { return 0 }
        return Double(otherTimeMs) / Double(totalTimeMs) * 100
    }

    var avgNfcRoundtripMs: Int64 {
        guard nfcCallCount > 0 else { return 0 }
        return nfcTimeMs / Int64(nfcCallCount)
    }

    // MARK: - SDK Conversion

    /// Converts this Swift ScanRecord to the SDK's ScanRecord for use with SDK utilities.
    func toSdkRecord() -> ScoopCardlink.ScanRecord {
        ScoopCardlink.ScanRecord(id: id.uuidString, metrics: metrics)
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension ScanRecord {
    /// Creates sample records for SwiftUI previews.
    static func sampleRecords(count: Int) -> [ScanRecord] {
        (0..<count).map { i in
            let totalTime = Int64.random(in: 3000...6000)
            let nfcTime = Int64.random(in: 2000...4000)
            let cryptoTime = Int64.random(in: 500...1500)
            let gzipTime = Int64.random(in: 10...100)
            let otherTime = totalTime - nfcTime - cryptoTime - gzipTime

            return ScanRecord(
                id: UUID(),
                metrics: PerformanceMetricsSnapshot(
                    timestampMs: Int64(Date().addingTimeInterval(Double(i) * -60).timeIntervalSince1970 * 1000),
                    totalTimeMs: totalTime,
                    nfcTimeMs: nfcTime,
                    nfcCallCount: Int32.random(in: 10...20),
                    totalCryptoTimeMs: cryptoTime,
                    aesCbcEncryptTimeMs: 100,
                    aesCbcEncryptCount: 5,
                    aesCbcDecryptTimeMs: 100,
                    aesCbcDecryptCount: 5,
                    aesCmacTimeMs: 50,
                    aesCmacCount: 10,
                    sha1TimeMs: 30,
                    sha1Count: 3,
                    sha256TimeMs: 40,
                    sha256Count: 4,
                    ecKeyGenTimeMs: 20,
                    ecKeyGenCount: 1,
                    ecScalarMultiplyTimeMs: 50,
                    ecScalarMultiplyCount: 2,
                    ecPointAddTimeMs: 10,
                    ecPointAddCount: 2,
                    gzipDecompressTimeMs: gzipTime,
                    gzipDecompressCount: 2,
                    otherTimeMs: otherTime,
                    apduExchanges: Self.sampleApduExchanges()
                )
            )
        }
    }

    private static func sampleApduExchanges() -> [ApduExchangeRecord] {
        [
            ApduExchangeRecord(command: "00A4040007D276000102010000", response: "9000", durationMs: 45, label: "SELECT DF by AID"),
            ApduExchangeRecord(command: "00220041", response: "9000", durationMs: 30, label: "MSE:Set AT"),
            ApduExchangeRecord(command: "10860000", response: "9000", durationMs: 150, label: "GENERAL AUTHENTICATE"),
            ApduExchangeRecord(command: "10860000", response: "9000", durationMs: 120, label: "GENERAL AUTHENTICATE"),
            ApduExchangeRecord(command: "10860000", response: "9000", durationMs: 180, label: "GENERAL AUTHENTICATE"),
            ApduExchangeRecord(command: "00860000", response: "9000", durationMs: 200, label: "GENERAL AUTHENTICATE"),
            ApduExchangeRecord(command: "0CB00000", response: "9000", durationMs: 80, label: "SM:READ BINARY"),
            ApduExchangeRecord(command: "0CB00000", response: "9000", durationMs: 75, label: "SM:READ BINARY"),
            ApduExchangeRecord(command: "0CB00000", response: "9000", durationMs: 90, label: "SM:READ BINARY"),
        ]
    }
}
#endif

// MARK: - Codable Conformance for Persistence

extension ScanRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case id, metrics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)

        // Decode metrics manually since PerformanceMetricsSnapshot comes from Kotlin
        let metricsContainer = try container.nestedContainer(keyedBy: MetricsCodingKeys.self, forKey: .metrics)
        metrics = PerformanceMetricsSnapshot(
            timestampMs: try metricsContainer.decode(Int64.self, forKey: .timestampMs),
            totalTimeMs: try metricsContainer.decode(Int64.self, forKey: .totalTimeMs),
            nfcTimeMs: try metricsContainer.decode(Int64.self, forKey: .nfcTimeMs),
            nfcCallCount: try metricsContainer.decode(Int32.self, forKey: .nfcCallCount),
            totalCryptoTimeMs: try metricsContainer.decode(Int64.self, forKey: .totalCryptoTimeMs),
            aesCbcEncryptTimeMs: try metricsContainer.decode(Int64.self, forKey: .aesCbcEncryptTimeMs),
            aesCbcEncryptCount: try metricsContainer.decode(Int32.self, forKey: .aesCbcEncryptCount),
            aesCbcDecryptTimeMs: try metricsContainer.decode(Int64.self, forKey: .aesCbcDecryptTimeMs),
            aesCbcDecryptCount: try metricsContainer.decode(Int32.self, forKey: .aesCbcDecryptCount),
            aesCmacTimeMs: try metricsContainer.decode(Int64.self, forKey: .aesCmacTimeMs),
            aesCmacCount: try metricsContainer.decode(Int32.self, forKey: .aesCmacCount),
            sha1TimeMs: try metricsContainer.decode(Int64.self, forKey: .sha1TimeMs),
            sha1Count: try metricsContainer.decode(Int32.self, forKey: .sha1Count),
            sha256TimeMs: try metricsContainer.decode(Int64.self, forKey: .sha256TimeMs),
            sha256Count: try metricsContainer.decode(Int32.self, forKey: .sha256Count),
            ecKeyGenTimeMs: try metricsContainer.decode(Int64.self, forKey: .ecKeyGenTimeMs),
            ecKeyGenCount: try metricsContainer.decode(Int32.self, forKey: .ecKeyGenCount),
            ecScalarMultiplyTimeMs: try metricsContainer.decode(Int64.self, forKey: .ecScalarMultiplyTimeMs),
            ecScalarMultiplyCount: try metricsContainer.decode(Int32.self, forKey: .ecScalarMultiplyCount),
            ecPointAddTimeMs: try metricsContainer.decode(Int64.self, forKey: .ecPointAddTimeMs),
            ecPointAddCount: try metricsContainer.decode(Int32.self, forKey: .ecPointAddCount),
            gzipDecompressTimeMs: try metricsContainer.decode(Int64.self, forKey: .gzipDecompressTimeMs),
            gzipDecompressCount: try metricsContainer.decode(Int32.self, forKey: .gzipDecompressCount),
            otherTimeMs: try metricsContainer.decode(Int64.self, forKey: .otherTimeMs),
            apduExchanges: try metricsContainer.decodeApduExchanges(forKey: .apduExchanges)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)

        var metricsContainer = container.nestedContainer(keyedBy: MetricsCodingKeys.self, forKey: .metrics)
        try metricsContainer.encode(metrics.timestampMs, forKey: .timestampMs)
        try metricsContainer.encode(metrics.totalTimeMs, forKey: .totalTimeMs)
        try metricsContainer.encode(metrics.nfcTimeMs, forKey: .nfcTimeMs)
        try metricsContainer.encode(metrics.nfcCallCount, forKey: .nfcCallCount)
        try metricsContainer.encode(metrics.totalCryptoTimeMs, forKey: .totalCryptoTimeMs)
        try metricsContainer.encode(metrics.aesCbcEncryptTimeMs, forKey: .aesCbcEncryptTimeMs)
        try metricsContainer.encode(metrics.aesCbcEncryptCount, forKey: .aesCbcEncryptCount)
        try metricsContainer.encode(metrics.aesCbcDecryptTimeMs, forKey: .aesCbcDecryptTimeMs)
        try metricsContainer.encode(metrics.aesCbcDecryptCount, forKey: .aesCbcDecryptCount)
        try metricsContainer.encode(metrics.aesCmacTimeMs, forKey: .aesCmacTimeMs)
        try metricsContainer.encode(metrics.aesCmacCount, forKey: .aesCmacCount)
        try metricsContainer.encode(metrics.sha1TimeMs, forKey: .sha1TimeMs)
        try metricsContainer.encode(metrics.sha1Count, forKey: .sha1Count)
        try metricsContainer.encode(metrics.sha256TimeMs, forKey: .sha256TimeMs)
        try metricsContainer.encode(metrics.sha256Count, forKey: .sha256Count)
        try metricsContainer.encode(metrics.ecKeyGenTimeMs, forKey: .ecKeyGenTimeMs)
        try metricsContainer.encode(metrics.ecKeyGenCount, forKey: .ecKeyGenCount)
        try metricsContainer.encode(metrics.ecScalarMultiplyTimeMs, forKey: .ecScalarMultiplyTimeMs)
        try metricsContainer.encode(metrics.ecScalarMultiplyCount, forKey: .ecScalarMultiplyCount)
        try metricsContainer.encode(metrics.ecPointAddTimeMs, forKey: .ecPointAddTimeMs)
        try metricsContainer.encode(metrics.ecPointAddCount, forKey: .ecPointAddCount)
        try metricsContainer.encode(metrics.gzipDecompressTimeMs, forKey: .gzipDecompressTimeMs)
        try metricsContainer.encode(metrics.gzipDecompressCount, forKey: .gzipDecompressCount)
        try metricsContainer.encode(metrics.otherTimeMs, forKey: .otherTimeMs)
        try metricsContainer.encodeApduExchanges(Array(metrics.apduExchanges), forKey: .apduExchanges)
    }

    private enum MetricsCodingKeys: String, CodingKey {
        case timestampMs, totalTimeMs, nfcTimeMs, nfcCallCount, totalCryptoTimeMs
        case aesCbcEncryptTimeMs, aesCbcEncryptCount, aesCbcDecryptTimeMs, aesCbcDecryptCount
        case aesCmacTimeMs, aesCmacCount, sha1TimeMs, sha1Count, sha256TimeMs, sha256Count
        case ecKeyGenTimeMs, ecKeyGenCount, ecScalarMultiplyTimeMs, ecScalarMultiplyCount
        case ecPointAddTimeMs, ecPointAddCount, gzipDecompressTimeMs, gzipDecompressCount, otherTimeMs
        case apduExchanges
    }
}

// MARK: - APDU Exchange Codable Helpers

private struct CodableApduExchange: Codable {
    let command: String
    let response: String
    let durationMs: Int64
    let label: String
}

private extension KeyedDecodingContainer {
    func decodeApduExchanges(forKey key: Key) throws -> [ApduExchangeRecord] {
        let codableExchanges = try decodeIfPresent([CodableApduExchange].self, forKey: key) ?? []
        return codableExchanges.map { exchange in
            ApduExchangeRecord(
                command: exchange.command,
                response: exchange.response,
                durationMs: exchange.durationMs,
                label: exchange.label
            )
        }
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeApduExchanges(_ exchanges: [ApduExchangeRecord], forKey key: Key) throws {
        let codableExchanges = exchanges.map { exchange in
            CodableApduExchange(
                command: exchange.command,
                response: exchange.response,
                durationMs: exchange.durationMs,
                label: exchange.label
            )
        }
        try encode(codableExchanges, forKey: key)
    }
}
