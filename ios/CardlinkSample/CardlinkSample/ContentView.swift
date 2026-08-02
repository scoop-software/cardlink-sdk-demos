import SwiftUI
import ScoopCardlink
import UIKit
import Security
import CommonCrypto
import Charts
import ScoopNfcUI

enum DemoCardlinkCacheProviderFactory {
    static func makeCanonical(bundle: Bundle = .main) throws -> any ScoopCardlink.CacheProvider {
        let configuration = try DemoCacheConfig(bundle: bundle)
        return try ScoopCardlink.SharedFileCacheProvider(
            appGroupId: configuration.appGroupId,
            keychainAccessGroup: configuration.keychainAccessGroup,
            securityLevel: .encrypted,
            fileOps: ScoopCardlink.DefaultFileOperations.shared,
            cryptoOps: ScoopCardlink.DefaultCryptoOperations.shared
        )
    }
}

/// Wrapper to hold certificate data for sheet presentation.
struct CertificateItem: Identifiable {
    let id = UUID()
    let data: Data
    let title: String
}

// MARK: - App Overlay (Version + Dev Dot)

struct AppOverlay: View {
    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        #if DEBUG
        return "\(version)-dev"
        #else
        return version
        #endif
    }

    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Spacer()
                    #if DEBUG
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .padding(.trailing, 12)
                    #endif
                }
                Spacer()
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(versionString)
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.trailing, 24)
                        .padding(.bottom, 4)
                }
            }
            .ignoresSafeArea()
        }
    }
}

/// Root view with tab navigation between Scan, Charts, and Settings.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var scanHistory = ScanHistory()
    @State private var selectedTab = 3  // Default to PoPP tab
    @State private var recordMetrics: Bool = true

    // Hoisted credentials — shared between Scan and Upload tabs
    @State private var keycloakBaseURL = DemoSharedCredentialSchema.defaultKeycloakBaseURL.absoluteString
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                ScanView(
                    scanHistory: scanHistory,
                    recordMetrics: $recordMetrics,
                    keycloakBaseURL: $keycloakBaseURL,
                    username: $username,
                    password: $password
                )
                    .tabItem {
                        Label("Scan", systemImage: "wave.3.right")
                    }
                    .tag(0)

                ChartsView(scanHistory: scanHistory, recordMetrics: $recordMetrics)
                    .tabItem {
                        Label("Charts", systemImage: "chart.bar.fill")
                    }
                    .tag(1)

                UploadView(
                    keycloakBaseURL: keycloakBaseURL,
                    username: username,
                    password: password
                )
                    .tabItem {
                        Label("Upload", systemImage: "paperplane")
                    }
                    .tag(2)

                PoppCheckInView(
                    keycloakBaseURL: $keycloakBaseURL,
                    username: $username,
                    password: $password,
                    scanHistory: scanHistory
                )
                    .tabItem {
                        Label("PoPP", systemImage: "mappin.and.ellipse")
                    }
                    .tag(3)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(4)
            }

            AppOverlay()
                .allowsHitTesting(false)
        }
        .onAppear(perform: reloadCredentials)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                reloadCredentials()
            }
        }
    }

    private func reloadCredentials() {
        let credentials = KeychainHelper.shared.load()
        keycloakBaseURL = credentials?.baseURL.absoluteString
            ?? DemoSharedCredentialSchema.defaultKeycloakBaseURL.absoluteString
        username = credentials?.username ?? ""
        password = credentials?.password ?? ""
    }
}

enum DemoCardlinkEnvironmentFactory {
    static func make(oauthBaseURLString: String) -> CardlinkEnvironment {
        let trimmed = oauthBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = URL(string: trimmed)
            .flatMap { try? DemoInternetCredential.validatedBaseURL($0) }
            ?? DemoSharedCredentialSchema.defaultKeycloakBaseURL
        return make(oauthBaseURL: baseURL)
    }

    static func make(oauthBaseURL: URL) -> CardlinkEnvironment {
        let defaults = CardlinkEnvironment.Default.shared
        return CardlinkEnvironment.Custom(
            websocketUrl: defaults.websocketUrl,
            oauthConfig: OAuthConfig(
                baseUrl: oauthBaseURL.absoluteString,
                clientId: DemoSharedCredentialSchema.oauthClientId,
                clientSecret: nil,
                scopes: ["openid"]
            ),
            restBaseUrl: defaults.restBaseUrl,
            developmentTransportPolicy: .secureOnly
        )
    }
}

// MARK: - Flow Handle (Unified Wrapper)

/// Wraps CardlinkFlow and ServerDrivenFlow behind a common interface.
private class FlowHandle {
    private let _submitPhoneNumber: (String) -> Void
    private let _submitSmsCode: (String) -> Void
    private let _submitCan: (String) -> Void
    private let _submitKnownCard: (String, String?) -> Void
    private let _retry: () -> Void
    private let _cancel: () -> Void
    private let _start: () async throws -> Void
    private let _startNewCardTap: () async throws -> Void
    let collectStates: (@escaping (CardlinkFlowState) -> Void) -> Task<Void, Never>
    let collectTraceEvents: (@escaping (CardlinkTraceEvent) -> Void) -> Task<Void, Never>

    init(clientFlow flow: CardlinkFlow) {
        _submitPhoneNumber = { flow.submitPhoneNumber(phone: $0) }
        _submitSmsCode = { flow.submitSmsCode(code: $0) }
        _submitCan = { flow.submitCan(can: $0) }
        _submitKnownCard = { can, _ in flow.submitCan(can: can) }
        _retry = { flow.retry() }
        _cancel = { flow.cancel() }
        _start = { try await flow.start() }
        _startNewCardTap = { try await flow.start() }
        collectStates = { handler in
            Task { for await state in flow.state { handler(state) } }
        }
        collectTraceEvents = { handler in
            Task { for await event in flow.traceEvents { handler(event) } }
        }
    }

    init(serverFlow flow: ServerDrivenFlow) {
        _submitPhoneNumber = { flow.submitPhoneNumber(phone: $0) }
        _submitSmsCode = { flow.submitSmsCode(code: $0) }
        _submitCan = { flow.submitCan(can: $0) }
        _submitKnownCard = { can, iccsn in flow.submitKnownCard(can: can, iccsn: iccsn) }
        _retry = { flow.retry() }
        _cancel = { flow.cancel() }
        _start = { try await flow.start() }
        _startNewCardTap = { try await flow.startNewCardTap() }
        collectStates = { handler in
            Task { for await state in flow.state { handler(state) } }
        }
        collectTraceEvents = { handler in
            Task { for await event in flow.traceEvents { handler(event) } }
        }
    }

    func submitPhoneNumber(phone: String) { _submitPhoneNumber(phone) }
    func submitSmsCode(code: String) { _submitSmsCode(code) }
    func submitCan(can: String) { _submitCan(can) }
    func submitKnownCard(can: String, iccsn: String?) { _submitKnownCard(can, iccsn) }
    func retry() { _retry() }
    func cancel() { _cancel() }
    func start() async throws { try await _start() }
    func startNewCardTap() async throws { try await _startNewCardTap() }
}

// MARK: - Flow View Model

/// ObservableObject that bridges CardlinkFlow/ServerDrivenFlow state to SwiftUI.
class FlowViewModel: ObservableObject {
    @Published var flowState: CardlinkFlowState = CardlinkFlowState.Idle.shared
    @Published var traceLog: [String] = []
    @Published var started = false

    private var flow: FlowHandle?
    private var flowTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var traceTask: Task<Void, Never>?
    private var cacheProvider: (any ScoopCardlink.CacheProvider)?

    func startFlow(
        keycloakBaseURL: URL,
        username: String,
        password: String,
        useServerFlow: Bool,
        poppMode: Bool,
        enableCache: Bool,
        knownCardCan: String? = nil,
        knownCardIccsn: String? = nil
    ) {
        // Cancel previous
        cancelFlow()

        let environment = DemoCardlinkEnvironmentFactory.make(oauthBaseURL: keycloakBaseURL)
        let storage = KeychainCredentialStorage()

        let cache: (any ScoopCardlink.CacheProvider)? = enableCache
            ? (try? DemoCardlinkCacheProviderFactory.makeCanonical())
            : nil
        cacheProvider = cache

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
            poppMode: poppMode,
            uploadTargetEnv: "dev"
        )

        let handle: FlowHandle
        if useServerFlow {
            handle = FlowHandle(serverFlow: ServerDrivenFlow(config: config))
        } else {
            handle = FlowHandle(clientFlow: CardlinkFlow(config: config))
        }
        self.flow = handle

        // Pre-set known card CAN+ICCSN so the flow skips the CAN dialog
        if let can = knownCardCan, let iccsn = knownCardIccsn {
            handle.submitKnownCard(can: can, iccsn: iccsn)
        }

        traceLog.removeAll()
        started = true

        // Collect state
        stateTask = handle.collectStates { [weak self] state in
            DispatchQueue.main.async {
                self?.flowState = state
            }
        }

        // Collect trace events
        traceTask = handle.collectTraceEvents { [weak self] event in
            DispatchQueue.main.async {
                self?.traceLog.insert(String(describing: event), at: 0)
                if (self?.traceLog.count ?? 0) > 300 {
                    self?.traceLog.removeLast()
                }
            }
        }

        // Launch flow
        flowTask = Task {
            do {
                try await handle.start()
            } catch {
                print("[Flow] Error: \(error)")
            }
        }
    }

    func submitPhoneNumber(_ phone: String) { flow?.submitPhoneNumber(phone: phone) }
    func submitSmsCode(_ code: String) { flow?.submitSmsCode(code: code) }
    func submitCan(_ can: String) { flow?.submitCan(can: can) }
    func submitKnownCard(can: String, iccsn: String) { flow?.submitKnownCard(can: can, iccsn: iccsn) }
    func retry() { flow?.retry() }

    func cancelFlow() {
        flow?.cancel()
        flowTask?.cancel()
        stateTask?.cancel()
        traceTask?.cancel()
        flow = nil
        flowTask = nil
        stateTask = nil
        traceTask = nil
        started = false
        flowState = CardlinkFlowState.Idle.shared
    }

    func startNewCardTap() {
        Task {
            try? await flow?.startNewCardTap()
        }
    }

    func getKnownCards() async -> [KnownCard] {
        guard let cache = cacheProvider else { return [] }
        do {
            return try await CacheProviderKt.getKnownCards(cache)
        } catch {
            return []
        }
    }
}

// MARK: - Scan View (Flow API)

struct ScanView: View {
    @ObservedObject var scanHistory: ScanHistory
    @Binding var recordMetrics: Bool
    @Binding var keycloakBaseURL: String
    @Binding var username: String
    @Binding var password: String

    @StateObject private var viewModel = FlowViewModel()

    // Setup state
    @State private var showPassword = false
    @State private var useServerFlow = true
    @State private var poppMode = false
    @State private var enableCache = true

    // Flow input
    @AppStorage("lastPhone") private var phone = ""
    @State private var smsCode = ""
    // The CAN is a card secret, so it is NOT stored in UserDefaults/@AppStorage.
    // The SDK's CanInputView never persists it — the host owns storage. Here we
    // seed the binding from the Keychain on appear and save it back on change.
    @State private var can = ""

    // UI state
    @State private var showTraceLog = false
    @State private var knownCards: [KnownCard] = []

    var body: some View {
        NavigationView {
            Group {
                if !viewModel.started {
                    setupView
                } else {
                    flowView
                }
            }
            .navigationTitle("Cardlink Demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.started {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 8) {
                            // Flow mode badge
                            Text(useServerFlow ? (poppMode ? "PoPP" : "SERVER") : "CLIENT")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(useServerFlow ? Color.purple : Color.blue)
                                .foregroundColor(.white)
                                .clipShape(Capsule())

                            Button("Log") { showTraceLog = true }
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showTraceLog) {
            TraceLogSheet(traceLog: viewModel.traceLog)
        }
        .onAppear {
            if let creds = KeychainHelper.shared.load() {
                keycloakBaseURL = creds.baseURL.absoluteString
                username = creds.username
                password = creds.password
            }
        }
        .task {
            await loadKnownCards()
        }
        .onChange(of: viewModel.flowState) { newState in
            // Record metrics on completion or error
            if newState is CardlinkFlowState.Completed || newState is CardlinkFlowState.Error {
                let record = ScanRecord.fromPerformanceMetrics()
                let success = newState is CardlinkFlowState.Completed
                scanHistory.add(record)
                RocketChatHelper.reportIfEnabled(record: record, success: success, traceLog: viewModel.traceLog)
                if success {
                    Task { await loadKnownCards() }
                }
            }
            // Auto-fill debug SMS code
            if let needsSms = newState as? CardlinkFlowState.NeedsSmsCode,
               let debugCode = needsSms.debugSmsCode, smsCode.isEmpty {
                smsCode = debugCode
            }
        }
    }

    private func loadKnownCards() async {
        guard let cache = try? DemoCardlinkCacheProviderFactory.makeCanonical() else {
            knownCards = []
            return
        }
        knownCards = (try? await CacheProviderKt.getKnownCards(cache)) ?? []
    }

    // MARK: - Setup View

    private var setupView: some View {
        Form {
            Section("Flow Options") {
                Toggle("File Cache", isOn: $enableCache)
                Toggle("Server-Driven Flow", isOn: $useServerFlow)
                if useServerFlow {
                    Toggle("PoPP Mode", isOn: $poppMode)
                }
            }

            Section("OAuth Credentials") {
                TextField("Keycloak URL", text: $keycloakBaseURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocapitalization(.none)

                HStack {
                    if showPassword {
                        TextField("Password", text: $password)
                            .autocapitalization(.none)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("Password", text: $password)
                            .font(.system(.body, design: .monospaced))
                    }
                    Button(action: { showPassword.toggle() }) {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button(action: {
                    guard let credential = KeychainHelper.shared.save(
                        baseURL: keycloakBaseURL,
                        username: username,
                        password: password
                    ) else {
                        return
                    }
                    viewModel.startFlow(
                        keycloakBaseURL: credential.baseURL,
                        username: credential.username,
                        password: credential.password,
                        useServerFlow: useServerFlow,
                        poppMode: poppMode,
                        enableCache: enableCache
                    )
                }) {
                    HStack {
                        Spacer()
                        Text("Start Flow")
                            .bold()
                        Spacer()
                    }
                }
                .disabled(!KeychainHelper.shared.isValid(
                    baseURL: keycloakBaseURL,
                    username: username,
                    password: password
                ))
            }

            if enableCache && !knownCards.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        ForEach(knownCards, id: \.iccsn) { card in
                            Button(action: {
                                can = card.can
                                guard let credential = KeychainHelper.shared.save(
                                    baseURL: keycloakBaseURL,
                                    username: username,
                                    password: password
                                ) else {
                                    return
                                }
                                viewModel.startFlow(
                                    keycloakBaseURL: credential.baseURL,
                                    username: credential.username,
                                    password: credential.password,
                                    useServerFlow: useServerFlow,
                                    poppMode: poppMode,
                                    enableCache: enableCache,
                                    knownCardCan: card.can,
                                    knownCardIccsn: card.iccsn
                                )
                            }) {
                                EgkCardView(
                                    fullName: card.displayName ?? "—",
                                    insuranceId: card.insuranceId ?? "—",
                                    insurerId: card.insurerId ?? "—",
                                    insurerName: card.insurerName ?? "—",
                                    can: card.can
                                )
                                .frame(height: 200)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } header: {
                    Text("Known Cards")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Flow View

    private var flowView: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch viewModel.flowState {
                case is CardlinkFlowState.Idle:
                    statusCard(title: "Idle", subtitle: "Waiting to start...")

                case is CardlinkFlowState.Cancelled:
                    statusCard(title: "Cancelled", subtitle: "The flow was cancelled.")

                case is CardlinkFlowState.Connecting:
                    statusCard(title: "Connecting", subtitle: "Authenticating...", loading: true)

                case is CardlinkFlowState.NeedsPhoneNumber:
                    phoneInputView

                case let state as CardlinkFlowState.SmsRequested:
                    statusCard(title: "SMS Requested", subtitle: "Sending SMS to \(state.phoneNumber)...", loading: true)

                case let state as CardlinkFlowState.NeedsSmsCode:
                    smsCodeInputView(phoneNumber: state.phoneNumber, debugCode: state.debugSmsCode)

                case let state as CardlinkFlowState.NeedsCan:
                    canInputView(previousCan: state.previousCan)

                case is CardlinkFlowState.WaitingForCard:
                    statusCard(title: "Waiting for Card", subtitle: "Hold your eGK near the iPhone.", loading: true)

                case let state as CardlinkFlowState.ReadingCard:
                    readingCardView(progress: state.progress, stepLabel: state.stepLabel, patientData: state.patientData)

                case is CardlinkFlowState.Registering:
                    statusCard(title: "Registering", subtitle: "Registering card with server...", loading: true)

                case is CardlinkFlowState.WaitingForPrescriptions:
                    statusCard(title: "Waiting", subtitle: "Waiting for prescriptions...", loading: true)

                case let state as CardlinkFlowState.Completed:
                    CompletedContentView(
                        iccsn: state.iccsn,
                        prescriptions: state.prescriptions,
                        tokensXml: state.tokensXml,
                        patientData: state.patientData,
                        useServerFlow: useServerFlow,
                        keycloakBaseURL: keycloakBaseURL,
                        username: username,
                        password: password,
                        onScanAnother: { viewModel.startNewCardTap() },
                        onNewSession: { viewModel.cancelFlow() },
                        onTrace: { msg in viewModel.traceLog.insert(msg, at: 0) }
                    )

                case let state as CardlinkFlowState.Error:
                    errorView(error: state.error)

                default:
                    statusCard(title: "Unknown State", subtitle: String(describing: viewModel.flowState))
                }
            }
            .padding()
        }
    }

    // MARK: - Flow State Views

    private func statusCard(title: String, subtitle: String, loading: Bool = false) -> some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 48)
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundColor(.secondary)
            if loading { ProgressView() }
        }
        .frame(maxWidth: .infinity)
    }

    private var phoneInputView: some View {
        VStack(spacing: 16) {
            Text("Enter Phone Number").font(.title2.bold())
            Text("We will send you an SMS verification code.")
                .foregroundColor(.secondary)

            TextField("Phone Number (+49...)", text: $phone)
                .keyboardType(.phonePad)
                .textFieldStyle(.roundedBorder)

            Button("Submit") { viewModel.submitPhoneNumber(phone.trimmingCharacters(in: .whitespaces)) }
                .buttonStyle(.borderedProminent)
                .disabled(phone.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func smsCodeInputView(phoneNumber: String, debugCode: String?) -> some View {
        VStack(spacing: 16) {
            Text("Enter SMS Code").font(.title2.bold())
            Text("Code sent to \(phoneNumber)")
                .foregroundColor(.secondary)

            if debugCode != nil {
                Text("Debug: code received from server")
                    .font(.caption)
                    .foregroundColor(.purple)
            }

            TextField("Verification Code", text: $smsCode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)

            Button("Verify") { viewModel.submitSmsCode(smsCode.trimmingCharacters(in: .whitespaces)) }
                .buttonStyle(.borderedProminent)
                .disabled(smsCode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func canInputView(previousCan: String?) -> some View {
        VStack(spacing: 16) {
            Text("Enter CAN").font(.title2.bold())
            Text("Enter the 6-digit Card Access Number from your eGK.")
                .foregroundColor(.secondary)

            if previousCan != nil {
                Text("Previous CAN was incorrect.")
                    .foregroundColor(.red)
                    .font(.caption)
            }

            CanInputView(can: $can)
                .onAppear { if can.isEmpty { can = CanKeychain.load() ?? "" } }
                .onChange(of: can) { if $0.count == 6 { CanKeychain.save($0) } }

            Button("Submit") { viewModel.submitCan(can.trimmingCharacters(in: .whitespaces)) }
                .buttonStyle(.borderedProminent)
                .disabled(can.count != 6)

            // Known cards
            if enableCache {
                KnownCardsPicker(cards: knownCards.map { KnownCardDisplay(iccsn: $0.iccsn, can: $0.can, displayName: $0.displayName, insuranceId: $0.insuranceId, insurerId: $0.insurerId, insurerName: $0.insurerName) }) { cardCan, iccsn in
                    can = cardCan
                    viewModel.submitKnownCard(can: cardCan, iccsn: iccsn)
                }
            }
        }
    }

    private func readingCardView(progress: Float, stepLabel: String, patientData: InsuredPersonData?) -> some View {
        VStack(spacing: 16) {
            Text("Reading Card").font(.title2.bold())
            Text("Keep your card steady!").foregroundColor(.secondary)

            ProgressView(value: Double(progress))
            Text("\(Int(progress * 100))% — \(stepLabel)")
                .font(.caption)

            if let pd = patientData {
                Text("Patient: \(pd.firstName ?? "") \(pd.lastName ?? "")")
                    .font(.headline)
                if let kvnr = pd.insuranceId {
                    Text("KVNR: \(kvnr)").font(.caption)
                }
            }
        }
    }

    private func errorView(error: CardlinkFlowError) -> some View {
        let isCardDisconnect = error.recoveryAction == .retryCard
        let title = isCardDisconnect ? "Card Disconnected" : "Error"
        let body = isCardDisconnect
            ? "The card was removed. Hold your eGK to the device again."
            : error.message

        return VStack(spacing: 16) {
            Spacer().frame(height: 48)
            Text(title).font(.title2.bold())
            Text(body).foregroundColor(.secondary)
            Text("Phase: \(String(describing: error.phase))")
                .font(.caption)
                .foregroundColor(.secondary)

            if !error.isTerminal {
                Button(isCardDisconnect ? "Hold Card Again" : "Retry") { viewModel.retry() }
                    .buttonStyle(.borderedProminent)
            }

            Button("Back to Setup") { viewModel.cancelFlow() }
                .buttonStyle(.bordered)
        }
    }
}

// MARK: - Known Cards Picker

/// Framework-agnostic view model for a known card, so KnownCardsPicker works
/// with either ScoopCardlink.KnownCard or ScoopPoppSDK.KnownCard (the same
/// Kotlin type surfaces as two distinct Swift types across the two frameworks).
struct KnownCardDisplay {
    let iccsn: String
    let can: String
    let displayName: String?
    let insuranceId: String?
    let insurerId: String?
    let insurerName: String?
}

struct KnownCardsPicker: View {
    let cards: [KnownCardDisplay]
    let onSubmit: (String, String) -> Void

    var body: some View {
        if !cards.isEmpty {
            VStack(spacing: 8) {
                Text("Known Cards").font(.headline)

                ForEach(cards, id: \.iccsn) { card in
                    KnownCardItem(
                        fullName: card.displayName ?? "—",
                        insuranceId: card.insuranceId ?? "—",
                        insurerId: card.insurerId ?? "—",
                        insurerName: card.insurerName ?? "—",
                        can: card.can,
                        onTap: { onSubmit(card.can, card.iccsn) }
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Prescription Card

struct PrescriptionCard: View {
    let index: Int
    let xml: String
    var deleteStatus: DeleteStatus? = nil
    var onDelete: (() -> Void)? = nil
    @State private var showRawXml = false

    var body: some View {
        let parsed = FhirBundleParser.shared.parse(xml: xml)
        let struckThrough: Bool = {
            if case .deleted = deleteStatus ?? .idle { return true }
            return false
        }()

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Prescription \(index + 1)")
                    .font(.title3.bold())
                Spacer()
                if let status = deleteStatus, let onDelete {
                    DeleteStatusButton(status: status, onDelete: onDelete)
                }
            }
            if case let .failed(message) = deleteStatus ?? .idle {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if let parsed = parsed {
                // Medication section
                VStack(alignment: .leading, spacing: 4) {
                    Text("Medication")
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                    if let name = parsed.medication.name {
                        Text(name)
                            .font(.subheadline.bold())
                    }
                    HStack(spacing: 12) {
                        if let pzn = parsed.medication.pzn {
                            Text("PZN: \(pzn)").font(.caption).foregroundColor(.secondary)
                        }
                        if let form = parsed.medication.form {
                            Text(form).font(.caption).foregroundColor(.secondary)
                        }
                        if let ng = parsed.medication.normgroesse {
                            Text(ng).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    ForEach(Array(parsed.medication.ingredients.enumerated()), id: \.offset) { _, ingredient in
                        Text("\(ingredient.name ?? "")\(ingredient.strength.map { " (\($0))" } ?? "")")
                            .font(.caption)
                    }
                    if let dosage = parsed.dosage {
                        Text("Dosage: \(dosage)").font(.caption)
                    }
                    if let qty = parsed.quantity {
                        Text("Quantity: \(qty)").font(.caption)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .cornerRadius(8)

                // Practitioner section
                if let doc = parsed.practitioner {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prescribing Doctor")
                            .font(.caption.bold())
                            .foregroundColor(.accentColor)
                        Text("\(doc.prefix.map { "\($0) " } ?? "")\(doc.name ?? "Unknown")")
                            .font(.subheadline.bold())
                        HStack(spacing: 12) {
                            if let qual = doc.qualification {
                                Text(qual).font(.caption).foregroundColor(.secondary)
                            }
                            if let lanr = doc.lanr {
                                Text("LANR: \(lanr)").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                }

                if let date = parsed.authoredOn {
                    Text("Issued: \(date)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Toggle raw XML
            Button(showRawXml ? "Hide XML" : "Show XML") {
                showRawXml.toggle()
            }
            .font(.caption)
            .buttonStyle(.bordered)

            if showRawXml {
                Text(xml)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .opacity(struckThrough ? 0.5 : 1.0)
    }
}

// MARK: - Completed Content View (CardLink/PoPP success + delete controls)

struct CompletedContentView: View {
    let iccsn: String
    let prescriptions: [String]
    let tokensXml: String?
    let patientData: InsuredPersonData?
    let useServerFlow: Bool
    let username: String
    let password: String
    let onScanAnother: () -> Void
    let onNewSession: () -> Void
    let onTrace: (String) -> Void

    @StateObject private var deleteVM: PrescriptionDeleteViewModel

    /// Indexes of prescriptions that expose a parseable taskId+accessCode.
    private let deletable: [(key: String, index: Int, taskId: String, accessCode: String)]

    init(
        iccsn: String,
        prescriptions: [String],
        tokensXml: String?,
        patientData: InsuredPersonData?,
        useServerFlow: Bool,
        keycloakBaseURL: String,
        username: String,
        password: String,
        onScanAnother: @escaping () -> Void,
        onNewSession: @escaping () -> Void,
        onTrace: @escaping (String) -> Void
    ) {
        self.iccsn = iccsn
        self.prescriptions = prescriptions
        self.tokensXml = tokensXml
        self.patientData = patientData
        self.useServerFlow = useServerFlow
        self.username = username
        self.password = password
        self.onScanAnother = onScanAnother
        self.onNewSession = onNewSession
        self.onTrace = onTrace

        // Prefer the server-supplied Task Bundle (`tokensXml`) — taskId + accessCode per
        // prescription, parallel to [prescriptions] by index. Fall back to parsing each
        // prescription XML for flows where the metadata is inlined.
        let fromTokens: [PrescriptionMetadata] = tokensXml.map {
            PrescriptionMetadataParser.shared.parseAll(xml: $0)
        } ?? []
        let items = prescriptions.enumerated().compactMap { (i, xml) -> (String, Int, String, String)? in
            if i < fromTokens.count {
                let m = fromTokens[i]
                return ("\(iccsn):\(i)", i, m.taskId, m.accessCode)
            }
            guard let meta = parsePrescriptionMetadata(xml: xml) else { return nil }
            return ("\(iccsn):\(i)", i, meta.taskId, meta.accessCode)
        }
        self.deletable = items

        _deleteVM = StateObject(wrappedValue: PrescriptionDeleteViewModel(
            environment: DemoCardlinkEnvironmentFactory.make(
                oauthBaseURLString: keycloakBaseURL
            ),
            username: username,
            password: password,
            onTrace: onTrace
        ))
    }

    var body: some View {
        let isPoppResult = !prescriptions.isEmpty && tryDecodeJwt(prescriptions.first!) != nil
        let remaining = deleteVM.remainingCount(for: deletable.map { $0.key })

        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(isPoppResult ? "PoPP Flow Completed!" : "Flow Completed!")
                    .font(.title2.bold())
                Text("ICCSN: \(iccsn)").font(.caption)
                Text(isPoppResult ? "PoPP Token received" : "\(prescriptions.count) prescription(s) received")
                if let pd = patientData {
                    Text("Patient: \(pd.firstName ?? "") \(pd.lastName ?? "")").font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)

            if useServerFlow {
                Button("Scan Another Card") { onScanAnother() }
                    .buttonStyle(.borderedProminent)
            }

            Button("New Session") { onNewSession() }
                .buttonStyle(.bordered)

            if !deletable.isEmpty {
                DeleteAllBar(
                    remaining: remaining,
                    lastGoodEnv: deleteVM.lastGoodEnv,
                    isDeletingAll: deleteVM.isDeletingAll,
                    onDeleteAll: {
                        let items = deletable.map { (key: $0.key, taskId: $0.taskId, accessCode: $0.accessCode) }
                        Task { await deleteVM.deleteAll(items) }
                    }
                )
            }

            ForEach(Array(prescriptions.enumerated()), id: \.offset) { index, prescription in
                let jwt = tryDecodeJwt(prescription)
                if jwt != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PoPP Token \(index + 1)").font(.headline)
                        Text(jwt!)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                } else {
                    let entry = deletable.first(where: { $0.index == index })
                    let status = entry.map { deleteVM.status(for: $0.key) }
                    let isDeleted: Bool = {
                        if case .deleted = status { return true }
                        return false
                    }()
                    if !isDeleted {
                        PrescriptionCard(
                            index: index,
                            xml: prescription,
                            deleteStatus: status,
                            onDelete: entry.map { e in {
                                Task { await deleteVM.delete(key: e.key, taskId: e.taskId, accessCode: e.accessCode) }
                            } }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .animation(
            .easeInOut(duration: 0.5),
            value: deletable.map { e in
                if case .deleted = deleteVM.status(for: e.key) { return true }
                return false
            }
        )
    }
}

// MARK: - Trace Log Sheet

struct TraceLogSheet: View {
    let traceLog: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    private var filteredLog: [String] {
        if filter.isEmpty { return traceLog }
        return traceLog.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                TextField("Filter…", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                ScrollView {
                    Text(filteredLog.joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Trace Log (\(traceLog.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Copy") {
                        UIPasteboard.general.string = traceLog.joined(separator: "\n")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - JWT Decoder

private func tryDecodeJwt(_ token: String) -> String? {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { return nil }

    var payload = String(parts[1])
    let mod = payload.count % 4
    if mod > 0 { payload += String(repeating: "=", count: 4 - mod) }

    guard let data = Data(base64Encoded: payload, options: .init(rawValue: 0)),
          let json = try? JSONSerialization.jsonObject(with: data),
          let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
          let formatted = String(data: jsonData, encoding: .utf8) else {
        return nil
    }
    return formatted
}

// MARK: - Certificate Detail View

struct CertificateDetailView: View {
    let certData: Data
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                Text(parseCertificate())
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func parseCertificate() -> String {
        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            return "Failed to parse certificate"
        }

        var info = ""
        let parsed = parseX509Certificate(certData)

        info += "Subject\n"
        info += String(repeating: "=", count: 35) + "\n"
        if let summary = SecCertificateCopySubjectSummary(certificate) as String? {
            info += "Common Name: \(summary)\n"
        }
        for (label, value) in parsed.subject {
            info += "\(label): \(value)\n"
        }

        info += "\nIssuer\n"
        info += String(repeating: "=", count: 35) + "\n"
        if !parsed.issuer.isEmpty {
            for (label, value) in parsed.issuer {
                info += "\(label): \(value)\n"
            }
        } else {
            info += "(Could not parse issuer)\n"
        }

        info += "\nValidity\n"
        info += String(repeating: "=", count: 35) + "\n"
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        if let notBefore = parsed.notBefore {
            info += "Not Before: \(formatter.string(from: notBefore))\n"
        }
        if let notAfter = parsed.notAfter {
            info += "Not After:  \(formatter.string(from: notAfter))\n"
            let now = Date()
            if now < (parsed.notBefore ?? Date.distantPast) {
                info += "Status:     Not yet valid\n"
            } else if now > notAfter {
                info += "Status:     Expired\n"
            } else {
                info += "Status:     Valid\n"
            }
        }

        info += "\nDetails\n"
        info += String(repeating: "=", count: 35) + "\n"
        if let serialData = SecCertificateCopySerialNumberData(certificate, nil) as Data? {
            let serialHex = serialData.map { String(format: "%02X", $0) }.joined(separator: ":")
            info += "Serial Number: \(serialHex)\n"
        }

        info += "\nPublic Key\n"
        info += String(repeating: "=", count: 35) + "\n"
        var keyInfoFound = false
        if let publicKey = SecCertificateCopyKey(certificate) {
            if let attributes = SecKeyCopyAttributes(publicKey) as? [String: Any] {
                var keyTypeName = "Unknown"
                if let keyTypeRef = attributes[kSecAttrKeyType as String] {
                    let keyTypeStr = String(describing: keyTypeRef)
                    if keyTypeStr.lowercased().contains("rsa") { keyTypeName = "RSA" }
                    else if keyTypeStr.lowercased().contains("ec") { keyTypeName = "EC" }
                }
                if let keySize = attributes[kSecAttrKeySizeInBits as String] as? Int {
                    info += "Algorithm: \(keyTypeName)\nKey Size:  \(keySize) bits\n"
                    keyInfoFound = true
                }
            }
            if !keyInfoFound, let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? {
                if keyData.count * 8 > 1000 {
                    info += "Algorithm: RSA\nKey Size:  ~\((keyData.count - 10) * 8 / 1024 * 1024) bits\n"
                } else {
                    info += "Algorithm: EC\nKey Size:  \(keyData.count * 8 / 2) bits (approx)\n"
                }
                keyInfoFound = true
            }
        }
        if !keyInfoFound { info += "\(parsed.publicKeyAlgorithm)\n" }

        info += "\nFingerprints\n"
        info += String(repeating: "=", count: 35) + "\n"
        info += "SHA-256:\n\(sha256Fingerprint(certData))\n\n"
        info += "SHA-1:\n\(sha1Fingerprint(certData))\n"

        return info
    }

    private func parseX509Certificate(_ data: Data) -> (subject: [(String, String)], issuer: [(String, String)], notBefore: Date?, notAfter: Date?, publicKeyAlgorithm: String) {
        let bytes = [UInt8](data)
        var subject: [(String, String)] = []
        var issuer: [(String, String)] = []
        var notBefore: Date?
        var notAfter: Date?
        var publicKeyAlgorithm = "Unknown"

        var i = 0
        var dateCount = 0
        while i < bytes.count - 13 {
            if bytes[i] == 0x17 {
                let len = Int(bytes[i + 1])
                if len >= 11 && i + 2 + len <= bytes.count {
                    let timeBytes = Array(bytes[(i + 2)..<(i + 2 + len)])
                    if let date = parseUTCTime(timeBytes) {
                        if dateCount == 0 { notBefore = date } else if dateCount == 1 { notAfter = date }
                        dateCount += 1
                    }
                    i += 2 + len
                    continue
                }
            } else if bytes[i] == 0x18 {
                let len = Int(bytes[i + 1])
                if len >= 13 && i + 2 + len <= bytes.count {
                    let timeBytes = Array(bytes[(i + 2)..<(i + 2 + len)])
                    if let date = parseGeneralizedTime(timeBytes) {
                        if dateCount == 0 { notBefore = date } else if dateCount == 1 { notAfter = date }
                        dateCount += 1
                    }
                    i += 2 + len
                    continue
                }
            }
            i += 1
        }

        let oidMappings: [(oid: [UInt8], label: String)] = [
            ([0x55, 0x04, 0x03], "CN"), ([0x55, 0x04, 0x06], "C"), ([0x55, 0x04, 0x07], "L"),
            ([0x55, 0x04, 0x08], "ST"), ([0x55, 0x04, 0x0A], "O"), ([0x55, 0x04, 0x0B], "OU"),
            ([0x55, 0x04, 0x05], "Serial"),
        ]

        i = 0
        while i < bytes.count - 5 {
            if bytes[i] == 0x06 {
                let oidLen = Int(bytes[i + 1])
                if oidLen >= 3 && i + 2 + oidLen < bytes.count {
                    let oidBytes = Array(bytes[(i + 2)..<(i + 2 + oidLen)])

                    if oidBytes.count >= 3 && oidBytes[0] == 0x55 && oidBytes[1] == 0x04 {
                        let valueStart = i + 2 + oidLen
                        if valueStart < bytes.count {
                            let valueTag = bytes[valueStart]
                            if valueTag == 0x13 || valueTag == 0x0C || valueTag == 0x16 || valueTag == 0x1E {
                                let valueLen = Int(bytes[valueStart + 1])
                                if valueStart + 2 + valueLen <= bytes.count {
                                    let valueBytes = Array(bytes[(valueStart + 2)..<(valueStart + 2 + valueLen)])
                                    if let valueStr = String(bytes: valueBytes, encoding: .utf8) ?? String(bytes: valueBytes, encoding: .ascii) {
                                        for (oid, label) in oidMappings {
                                            if oidBytes.starts(with: oid) || (oidBytes.count >= 3 && oidBytes[2] == oid[2]) {
                                                if issuer.isEmpty || (issuer.count < 5 && subject.isEmpty) {
                                                    issuer.append((label, valueStr))
                                                } else {
                                                    subject.append((label, valueStr))
                                                }
                                                break
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if oidBytes.starts(with: [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01]) {
                        publicKeyAlgorithm = "RSA"
                    } else if oidBytes.starts(with: [0x2A, 0x86, 0x48, 0xCE, 0x3D]) {
                        publicKeyAlgorithm = "EC"
                    }
                }
            }
            i += 1
        }

        return (subject, issuer, notBefore, notAfter, publicKeyAlgorithm)
    }

    private func parseUTCTime(_ bytes: [UInt8]) -> Date? {
        guard bytes.count >= 13 else { return nil }
        let str = String(bytes: bytes, encoding: .ascii) ?? ""
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: str)
    }

    private func parseGeneralizedTime(_ bytes: [UInt8]) -> Date? {
        guard bytes.count >= 15 else { return nil }
        let str = String(bytes: bytes, encoding: .ascii) ?? ""
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: str)
    }

    private func sha256Fingerprint(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private func sha1Fingerprint(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}

// MARK: - Medication Info

struct MedicationInfo: Identifiable {
    let id = UUID()
    let name: String
    let dosage: String?
    let form: String?
    let pzn: String?
}

// MARK: - Prescription Result View

struct PrescriptionResultView: View {
    let medications: [MedicationInfo]
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            List {
                if medications.isEmpty {
                    Text("No medications found in prescription bundles.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(medications) { med in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(med.name).font(.headline)
                            if let dosage = med.dosage {
                                Text(dosage).font(.subheadline).foregroundColor(.secondary)
                            }
                            HStack {
                                if let form = med.form {
                                    Text(form).font(.caption).foregroundColor(.secondary)
                                }
                                if let pzn = med.pzn {
                                    Text("PZN: \(pzn)").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Prescriptions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }
}

// MARK: - Keychain Helper

final class KeychainHelper {
    static let shared = KeychainHelper()

    private init() {}

    @discardableResult
    func save(baseURL: String, username: String, password: String) -> DemoInternetCredential? {
        guard let credential = credential(
            baseURL: baseURL,
            username: username,
            password: password
        ), DemoSharedCredentialAccess.write(credential, for: .keycloak) else {
            return nil
        }
        return credential
    }

    func load() -> DemoInternetCredential? {
        DemoSharedCredentialAccess.read(.keycloak)
    }

    func isValid(baseURL: String, username: String, password: String) -> Bool {
        credential(baseURL: baseURL, username: username, password: password) != nil
    }

    private func credential(
        baseURL: String,
        username: String,
        password: String
    ) -> DemoInternetCredential? {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return try? DemoInternetCredential(
            baseURL: url,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        ).validated()
    }
}

#Preview {
    ContentView()
}

/// Keychain-backed store for the CAN — the recommended host pattern for a
/// "remember CAN" experience. The CAN is a card secret, so it lives in the
/// Keychain (encrypted, device-only) rather than UserDefaults. The SDK's
/// CanInputView never persists the CAN itself; the host seeds and saves it.
enum CanKeychain {
    private static let service = "de.scoopsoftware.cardlink.can"
    private static let account = "lastCan"

    static func save(_ can: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(can.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
