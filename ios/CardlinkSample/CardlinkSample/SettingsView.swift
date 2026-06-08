import SwiftUI
import ScoopCardlink
import CommonCrypto
import ScoopNfcUI

/// Settings view with Device & SDK info and Secure Storage sections.
/// Matches the functionality of the Android demo Settings screen.
struct SettingsView: View {
    @AppStorage("scoopSignatureMode") private var scoopSignatureMode = false
    @EnvironmentObject private var themeStore: BrandThemeStore
    @State private var refreshTrigger = 0
    @State private var knownCards: [KnownCard] = []
    @State private var undoCard: (card: KnownCard, index: Int)? = nil
    @State private var undoWorkItem: DispatchWorkItem? = nil

    // Device info from SDK (top-level property)
    private var info: DeviceInfo {
        DeviceInfoKt.deviceInfo
    }

    // Credential storage for reading stored tokens
    private var credentialStorage: any CredentialStorage {
        CredentialStorageFactory.shared.create(context: nil)
    }

    // Cache provider for known cards
    private var cacheProvider: SharedFileCacheProvider {
        SharedFileCacheProvider(
            appGroupId: "group.de.scoopsoftware.nfc",
            securityLevel: .encrypted,
            fileOps: DefaultFileOperations.shared,
            cryptoOps: DefaultCryptoOperations.shared
        )
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Account Header (if logged in)
                    if let tokens = credentialStorage.getTokens() {
                        AccountHeader(accessToken: tokens.accessToken)
                            .padding(.horizontal)
                    }

                    // App Theme Picker
                    CollapsibleSection(title: "App Theme") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(BrandTheme.allCases) { theme in
                                Button {
                                    themeStore.current = theme
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(theme.previewColor)
                                            .frame(width: 16, height: 16)
                                        Text(theme.displayName)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        if themeStore.current == theme {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Device & SDK Info Section
                    CollapsibleSection(
                        title: "Device & SDK",
                        action: {
                            Button("Copy") {
                                copyDeviceInfoToClipboard()
                            }
                            .font(.subheadline)
                        }
                    ) {
                        DeviceInfoContent(info: info)
                    }
                    .padding(.horizontal)

                    // PoPP Settings
                    CollapsibleSection(title: "PoPP") {
                        Toggle("SCOOP Signature Mode", isOn: $scoopSignatureMode)
                    }
                    .padding(.horizontal)

                    // RocketChat Integration
                    RocketChatSettingsSection()
                        .padding(.horizontal)

                    // Known Cards Section
                    if !knownCards.isEmpty {
                        CollapsibleSection(
                            title: "Known Cards",
                            action: {
                                Button("Remove All") {
                                    Task {
                                        try? await cacheProvider.clear()
                                        knownCards = []
                                    }
                                }
                                .font(.subheadline)
                                .foregroundColor(.red)
                            }
                        ) {
                            ForEach(knownCards, id: \.iccsn) { card in
                                KnownCardItem(
                                    fullName: card.displayName ?? "—",
                                    insuranceId: card.insuranceId ?? "—",
                                    insurerId: card.insurerId ?? "—",
                                    insurerName: card.insurerName ?? "—",
                                    can: card.can,
                                    onSwipeDismiss: {
                                        let index = knownCards.firstIndex(where: { $0.iccsn == card.iccsn }) ?? knownCards.count
                                        withAnimation { knownCards.removeAll { $0.iccsn == card.iccsn } }
                                        // Cancel previous undo timer and commit that deletion
                                        if let prev = undoCard {
                                            undoWorkItem?.cancel()
                                            Task { try? await cacheProvider.remove(iccsn: prev.card.iccsn) }
                                        }
                                        undoCard = (card, index)
                                        let work = DispatchWorkItem {
                                            Task { try? await cacheProvider.remove(iccsn: card.iccsn) }
                                            undoCard = nil
                                        }
                                        undoWorkItem = work
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
                                    }
                                )
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Secure Storage Section
                    if hasStoredData {
                        CollapsibleSection(
                            title: "Secure Storage",
                            expanded: false,
                            action: {
                                Button("Copy") {
                                    copySecureStorageToClipboard()
                                }
                                .font(.subheadline)
                            }
                        ) {
                            SecureStorageContent(
                                credentialStorage: credentialStorage,
                                refreshTrigger: $refreshTrigger
                            )
                        }
                        .padding(.horizontal)
                    } else {
                        CollapsibleSection(
                            title: "Secure Storage",
                            expanded: false
                        ) {
                            SecureStorageContent(
                                credentialStorage: credentialStorage,
                                refreshTrigger: $refreshTrigger
                            )
                        }
                        .padding(.horizontal)
                    }

                    // UserDefaults Debug Section
                    CollapsibleSection(
                        title: "UserDefaults",
                        expanded: false
                    ) {
                        let appleKeyPrefixes = ["Apple", "NS", "AK", "com.apple", "PK", "INNext", "AddingEmojiKeybordHandled", "FactoryPresetPaths"]
                        let defaults = UserDefaults.standard.dictionaryRepresentation()
                            .filter { key, _ in !appleKeyPrefixes.contains(where: { key.hasPrefix($0) }) }
                            .sorted(by: { $0.key < $1.key })
                        ForEach(defaults, id: \.key) { key, value in
                            HStack(alignment: .top) {
                                Text(key)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                Text(String(describing: value))
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.vertical)
            }
            .navigationTitle("Settings")
            .id(refreshTrigger) // Force refresh when triggered
            .task {
                knownCards = (try? await CacheProviderKt.getKnownCards(cacheProvider)) ?? []
            }
            .overlay(alignment: .bottom) {
                if let undo = undoCard {
                    HStack {
                        Text("Card removed")
                            .foregroundColor(.white)
                        Spacer()
                        Button("Undo") {
                            undoWorkItem?.cancel()
                            knownCards.insert(undo.card, at: min(undo.index, knownCards.count))
                            undoCard = nil
                        }
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                    }
                    .padding()
                    .background(Color(.darkGray).cornerRadius(12))
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: undoCard != nil)
        }
    }

    private var hasStoredData: Bool {
        credentialStorage.getTokens() != nil
    }

    private func copyDeviceInfoToClipboard() {
        let text = """
        App: \(info.appName)
        App ID: \(info.appId)
        App Version: \(info.appVersion)
        Device: \(info.deviceVendor) \(info.deviceType)
        Platform: \(info.platform)
        SDK Version: \(info.sdkVersion)
        SDK Type: \(info.sdkType)
        """
        UIPasteboard.general.string = text
    }

    private func copySecureStorageToClipboard() {
        var text = ""

        if let tokens = credentialStorage.getTokens() {
            text += "=== OAuth Tokens ===\n"

            text += "Access Token:\n"
            text += formatTokenForClipboard(tokens.accessToken)
            text += "\n"

            if let refreshToken = tokens.refreshToken {
                text += "Refresh Token:\n"
                text += "  \(refreshToken)\n\n"
            }

            if let idToken = tokens.idToken {
                text += "ID Token:\n"
                text += formatTokenForClipboard(idToken)
                text += "\n"
            }
        }

        UIPasteboard.general.string = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatTokenForClipboard(_ token: String) -> String {
        var result = "  Raw Token:\n  \(token)\n"

        if let decoded = try? JwtDecoder.shared.decode(token: token) {
            result += "\n  Decoded JWT:\n"
            result += "  \(decoded.toFormattedString().replacingOccurrences(of: "\n", with: "\n  "))"
        }

        return result
    }
}

// MARK: - Account Header

struct AccountHeader: View {
    let accessToken: String
    @State private var showJwt = false
    @State private var svgString: String?

    private var decodedJwt: DecodedJwt? {
        try? JwtDecoder.shared.decode(token: accessToken)
    }

    private var username: String? {
        decodedJwt?.payload.preferredUsername ?? decodedJwt?.payload.name ?? decodedJwt?.payload.subject
    }

    private var email: String? {
        decodedJwt?.payload.email
    }

    private var pictureUrl: URL? {
        guard let picture = decodedJwt?.payload.picture else { return nil }
        return URL(string: picture)
    }

    private var gravatarUrl: URL? {
        guard let email = email else { return nil }
        let hash = email.lowercased().trimmingCharacters(in: .whitespaces).md5Hash()
        return URL(string: "https://www.gravatar.com/avatar/\(hash)?s=96&d=identicon")
    }

    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            if let svgString = svgString {
                SVGWebView(svgString: svgString)
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
            } else {
                AsyncImage(url: pictureUrl ?? gravatarUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        // picture URL failed (e.g. SVG not loaded yet), try Gravatar
                        AsyncImage(url: gravatarUrl) { gravatarPhase in
                            switch gravatarPhase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Image(systemName: "person.circle.fill")
                                    .resizable().foregroundColor(.gray)
                            }
                        }
                    case .empty:
                        ProgressView()
                    @unknown default:
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundColor(.gray)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                if let username = username {
                    Text(username)
                        .font(.headline)
                }
                if let email = email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                showJwt = true
            } label: {
                Image(systemName: "key.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .sheet(isPresented: $showJwt) {
            JwtDetailSheet(jwt: decodedJwt)
        }
        .task {
            // If picture URL points to SVG, fetch and render via SVGWebView
            guard let url = pictureUrl else { return }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
                let text = String(data: data, encoding: .utf8) ?? ""
                if contentType.contains("svg") || text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<svg") {
                    svgString = text
                }
            } catch {
                // Not SVG or fetch failed — AsyncImage handles it
            }
        }
    }
}

struct JwtDetailSheet: View {
    let jwt: DecodedJwt?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                if let jwt = jwt {
                    Text(jwt.toRawJson())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                } else {
                    Text("Failed to decode JWT")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .navigationTitle("Access Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                if let jwt = jwt {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Copy") {
                            UIPasteboard.general.string = jwt.toRawJson()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Collapsible Section

struct CollapsibleSection<Content: View, Action: View>: View {
    let title: String
    @State private var expanded: Bool
    let action: (() -> Action)?
    let content: () -> Content

    init(
        title: String,
        expanded: Bool = true,
        @ViewBuilder action: @escaping () -> Action,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self._expanded = State(initialValue: expanded)
        self.action = action
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Button(action: { withAnimation { expanded.toggle() } }) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    if let action = action {
                        action()
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                    }

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Content
            if expanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// Convenience initializer for optional action
extension CollapsibleSection where Action == EmptyView {
    init(
        title: String,
        expanded: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self._expanded = State(initialValue: expanded)
        self.action = nil
        self.content = content
    }
}

// MARK: - Device Info Content

/// Device & SDK info styled like Android (horizontal 3-column cards).
struct DeviceInfoContent: View {
    let info: DeviceInfo

    var body: some View {
        VStack(spacing: 8) {
            // Device info card - horizontal 3-column layout
            HStack(spacing: 0) {
                InfoItem(label: "Manufacturer", value: info.deviceVendor, alignment: .leading)
                Spacer()
                InfoItem(label: "Model", value: info.deviceType, alignment: .center)
                Spacer()
                InfoItem(label: "Platform", value: info.platform, alignment: .trailing)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)

            // SDK info card - horizontal 2-column layout
            HStack(spacing: 0) {
                InfoItem(label: "SDK Version", value: info.sdkVersion, alignment: .leading)
                Spacer()
                InfoItem(label: "SDK Type", value: info.sdkType, alignment: .trailing)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

/// Single info item with label and value stacked vertically (like Android's InfoItem).
struct InfoItem: View {
    let label: String
    let value: String
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
    }
}

// MARK: - Secure Storage Content

struct SecureStorageContent: View {
    let credentialStorage: any CredentialStorage
    @Binding var refreshTrigger: Int

    private var tokens: TokenResponse? {
        credentialStorage.getTokens()
    }

    private var rcUsername: String? { RocketChatKeychain.load(key: "rcUsername") }
    private var rcPassword: String? { RocketChatKeychain.load(key: "rcPassword") }
    private var hasRcCredentials: Bool { rcUsername != nil || rcPassword != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tokens == nil && !hasRcCredentials {
                Text("No stored credentials")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                // OAuth Tokens
                if let tokens = tokens {
                    TokenSection(tokens: tokens)
                }

                // RocketChat Keychain
                if hasRcCredentials {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RocketChat")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        if let user = rcUsername {
                            HStack(alignment: .top) {
                                Text("username")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                Text(user)
                                    .font(.system(size: 10, design: .monospaced))
                            }
                        }
                        if rcPassword != nil {
                            HStack(alignment: .top) {
                                Text("password")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                Text("••••••••")
                                    .font(.system(size: 10, design: .monospaced))
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.systemGray5))
                    .cornerRadius(6)
                }

                // Clear All Button
                Button(role: .destructive) {
                    credentialStorage.clearTokens()
                    refreshTrigger += 1
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear All Storage")
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Token Section

struct TokenSection: View {
    let tokens: TokenResponse
    @State private var expandedTokens: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OAuth Tokens")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            TokenRow(
                name: "Access Token",
                token: tokens.accessToken,
                expanded: expandedTokens.contains("access"),
                onToggle: { toggleToken("access") }
            )

            if let refreshToken = tokens.refreshToken {
                TokenRow(
                    name: "Refresh Token",
                    token: refreshToken,
                    expanded: expandedTokens.contains("refresh"),
                    onToggle: { toggleToken("refresh") }
                )
            }

            if let idToken = tokens.idToken {
                TokenRow(
                    name: "ID Token",
                    token: idToken,
                    expanded: expandedTokens.contains("id"),
                    onToggle: { toggleToken("id") }
                )
            }
        }
    }

    private func toggleToken(_ name: String) {
        withAnimation {
            if expandedTokens.contains(name) {
                expandedTokens.remove(name)
            } else {
                expandedTokens.insert(name)
            }
        }
    }
}

struct TokenRow: View {
    let name: String
    let token: String
    let expanded: Bool
    let onToggle: () -> Void

    private var decodedJwt: DecodedJwt? {
        try? JwtDecoder.shared.decode(token: token)
    }

    private var tokenSummary: String {
        if let jwt = decodedJwt {
            let username = jwt.payload.preferredUsername ?? jwt.payload.subject ?? "unknown"
            if let exp = jwt.payload.expirationTime {
                let expDate = Date(timeIntervalSince1970: Double(truncating: exp))
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                let relative = formatter.localizedString(for: expDate, relativeTo: Date())
                return "\(username) (expires \(relative))"
            }
            return username
        }
        return String(token.prefix(20)) + "..."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggle) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(tokenSummary)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                if let jwt = decodedJwt {
                    Text(jwt.toFormattedString())
                        .font(.system(.caption2, design: .monospaced))
                        .padding(8)
                        .background(Color(.systemBackground))
                        .cornerRadius(4)
                        .textSelection(.enabled)
                } else {
                    Text(token)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(3)
                        .padding(8)
                        .background(Color(.systemBackground))
                        .cornerRadius(4)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray5))
        .cornerRadius(6)
    }
}

// MARK: - MD5 Hash Extension

extension String {
    /// Returns the MD5 hash of the string as a lowercase hex string.
    func md5Hash() -> String {
        let data = Data(self.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - RocketChat Settings

struct RocketChatSettingsSection: View {
    @AppStorage("rcEnabled") private var enabled = false
    @AppStorage("rcServerUrl") private var serverUrl = ""
    @AppStorage("rcChannel") private var channel = "PoPP-Demo"
    @State private var username = ""
    @State private var password = ""
    @State private var testResult: String?
    @State private var testing = false

    private static let defaultServerUrl = "https://rocketchat.scoop-gmbh.de"

    var body: some View {
        CollapsibleSection(title: "RocketChat", expanded: false) {
            VStack(spacing: 12) {
                Toggle("Post scan results", isOn: $enabled)

                TextField("Server URL", text: $serverUrl)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: username) { _ in
                        RocketChatKeychain.save(key: "rcUsername", value: username)
                        RocketChatReporter.shared.clearAuth()
                    }

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: password) { _ in
                        RocketChatKeychain.save(key: "rcPassword", value: password)
                        RocketChatReporter.shared.clearAuth()
                    }

                TextField("Channel", text: $channel)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                Button {
                    testing = true
                    testResult = nil
                    Task {
                        do {
                            let error = try await RocketChatReporter.shared.testConnection(
                                serverUrl: serverUrl,
                                username: username,
                                password: password
                            )
                            testResult = error ?? "Connected"
                        } catch {
                            testResult = error.localizedDescription
                        }
                        testing = false
                    }
                } label: {
                    HStack {
                        if testing {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text(testing ? "Testing…" : "Test Connection")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(testing || serverUrl.isEmpty || username.isEmpty)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result == "Connected" ? .green : .red)
                }
            }
        }
        .onAppear {
            if serverUrl.isEmpty { serverUrl = Self.defaultServerUrl }
            if channel.isEmpty { channel = "PoPP-Demo" }
            username = RocketChatKeychain.load(key: "rcUsername") ?? ""
            password = RocketChatKeychain.load(key: "rcPassword") ?? ""
            // Migrate from UserDefaults if present
            let defaults = UserDefaults.standard
            if let oldUser = defaults.string(forKey: "rcUsername"), !oldUser.isEmpty {
                username = oldUser
                RocketChatKeychain.save(key: "rcUsername", value: oldUser)
                defaults.removeObject(forKey: "rcUsername")
            }
            if let oldPass = defaults.string(forKey: "rcPassword"), !oldPass.isEmpty {
                password = oldPass
                RocketChatKeychain.save(key: "rcPassword", value: oldPass)
                defaults.removeObject(forKey: "rcPassword")
            }
        }
        .onChange(of: serverUrl) { _ in RocketChatReporter.shared.clearAuth() }
    }
}

// MARK: - RocketChat Keychain Helper

enum RocketChatKeychain {
    private static let service = "de.scoopsoftware.cardlink.rocketchat"

    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

#Preview {
    SettingsView()
}
