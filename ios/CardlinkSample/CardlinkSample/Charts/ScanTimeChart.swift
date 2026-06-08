import SwiftUI
import Charts
import ScoopCardlink
import ScoopNfcUI

/// Line chart showing total scan time over multiple scans.
struct ScanTimeChart: View {
    let records: [ScanRecord]

    var body: some View {
        Chart {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                LineMark(
                    x: .value("Scan", index + 1),
                    y: .value("Time (ms)", record.totalTimeMs)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Scan", index + 1),
                    y: .value("Time (ms)", record.totalTimeMs)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Scan", index + 1),
                    y: .value("Time (ms)", record.totalTimeMs)
                )
                .foregroundStyle(.blue)
                .symbolSize(30)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: min(records.count, 8))) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("#\(intValue)")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let ms = value.as(Int.self) {
                        Text(MetricsFormatting.shared.formatMs(ms: Int64(ms)))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxisLabel("Time", position: .leading)
    }
}

#if DEBUG
#Preview {
    ScanTimeChart(records: ScanRecord.sampleRecords(count: 10))
        .frame(height: 200)
        .padding()
}
#endif
