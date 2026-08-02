import Foundation
import Security

struct DemoInternetCredential: Equatable {
    let baseURL: URL
    let username: String
    let password: String

    func validated() throws -> DemoInternetCredential {
        guard !username.isEmpty, !password.isEmpty else {
            throw DemoSharedCredentialStoreError.incompleteCredential
        }

        let normalizedURL = try Self.validatedBaseURL(baseURL)

        return DemoInternetCredential(
            baseURL: normalizedURL,
            username: username,
            password: password
        )
    }

    static func validatedBaseURL(_ baseURL: URL) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            throw DemoSharedCredentialStoreError.invalidBaseURL
        }

        let port = components.port ?? 443
        guard (1...65_535).contains(port) else {
            throw DemoSharedCredentialStoreError.invalidBaseURL
        }

        components.scheme = "https"
        components.host = host
        components.port = port == 443 ? nil : port
        guard let normalizedURL = components.url else {
            throw DemoSharedCredentialStoreError.invalidBaseURL
        }

        return normalizedURL
    }
}

struct DemoLegacyUsernamePassword: Equatable {
    let username: String
    let password: String
}

struct DemoLegacyCredentialCandidate: Equatable {
    let baseURLString: String
    let username: String
    let password: String

    fileprivate func validated() throws -> DemoInternetCredential {
        guard !baseURLString.isEmpty, !username.isEmpty, !password.isEmpty,
              let baseURL = URL(string: baseURLString)
        else {
            throw DemoCredentialMigrationError.incompleteLegacyCredential
        }
        return try DemoInternetCredential(
            baseURL: baseURL,
            username: username,
            password: password
        ).validated()
    }
}

enum DemoCredentialKind: String, CaseIterable {
    case keycloak
    case rocketChat

    fileprivate var label: String {
        switch self {
        case .keycloak:
            DemoSharedCredentialSchema.keycloakLabel
        case .rocketChat:
            DemoSharedCredentialSchema.rocketChatLabel
        }
    }
}

protocol DemoInternetCredentialReader {
    func read(_ kind: DemoCredentialKind) throws -> DemoInternetCredential?
}

protocol DemoInternetCredentialStore: DemoInternetCredentialReader {
    func write(_ credential: DemoInternetCredential, for kind: DemoCredentialKind) throws
}

protocol DemoLegacyCredentialCandidateReader {
    func read(_ kind: DemoCredentialKind) throws -> DemoLegacyCredentialCandidate?
}

protocol DemoCredentialMigrationMarkerStore {
    func isComplete(_ kind: DemoCredentialKind) -> Bool
    func markComplete(_ kind: DemoCredentialKind)
}

enum DemoCredentialMigrationError: Error {
    case incompleteCanonicalCredential(DemoCredentialKind)
    case incompleteLegacyCredential
    case readBackMismatch(DemoCredentialKind)
}

struct DemoCredentialMigrator {
    private let canonical: any DemoInternetCredentialStore
    private let legacy: any DemoLegacyCredentialCandidateReader
    private let markers: any DemoCredentialMigrationMarkerStore

    init(
        canonical: any DemoInternetCredentialStore,
        legacy: any DemoLegacyCredentialCandidateReader,
        markers: any DemoCredentialMigrationMarkerStore
    ) {
        self.canonical = canonical
        self.legacy = legacy
        self.markers = markers
    }

    func migrate(_ kind: DemoCredentialKind) throws {
        guard !markers.isComplete(kind) else {
            return
        }

        if let canonicalCredential = try canonical.read(kind) {
            do {
                _ = try canonicalCredential.validated()
            } catch {
                throw DemoCredentialMigrationError.incompleteCanonicalCredential(kind)
            }
            markers.markComplete(kind)
            return
        }

        guard let candidate = try legacy.read(kind) else {
            return
        }
        let credential = try candidate.validated()

        try canonical.write(credential, for: kind)
        guard try canonical.read(kind) == credential else {
            throw DemoCredentialMigrationError.readBackMismatch(kind)
        }
        markers.markComplete(kind)
    }
}

protocol DemoLegacyCredentialKeychainClient {
    func readCardlinkPair() throws -> DemoLegacyUsernamePassword?
    func readRocketChatValue(account: String) throws -> Data?
}

struct SecurityDemoLegacyCredentialKeychainClient: DemoLegacyCredentialKeychainClient {
    func readCardlinkPair() throws -> DemoLegacyUsernamePassword? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: "cardlink.scoopsoftware.de",
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrSynchronizable as String: true,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let item = result as? [String: Any],
                  let username = item[kSecAttrAccount as String] as? String,
                  let passwordData = item[kSecValueData as String] as? Data,
                  let password = String(data: passwordData, encoding: .utf8)
            else {
                throw DemoSharedCredentialStoreError.keychainStatus(errSecDecode)
            }
            return DemoLegacyUsernamePassword(username: username, password: password)
        case errSecItemNotFound:
            return nil
        default:
            throw DemoSharedCredentialStoreError.keychainStatus(status)
        }
    }

    func readRocketChatValue(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "de.scoopsoftware.cardlink.rocketchat",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw DemoSharedCredentialStoreError.keychainStatus(errSecDecode)
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw DemoSharedCredentialStoreError.keychainStatus(status)
        }
    }
}

struct DemoNativeLegacyCredentialReader: DemoLegacyCredentialCandidateReader {
    private let keychainClient: any DemoLegacyCredentialKeychainClient
    private let defaults: UserDefaults

    init(
        keychainClient: any DemoLegacyCredentialKeychainClient = SecurityDemoLegacyCredentialKeychainClient(),
        defaults: UserDefaults = .standard
    ) {
        self.keychainClient = keychainClient
        self.defaults = defaults
    }

    func read(_ kind: DemoCredentialKind) throws -> DemoLegacyCredentialCandidate? {
        switch kind {
        case .keycloak:
            guard let pair = try keychainClient.readCardlinkPair() else {
                return nil
            }
            return DemoLegacyCredentialCandidate(
                baseURLString: DemoSharedCredentialSchema.defaultKeycloakBaseURL.absoluteString,
                username: pair.username,
                password: pair.password
            )

        case .rocketChat:
            guard let pair = try readRocketChatPair() else {
                return nil
            }
            return DemoLegacyCredentialCandidate(
                baseURLString: defaults.string(forKey: "rcServerUrl") ?? "",
                username: pair.username,
                password: pair.password
            )
        }
    }

    private func readRocketChatPair() throws -> DemoLegacyUsernamePassword? {
        let usernameData = try keychainClient.readRocketChatValue(account: "rcUsername")
        let passwordData = try keychainClient.readRocketChatValue(account: "rcPassword")
        if usernameData != nil || passwordData != nil {
            return DemoLegacyUsernamePassword(
                username: try decode(usernameData, account: "rcUsername"),
                password: try decode(passwordData, account: "rcPassword")
            )
        }

        let username = defaults.string(forKey: "rcUsername")
        let password = defaults.string(forKey: "rcPassword")
        guard username != nil || password != nil else {
            return nil
        }
        return DemoLegacyUsernamePassword(
            username: username ?? "",
            password: password ?? ""
        )
    }

    private func decode(_ data: Data?, account: String) throws -> String {
        guard let data else {
            return ""
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw DemoSharedCredentialStoreError.invalidEncoding(attribute: account)
        }
        return value
    }
}

struct UserDefaultsDemoCredentialMigrationMarkerStore: DemoCredentialMigrationMarkerStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isComplete(_ kind: DemoCredentialKind) -> Bool {
        defaults.bool(forKey: markerKey(for: kind))
    }

    func markComplete(_ kind: DemoCredentialKind) {
        defaults.set(true, forKey: markerKey(for: kind))
    }

    private func markerKey(for kind: DemoCredentialKind) -> String {
        switch kind {
        case .keycloak:
            "demo.shared-storage.credentials.keycloak.v1"
        case .rocketChat:
            "demo.shared-storage.credentials.rocketchat.v1"
        }
    }
}

enum DemoSharedCredentialSchema {
    static let keychainAccessGroupSuffix = "group.de.scoopsoftware.nfc.healthcard"
    static let keycloakLabel = "de.scoopsoftware.cardlink.demo.keycloak"
    static let rocketChatLabel = "de.scoopsoftware.cardlink.demo.rocketchat"
    static let defaultKeycloakBaseURL = URL(
        string: "https://auth-cardlink-dev.demo.scoop-gmbh.de/realms/cardlinkdemo/protocol/openid-connect"
    )!
    static let oauthClientId = "cardlink-app"
}

enum DemoKeychainAccessibility: Hashable {
    case whenUnlockedThisDeviceOnly

    fileprivate var securityValue: CFString {
        switch self {
        case .whenUnlockedThisDeviceOnly:
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
    }
}

enum DemoInternetPasswordProtocol: Hashable {
    case https

    fileprivate var securityValue: CFString {
        switch self {
        case .https:
            kSecAttrProtocolHTTPS
        }
    }
}

struct DemoInternetPasswordRecord: Hashable {
    let label: String
    let accessGroup: String
    let server: String
    let protocolType: DemoInternetPasswordProtocol
    let port: Int
    let path: String
    let account: String
    let passwordData: Data
    let accessibility: DemoKeychainAccessibility
    let synchronizable: Bool
}

protocol DemoInternetPasswordClient {
    func read(label: String, accessGroup: String) throws -> DemoInternetPasswordRecord?
    func upsert(_ record: DemoInternetPasswordRecord) throws
}

enum DemoSharedCredentialStoreError: Error {
    case invalidAccessGroup
    case invalidBaseURL
    case incompleteCredential
    case invalidEncoding(attribute: String)
    case malformedKeychainItem
    case keychainStatus(OSStatus)
    case readBackMismatch
}

struct SecurityDemoInternetPasswordClient: DemoInternetPasswordClient {
    func read(label: String, accessGroup: String) throws -> DemoInternetPasswordRecord? {
        var query = lookupQuery(label: label, accessGroup: accessGroup)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let item = result as? [String: Any],
                  let server = item[kSecAttrServer as String] as? String,
                  let account = item[kSecAttrAccount as String] as? String,
                  let passwordData = item[kSecValueData as String] as? Data,
                  let protocolValue = item[kSecAttrProtocol as String] as? String,
                  protocolValue == (kSecAttrProtocolHTTPS as String),
                  let accessibility = item[kSecAttrAccessible as String] as? String,
                  accessibility == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String),
                  let synchronizable = item[kSecAttrSynchronizable as String] as? NSNumber,
                  !synchronizable.boolValue
            else {
                throw DemoSharedCredentialStoreError.malformedKeychainItem
            }

            let port = (item[kSecAttrPort as String] as? NSNumber)?.intValue ?? 443
            let path = item[kSecAttrPath as String] as? String ?? ""
            return DemoInternetPasswordRecord(
                label: label,
                accessGroup: accessGroup,
                server: server,
                protocolType: .https,
                port: port,
                path: path,
                account: account,
                passwordData: passwordData,
                accessibility: .whenUnlockedThisDeviceOnly,
                synchronizable: false
            )

        case errSecItemNotFound:
            return nil
        default:
            throw DemoSharedCredentialStoreError.keychainStatus(status)
        }
    }

    func upsert(_ record: DemoInternetPasswordRecord) throws {
        let query = lookupQuery(label: record.label, accessGroup: record.accessGroup)
        let values = mutableValues(for: record)
        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw DemoSharedCredentialStoreError.keychainStatus(updateStatus)
        }

        var addQuery = query
        values.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }
        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
            guard retryStatus == errSecSuccess else {
                throw DemoSharedCredentialStoreError.keychainStatus(retryStatus)
            }
            return
        }
        throw DemoSharedCredentialStoreError.keychainStatus(addStatus)
    }

    private func lookupQuery(label: String, accessGroup: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: label,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private func mutableValues(for record: DemoInternetPasswordRecord) -> [String: Any] {
        [
            kSecAttrServer as String: record.server,
            kSecAttrProtocol as String: record.protocolType.securityValue,
            kSecAttrAuthenticationType as String: kSecAttrAuthenticationTypeDefault,
            kSecAttrPort as String: record.port,
            kSecAttrPath as String: record.path,
            kSecAttrAccount as String: record.account,
            kSecValueData as String: record.passwordData,
            kSecAttrAccessible as String: record.accessibility.securityValue,
        ]
    }
}

struct DemoSharedCredentialStore: DemoInternetCredentialStore {
    private let keychainAccessGroup: String
    private let client: any DemoInternetPasswordClient

    init(
        keychainAccessGroup: String,
        client: any DemoInternetPasswordClient = SecurityDemoInternetPasswordClient()
    ) throws {
        let trimmedAccessGroup = keychainAccessGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        let accessGroupPrefix = trimmedAccessGroup.dropLast(
            DemoSharedCredentialSchema.keychainAccessGroupSuffix.count
        )
        guard !trimmedAccessGroup.isEmpty,
              !trimmedAccessGroup.contains("$("),
              trimmedAccessGroup.hasSuffix(DemoSharedCredentialSchema.keychainAccessGroupSuffix),
              !accessGroupPrefix.isEmpty,
              accessGroupPrefix.hasSuffix(".")
        else {
            throw DemoSharedCredentialStoreError.invalidAccessGroup
        }

        self.keychainAccessGroup = trimmedAccessGroup
        self.client = client
    }

    init(
        bundle: Bundle = .main,
        client: any DemoInternetPasswordClient = SecurityDemoInternetPasswordClient()
    ) throws {
        guard let keychainAccessGroup = bundle.object(
            forInfoDictionaryKey: "ScoopKeychainAccessGroup"
        ) as? String else {
            throw DemoSharedCredentialStoreError.invalidAccessGroup
        }
        try self.init(keychainAccessGroup: keychainAccessGroup, client: client)
    }

    func read(_ kind: DemoCredentialKind) throws -> DemoInternetCredential? {
        guard let record = try client.read(
            label: kind.label,
            accessGroup: keychainAccessGroup
        ) else {
            return nil
        }
        return try credential(from: record).validated()
    }

    func write(_ credential: DemoInternetCredential, for kind: DemoCredentialKind) throws {
        let normalized = try credential.validated()
        try client.upsert(record(from: normalized, kind: kind))
        guard try read(kind) == normalized else {
            throw DemoSharedCredentialStoreError.readBackMismatch
        }
    }

    private func record(
        from credential: DemoInternetCredential,
        kind: DemoCredentialKind
    ) throws -> DemoInternetPasswordRecord {
        guard let components = URLComponents(
            url: credential.baseURL,
            resolvingAgainstBaseURL: false
        ), let server = components.host else {
            throw DemoSharedCredentialStoreError.invalidBaseURL
        }
        return DemoInternetPasswordRecord(
            label: kind.label,
            accessGroup: keychainAccessGroup,
            server: server,
            protocolType: .https,
            port: components.port ?? 443,
            path: components.percentEncodedPath,
            account: credential.username,
            passwordData: Data(credential.password.utf8),
            accessibility: .whenUnlockedThisDeviceOnly,
            synchronizable: false
        )
    }

    private func credential(from record: DemoInternetPasswordRecord) throws -> DemoInternetCredential {
        guard record.accessGroup == keychainAccessGroup,
              record.protocolType == .https,
              record.accessibility == .whenUnlockedThisDeviceOnly,
              !record.synchronizable,
              let password = String(data: record.passwordData, encoding: .utf8)
        else {
            throw DemoSharedCredentialStoreError.malformedKeychainItem
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = record.server
        components.port = record.port == 443 ? nil : record.port
        components.percentEncodedPath = record.path
        guard let baseURL = components.url else {
            throw DemoSharedCredentialStoreError.malformedKeychainItem
        }
        return DemoInternetCredential(
            baseURL: baseURL,
            username: record.account,
            password: password
        )
    }
}

enum DemoSharedCredentialAccess {
    static func read(_ kind: DemoCredentialKind) -> DemoInternetCredential? {
        guard let store = try? DemoSharedCredentialStore(bundle: .main) else {
            return nil
        }
        return try? store.read(kind)
    }

    @discardableResult
    static func write(_ credential: DemoInternetCredential, for kind: DemoCredentialKind) -> Bool {
        guard let store = try? DemoSharedCredentialStore(bundle: .main) else {
            return false
        }
        do {
            try store.write(credential, for: kind)
            return true
        } catch {
            return false
        }
    }
}

enum DemoCredentialMigrationBootstrap {
    static func run() {
        let canonical: DemoSharedCredentialStore
        do {
            canonical = try DemoSharedCredentialStore(bundle: .main)
        } catch {
            print("[CredentialMigration] configuration-unavailable")
            return
        }

        let migrator = DemoCredentialMigrator(
            canonical: canonical,
            legacy: DemoNativeLegacyCredentialReader(),
            markers: UserDefaultsDemoCredentialMigrationMarkerStore()
        )

        for kind in DemoCredentialKind.allCases {
            do {
                try migrator.migrate(kind)
            } catch {
                print("[CredentialMigration] \(kind.rawValue)-failed")
            }
        }
    }
}
