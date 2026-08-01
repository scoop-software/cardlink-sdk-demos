import Foundation
import Security

struct DemoCredentialPair: Equatable {
    let username: String
    let password: String
}

enum DemoCredentialKind: String, CaseIterable {
    case cardlink
    case rocketChat

    fileprivate var usernameAccount: String {
        switch self {
        case .cardlink:
            DemoSharedCredentialSchema.cardlinkUsername
        case .rocketChat:
            DemoSharedCredentialSchema.rocketChatUsername
        }
    }

    fileprivate var passwordAccount: String {
        switch self {
        case .cardlink:
            DemoSharedCredentialSchema.cardlinkPassword
        case .rocketChat:
            DemoSharedCredentialSchema.rocketChatPassword
        }
    }
}

protocol DemoCredentialPairStore {
    func read(_ kind: DemoCredentialKind) throws -> DemoCredentialPair?
    func write(_ pair: DemoCredentialPair, for kind: DemoCredentialKind) throws
}

enum DemoSharedCredentialSchema {
    static let service = "de.scoopsoftware.cardlink.demo.shared"
    static let cardlinkUsername = "cardlink.username"
    static let cardlinkPassword = "cardlink.password"
    static let rocketChatUsername = "rocketchat.username"
    static let rocketChatPassword = "rocketchat.password"
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

struct DemoKeychainItem: Hashable {
    let service: String
    let account: String
    let accessGroup: String
    let accessibility: DemoKeychainAccessibility
    let synchronizable: Bool
}

protocol DemoKeychainClient {
    func read(_ item: DemoKeychainItem) throws -> Data?
    func write(_ data: Data, to item: DemoKeychainItem) throws
}

enum DemoSharedCredentialStoreError: Error {
    case invalidAccessGroup
    case invalidEncoding(account: String)
    case keychainStatus(OSStatus)
    case readBackMismatch
}

struct SecurityDemoKeychainClient: DemoKeychainClient {
    func read(_ item: DemoKeychainItem) throws -> Data? {
        var query = baseQuery(for: item)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

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

    func write(_ data: Data, to item: DemoKeychainItem) throws {
        let query = baseQuery(for: item)
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw DemoSharedCredentialStoreError.keychainStatus(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = item.accessibility.securityValue
        addQuery[kSecAttrSynchronizable as String] = item.synchronizable
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw DemoSharedCredentialStoreError.keychainStatus(addStatus)
        }
    }

    private func baseQuery(for item: DemoKeychainItem) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: item.service,
            kSecAttrAccount as String: item.account,
            kSecAttrAccessGroup as String: item.accessGroup,
            kSecAttrSynchronizable as String: item.synchronizable,
        ]
    }
}

struct DemoSharedCredentialStore: DemoCredentialPairStore {
    private let keychainAccessGroup: String
    private let client: DemoKeychainClient

    init(
        keychainAccessGroup: String,
        client: DemoKeychainClient = SecurityDemoKeychainClient()
    ) throws {
        let trimmedAccessGroup = keychainAccessGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccessGroup.isEmpty,
              !trimmedAccessGroup.contains("$(")
        else {
            throw DemoSharedCredentialStoreError.invalidAccessGroup
        }

        self.keychainAccessGroup = trimmedAccessGroup
        self.client = client
    }

    init(
        bundle: Bundle = .main,
        client: DemoKeychainClient = SecurityDemoKeychainClient()
    ) throws {
        guard let keychainAccessGroup = bundle.object(
            forInfoDictionaryKey: "ScoopKeychainAccessGroup"
        ) as? String else {
            throw DemoSharedCredentialStoreError.invalidAccessGroup
        }
        try self.init(keychainAccessGroup: keychainAccessGroup, client: client)
    }

    func read(_ kind: DemoCredentialKind) throws -> DemoCredentialPair? {
        let usernameData = try client.read(item(account: kind.usernameAccount))
        let passwordData = try client.read(item(account: kind.passwordAccount))

        guard usernameData != nil || passwordData != nil else {
            return nil
        }

        return DemoCredentialPair(
            username: try decode(usernameData, account: kind.usernameAccount),
            password: try decode(passwordData, account: kind.passwordAccount)
        )
    }

    func write(_ pair: DemoCredentialPair, for kind: DemoCredentialKind) throws {
        try client.write(Data(pair.username.utf8), to: item(account: kind.usernameAccount))
        try client.write(Data(pair.password.utf8), to: item(account: kind.passwordAccount))

        guard try read(kind) == pair else {
            throw DemoSharedCredentialStoreError.readBackMismatch
        }
    }

    private func item(account: String) -> DemoKeychainItem {
        DemoKeychainItem(
            service: DemoSharedCredentialSchema.service,
            account: account,
            accessGroup: keychainAccessGroup,
            accessibility: .whenUnlockedThisDeviceOnly,
            synchronizable: false
        )
    }

    private func decode(_ data: Data?, account: String) throws -> String {
        guard let data else {
            return ""
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw DemoSharedCredentialStoreError.invalidEncoding(account: account)
        }
        return value
    }
}
