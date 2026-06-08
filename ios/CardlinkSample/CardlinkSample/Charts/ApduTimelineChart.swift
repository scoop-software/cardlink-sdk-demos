import SwiftUI
import Charts
import ScoopCardlink
import ScoopNfcUI

/// Represents a single APDU exchange for charting.
private struct ApduChartItem: Identifiable {
    let id: Int
    let label: String
    let startMs: Int64
    let durationMs: Int64
}

/// Represents aggregated APDU data across all scans.
struct AggregatedApduItem: Identifiable {
    let id: String // label as ID
    let label: String
    let totalMs: Int64
    let count: Int
    let avgMs: Int64
}

/// Chart mode for APDU visualization.
enum ApduChartMode: String, CaseIterable {
    case lastScan = "Last Scan"
    case allScans = "All Scans"
}

/// Horizontal bar chart showing APDU timing as a waterfall/timeline.
struct ApduTimelineChart: View {
    let record: ScanRecord
    @State private var animationProgress: Double = 0

    private var apduData: [ApduChartItem] {
        var cumulativeTime: Int64 = 0
        return record.apduExchanges.enumerated().map { index, exchange in
            let start = cumulativeTime
            cumulativeTime += exchange.durationMs
            return ApduChartItem(
                id: index,
                label: exchange.label.isEmpty ? "APDU" : exchange.label,
                startMs: start,
                durationMs: exchange.durationMs
            )
        }
    }

    var body: some View {
        let data = apduData
        if data.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No APDU Data")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Enable \"Record APDU Exchanges\" in settings to capture timing data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            chartContent(data: data)
        }
    }

    @ViewBuilder
    private func chartContent(data: [ApduChartItem]) -> some View {
        Chart(data) { item in
            let animatedStart = Double(item.startMs) * animationProgress
            let animatedDuration = Double(item.durationMs) * animationProgress

            BarMark(
                xStart: .value("Start", animatedStart),
                xEnd: .value("End", animatedStart + animatedDuration),
                y: .value("APDU", item.id)
            )
            .foregroundStyle(MetricsFormatting.shared.colorForApduLabel(label: item.label).toSwiftUIColor())
            .annotation(position: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Text(item.label)
                        .font(.system(size: 8, weight: .medium))
                    Text("\(item.durationMs)ms")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animationProgress = 1.0
            }
        }
        .onChange(of: record.id) { _ in
            animationProgress = 0
            withAnimation(.easeOut(duration: 0.4)) {
                animationProgress = 1.0
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let ms = value.as(Int.self) {
                        Text(MetricsFormatting.shared.formatMs(ms: Int64(ms)))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .chartXAxisLabel("Time", position: .bottom)
    }
}

/// Aggregated APDU chart showing average time per command type across all scans.
struct ApduAggregatedChart: View {
    let records: [ScanRecord]
    @State private var animationProgress: Double = 0

    private var aggregatedData: [AggregatedApduItem] {
        var groups: [String: (count: Int, totalMs: Int64)] = [:]

        for record in records {
            for exchange in record.apduExchanges {
                let label = exchange.label.isEmpty ? "Other" : exchange.label
                let current = groups[label] ?? (0, 0)
                groups[label] = (current.count + 1, current.totalMs + exchange.durationMs)
            }
        }

        return groups.map { label, value in
            AggregatedApduItem(
                id: label,
                label: label,
                totalMs: value.totalMs,
                count: value.count,
                avgMs: value.count > 0 ? value.totalMs / Int64(value.count) : 0
            )
        }.sorted { $0.avgMs > $1.avgMs }  // Sort by average, slowest first
    }

    var body: some View {
        let data = aggregatedData
        if data.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No APDU Data")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Enable \"Record APDU Exchanges\" in settings to capture timing data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            chartContent(data: data)
        }
    }

    @ViewBuilder
    private func chartContent(data: [AggregatedApduItem]) -> some View {
        Chart(data) { item in
            BarMark(
                x: .value("Duration", Double(item.avgMs) * animationProgress),
                y: .value("Command", item.label)
            )
            .foregroundStyle(MetricsFormatting.shared.colorForApduLabel(label: item.label).toSwiftUIColor())
            .annotation(position: .trailing, spacing: 4) {
                Text("\(item.avgMs)ms avg (\(item.count)x)")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animationProgress = 1.0
            }
        }
        .onChange(of: records.count) { _ in
            animationProgress = 0
            withAnimation(.easeOut(duration: 0.4)) {
                animationProgress = 1.0
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let ms = value.as(Int.self) {
                        Text(MetricsFormatting.shared.formatMs(ms: Int64(ms)))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: 8))
            }
        }
        .chartXAxisLabel("Average Time", position: .bottom)
    }
}

/// Summary view showing APDU statistics grouped by type.
struct ApduSummaryView: View {
    let record: ScanRecord

    private var groupedStats: [(description: String, count: Int, totalMs: Int64, avgMs: Int64)] {
        var groups: [String: (count: Int, totalMs: Int64)] = [:]

        for exchange in record.apduExchanges {
            let desc = exchange.label.isEmpty ? "Other" : exchange.label
            let current = groups[desc] ?? (0, 0)
            groups[desc] = (current.count + 1, current.totalMs + exchange.durationMs)
        }

        return groups.map { key, value in
            (key, value.count, value.totalMs, value.count > 0 ? value.totalMs / Int64(value.count) : 0)
        }.sorted { $0.totalMs > $1.totalMs }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groupedStats, id: \.description) { stat in
                HStack {
                    Circle()
                        .fill(MetricsFormatting.shared.colorForApduLabel(label: stat.description).toSwiftUIColor())
                        .frame(width: 8, height: 8)
                    Text(stat.description)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text("\(stat.count)x")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(stat.totalMs)ms")
                        .font(.caption.monospacedDigit())
                        .frame(width: 50, alignment: .trailing)
                    Text("(\(stat.avgMs)ms avg)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - ApduColor Extension for SwiftUI

// Note: ScoopNfcUI ships an equivalent extension on ScoopNfc.ApduColor,
// but Cardlink and NFC's XCFrameworks each compile their own Kotlin type
// bindings, so ScoopCardlink.ApduColor (used here via Cardlink's typealias
// re-export) is a different Swift type. Until Cardlink consumes NFC as a
// binary dependency rather than re-compiling its types, this extension
// stays demo-local.
extension ApduColor {
    func toSwiftUIColor() -> Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .gray: return .gray
        case .purple: return .purple
        case .cyan: return .cyan
        default: return .gray
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: 20) {
            let record = ScanRecord.sampleRecords(count: 1).first!

            Text("APDU Timeline")
                .font(.headline)

            ApduTimelineChart(record: record)
                .frame(height: 300)

            Divider()

            Text("APDU Summary")
                .font(.headline)

            ApduSummaryView(record: record)
        }
        .padding()
    }
}
#endif
