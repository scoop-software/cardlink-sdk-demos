import SwiftUI
import Charts
import ScoopCardlink
import ScoopNfcUI

/// Helper to compute time breakdown from a ScanRecord's APDU exchanges.
private struct TimeBreakdown {
    let paceMs: Int64
    let poppApduMs: Int64
    let otherNfcMs: Int64
    let cryptoMs: Int64
    let gzipMs: Int64
    let networkMs: Int64
    let otherMs: Int64

    init(record: ScanRecord) {
        let exchanges = record.apduExchanges

        // Categorize APDU exchanges by label
        let paceLabels = ["MSE:SET AT", "GENERAL AUTHENTICATE", "SM:MSE:SET AT", "SM:GENERAL AUTHENTICATE", "CardAccess"]
        var pace: Int64 = 0
        var popp: Int64 = 0
        var network: Int64 = 0
        var otherNfc: Int64 = 0

        for exchange in exchanges {
            let label = exchange.label
            if label.hasPrefix("Network:") {
                network += exchange.durationMs
            } else if paceLabels.contains(where: { label.contains($0) }) {
                pace += exchange.durationMs
            } else if label.hasPrefix("PoPP:") {
                popp += exchange.durationMs
            } else {
                otherNfc += exchange.durationMs
            }
        }

        // If no APDU-level breakdown, fall back to total NFC
        if exchanges.isEmpty {
            otherNfc = record.nfcTimeMs
        }

        self.paceMs = pace
        self.poppApduMs = popp
        self.otherNfcMs = otherNfc
        self.cryptoMs = record.cryptoTimeMs
        self.gzipMs = record.gzipTimeMs
        self.networkMs = network
        // Subtract network from "other" since PerformanceMetrics includes it there
        self.otherMs = max(0, record.otherTimeMs - network)
    }

    var hasPoppData: Bool { poppApduMs > 0 || networkMs > 0 }
}

/// Stacked bar chart showing time breakdown per scan.
/// Splits NFC into PACE, PoPP APDUs, and other NFC when APDU data is available.
struct BreakdownChart: View {
    let records: [ScanRecord]

    private var hasPoppScans: Bool {
        records.contains { TimeBreakdown(record: $0).hasPoppData }
    }

    var body: some View {
        Chart {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                marks(index: index, record: record)
            }
        }
        .chartForegroundStyleScale([
            "PACE": Color.indigo,
            "PoPP APDU": Color.blue,
            "NFC (other)": Color.cyan,
            "NFC": Color.blue,
            "Network": Color.purple,
            "Crypto": Color.green,
            "Gzip": Color.orange,
            "Other": Color.gray
        ])
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: min(records.count, 8))) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("#\(intValue)").font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let ms = value.as(Int.self) {
                        Text(MetricsFormatting.shared.formatMs(ms: Int64(ms))).font(.caption2)
                    }
                }
            }
        }
    }

    @ChartContentBuilder
    private func marks(index: Int, record: ScanRecord) -> some ChartContent {
        let breakdown = TimeBreakdown(record: record)
        let scan = index + 1

        if breakdown.hasPoppData || hasPoppScans {
            if breakdown.paceMs > 0 {
                BarMark(x: .value("Scan", scan), y: .value("Time", breakdown.paceMs))
                    .foregroundStyle(by: .value("Category", "PACE"))
            }
            if breakdown.poppApduMs > 0 {
                BarMark(x: .value("Scan", scan), y: .value("Time", breakdown.poppApduMs))
                    .foregroundStyle(by: .value("Category", "PoPP APDU"))
            }
            if breakdown.otherNfcMs > 0 {
                BarMark(x: .value("Scan", scan), y: .value("Time", breakdown.otherNfcMs))
                    .foregroundStyle(by: .value("Category", "NFC (other)"))
            }
        } else {
            BarMark(x: .value("Scan", scan), y: .value("Time", record.nfcTimeMs))
                .foregroundStyle(by: .value("Category", "NFC"))
        }

        if breakdown.networkMs > 0 {
            BarMark(x: .value("Scan", scan), y: .value("Time", breakdown.networkMs))
                .foregroundStyle(by: .value("Category", "Network"))
        }
        if breakdown.cryptoMs > 0 {
            BarMark(x: .value("Scan", scan), y: .value("Time", breakdown.cryptoMs))
                .foregroundStyle(by: .value("Category", "Crypto"))
        }
        if breakdown.gzipMs > 0 {
            BarMark(x: .value("Scan", scan), y: .value("Time", breakdown.gzipMs))
                .foregroundStyle(by: .value("Category", "Gzip"))
        }
        if breakdown.otherMs > 0 {
            BarMark(x: .value("Scan", scan), y: .value("Time", breakdown.otherMs))
                .foregroundStyle(by: .value("Category", "Other"))
        }
    }
}

/// Legend items for the breakdown chart with vertical rotated labels.
struct BreakdownLegend: View {
    let hasPoppScans: Bool

    var body: some View {
        HStack(spacing: 4) {
            if hasPoppScans {
                VerticalLegendItem(color: .indigo, label: "PACE")
                VerticalLegendItem(color: .blue, label: "PoPP APDU")
                VerticalLegendItem(color: .cyan, label: "NFC (other)")
                VerticalLegendItem(color: .purple, label: "Network")
            } else {
                VerticalLegendItem(color: .blue, label: "NFC")
            }
            VerticalLegendItem(color: .green, label: "Crypto")
            VerticalLegendItem(color: .orange, label: "Gzip")
            VerticalLegendItem(color: .gray, label: "Other")
        }
    }
}

private struct VerticalLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 9))
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(90))
                .frame(height: 60)
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview {
    VStack {
        BreakdownChart(records: ScanRecord.sampleRecords(count: 5))
            .frame(height: 200)
        BreakdownLegend(hasPoppScans: true)
    }
    .padding()
}
#endif
