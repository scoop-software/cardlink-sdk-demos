import SwiftUI
import Charts
import ScoopCardlink
import ScoopNfcUI

/// Main charts view showing performance history and statistics.
struct ChartsView: View {
    @ObservedObject var scanHistory: ScanHistory
    @Binding var recordMetrics: Bool
    @State private var showingClearConfirmation = false
    @State private var exportItem: ExportItem?
    @State private var apduChartMode: ApduChartMode = .lastScan

    var body: some View {
        NavigationView {
            ZStack {
                // Glass background
                Color.clear
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()

                if scanHistory.records.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Summary statistics card
                            summaryCard
                                .modifier(ScrollTransitionModifier())

                            // Total scan time chart
                            scanTimeChartCard
                                .modifier(ScrollTransitionModifier())

                            // Time breakdown chart
                            breakdownChartCard
                                .modifier(ScrollTransitionModifier())

                            // APDU Timeline (most recent scan)
                            apduTimelineCardView
                                .modifier(ScrollTransitionModifier())
                        }
                        .padding()
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Performance")
            .toolbar {
                if !scanHistory.records.isEmpty {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            exportItem = ExportItem(csvData: scanHistory.exportCSV())
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .sheet(item: $exportItem) { item in
                ShareSheet(csvData: item.csvData)
            }
            .confirmationDialog("Clear History?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
                Button("Clear All Data", role: .destructive) {
                    scanHistory.clear()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all \(scanHistory.totalScans) scan records. This action cannot be undone.")
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Scan Data")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Scan a card with metrics enabled to see performance charts here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Toggle("Record Metrics", isOn: $recordMetrics)
                .toggleStyle(.switch)
                .frame(width: 180)
                .padding(.top, 8)
        }
    }

    // MARK: - APDU Timeline Card View

    private var apduTimelineCardView: some View {
        let lastRecord = scanHistory.records.last!
        let hasApduData = apduChartMode == .lastScan
            ? !lastRecord.apduExchanges.isEmpty
            : scanHistory.records.contains { !$0.apduExchanges.isEmpty }

        // Calculate chart height based on mode
        let chartHeight: CGFloat = {
            if !hasApduData { return 120 }
            if apduChartMode == .lastScan {
                return CGFloat(lastRecord.apduExchanges.count * 30 + 60)
            } else {
                // For aggregated view, count unique labels across all records
                var uniqueLabels = Set<String>()
                for record in scanHistory.records {
                    for exchange in record.apduExchanges {
                        uniqueLabels.insert(exchange.label.isEmpty ? "Other" : exchange.label)
                    }
                }
                return CGFloat(uniqueLabels.count * 30 + 60)
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("APDU Timeline", systemImage: "rectangle.stack")
                    .font(.headline)

                Spacer()

                Picker("Mode", selection: $apduChartMode) {
                    ForEach(ApduChartMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if apduChartMode == .lastScan {
                ApduTimelineChart(record: lastRecord)
                    .frame(height: chartHeight)
            } else {
                ApduAggregatedChart(records: scanHistory.records)
                    .frame(height: chartHeight)
            }

            if hasApduData && apduChartMode == .lastScan {
                Divider()

                Text("Summary by Type")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ApduSummaryView(record: lastRecord)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Summary", systemImage: "chart.pie")
                .font(.headline)

            let lastRecord = scanHistory.records.last
            let hasPoPP = lastRecord.map { !$0.apduExchanges.filter { $0.label.hasPrefix("PoPP:") }.isEmpty } ?? false

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCell(title: "Total Scans", value: "\(scanHistory.totalScans)")
                StatCell(title: "Average", value: MetricsFormatting.shared.formatMs(ms: scanHistory.averageTotalTimeMs))
                StatCell(title: "Worst", value: MetricsFormatting.shared.formatMs(ms: scanHistory.maxTotalTimeMs))
                StatCell(title: "Best", value: MetricsFormatting.shared.formatMs(ms: scanHistory.minTotalTimeMs))

                if hasPoPP, let record = lastRecord {
                    let paceMs = record.apduExchanges
                        .filter { $0.label.contains("MSE:SET AT") || $0.label.contains("GENERAL AUTHENTICATE") }
                        .reduce(Int64(0)) { $0 + $1.durationMs }
                    let poppMs = record.apduExchanges
                        .filter { $0.label.hasPrefix("PoPP:") }
                        .reduce(Int64(0)) { $0 + $1.durationMs }
                    let cachedCount = record.apduExchanges.filter { $0.label.contains("cached") }.count

                    StatCell(title: "PACE", value: MetricsFormatting.shared.formatMs(ms: paceMs))
                    StatCell(title: "PoPP APDU", value: MetricsFormatting.shared.formatMs(ms: poppMs))
                    if cachedCount > 0 {
                        StatCell(title: "Cached", value: "\(cachedCount) APDUs")
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Scan Time Chart Card

    private var scanTimeChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Scan Time History", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            ScanTimeChart(records: scanHistory.records)
                .frame(height: 200)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Breakdown Chart Card

    private var breakdownChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Time Breakdown", systemImage: "chart.bar.fill")
                .font(.headline)

            BreakdownChart(records: scanHistory.records)
                .frame(height: 200)

            // Legend (adapts to show PoPP categories when PoPP scans exist)
            BreakdownLegend(hasPoppScans: scanHistory.records.contains {
                !$0.apduExchanges.filter { $0.label.hasPrefix("PoPP:") }.isEmpty
            })
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

}

// MARK: - Scroll Transition Modifier

struct ScrollTransitionModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .scrollTransition { view, phase in
                    view
                        .opacity(phase.isIdentity ? 1 : 0.6)
                        .scaleEffect(phase.isIdentity ? 1 : 0.95)
                }
        } else {
            content
        }
    }
}

// MARK: - Supporting Views

struct StatCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Export Item

struct ExportItem: Identifiable {
    let id = UUID()
    let csvData: String
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let csvData: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let itemSource = CSVActivityItemSource(csvData: csvData)

        let controller = UIActivityViewController(
            activityItems: [itemSource],
            applicationActivities: nil
        )
        controller.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .postToFacebook,
            .postToTwitter,
            .postToWeibo,
            .postToVimeo,
            .postToTencentWeibo,
            .postToFlickr
        ]
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - CSV Activity Item Source

final class CSVActivityItemSource: NSObject, UIActivityItemSource {
    private let csvData: String
    private let fileName = "cardlink-metrics.csv"
    private lazy var fileURL: URL = {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent(fileName)
    }()

    init(csvData: String) {
        self.csvData = csvData
        super.init()
        // Write CSV to temp file for sharing
        try? csvData.data(using: .utf8)?.write(to: fileURL)
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        return fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        return "Cardlink Performance Metrics"
    }
}

#Preview {
    ChartsView(scanHistory: ScanHistory(), recordMetrics: .constant(true))
}
