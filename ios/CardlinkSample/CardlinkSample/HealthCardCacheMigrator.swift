import Foundation
import ScoopNfc

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
    static let markerKey = "demo.shared-storage.cache.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isComplete: Bool {
        defaults.bool(forKey: Self.markerKey)
    }

    func markComplete() {
        defaults.set(true, forKey: Self.markerKey)
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
