import Foundation
import ScoopNfc

enum DemoCacheConfigError: Error, Equatable {
    case invalidConfiguration(String)
}

struct DemoCacheConfig: Equatable {
    static let canonicalAppGroupId = "group.de.scoopsoftware.nfc.healthcard"
    static let legacyAppGroupIdValue = "group.de.scoopsoftware.nfc"

    let appGroupId: String
    let keychainAccessGroup: String
    let legacyAppGroupId: String
    let legacyKeychainAccessGroup: String

    init(bundle: Bundle = .main) throws {
        try self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    init(infoDictionary: [String: Any]) throws {
        appGroupId = try Self.validatedAppGroup(
            infoDictionary["ScoopAppGroupId"],
            expected: Self.canonicalAppGroupId,
            key: "ScoopAppGroupId"
        )
        keychainAccessGroup = try Self.validatedKeychainGroup(
            infoDictionary["ScoopKeychainAccessGroup"],
            expectedSuffix: Self.canonicalAppGroupId,
            key: "ScoopKeychainAccessGroup"
        )
        legacyAppGroupId = try Self.validatedAppGroup(
            infoDictionary["ScoopLegacyAppGroupId"],
            expected: Self.legacyAppGroupIdValue,
            key: "ScoopLegacyAppGroupId"
        )
        legacyKeychainAccessGroup = try Self.validatedKeychainGroup(
            infoDictionary["ScoopLegacyKeychainAccessGroup"],
            expectedSuffix: Self.legacyAppGroupIdValue,
            key: "ScoopLegacyKeychainAccessGroup"
        )

        guard Self.teamPrefix(of: keychainAccessGroup, suffix: appGroupId)
                == Self.teamPrefix(of: legacyKeychainAccessGroup, suffix: legacyAppGroupId)
        else {
            throw DemoCacheConfigError.invalidConfiguration("KeychainAccessGroupPrefix")
        }
    }

    private static func validatedAppGroup(
        _ value: Any?,
        expected: String,
        key: String
    ) throws -> String {
        let value = try validatedString(value, key: key)
        guard value == expected else {
            throw DemoCacheConfigError.invalidConfiguration(key)
        }
        return value
    }

    private static func validatedKeychainGroup(
        _ value: Any?,
        expectedSuffix: String,
        key: String
    ) throws -> String {
        let value = try validatedString(value, key: key)
        let prefix = teamPrefix(of: value, suffix: expectedSuffix)
        guard !prefix.isEmpty, prefix.hasSuffix(".") else {
            throw DemoCacheConfigError.invalidConfiguration(key)
        }
        return value
    }

    private static func validatedString(_ value: Any?, key: String) throws -> String {
        guard let string = value as? String else {
            throw DemoCacheConfigError.invalidConfiguration(key)
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            throw DemoCacheConfigError.invalidConfiguration(key)
        }
        return trimmed
    }

    private static func teamPrefix(of value: String, suffix: String) -> String {
        guard value.hasSuffix(suffix) else {
            return ""
        }
        return String(value.dropLast(suffix.count))
    }
}

enum DemoNfcCacheProviderFactory {
    static func makeCanonical(bundle: Bundle = .main) throws -> any CacheProvider {
        let configuration = try DemoCacheConfig(bundle: bundle)
        return try make(
            appGroupId: configuration.appGroupId,
            keychainAccessGroup: configuration.keychainAccessGroup
        )
    }

    static func makeLegacy(bundle: Bundle = .main) throws -> any CacheProvider {
        let configuration = try DemoCacheConfig(bundle: bundle)
        return try SharedFileCacheProvider(
            appGroupId: configuration.legacyAppGroupId,
            keychainAccessGroup: configuration.legacyKeychainAccessGroup,
            securityLevel: .encrypted,
            invalidCacheEntryPolicy: .preserve
        )
    }

    static func makeLegacyAppPrivate() -> any CacheProvider {
        FileCacheProvider(
            securityLevel: .encrypted,
            invalidCacheEntryPolicy: .preserve
        )
    }

    private static func make(
        appGroupId: String,
        keychainAccessGroup: String
    ) throws -> any CacheProvider {
        try SharedFileCacheProvider(
            appGroupId: appGroupId,
            keychainAccessGroup: keychainAccessGroup,
            securityLevel: .encrypted,
            fileOps: DefaultFileOperations.shared,
            cryptoOps: DefaultCryptoOperations.shared
        )
    }
}

enum DemoSharedStorageBootstrapResult: Equatable {
    case ready
    case cacheMigrationFailed
}

enum DemoSharedStorageCacheMigrationError: Error {
    case oneOrMoreSourcesFailed
}

enum DemoSharedStorageBootstrap {
    static func run(
        migrateCredentials: () -> Void,
        migrateCache: () async throws -> Void,
        log: (String) -> Void
    ) async -> DemoSharedStorageBootstrapResult {
        migrateCredentials()
        do {
            try await migrateCache()
            return .ready
        } catch {
            log("[SharedStorageMigration] cache-failed")
            return .cacheMigrationFailed
        }
    }

    static func run(bundle: Bundle = .main) async -> DemoSharedStorageBootstrapResult {
        await run(
            migrateCredentials: {
                DemoCredentialMigrationBootstrap.run()
            },
            migrateCache: {
                let legacyShared = try DemoNfcCacheProviderFactory.makeLegacy(bundle: bundle)
                let legacyAppPrivate = DemoNfcCacheProviderFactory.makeLegacyAppPrivate()
                let destination = try DemoNfcCacheProviderFactory.makeCanonical(bundle: bundle)
                try await migrateCaches(
                    legacyShared: ScoopNfcHealthCardCacheAdapter(provider: legacyShared),
                    legacyAppPrivate: ScoopNfcHealthCardCacheAdapter(provider: legacyAppPrivate),
                    destination: ScoopNfcHealthCardCacheAdapter(provider: destination),
                    legacySharedMarker: UserDefaultsDemoCacheMigrationMarkerStore(
                        markerKey: .legacyShared
                    ),
                    legacyAppPrivateMarker: UserDefaultsDemoCacheMigrationMarkerStore(
                        markerKey: .legacyAppPrivate
                    )
                )
            },
            log: { message in
                print(message)
            }
        )
    }

    static func migrateCaches(
        legacyShared: any DemoHealthCardCache,
        legacyAppPrivate: any DemoHealthCardCache,
        destination: any DemoHealthCardCache,
        legacySharedMarker: any DemoCacheMigrationMarkerStore,
        legacyAppPrivateMarker: any DemoCacheMigrationMarkerStore
    ) async throws {
        var migrationFailed = false

        do {
            try await HealthCardCacheMigrator(
                source: legacyShared,
                destination: destination,
                markerStore: legacySharedMarker
            ).migrate()
        } catch {
            migrationFailed = true
        }

        do {
            try await HealthCardCacheMigrator(
                source: legacyAppPrivate,
                destination: destination,
                markerStore: legacyAppPrivateMarker
            ).migrate()
        } catch {
            migrationFailed = true
        }

        if migrationFailed {
            throw DemoSharedStorageCacheMigrationError.oneOrMoreSourcesFailed
        }
    }
}

enum DemoCacheEntry: Equatable {
    case found(Data)
    case notOnCard
    case notCached
}

protocol DemoHealthCardCache {
    func allCards() async throws -> [String]
    func can(for iccsn: String) async throws -> String?
    func saveCan(_ can: String, for iccsn: String) async throws
    func cachedFiles(for iccsn: String) async throws -> [String]
    func entry(for iccsn: String, fileName: String) async throws -> DemoCacheEntry
    func put(_ data: Data, for iccsn: String, fileName: String) async throws
}

protocol DemoCacheMigrationMarkerStore: AnyObject {
    var isComplete: Bool { get }
    func markComplete()
}

enum HealthCardCacheMigrationError: Error, Equatable {
    case readBackMismatch
    case sourceEntryUnavailable
}

struct HealthCardCacheMigrator {
    let source: any DemoHealthCardCache
    let destination: any DemoHealthCardCache
    let markerStore: any DemoCacheMigrationMarkerStore

    func migrate() async throws {
        guard !markerStore.isComplete else {
            return
        }

        for iccsn in try await source.allCards() {
            try await migrateCan(for: iccsn)
            try await migrateEntries(for: iccsn)
        }

        markerStore.markComplete()
    }

    private func migrateCan(for iccsn: String) async throws {
        guard try await destination.can(for: iccsn) == nil,
              let sourceCan = try await source.can(for: iccsn) else {
            return
        }

        try await destination.saveCan(sourceCan, for: iccsn)
        guard try await destination.can(for: iccsn) == sourceCan else {
            throw HealthCardCacheMigrationError.readBackMismatch
        }
    }

    private func migrateEntries(for iccsn: String) async throws {
        for fileName in try await source.cachedFiles(for: iccsn) {
            guard try await destination.entry(for: iccsn, fileName: fileName) == .notCached else {
                continue
            }

            let sourceEntry = try await source.entry(for: iccsn, fileName: fileName)
            let data: Data
            switch sourceEntry {
            case let .found(bytes):
                data = bytes
            case .notOnCard:
                data = Data()
            case .notCached:
                throw HealthCardCacheMigrationError.sourceEntryUnavailable
            }

            try await destination.put(data, for: iccsn, fileName: fileName)
            guard try await destination.entry(for: iccsn, fileName: fileName) == sourceEntry else {
                throw HealthCardCacheMigrationError.readBackMismatch
            }
        }
    }
}

final class UserDefaultsDemoCacheMigrationMarkerStore: DemoCacheMigrationMarkerStore {
    enum MarkerKey: String {
        case legacyShared = "demo.shared-storage.cache.v1"
        case legacyAppPrivate = "demo.shared-storage.cache.app-private.v1"
    }

    private let defaults: UserDefaults
    private let markerKey: String

    init(
        defaults: UserDefaults = .standard,
        markerKey: MarkerKey = .legacyShared
    ) {
        self.defaults = defaults
        self.markerKey = markerKey.rawValue
    }

    var isComplete: Bool {
        defaults.bool(forKey: markerKey)
    }

    func markComplete() {
        defaults.set(true, forKey: markerKey)
    }
}

enum ScoopNfcHealthCardCacheAdapterError: Error {
    case unsupportedCacheResult
}

struct ScoopNfcHealthCardCacheAdapter: DemoHealthCardCache {
    private let provider: any CacheProvider

    init(provider: any CacheProvider) {
        self.provider = provider
    }

    func allCards() async throws -> [String] {
        try await provider.getAll()
    }

    func can(for iccsn: String) async throws -> String? {
        try await provider.getCan(iccsn: iccsn)
    }

    func saveCan(_ can: String, for iccsn: String) async throws {
        try await provider.saveCan(iccsn: iccsn, can: can)
    }

    func cachedFiles(for iccsn: String) async throws -> [String] {
        try await provider.getCachedFiles(iccsn: iccsn)
    }

    func entry(for iccsn: String, fileName: String) async throws -> DemoCacheEntry {
        let result = try await provider.get(iccsn: iccsn, fileName: fileName, maxAgeMs: 0)
        switch result {
        case let found as CacheResultFound:
            return .found(Self.data(from: found.data))
        case is CacheResultNotOnCard:
            return .notOnCard
        case is CacheResultNotCached:
            return .notCached
        default:
            throw ScoopNfcHealthCardCacheAdapterError.unsupportedCacheResult
        }
    }

    func put(_ data: Data, for iccsn: String, fileName: String) async throws {
        try await provider.put(
            iccsn: iccsn,
            fileName: fileName,
            data: Self.kotlinBytes(from: data)
        )
    }

    private static func data(from bytes: KotlinByteArray) -> Data {
        Data((0..<Int(bytes.size)).map { index in
            UInt8(bitPattern: bytes.get(index: Int32(index)))
        })
    }

    private static func kotlinBytes(from data: Data) -> KotlinByteArray {
        let bytes = KotlinByteArray(size: Int32(data.count))
        for (index, value) in data.enumerated() {
            bytes.set(index: Int32(index), value: Int8(bitPattern: value))
        }
        return bytes
    }
}
