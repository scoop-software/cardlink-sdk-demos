import SwiftUI
import CoreNFC
import Combine
import ScoopNfcUI
@preconcurrency import ScoopCardlink

// MARK: - Upload View Model

/// ObservableObject that bridges ErezeptUploadFlow state to SwiftUI.
class UploadViewModel: ObservableObject {
    @Published var flowState: ErezeptUploadState = ErezeptUploadState.NeedsBundle(bundles: ErezeptBundles.shared.byType())
    @Published var traceLog: [String] = []

    /// Tracks selections made so far (persisted across state transitions).
    @Published var selectedBundle: ErezeptBundleInfo?
    @Published var selectedCardLabel: String?

    private var flow: ErezeptUploadFlow?
    private var nfcSessionManager: NfcSessionManager?
    private var flowTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var traceTask: Task<Void, Never>?

    func startFlow(username: String, password: String, useRU: Bool = false) {
        cancelFlow()

        let environment: CardlinkEnvironment = CardlinkEnvironment.Default.shared
        let storage = CredentialStorageFactory.shared.create(context: nil)
        let cache = SharedFileCacheProvider(
            appGroupId: "group.de.scoopsoftware.nfc",
            securityLevel: .encrypted,
            fileOps: DefaultFileOperations.shared,
            cryptoOps: DefaultCryptoOperations.shared
        )

        let config = CardlinkFlowConfig(
            environment: environment,
            username: username,
            password: password,
            smsSenderId: "Cardlink",
            smsTemplate: "Your Cardlink code: {0}",
            credentialStorage: storage,
            nfcTimeoutMs: 2500,
            enableApduTracing: false,
            sessionValidityMs: 15 * 60 * 1000,
            tokenRefreshBufferMs: 60_000,
            cacheProvider: cache,
            poppMode: false,
            uploadTargetEnv: "dev"
        )

        let nfcProvider = IosNfcTransceiverProvider()
        let nfcSession = NfcSessionManager(provider: nfcProvider)
        self.nfcSessionManager = nfcSession

        nfcProvider.onReadyForSession = { [weak nfcSession] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                nfcSession?.startSession()
            }
        }

        let uploadFlow = ErezeptUploadFlow(config: config, nfcProvider: nfcProvider)
        self.flow = uploadFlow

        traceLog.removeAll()
        selectedBundle = nil
        selectedCardLabel = nil

        // Collect state
        stateTask = Task { [weak self] in
            for await state in uploadFlow.state {
                DispatchQueue.main.async {
                    self?.flowState = state
                    self?.updateSelections(from: state)

                    // Manage NFC session hints
                    if let mgr = self?.nfcSessionManager {
                        let hint = state.nfcSessionHint
                        switch hint.action {
                        case .updateMessage:
                            mgr.updateAlertMessage(hint.message)
                        case .invalidate:
                            mgr.updateAlertMessage(hint.message)
                            mgr.invalidateSession()
                        case .invalidateWithError:
                            mgr.invalidateSession(errorMessage: hint.message)
                        default:
                            break
                        }
                    }
                }
            }
        }

        // Collect trace events
        traceTask = Task { [weak self] in
            for await event in uploadFlow.traceEvents {
                DispatchQueue.main.async {
                    self?.traceLog.insert(String(describing: event), at: 0)
                    if (self?.traceLog.count ?? 0) > 300 {
                        self?.traceLog.removeLast()
                    }
                }
            }
        }

        // Launch flow
        flowTask = Task {
            do {
                try await uploadFlow.start()
            } catch {
                print("[UploadFlow] Error: \(error)")
            }
        }
    }

    func submitBundle(_ bundleId: String) { flow?.submitBundle(bundleId: bundleId) }
    func submitCardInfo(can: String, iccsn: String? = nil) { flow?.submitCardInfo(can: can, iccsn: iccsn) }
    func submitKnownCard(_ card: KnownCard) { flow?.submitKnownCard(card: card) }
    func exportFailedBundles() -> String { flow?.exportFailedBundles() ?? "" }

    func cancelFlow() {
        flow?.cancel()
        flowTask?.cancel()
        stateTask?.cancel()
        traceTask?.cancel()
        flow = nil
        nfcSessionManager = nil
        flowTask = nil
        stateTask = nil
        traceTask = nil
        flowState = ErezeptUploadState.NeedsBundle(bundles: ErezeptBundles.shared.byType())
        selectedBundle = nil
        selectedCardLabel = nil
    }

    private func updateSelections(from state: ErezeptUploadState) {
        if let needsCard = state as? ErezeptUploadState.NeedsCard {
            selectedBundle = needsCard.selectedBundle
        }
        // Once we move past NeedsCard, card was selected
        if state is ErezeptUploadState.WaitingForCard ||
           state is ErezeptUploadState.ReadingCard ||
           state is ErezeptUploadState.Uploading ||
           state is ErezeptUploadState.Completed ||
           state is ErezeptUploadState.Error {
            if selectedCardLabel == nil {
                selectedCardLabel = "eGK"
            }
        }
        // Update bundle from Completed/Error if available
        if let completed = state as? ErezeptUploadState.Completed, let b = completed.bundle {
            selectedBundle = b
        }
        if let error = state as? ErezeptUploadState.Error, let b = error.bundle {
            selectedBundle = b
        }
        // Clear on restart
        if state is ErezeptUploadState.NeedsBundle {
            selectedBundle = nil
            selectedCardLabel = nil
        }
    }
}

// MARK: - Upload View

struct UploadView: View {
    let username: String
    let password: String

    @StateObject private var viewModel = UploadViewModel()
    @State private var can: String = ""
    @State private var showTraceLog = false
    @State private var useRU = false

    /// Whether the flow has progressed past bundle selection.
    private var pastBundleSelection: Bool {
        !(viewModel.flowState is ErezeptUploadState.NeedsBundle)
    }

    /// Whether the flow has progressed past card selection.
    private var pastCardSelection: Bool {
        let s = viewModel.flowState
        return s is ErezeptUploadState.WaitingForCard ||
               s is ErezeptUploadState.ReadingCard ||
               s is ErezeptUploadState.Uploading ||
               s is ErezeptUploadState.Completed ||
               s is ErezeptUploadState.Error
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Step 1: Prescription
                    stepHeader("1. Prescription", done: pastBundleSelection)

                    if let bundle = viewModel.selectedBundle, pastBundleSelection {
                        bundleSummaryRow(bundle)
                    } else if let state = viewModel.flowState as? ErezeptUploadState.NeedsBundle {
                        bundleSelector(grouped: state.bundles)
                    }

                    // Step 2: Card (only show once bundle is selected)
                    if pastBundleSelection {
                        stepHeader("2. Card", done: pastCardSelection)

                        if pastCardSelection {
                            cardSummaryRow()
                        } else if let state = viewModel.flowState as? ErezeptUploadState.NeedsCard {
                            cardSelector(state: state)
                        }
                    }

                    // Step 3: Upload (only show once card is selected)
                    if pastCardSelection {
                        stepHeader("3. Upload", done: viewModel.flowState is ErezeptUploadState.Completed)

                        uploadStatus()
                    }
                }
                .padding()
            }
            .navigationTitle("eRezept Upload")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Picker("Environment", selection: $useRU) {
                        Text("DEV").tag(false)
                        Text("RU").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    .onChange(of: useRU) { _ in
                        viewModel.cancelFlow()
                        if !username.isEmpty && !password.isEmpty {
                            viewModel.startFlow(username: username, password: password, useRU: useRU)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Log") { showTraceLog = true }
                        .font(.caption)
                }
            }
            .task {
                if !username.isEmpty && !password.isEmpty {
                    viewModel.startFlow(username: username, password: password, useRU: useRU)
                }
            }
        }
        .sheet(isPresented: $showTraceLog) {
            TraceLogSheet(traceLog: viewModel.traceLog)
        }
    }

    // MARK: - Step Header

    private func stepHeader(_ title: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
            }
            Text(title)
                .font(.headline)
                .foregroundColor(done ? .secondary : .primary)
        }
    }

    // MARK: - Step 1: Bundle

    private func bundleSummaryRow(_ bundle: ErezeptBundleInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bundle.medicationName)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("\(bundle.type.name) · KBV \(bundle.version) · \(bundle.source)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func bundleSelector(grouped: [ErezeptType: [ErezeptBundleInfo]]) -> some View {
        let typeOrder: [ErezeptType] = [.pzn, .wirkstoff, .freitext, .rezeptur]

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(typeOrder, id: \.self) { type in
                if let bundles = grouped[type] as? [ErezeptBundleInfo], !bundles.isEmpty {
                    Text(type.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    ForEach(Array(bundles.enumerated()), id: \.offset) { _, bundle in
                        Button {
                            viewModel.submitBundle(bundle.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(bundle.medicationName)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Text("KBV \(bundle.version) · \(bundle.source)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Step 2: Card

    private func cardSummaryRow() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "creditcard.fill")
                .foregroundColor(.secondary)
            Text(viewModel.selectedCardLabel ?? "eGK")
                .font(.subheadline)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func cardSelector(state: ErezeptUploadState.NeedsCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !state.knownCards.isEmpty {
                Text("Known Cards")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(Array(state.knownCards.enumerated()), id: \.offset) { _, item in
                    let card = item as! KnownCard
                    KnownCardItem(
                        fullName: card.displayName ?? "—",
                        insuranceId: card.insuranceId ?? "—",
                        insurerId: card.insurerId ?? "—",
                        insurerName: card.insurerName ?? "—",
                        can: card.can,
                        onTap: {
                            can = card.can
                            viewModel.selectedCardLabel = (card.displayName ?? "").isEmpty ? "CAN \(card.can)" : card.displayName!
                            viewModel.submitKnownCard(card)
                        }
                    )
                }

                Divider().padding(.vertical, 4)

                Text("Or use a new card")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            CanInputView(can: $can)

            Button("Use New Card") {
                viewModel.selectedCardLabel = "CAN \(can)"
                viewModel.submitCardInfo(can: can.trimmingCharacters(in: .whitespaces))
            }
            .buttonStyle(.borderedProminent)
            .disabled(can.count != 6)
        }
    }

    // MARK: - Step 3: Upload Status

    @ViewBuilder
    private func uploadStatus() -> some View {
        let state = viewModel.flowState

        if state is ErezeptUploadState.WaitingForCard {
            statusRow("Hold your eGK near the iPhone...", loading: true)
        } else if let reading = state as? ErezeptUploadState.ReadingCard {
            VStack(spacing: 8) {
                ProgressView(value: Double(reading.progress), total: 1.0)
                Text(reading.stepLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if state is ErezeptUploadState.Uploading {
            statusRow("Sending prescription to server...", loading: true)
        } else if let completed = state as? ErezeptUploadState.Completed {
            CompletedContent(state: completed) {
                viewModel.startFlow(username: username, password: password, useRU: useRU)
            }
        } else if let error = state as? ErezeptUploadState.Error {
            errorContent(state: error)
        }
    }

    private func statusRow(_ text: String, loading: Bool = false) -> some View {
        HStack(spacing: 8) {
            if loading { ProgressView() }
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(10)
    }

    private func errorContent(state: ErezeptUploadState.Error) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Error (\(state.phase.name))")
                .font(.subheadline)
                .foregroundColor(.red)

            Text(state.message)
                .font(.caption)
                .foregroundColor(.red)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack {
                Button("Start Over") {
                    viewModel.startFlow(username: username, password: password, useRU: useRU)
                }
                .buttonStyle(.bordered)

                let failed = viewModel.exportFailedBundles()
                if !failed.isEmpty {
                    Button("Copy Failed Bundles") {
                        UIPasteboard.general.string = failed
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
        }
    }
}

// MARK: - Completed Content

private struct CompletedContent: View {
    let state: ErezeptUploadState.Completed
    let onStartOver: () -> Void
    @State private var showResponse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Upload Successful (\(state.statusCode))")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }

            HStack {
                if !state.body.isEmpty && !showResponse {
                    Text("Show Response")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                        .onTapGesture { showResponse = true }
                }
                Spacer()
                Button("Start Over") { onStartOver() }
                    .buttonStyle(.bordered)
            }

            if showResponse && !state.body.isEmpty {
                Text(state.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
