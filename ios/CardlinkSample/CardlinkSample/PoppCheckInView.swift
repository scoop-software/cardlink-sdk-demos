import SwiftUI
import Lottie
import ScoopCardlink
import ScoopPoppSDK
import ScoopNfcUI

private let TELEMATIK_ID = "3-SMC-B-Testkarte--883110000153556"

/// PoPP check-in flow — orchestrates all screens using SDK defaults.
///
/// OS-mandatory screens (consent, result, error) use native UIAlertController.
/// App-replaceable screens are SwiftUI views below.
struct PoppCheckInView: View {
    @Binding var username: String
    @Binding var password: String
    @State private var passwordVisible: Bool = false
    @ObservedObject var scanHistory: ScanHistory
    @StateObject private var viewModel = PoppViewModel()
    @EnvironmentObject private var themeStore: BrandThemeStore
    @State private var showLog = false
    @Environment(\.scenePhase) private var scenePhase
    // Default to true until 2026-03-23 09:00 CET
    @State private var useFakeErezept: Bool = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let cutoff = calendar.date(from: DateComponents(year: 2026, month: 3, day: 23, hour: 9))!
        return Date() < cutoff
    }()
    @AppStorage("scoopSignatureMode") private var useFileCache = false
    @State private var useRisePoppService = true

    var body: some View {
        NavigationView {
            Group {
                switch viewModel.state {
                case .idle:
                    idleView
                case .initializing:
                    initializingView
                case .needsLeiSelectionMethod(let hasFavorites):
                    leiSelectionMethodView(hasFavorites: hasFavorites)
                case .scanningQr:
                    scanningQrView
                case .needsVzdSearch:
                    vzdSearchView
                case .needsFavoriteSelection(let favorites):
                    favoriteSelectionView(favorites: favorites)
                case .needsConsent:
                    ProgressView() // Consent shown by module via native UI
                case .needsAuthMethod(let gidAvailable):
                    authMethodView(gidAvailable: gidAvailable)
                case .needsCan(let knownCards, let errorMessage):
                    canInputView(knownCards: knownCards, errorMessage: errorMessage)
                case .waitingForCard:
                    waitingForCardView
                case .authenticatingEgk:
                    authenticatingEgkView
                case .authenticatingGid:
                    authenticatingGidView
                case .completed(let result):
                    completedView(result: result)
                case .cancelled(let message):
                    cancelledView(message: message)
                case .fetchingTokens:
                    fetchingTokensView
                case .tokensReceived(let tokens):
                    DeletableTokensView(
                        tokens: tokens,
                        hasPrescriptions: viewModel.hasPrescriptions,
                        showConfetti: viewModel.showConfetti,
                        username: username,
                        password: password,
                        onCancel: { viewModel.cancel() },
                        onTrace: { msg in viewModel.traceLog.append(msg) }
                    )
                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle("PoPP Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showLog.toggle()
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .disabled(viewModel.traceLog.isEmpty)
                }
            }
            .sheet(isPresented: $showLog) {
                TraceLogSheet(traceLog: viewModel.traceLog)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active && viewModel.hasPrescriptions && !viewModel.showConfetti {
                viewModel.showConfetti = true
            }
        }
        .onChange(of: viewModel.hasPrescriptions) { hasThem in
            if hasThem && scenePhase == .active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    viewModel.showConfetti = true
                }
            }
        }
        .onReceive(viewModel.$state) { newState in
            switch newState {
            case .completed:
                let record = ScanRecord.fromPerformanceMetrics()
                scanHistory.add(record)
                RocketChatHelper.reportIfEnabled(record: record, success: true, traceLog: viewModel.traceLog)
            default:
                break
            }
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        ScrollView {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            Text("PoPP Check-in")
                .font(.title)
            Text("Proof of Patient Presence — Nachweis der Anwesenheit beim Leistungserbringer")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 8) {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                HStack {
                    Group {
                        if passwordVisible {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    Button {
                        passwordVisible.toggle()
                    } label: {
                        Image(systemName: passwordVisible ? "eye.slash" : "eye")
                    }
                }
            }
            .padding(.horizontal, 32)

            Toggle("Fake E-Rezept", isOn: $useFakeErezept)
                .padding(.horizontal, 40)
            Toggle("RISE PoPP Service", isOn: $useRisePoppService)
                .padding(.horizontal, 40)

            Spacer()
            Button("Check-in starten") {
                viewModel.useFakeErezept = useFakeErezept
                viewModel.useFileCache = useFileCache
                viewModel.useRisePoppService = useRisePoppService
                viewModel.startCheckIn(username: username, password: password, themeColor: themeStore.current.uiColor)
            }
            .disabled(username.isEmpty || password.isEmpty)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                viewModel.useFakeErezept = useFakeErezept
                viewModel.useFileCache = useFileCache
                viewModel.useRisePoppService = useRisePoppService
                viewModel.startCheckIn(username: username, password: password, telematikId: nil, themeColor: themeStore.current.uiColor)
            } label: {
                Label("QR-Code scannen", systemImage: "qrcode.viewfinder")
            }
            .disabled(username.isEmpty || password.isEmpty)
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()
        }
        .padding()
        .task { await viewModel.loadKnownCards() }
        }
    }

    // MARK: - Initializing

    private var initializingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(PoppStrings.shared.INITIALIZING)
                .font(.body)
        }
    }

    // MARK: - LEI Selection Method

    private func leiSelectionMethodView(hasFavorites: Bool) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(PoppStrings.shared.LEI_SELECTION_TITLE)
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                leiOptionButton(title: PoppStrings.shared.LEI_SCAN_QR, icon: "qrcode.viewfinder") {
                    viewModel.submitLeiSelectionMethod(.qrScan)
                }
                leiOptionButton(title: PoppStrings.shared.LEI_SEARCH_VZD, icon: "magnifyingglass") {
                    viewModel.submitLeiSelectionMethod(.vzdSearch)
                }
                if hasFavorites {
                    leiOptionButton(title: PoppStrings.shared.LEI_FAVORITES, icon: "star.fill") {
                        viewModel.submitLeiSelectionMethod(.favorites)
                    }
                }
            }
            .padding(.horizontal)

            Spacer()
            Button(PoppStrings.shared.CANCEL) { viewModel.cancel() }
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private func leiOptionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.title2).frame(width: 32).foregroundColor(.accentColor)
                Text(title).font(.body).fontWeight(.medium).foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - QR Scanner

    private var scanningQrView: some View {
        QrScannerView(
            onResult: { payload in viewModel.submitQrScanResult(payload) },
            onCancel: { viewModel.submitQrScanResult(nil) }
        )
    }

    // MARK: - VZD Search

    private var vzdSearchView: some View {
        VzdSearchInputView(
            onSearch: { viewModel.submitVzdSearch($0) },
            onCancel: { viewModel.submitVzdSearch(nil) }
        )
    }

    // MARK: - Favorite Selection

    private func favoriteSelectionView(favorites: [PoppFavorite]) -> some View {
        VStack(spacing: 0) {
            Text(PoppStrings.shared.FAVORITES_TITLE).font(.title2).fontWeight(.semibold).padding()
            if favorites.isEmpty {
                Spacer()
                Text(PoppStrings.shared.FAVORITES_EMPTY).foregroundColor(.secondary)
                Spacer()
            } else {
                List(favorites, id: \.telematikId) { favorite in
                    Button {
                        viewModel.submitFavoriteSelection(favorite)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(favorite.name).font(.body).fontWeight(.medium)
                            if let address = favorite.address {
                                Text(address).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            Button(PoppStrings.shared.CANCEL) { viewModel.submitFavoriteSelection(nil) }
                .foregroundColor(.secondary).padding()
        }
    }

    // MARK: - Auth Method

    private func authMethodView(gidAvailable: Bool) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(PoppStrings.shared.AUTH_METHOD_TITLE).font(.title2).fontWeight(.semibold)
            VStack(spacing: 12) {
                Button { viewModel.submitAuthMethod(.egk) } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "creditcard.fill").font(.title2).frame(width: 32).foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(PoppStrings.shared.AUTH_EGK).font(.body).fontWeight(.medium).foregroundColor(.primary)
                            Text(PoppStrings.shared.AUTH_EGK_SUBTITLE).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                Button {
                    // GesundheitsID not yet implemented
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill").font(.title2).frame(width: 32).foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(PoppStrings.shared.AUTH_GID).font(.body).fontWeight(.medium).foregroundColor(.primary)
                                Text("Coming soon").font(.caption2).foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.gray).cornerRadius(4)
                            }
                            Text(PoppStrings.shared.AUTH_GID_SUBTITLE).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .opacity(0.6)
                }
                .buttonStyle(.plain)
                .disabled(true)
            }
            .padding(.horizontal)
            Spacer()
        }
    }

    // MARK: - CAN Input

    private func canInputView(knownCards: [ScoopPoppSDK.KnownCard], errorMessage: String?) -> some View {
        PoppCanInputView(
            knownCards: knownCards,
            errorMessage: errorMessage,
            onSubmitCan: { viewModel.submitCan($0) },
            onSubmitKnownCard: { viewModel.submitKnownCard($0) },
            onCancel: { viewModel.cancel() }
        )
    }

    // MARK: - Waiting for Card

    private var waitingForCardView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "wave.3.right")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            Text(PoppStrings.shared.EGK_HOLD_CARD)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Authenticating eGK

    private var authenticatingEgkView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView().scaleEffect(2)
            Text(PoppStrings.shared.EGK_TITLE).font(.title2)
            Text(PoppStrings.shared.EGK_READING).font(.body).foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Authenticating GID

    private var authenticatingGidView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView().scaleEffect(2)
            Text(PoppStrings.shared.GID_TITLE).font(.title2)
            Text(PoppStrings.shared.GID_REDIRECT).font(.body).foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Completed

    private func completedView(result: PoppCheckInResult) -> some View {
        VStack(spacing: 16) {
            Spacer()
            if result is PoppCheckInResult.Success {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.green)
                Text(PoppStrings.shared.RESULT_SUCCESS_TITLE)
                    .font(.title2).fontWeight(.semibold)
                Text(PoppStrings.shared.RESULT_SUCCESS_MESSAGE)
                    .font(.body).foregroundColor(.secondary)
            } else if let pending = result as? PoppCheckInResult.Pending {
                ProgressView().scaleEffect(1.5)
                Text(PoppStrings.shared.RESULT_PENDING_TITLE)
                    .font(.title2).fontWeight(.semibold)
                Text(pending.message)
                    .font(.body).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                // Fallback for unexpected result types
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                Text("Check-in abgeschlossen")
                    .font(.title2).fontWeight(.semibold)
            }
            Spacer()
            Button("Fertig") { viewModel.cancel() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 50)
            Spacer()
        }
        .padding()
    }

    // MARK: - Error

    // MARK: - Fetching Tokens

    private var fetchingTokensView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().scaleEffect(1.5)
            Text("PoPP-Token wird abgerufen...")
                .font(.title3)
            Spacer()
        }
    }


    // MARK: - Cancelled

    private func cancelledView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.orange)
            Text("Check-in vom Benutzer abgebrochen")
                .font(.title2).fontWeight(.semibold)
            if !message.isEmpty {
                Text(message)
                    .font(.body).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
            Button("OK") { viewModel.cancel() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 50)
            Spacer()
        }
        .padding()
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundColor(.red)
            Text(PoppStrings.shared.RESULT_ERROR_TITLE)
                .font(.title2).fontWeight(.semibold)
            Text(message)
                .font(.body).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            Button("Schade") { viewModel.cancel() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 50)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Lottie Confetti Celebration

// MARK: - Deletable Tokens View (conference demo cleanup)

private struct DeletableTokensView: View {
    let tokens: [PoppViewModel.PoppTokenEntry]
    let hasPrescriptions: Bool
    let showConfetti: Bool
    let username: String
    let password: String
    let onCancel: () -> Void
    let onTrace: (String) -> Void

    @StateObject private var deleteVM: PrescriptionDeleteViewModel

    /// Every deletable prescription across all tokens, keyed by "<tokenIndex>:<presIndex>".
    private var allDeletable: [(key: String, taskId: String, accessCode: String)] {
        tokens.flatMap { token -> [(String, String, String)] in
            if case .loaded(let prescriptions, let metadata) = token.prescriptionState {
                return prescriptions.indices.compactMap { i in
                    guard i < metadata.count, let m = metadata[i] else { return nil }
                    return ("\(token.index):\(i)", m.taskId, m.accessCode)
                }
            }
            return []
        }
    }

    init(
        tokens: [PoppViewModel.PoppTokenEntry],
        hasPrescriptions: Bool,
        showConfetti: Bool,
        username: String,
        password: String,
        onCancel: @escaping () -> Void,
        onTrace: @escaping (String) -> Void
    ) {
        self.tokens = tokens
        self.hasPrescriptions = hasPrescriptions
        self.showConfetti = showConfetti
        self.username = username
        self.password = password
        self.onCancel = onCancel
        self.onTrace = onTrace
        _deleteVM = StateObject(wrappedValue: PrescriptionDeleteViewModel(
            environment: CardlinkEnvironment.Default.shared,
            username: username,
            password: password,
            onTrace: onTrace
        ))
    }

    var body: some View {
        let deletable = allDeletable
        let remaining = deleteVM.remainingCount(for: deletable.map { $0.key })

        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.green)
                        Text("PoPP Check-in erfolgreich")
                            .font(.title2).fontWeight(.semibold)
                    }
                    .padding(.horizontal)

                    Text("\(tokens.count) Token")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal)

                    if !deletable.isEmpty {
                        DeleteAllBar(
                            remaining: remaining,
                            lastGoodEnv: deleteVM.lastGoodEnv,
                            isDeletingAll: deleteVM.isDeletingAll,
                            onDeleteAll: { Task { await deleteVM.deleteAll(deletable) } }
                        )
                        .padding(.horizontal)
                    }

                    ForEach(tokens) { token in
                        PoppTokenSection(token: token, deleteVM: deleteVM)
                    }

                    Button(hasPrescriptions ? "Great Scott!" : "Try again") { onCancel() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .accessibilityHint(hasPrescriptions ? "Completes the check-in flow" : "Returns to the start to try again")
                        .padding()
                }
                .padding(.vertical)
            }

            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
        }
    }
}

private struct ConfettiView: View {
    var body: some View {
        LottieView(animation: .named("confetti"))
            .playing(loopMode: .playOnce)
    }
}

// MARK: - PoPP Token Section (collapsible with segmented Prescription/Token)

private struct PoppTokenSection: View {
    let token: PoppViewModel.PoppTokenEntry
    @ObservedObject var deleteVM: PrescriptionDeleteViewModel
    @State private var isExpanded = true
    @State private var selectedTab = 0  // 0 = Prescriptions, 1 = Token

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — tap to collapse/expand
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text("Token \(token.index + 1)")
                        .font(.headline)
                    Spacer()
                    prescriptionBadge
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Picker("", selection: $selectedTab) {
                    Text("Prescriptions").tag(0)
                    Text("Token").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                if selectedTab == 0 {
                    prescriptionsContent
                } else {
                    tokenContent
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var prescriptionBadge: some View {
        switch token.prescriptionState {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView().scaleEffect(0.7)
        case .loaded(let prescriptions, _):
            let remaining = (0..<prescriptions.count).filter { i in
                if case .deleted = deleteVM.status(for: "\(token.index):\(i)") { return false }
                return true
            }.count
            Text("\(remaining)")
                .font(.caption2).fontWeight(.bold)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(remaining == 0 ? Color.gray : Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption).foregroundColor(.orange)
        }
    }

    @ViewBuilder
    private var prescriptionsContent: some View {
        switch token.prescriptionState {
        case .idle:
            Text("Waiting...").font(.caption).foregroundColor(.secondary).padding()
        case .loading:
            VStack(spacing: 8) {
                ProgressView()
                Text("Rezepte werden abgerufen...").font(.caption).foregroundColor(.secondary)
            }
            .padding()
        case .loaded(let prescriptions, let metadata):
            if prescriptions.isEmpty {
                Text("Keine Rezepte verfügbar").font(.caption).foregroundColor(.secondary).padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(prescriptions.enumerated()), id: \.offset) { index, xml in
                        let meta = index < metadata.count ? metadata[index] : nil
                        let key = "\(token.index):\(index)"
                        let status: DeleteStatus? = meta != nil ? deleteVM.status(for: key) : nil
                        let isDeleted: Bool = {
                            if case .deleted = status { return true }
                            return false
                        }()
                        if !isDeleted {
                            PrescriptionCard(
                                index: index,
                                xml: xml,
                                deleteStatus: status,
                                onDelete: meta.map { m in {
                                    Task { await deleteVM.delete(key: key, taskId: m.taskId, accessCode: m.accessCode) }
                                } }
                            )
                            .padding(.horizontal, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.bottom, 8)
                .animation(
                    .easeInOut(duration: 0.5),
                    value: (0..<prescriptions.count).map { i -> Bool in
                        if case .deleted = deleteVM.status(for: "\(token.index):\(i)") { return true }
                        return false
                    }
                )
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text("Rezeptabruf fehlgeschlagen").font(.caption.bold())
                }
                Text(message)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }

    private var tokenContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                Text("Header").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                Text(token.header)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                Text("Payload").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                Text(token.payload)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - VZD Search Input

private struct VzdSearchInputView: View {
    let onSearch: (String?) -> Void
    let onCancel: () -> Void
    @State private var query = ""

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(PoppStrings.shared.VZD_SEARCH_TITLE).font(.title2).fontWeight(.semibold)
            TextField(PoppStrings.shared.VZD_SEARCH_HINT, text: $query)
                .textFieldStyle(.roundedBorder).padding(.horizontal)
            HStack(spacing: 12) {
                Button(PoppStrings.shared.CANCEL) { onCancel() }.buttonStyle(.bordered)
                Button(PoppStrings.shared.VZD_SEARCH_BUTTON) { onSearch(query.isEmpty ? nil : query) }
                    .buttonStyle(.borderedProminent).disabled(query.isEmpty)
            }
            Spacer()
        }
    }
}

// MARK: - CAN Input View (reuses CanInputView + KnownCardsPicker from Cardlink demo)

private struct PoppCanInputView: View {
    let knownCards: [ScoopPoppSDK.KnownCard]
    var errorMessage: String? = nil
    let onSubmitCan: (String) -> Void
    let onSubmitKnownCard: (ScoopPoppSDK.KnownCard) -> Void
    let onCancel: () -> Void
    @State private var can = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("CAN eingeben")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.top, 24)

                Text("Geben Sie die 6-stellige CAN Ihrer Gesundheitskarte ein")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.callout)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }

                CanInputView(can: $can)
                    .padding(.horizontal)

                Button("Weiter") {
                    onSubmitCan(can.trimmingCharacters(in: .whitespaces))
                }
                .buttonStyle(.borderedProminent)
                .disabled(can.count != 6)

                // Reuse existing KnownCardsPicker
                KnownCardsPicker(cards: knownCards.map { KnownCardDisplay(iccsn: $0.iccsn, can: $0.can, displayName: $0.displayName, insuranceId: $0.insuranceId, insurerId: $0.insurerId, insurerName: $0.insurerName) }) { cardCan, iccsn in
                    onSubmitCan(cardCan)
                }

                Button(PoppStrings.shared.CANCEL) { onCancel() }
                    .foregroundColor(.secondary)
                    .padding(.bottom)
            }
        }
    }
}

// MARK: - View Model

@MainActor
class PoppViewModel: ObservableObject {
    enum State {
        case idle
        case initializing
        case needsLeiSelectionMethod(hasFavorites: Bool)
        case scanningQr
        case needsVzdSearch
        case needsFavoriteSelection(favorites: [PoppFavorite])
        case needsConsent(lei: PoppLeiInfo)
        case needsAuthMethod(gidAvailable: Bool)
        case needsCan(knownCards: [ScoopPoppSDK.KnownCard], errorMessage: String?)
        case waitingForCard
        case authenticatingEgk
        case authenticatingGid
        case completed(result: PoppCheckInResult)
        case cancelled(message: String)
        case fetchingTokens
        case tokensReceived(tokens: [PoppTokenEntry])
        case error(message: String)
    }

    /// PoPP token with decoded JWT and associated prescriptions
    struct PoppTokenEntry: Identifiable {
        let id = UUID()
        let index: Int
        let raw: String
        let header: String
        let payload: String
        var prescriptionState: PrescriptionFetchState = .idle
    }

    enum PrescriptionFetchState {
        case idle
        case loading
        /// [prescriptions] and [metadata] are parallel; a metadata entry is nil when
        /// taskId/accessCode couldn't be parsed (delete icon is omitted for that row).
        case loaded(prescriptions: [String], metadata: [PrescriptionMetadata?])
        case error(message: String)
    }

    @Published var state: State = .idle
    @Published var traceLog: [String] = []
    @Published var knownCards: [ScoopPoppSDK.KnownCard] = []
    var useFakeErezept = false
    var useFileCache = false
    var useRisePoppService = false
    @Published var hasPrescriptions = false
    @Published var showConfetti = false

    private var poppFlow: PoppFlow?
    private var poppClient: MockVzdRealPoppClient?
    private var stateTask: Task<Void, Never>?
    private var traceTask: Task<Void, Never>?

    private var cacheProvider: (any ScoopPoppSDK.CacheProvider)? {
        (try? ScoopPoppSDK.SharedFileCacheProvider(
            appGroupId: DemoCacheConfig.appGroupId,
            keychainAccessGroup: DemoCacheConfig.keychainAccessGroup,
            securityLevel: .encrypted,
            fileOps: ScoopPoppSDK.DefaultFileOperations.shared,
            cryptoOps: ScoopPoppSDK.DefaultCryptoOperations.shared
        )) ?? ScoopPoppSDK.FileCacheProvider(securityLevel: .encrypted)   // F3: per-app persistent fallback
    }

    func loadKnownCards() async {
        if let cacheProvider {
            knownCards = (try? await ScoopPoppSDK.CacheProviderKt.getKnownCards(cacheProvider)) ?? []
        }
    }

    func startCheckIn(username: String, password: String, telematikId: String? = TELEMATIK_ID, themeColor: UIColor? = nil) {
        traceLog.removeAll()

        let config = PoppFlowConfig(
            zetaClient: { [weak self] () -> MockVzdRealPoppClient in
                let client = MockVzdRealPoppClient(username: username, password: password, trace: { msg in
                    DispatchQueue.main.async { self?.traceLog.append(msg) }
                }, extraHeaders: self?.useRisePoppService == true ? ["X-PoPP-Service": "RISE-DEV"] : [:])
                self?.poppClient = client
                return client
            }(),
            storage: PoppStorageImpl(),
            moduleConfig: PoppConfig(
                poppServiceBaseUrl: "https://popp-sample-server-dev.demo.scoop-gmbh.de",
                vzdBaseUrl: "https://popp-sample-server-dev.demo.scoop-gmbh.de",
                clientId: "scoop-cardlink-demo",
                developmentTransportPolicy: .secureOnly
            ),
            nfcProvider: ScoopPoppSDK.IosNfcTransceiverProvider(),
            knownCards: knownCards,
            cacheProvider: useFileCache ? cacheProvider : nil,
            // Turnkey: the SDK provider drives the system NFC sheet, so the app needs
            // no onNfcMessage/onNfcDone session wiring. (Passed explicitly because
            // these optional params aren't bridged with Kotlin defaults via SKIE.)
            onNfcDone: nil,
            onNfcMessage: nil,
            onTrace: { [weak self] message in
                DispatchQueue.main.async {
                    self?.traceLog.append(message)
                }
            },
            appUserAgent: "\(Bundle.main.bundleIdentifier ?? "unknown")/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")",
            uiContext: {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootVC = windowScene.windows.first?.rootViewController else { return nil }
                var vc = rootVC
                while let presented = vc.presentedViewController { vc = presented }
                return PoppUiContext(viewController: vc, tintColor: themeColor)
            }(),
            // GID (GesundheitsID) auth is not wired in this demo — eGK only.
            gidProvider: nil
        )
        let flow = PoppFlow(flowConfig: config)
        self.poppFlow = flow

        // Collect state changes
        stateTask = Task { [weak self] in
            for await flowState in flow.state {
                guard let self = self else { break }
                self.mapState(flowState)
            }
        }

        // Also log Swift-side events into the same trace
        addTrace("[Swift] OAuth login as \(username)...")

        flow.startCheckIn(telematikId: telematikId, workplaceId: nil, preferEgk: false)
    }

    private func mapState(_ flowState: PoppFlowState) {
        switch flowState {
        case is PoppFlowState.Idle:
            state = .idle
        case is PoppFlowState.Initializing:
            state = .initializing
        case let s as PoppFlowState.NeedsLeiSelectionMethod:
            state = .needsLeiSelectionMethod(hasFavorites: s.hasFavorites)
        case is PoppFlowState.ScanningQr:
            state = .scanningQr
        case is PoppFlowState.NeedsVzdSearch:
            state = .needsVzdSearch
        case let s as PoppFlowState.NeedsFavoriteSelection:
            state = .needsFavoriteSelection(favorites: s.favorites)
        case let s as PoppFlowState.NeedsConsent:
            // Consent handled natively by the PoPP module via showConsentSheet
            state = .needsConsent(lei: s.lei)
        case let s as PoppFlowState.NeedsAuthMethod:
            state = .needsAuthMethod(gidAvailable: s.gidAvailable)
        case let s as PoppFlowState.NeedsCan:
            state = .needsCan(knownCards: s.knownCards, errorMessage: s.errorMessage)
        case is PoppFlowState.WaitingForCard:
            state = .waitingForCard
        case is PoppFlowState.AuthenticatingEgk:
            state = .authenticatingEgk
        case is PoppFlowState.AuthenticatingGid:
            state = .authenticatingGid
        case let s as PoppFlowState.Completed:
            state = .completed(result: s.result)
            // After check-in completes, fetch PoPP tokens
            if s.result is PoppCheckInResult.Success || s.result is PoppCheckInResult.Pending {
                Task { await fetchPoppTokens() }
            }
        case let s as PoppFlowState.Cancelled:
            state = .cancelled(message: s.message)
        case let s as PoppFlowState.Error:
            state = .error(message: s.message)
        default:
            break
        }
    }

    // MARK: - Submit methods

    func submitQrScanResult(_ payload: String?) {
        poppFlow?.submitQrScanResult(payload: payload)
    }

    func submitLeiSelectionMethod(_ method: LeiSelectionMethod) {
        poppFlow?.submitLeiSelectionMethod(method: method)
    }

    func submitVzdSearch(_ query: String?) {
        poppFlow?.submitVzdSearch(query: query)
    }

    func submitFavoriteSelection(_ favorite: PoppFavorite?) {
        poppFlow?.submitFavoriteSelection(favorite: favorite)
    }

    func submitConsent(_ granted: Bool) {
        poppFlow?.submitConsent(granted: granted)
    }

    func submitAuthMethod(_ method: AuthMethod) {
        poppFlow?.submitAuthMethod(method: method)
    }

    func submitCan(_ can: String) {
        poppFlow?.submitCan(can: can)
    }

    func submitKnownCard(_ card: ScoopPoppSDK.KnownCard) {
        poppFlow?.submitKnownCard(knownCard: card)
    }

    func addTrace(_ message: String) {
        print("[PoPP] \(message)")
        traceLog.append(message)
    }

    /// Fetch PoPP tokens from ticonnect after successful check-in
    func fetchPoppTokens() async {
        state = .fetchingTokens
        addTrace("Fetching PoPP tokens...")

        let telematikId = TELEMATIK_ID
        let urlString = "https://ticonnect-dev.demo.scoop-gmbh.de/internal/popp/token-via-popp-module?telematikId=\(telematikId)"
        guard let url = URL(string: urlString) else {
            state = .error(message: "Invalid token URL")
            return
        }

        // Reuse the same OAuth token
        guard let token = poppClient?.getAccessToken() else {
            addTrace("No access token available for token fetch")
            state = .error(message: "No access token available")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        addTrace(">>> GET \(urlString)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as! HTTPURLResponse
            let body = String(data: data, encoding: .utf8) ?? ""
            addTrace("<<< \(httpResponse.statusCode): \(body.prefix(300))")

            guard httpResponse.statusCode == 200 else {
                state = .error(message: "Token fetch failed: HTTP \(httpResponse.statusCode)\n\(body)")
                return
            }

            // Parse {"workplaceId": "...", "poppTokens": ["jwt1", "jwt2"]}
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tokenStrings = json["poppTokens"] as? [String] else {
                state = .error(message: "Failed to parse token response: \(body.prefix(200))")
                return
            }
            if let workplaceId = json["workplaceId"] as? String {
                addTrace("WorkplaceId: \(workplaceId)")
            }

            addTrace("Received \(tokenStrings.count) PoPP token(s)")

            var entries = tokenStrings.enumerated().map { (i, jwt) -> PoppTokenEntry in
                let parts = jwt.split(separator: ".")
                let header = parts.count >= 1 ? decodeBase64UrlJson(String(parts[0])) : "?"
                let payload = parts.count >= 2 ? decodeBase64UrlJson(String(parts[1])) : "?"
                return PoppTokenEntry(index: i, raw: jwt, header: header, payload: payload)
            }
            state = .tokensReceived(tokens: entries)

            // Fetch prescriptions for each token in parallel
            for i in entries.indices {
                entries[i].prescriptionState = .loading
                state = .tokensReceived(tokens: entries)
                let result = await fetchPrescriptions(poppToken: entries[i].raw)
                entries[i].prescriptionState = result
                state = .tokensReceived(tokens: entries)
            }
        } catch {
            addTrace("Token fetch error: \(error)")
            state = .error(message: "Token fetch failed: \(error.localizedDescription)")
        }
    }

    private func decodeBase64UrlJson(_ str: String) -> String {
        var base64 = str.replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return str
        }
        return result
    }

    /// Fetch e-Rezept prescriptions using a PoPP token
    private func fetchPrescriptions(poppToken: String) async -> PrescriptionFetchState {
        let urlString = "https://ticonnect-dev.demo.scoop-gmbh.de/internal/popp/erezept"
        guard let url = URL(string: urlString),
              let token = poppClient?.getAccessToken() else {
            return .error(message: "No URL or access token")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(poppToken, forHTTPHeaderField: "X-PoPP-Token")
        if useFakeErezept {
            request.setValue("0xdeadbead", forHTTPHeaderField: "PRezept")
        }

        addTrace(">>> GET \(urlString)")
        addTrace(">>> X-PoPP-Token: \(poppToken.prefix(40))...")
        if useFakeErezept { addTrace(">>> PRezept: 0xdeadbead (fake)") }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as! HTTPURLResponse
            let body = String(data: data, encoding: .utf8) ?? ""
            addTrace("<<< \(httpResponse.statusCode): \(body)")

            guard httpResponse.statusCode == 200 else {
                return .error(message: "HTTP \(httpResponse.statusCode): \(body)")
            }

            // Response: {"pnResult":"...","taskXML":"...","medicationXMLs":["..."]}
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .error(message: "Failed to parse erezept response")
            }

            let prescriptions = (json["medicationXMLs"] as? [String]) ?? []
            let taskXml = json["taskXML"] as? String
            let taskMeta: [PrescriptionMetadata] = taskXml.map {
                PrescriptionMetadataParser.shared.parseAll(xml: $0)
            } ?? []
            let metadata: [PrescriptionMetadata?] = prescriptions.enumerated().map { (i, xml) in
                if i < taskMeta.count { return taskMeta[i] }
                return PrescriptionMetadataParser.shared.parseFirst(xml: xml)
            }

            addTrace("Received \(prescriptions.count) prescription XML(s); deletable=\(metadata.compactMap { $0 }.count)")
            if !prescriptions.isEmpty {
                hasPrescriptions = true
                // Confetti triggered by the view when it regains focus after NFC sheet closes
            }
            return .loaded(prescriptions: prescriptions, metadata: metadata)
        } catch {
            addTrace("eRezept fetch error: \(error)")
            return .error(message: error.localizedDescription)
        }
    }

    func cancel() {
        stateTask?.cancel()
        traceTask?.cancel()
        // poppFlow.cancel() closes the NFC session via the SDK provider (turnkey).
        poppFlow?.cancel()
        poppFlow = nil
        hasPrescriptions = false
        showConfetti = false
        state = .idle
    }

    // MARK: - OS-Mandatory Native Dialogs

    private func showConsentDialog(lei: PoppLeiInfo) {
        guard let vc = Self.topViewController() else { return }
        let alert = UIAlertController(
            title: PoppStrings.shared.CONSENT_TITLE,
            message: PoppStrings.shared.consentMessage(lei: lei),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: PoppStrings.shared.CONSENT_CONFIRM, style: .default) { [weak self] _ in
            self?.submitConsent(true)
        })
        alert.addAction(UIAlertAction(title: PoppStrings.shared.CONSENT_CANCEL, style: .cancel) { [weak self] _ in
            self?.submitConsent(false)
        })
        vc.present(alert, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else { return nil }
        var vc = root
        while let presented = vc.presentedViewController { vc = presented }
        return vc
    }
}

// MARK: - Mock Implementations (demo only)

/// Hybrid client: mocks VZD (no auth available) but uses real HTTP for eGK check-in.
/// The real PoPP-Service at the configured URL handles the APDU loop.
private class MockVzdRealPoppClient: NSObject, PoppZetaClient {
    private let username: String
    private let password: String
    private var accessToken: String?
    private let trace: (String) -> Void
    private let extraHeaders: [String: String]

    init(username: String, password: String, trace: @escaping (String) -> Void, extraHeaders: [String: String] = [:]) {
        self.username = username
        self.password = password
        self.trace = trace
        self.extraHeaders = extraHeaders
        super.init()
    }

    func getAccessToken() -> String? { accessToken }

    func __doInit() async throws {
        // OAuth Resource Owner Password Credentials — same as Cardlink flow
        trace("OAuth: Logging in as \(username)...")
        let tokenUrl = "https://auth-cardlink-dev.demo.scoop-gmbh.de/realms/cardlinkdemo/protocol/openid-connect/token"
        guard let url = URL(string: tokenUrl) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=password&client_id=cardlink-app&username=\(username)&password=\(password)&scope=openid"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "PoPP", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "OAuth failed (\(httpResponse.statusCode)): \(errorBody)"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw NSError(domain: "PoPP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse access token"])
        }
        accessToken = token
        trace("OAuth: Token acquired (\(token.prefix(20))...)")
    }

    // Transform module's FHIR-VZD request into PoPP Service practitioner-information call.
    // Module sends: GET ${vzdBaseUrl}/Organization?identifier=<tid> or ?name=<query>
    // PoPP Service: GET /popp/patient/api/practitioner/v1/practitioner-information?searchrequest=<value>
    func __executeVzdRequest(request: PoppHttpRequest) async throws -> PoppHttpResponse {
        guard let queryRange = request.url.range(of: "Organization?") else {
            return PoppHttpResponse(statusCode: 400, body: "{\"errorCode\":\"INVALID_REQUEST\"}", headers: [:])
        }
        let queryString = String(request.url[queryRange.upperBound...])
        // Extract the value after "identifier=" or "name="
        let searchValue: String
        if let eqIdx = queryString.firstIndex(of: "=") {
            searchValue = String(queryString[queryString.index(after: eqIdx)...])
        } else {
            return PoppHttpResponse(statusCode: 400, body: "{\"errorCode\":\"INVALID_REQUEST\"}", headers: [:])
        }
        let encoded = searchValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchValue
        let poppUrl = "https://popp-sample-server-dev.demo.scoop-gmbh.de/popp/patient/api/practitioner/v1/practitioner-information?searchrequest=\(encoded)"
        trace("VZD resolve: \(poppUrl)")
        let poppRequest = PoppHttpRequest(url: poppUrl, method: "GET", headers: request.headers, body: nil)
        let response = try await executeHttp(request: poppRequest)

        // Transform response: PoPP returns { "searchresult": { displayName, address, specialty, telematikId } }
        // Module expects a FHIR Bundle with Organization entries.
        guard let data = response.body.data(using: .utf8),
              let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = wrapper["searchresult"] as? [String: Any] else {
            return response
        }
        let displayName = result["displayName"] as? String ?? ""
        let address = result["address"] as? String ?? ""
        let specialty = result["specialty"] as? String ?? ""
        let tid = result["telematikId"] as? String ?? ""
        let bundle: [String: Any] = [
            "entry": [[
                "resource": [
                    "name": displayName,
                    "type": [["coding": [["display": specialty]]]],
                    "address": [["text": address]],
                    "identifier": [["value": tid]],
                ]
            ]]
        ]
        guard let bundleData = try? JSONSerialization.data(withJSONObject: bundle),
              let bundleJson = String(data: bundleData, encoding: .utf8) else {
            return response
        }
        return PoppHttpResponse(statusCode: 200, body: bundleJson, headers: [:])
    }

    // Real HTTP to PoPP-Service via URLSession
    func __executeEgkCheckIn(request: PoppHttpRequest, authorizationDetails: String) async throws -> PoppHttpResponse {
        return try await executeHttp(request: request)
    }

    func __executeGidCheckIn(request: PoppHttpRequest, authorizationDetails: String) async throws -> PoppHttpResponse {
        return try await executeHttp(request: request)
    }

    func __executeStatusRequest(request: PoppHttpRequest) async throws -> PoppHttpResponse {
        return try await executeHttp(request: request)
    }

    private func executeHttp(request: PoppHttpRequest) async throws -> PoppHttpResponse {
        trace(">>> \(request.method) \(request.url)")
        guard let url = URL(string: request.url) else {
            return PoppHttpResponse(statusCode: 400, body: "Invalid URL: \(request.url)", headers: [:])
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        for (key, value) in extraHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        // Add Bearer token
        if let token = accessToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = request.body {
            urlRequest.httpBody = body.data(using: .utf8)
        }

        // Log all request headers
        if let allHeaders = urlRequest.allHTTPHeaderFields, !allHeaders.isEmpty {
            for (key, value) in allHeaders.sorted(by: { $0.key < $1.key }) {
                let displayValue = key.lowercased() == "authorization" ? "\(value.prefix(30))..." : value
                trace(">>> \(key): \(displayValue)")
            }
        }
        if let httpBody = urlRequest.httpBody, let bodyStr = String(data: httpBody, encoding: .utf8) {
            trace(">>> Body: \(bodyStr.prefix(300))")
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let httpResponse = response as! HTTPURLResponse
        let body = String(data: data, encoding: .utf8) ?? ""

        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                headers[k] = v
            }
        }

        // Log response status + headers + body
        trace("<<< \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))")
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            trace("<<< \(key): \(value)")
        }
        trace("<<< Body: \(body.prefix(500))")
        return PoppHttpResponse(statusCode: Int32(httpResponse.statusCode), body: body, headers: headers)
    }

}
