import Foundation
import ScoopCardlink
import ScoopNfc
import XCTest
@testable import CardlinkDemo

final class FlowViewModelTests: XCTestCase {
    func testCancelledSdkStateReturnsToSetup() {
        let viewModel = FlowViewModel()
        viewModel.started = true

        viewModel.receiveFlowState(CardlinkFlowState.Cancelled.shared)

        XCTAssertFalse(viewModel.started)
        XCTAssertTrue(viewModel.flowState is CardlinkFlowState.Idle)
    }
}

final class HealthCardCacheMigratorTests: XCTestCase {
    func testCacheConfigurationLoadsCanonicalAndLegacyGroups() throws {
        let configuration = try DemoCacheConfig(infoDictionary: [
            "ScoopAppGroupId": "group.de.scoopsoftware.nfc.healthcard",
            "ScoopKeychainAccessGroup": "TESTTEAM.group.de.scoopsoftware.nfc.healthcard",
            "ScoopLegacyAppGroupId": "group.de.scoopsoftware.nfc",
            "ScoopLegacyKeychainAccessGroup": "TESTTEAM.group.de.scoopsoftware.nfc",
        ])

        XCTAssertEqual(configuration.appGroupId, "group.de.scoopsoftware.nfc.healthcard")
        XCTAssertEqual(
            configuration.keychainAccessGroup,
            "TESTTEAM.group.de.scoopsoftware.nfc.healthcard"
        )
        XCTAssertEqual(configuration.legacyAppGroupId, "group.de.scoopsoftware.nfc")
        XCTAssertEqual(
            configuration.legacyKeychainAccessGroup,
            "TESTTEAM.group.de.scoopsoftware.nfc"
        )
    }

    func testCacheConfigurationRejectsMissingEmptyAndUnexpandedValues() {
        let valid = [
            "ScoopAppGroupId": "group.de.scoopsoftware.nfc.healthcard",
            "ScoopKeychainAccessGroup": "TESTTEAM.group.de.scoopsoftware.nfc.healthcard",
            "ScoopLegacyAppGroupId": "group.de.scoopsoftware.nfc",
            "ScoopLegacyKeychainAccessGroup": "TESTTEAM.group.de.scoopsoftware.nfc",
        ]

        for key in valid.keys {
            var missing = valid
            missing.removeValue(forKey: key)
            XCTAssertThrowsError(try DemoCacheConfig(infoDictionary: missing))

            var empty = valid
            empty[key] = "  "
            XCTAssertThrowsError(try DemoCacheConfig(infoDictionary: empty))

            var unresolved = valid
            unresolved[key] = "$(UNRESOLVED_SETTING)"
            XCTAssertThrowsError(try DemoCacheConfig(infoDictionary: unresolved))
        }
    }

    func testSharedStorageBootstrapMigratesCredentialsBeforeCache() async {
        let recorder = ThreadSafeStringRecorder()

        let result = await DemoSharedStorageBootstrap.run(
            migrateCredentials: { recorder.append("credentials") },
            migrateCache: { recorder.append("cache") },
            log: { recorder.append($0) }
        )

        XCTAssertEqual(result, .ready)
        XCTAssertEqual(recorder.values, ["credentials", "cache"])
    }

    func testSharedStorageBootstrapContinuesWithCanonicalStorageAfterCacheFailure() async {
        let recorder = ThreadSafeStringRecorder()

        let result = await DemoSharedStorageBootstrap.run(
            migrateCredentials: { recorder.append("credentials") },
            migrateCache: {
                recorder.append("cache")
                throw TestCacheFailure()
            },
            log: { recorder.append($0) }
        )

        XCTAssertEqual(result, .cacheMigrationFailed)
        XCTAssertEqual(
            recorder.values,
            ["credentials", "cache", "[SharedStorageMigration] cache-failed"]
        )
    }

    func testCacheMigrationIncludesAppPrivateFallbackAfterSharedMigrationCompleted() async throws {
        let legacyShared = FakeHealthCardCache()
        let legacyAppPrivate = FakeHealthCardCache(
            cards: ["fallback-card"],
            cans: ["fallback-card": "123456"]
        )
        let destination = FakeHealthCardCache()
        let sharedMarker = FakeCacheMigrationMarkerStore(isComplete: true)
        let appPrivateMarker = FakeCacheMigrationMarkerStore()

        try await DemoSharedStorageBootstrap.migrateCaches(
            legacyShared: legacyShared,
            legacyAppPrivate: legacyAppPrivate,
            destination: destination,
            legacySharedMarker: sharedMarker,
            legacyAppPrivateMarker: appPrivateMarker
        )

        XCTAssertEqual(destination.cans, ["fallback-card": "123456"])
        XCTAssertEqual(legacyShared.allCardsCallCount, 0)
        XCTAssertEqual(legacyAppPrivate.allCardsCallCount, 1)
        XCTAssertTrue(appPrivateMarker.isComplete)
    }

    func testAppPrivateMigrationStillRunsWhenLegacySharedMigrationFails() async {
        let legacyShared = FakeHealthCardCache(cards: ["broken-shared-card"])
        legacyShared.failure = TestCacheFailure()
        let legacyAppPrivate = FakeHealthCardCache(
            cards: ["fallback-card"],
            cans: ["fallback-card": "123456"]
        )
        let destination = FakeHealthCardCache()
        let sharedMarker = FakeCacheMigrationMarkerStore()
        let appPrivateMarker = FakeCacheMigrationMarkerStore()

        do {
            try await DemoSharedStorageBootstrap.migrateCaches(
                legacyShared: legacyShared,
                legacyAppPrivate: legacyAppPrivate,
                destination: destination,
                legacySharedMarker: sharedMarker,
                legacyAppPrivateMarker: appPrivateMarker
            )
            XCTFail("Expected a failed legacy source to keep the bootstrap retryable")
        } catch {
            XCTAssertEqual(destination.cans, ["fallback-card": "123456"])
            XCTAssertFalse(sharedMarker.isComplete)
            XCTAssertTrue(appPrivateMarker.isComplete)
        }
    }

    func testScoopNfcAdapterMapsThePublicCacheAPI() async throws {
        let adapter = ScoopNfcHealthCardCacheAdapter(provider: MemoryCacheProvider())
        let initiallyUncached = try await adapter.entry(
            for: "adapter-card",
            fileName: "EF.VD"
        )

        XCTAssertEqual(initiallyUncached, .notCached)

        try await adapter.saveCan("123456", for: "adapter-card")
        try await adapter.put(Data([0x00, 0x80, 0xFF]), for: "adapter-card", fileName: "EF.VD")
        try await adapter.put(Data(), for: "adapter-card", fileName: "EF.GVD")

        let allCards = try await adapter.allCards()
        let can = try await adapter.can(for: "adapter-card")
        let cachedFiles = try await adapter.cachedFiles(for: "adapter-card")
        let found = try await adapter.entry(for: "adapter-card", fileName: "EF.VD")
        let notOnCard = try await adapter.entry(for: "adapter-card", fileName: "EF.GVD")

        XCTAssertEqual(allCards, ["adapter-card"])
        XCTAssertEqual(can, "123456")
        XCTAssertEqual(Set(cachedFiles), ["EF.VD", "EF.GVD"])
        XCTAssertEqual(found, .found(Data([0x00, 0x80, 0xFF])))
        XCTAssertEqual(notOnCard, .notOnCard)
    }

    func testAppPrivateCacheWrittenByCardlinkCanBeReadByNfcMigrationProvider() async throws {
        let directory = NSTemporaryDirectory()
            .appending("cache-provider-interop-")
            .appending(UUID().uuidString)
        let writer = ScoopCardlink.FileCacheProvider(
            directory: directory,
            securityLevel: ScoopCardlink.SecurityLevel.encrypted
        )
        let reader = ScoopNfc.FileCacheProvider(
            directory: directory,
            securityLevel: ScoopNfc.SecurityLevel.encrypted
        )
        addTeardownBlock {
            try? await writer.clear()
        }

        try await writer.saveCan(iccsn: "interop-card", can: "123456")
        let cards = try await reader.getAll()
        let can = try await reader.getCan(iccsn: "interop-card")

        XCTAssertEqual(cards, ["interop-card"])
        XCTAssertEqual(can, "123456")
    }

    func testCopiesCanWhenDestinationCanIsAbsent() async throws {
        let source = FakeHealthCardCache(
            cards: ["source-card"],
            cans: ["source-card": "123456"]
        )
        let destination = FakeHealthCardCache()
        let marker = FakeCacheMigrationMarkerStore()

        try await makeMigrator(source: source, destination: destination, marker: marker).migrate()

        XCTAssertEqual(destination.cans, ["source-card": "123456"])
        XCTAssertEqual(destination.saveCanCalls, [.init(iccsn: "source-card", can: "123456")])
    }

    func testPreservesExistingDestinationCan() async throws {
        let source = FakeHealthCardCache(
            cards: ["source-card"],
            cans: ["source-card": "123456"]
        )
        let destination = FakeHealthCardCache(cans: ["source-card": "654321"])

        try await makeMigrator(source: source, destination: destination).migrate()

        XCTAssertEqual(destination.cans, ["source-card": "654321"])
        XCTAssertTrue(destination.saveCanCalls.isEmpty)
    }

    func testCopiesFoundBytesWhenDestinationIsNotCached() async throws {
        let bytes = Data([0x01, 0x80, 0xFF])
        let source = FakeHealthCardCache(
            cards: ["source-card"],
            cans: ["source-card": "123456"],
            entries: [.init(iccsn: "source-card", fileName: "EF.VD"): .found(bytes)]
        )
        let destination = FakeHealthCardCache(cans: ["source-card": "654321"])

        try await makeMigrator(source: source, destination: destination).migrate()

        XCTAssertEqual(
            destination.entries[.init(iccsn: "source-card", fileName: "EF.VD")],
            .found(bytes)
        )
        XCTAssertEqual(destination.putCalls.map(\.data), [bytes])
    }

    func testCopiesNotOnCardMarkerAsEmptyData() async throws {
        let key = FakeHealthCardCache.EntryKey(iccsn: "source-card", fileName: "EF.GVD")
        let source = FakeHealthCardCache(
            cards: ["source-card"],
            cans: ["source-card": "123456"],
            entries: [key: .notOnCard]
        )
        let destination = FakeHealthCardCache(cans: ["source-card": "654321"])

        try await makeMigrator(source: source, destination: destination).migrate()

        XCTAssertEqual(destination.entries[key], .notOnCard)
        XCTAssertEqual(destination.putCalls.map(\.data), [Data()])
    }

    func testPreservesEveryExistingDestinationEntry() async throws {
        let foundKey = FakeHealthCardCache.EntryKey(iccsn: "source-card", fileName: "EF.VD")
        let absentKey = FakeHealthCardCache.EntryKey(iccsn: "source-card", fileName: "EF.GVD")
        let source = FakeHealthCardCache(
            cards: ["source-card"],
            cans: ["source-card": "123456"],
            entries: [
                foundKey: .found(Data([0x01])),
                absentKey: .found(Data([0x02])),
            ]
        )
        let destination = FakeHealthCardCache(
            cans: ["source-card": "654321"],
            entries: [
                foundKey: .found(Data([0x99])),
                absentKey: .notOnCard,
            ]
        )

        try await makeMigrator(source: source, destination: destination).migrate()

        XCTAssertEqual(destination.entries[foundKey], .found(Data([0x99])))
        XCTAssertEqual(destination.entries[absentKey], .notOnCard)
        XCTAssertTrue(destination.putCalls.isEmpty)
    }

    func testCopiesOnlyMissingEntriesAcrossMultipleCards() async throws {
        let cardOneMissing = FakeHealthCardCache.EntryKey(iccsn: "card-one", fileName: "EF.VD")
        let cardOneExisting = FakeHealthCardCache.EntryKey(iccsn: "card-one", fileName: "EF.PD")
        let cardTwoMissing = FakeHealthCardCache.EntryKey(iccsn: "card-two", fileName: "EF.GVD")
        let source = FakeHealthCardCache(
            cards: ["card-one", "card-two"],
            cans: ["card-one": "111111", "card-two": "222222"],
            entries: [
                cardOneMissing: .found(Data([0x01])),
                cardOneExisting: .found(Data([0x02])),
                cardTwoMissing: .notOnCard,
            ]
        )
        let destination = FakeHealthCardCache(
            cans: ["card-one": "999999"],
            entries: [cardOneExisting: .found(Data([0x77]))]
        )

        try await makeMigrator(source: source, destination: destination).migrate()

        XCTAssertEqual(destination.cans, ["card-one": "999999", "card-two": "222222"])
        XCTAssertEqual(destination.entries[cardOneMissing], .found(Data([0x01])))
        XCTAssertEqual(destination.entries[cardOneExisting], .found(Data([0x77])))
        XCTAssertEqual(destination.entries[cardTwoMissing], .notOnCard)
        XCTAssertEqual(Set(destination.putCalls.map(\.key)), [cardOneMissing, cardTwoMissing])
    }

    func testCanReadBackMismatchLeavesMarkerUnset() async {
        let source = FakeHealthCardCache(
            cards: ["source-card"],
            cans: ["source-card": "123456"]
        )
        let destination = FakeHealthCardCache()
        destination.canReadOverrides["source-card"] = "000000"
        let marker = FakeCacheMigrationMarkerStore()

        await assertMigrationFailsWithVerificationError(
            source: source,
            destination: destination,
            marker: marker
        )
    }

    func testFoundEntryReadBackMismatchLeavesMarkerUnset() async {
        let key = FakeHealthCardCache.EntryKey(iccsn: "source-card", fileName: "EF.VD")
        let source = FakeHealthCardCache(
            cards: ["source-card"],
            cans: ["source-card": "123456"],
            entries: [key: .found(Data([0x01]))]
        )
        let destination = FakeHealthCardCache(cans: ["source-card": "654321"])
        destination.entryReadOverrides[key] = .found(Data([0x02]))
        let marker = FakeCacheMigrationMarkerStore()

        await assertMigrationFailsWithVerificationError(
            source: source,
            destination: destination,
            marker: marker
        )
    }

    func testNotOnCardReadBackMismatchLeavesMarkerUnset() async {
        let key = FakeHealthCardCache.EntryKey(iccsn: "source-card", fileName: "EF.GVD")
        let source = FakeHealthCardCache(
            cards: ["source-card"],
            cans: ["source-card": "123456"],
            entries: [key: .notOnCard]
        )
        let destination = FakeHealthCardCache(cans: ["source-card": "654321"])
        destination.entryReadOverrides[key] = .notCached
        let marker = FakeCacheMigrationMarkerStore()

        await assertMigrationFailsWithVerificationError(
            source: source,
            destination: destination,
            marker: marker
        )
    }

    func testUnavailableEnumeratedSourceEntryLeavesMarkerUnset() async {
        let key = FakeHealthCardCache.EntryKey(iccsn: "source-card", fileName: "EF.VD")
        let source = FakeHealthCardCache(
            cards: ["source-card"],
            cans: ["source-card": "123456"],
            entries: [key: .notCached],
            enumeratedFiles: ["source-card": ["EF.VD"]]
        )
        let marker = FakeCacheMigrationMarkerStore()

        do {
            try await makeMigrator(source: source, marker: marker).migrate()
            XCTFail("Expected migration to reject an unavailable enumerated source entry")
        } catch let error as HealthCardCacheMigrationError {
            XCTAssertEqual(error, .sourceEntryUnavailable)
            XCTAssertFalse(marker.isComplete)
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }

    func testCacheFailureLeavesMarkerUnset() async {
        let source = FakeHealthCardCache(cards: ["source-card"])
        source.failure = TestCacheFailure()
        let marker = FakeCacheMigrationMarkerStore()

        do {
            try await makeMigrator(source: source, marker: marker).migrate()
            XCTFail("Expected cache failure")
        } catch is TestCacheFailure {
            XCTAssertFalse(marker.isComplete)
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }

    func testSuccessfulMigrationMarksCompletion() async throws {
        let marker = FakeCacheMigrationMarkerStore()

        try await makeMigrator(marker: marker).migrate()

        XCTAssertTrue(marker.isComplete)
        XCTAssertEqual(marker.markCompleteCallCount, 1)
    }

    func testCompletionMarkerMakesRerunNoOp() async throws {
        let source = FakeHealthCardCache(cards: ["source-card"])
        let destination = FakeHealthCardCache()
        let marker = FakeCacheMigrationMarkerStore(isComplete: true)

        try await makeMigrator(source: source, destination: destination, marker: marker).migrate()

        XCTAssertEqual(source.allCardsCallCount, 0)
        XCTAssertTrue(destination.saveCanCalls.isEmpty)
        XCTAssertTrue(destination.putCalls.isEmpty)
        XCTAssertEqual(marker.markCompleteCallCount, 0)
    }

    func testMigrationErrorsDoNotExposeCardOrFileIdentifiers() async {
        let secretCard = "SECRET-ICCSN"
        let secretFile = "SECRET-FILE"
        let key = FakeHealthCardCache.EntryKey(iccsn: secretCard, fileName: secretFile)
        let source = FakeHealthCardCache(
            cards: [secretCard],
            cans: [secretCard: "123456"],
            entries: [key: .notCached],
            enumeratedFiles: [secretCard: [secretFile]]
        )

        do {
            try await makeMigrator(source: source).migrate()
            XCTFail("Expected migration error")
        } catch {
            let description = String(describing: error)
            XCTAssertFalse(description.contains(secretCard))
            XCTAssertFalse(description.contains(secretFile))
        }
    }

    private func makeMigrator(
        source: FakeHealthCardCache = FakeHealthCardCache(),
        destination: FakeHealthCardCache = FakeHealthCardCache(),
        marker: FakeCacheMigrationMarkerStore = FakeCacheMigrationMarkerStore()
    ) -> HealthCardCacheMigrator {
        HealthCardCacheMigrator(source: source, destination: destination, markerStore: marker)
    }

    private func assertMigrationFailsWithVerificationError(
        source: FakeHealthCardCache,
        destination: FakeHealthCardCache,
        marker: FakeCacheMigrationMarkerStore
    ) async {
        do {
            try await makeMigrator(
                source: source,
                destination: destination,
                marker: marker
            ).migrate()
            XCTFail("Expected read-back verification failure")
        } catch let error as HealthCardCacheMigrationError {
            XCTAssertEqual(error, .readBackMismatch)
            XCTAssertFalse(marker.isComplete)
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }
}

private final class ThreadSafeStringRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private final class FakeHealthCardCache: DemoHealthCardCache {
    struct EntryKey: Hashable {
        let iccsn: String
        let fileName: String
    }

    struct SavedCan: Equatable {
        let iccsn: String
        let can: String
    }

    struct PutCall: Equatable {
        let key: EntryKey
        let data: Data
    }

    var cards: [String]
    var cans: [String: String]
    var entries: [EntryKey: DemoCacheEntry]
    var enumeratedFiles: [String: [String]]
    var canReadOverrides: [String: String?] = [:]
    var entryReadOverrides: [EntryKey: DemoCacheEntry] = [:]
    var failure: Error?
    private(set) var allCardsCallCount = 0
    private(set) var saveCanCalls: [SavedCan] = []
    private(set) var putCalls: [PutCall] = []

    init(
        cards: [String] = [],
        cans: [String: String] = [:],
        entries: [EntryKey: DemoCacheEntry] = [:],
        enumeratedFiles: [String: [String]]? = nil
    ) {
        self.cards = cards
        self.cans = cans
        self.entries = entries
        self.enumeratedFiles = enumeratedFiles ?? Dictionary(grouping: entries.keys, by: \.iccsn)
            .mapValues { $0.map(\.fileName).sorted() }
    }

    func allCards() async throws -> [String] {
        try throwFailureIfNeeded()
        allCardsCallCount += 1
        return cards
    }

    func can(for iccsn: String) async throws -> String? {
        try throwFailureIfNeeded()
        if saveCanCalls.contains(where: { $0.iccsn == iccsn }),
           canReadOverrides.keys.contains(iccsn) {
            return canReadOverrides[iccsn] ?? nil
        }
        return cans[iccsn]
    }

    func saveCan(_ can: String, for iccsn: String) async throws {
        try throwFailureIfNeeded()
        cans[iccsn] = can
        saveCanCalls.append(.init(iccsn: iccsn, can: can))
    }

    func cachedFiles(for iccsn: String) async throws -> [String] {
        try throwFailureIfNeeded()
        return enumeratedFiles[iccsn] ?? []
    }

    func entry(for iccsn: String, fileName: String) async throws -> DemoCacheEntry {
        try throwFailureIfNeeded()
        let key = EntryKey(iccsn: iccsn, fileName: fileName)
        if putCalls.contains(where: { $0.key == key }),
           let override = entryReadOverrides[key] {
            return override
        }
        return entries[key] ?? .notCached
    }

    func put(_ data: Data, for iccsn: String, fileName: String) async throws {
        try throwFailureIfNeeded()
        let key = EntryKey(iccsn: iccsn, fileName: fileName)
        entries[key] = data.isEmpty ? .notOnCard : .found(data)
        putCalls.append(.init(key: key, data: data))
    }

    private func throwFailureIfNeeded() throws {
        if let failure {
            throw failure
        }
    }
}

private final class FakeCacheMigrationMarkerStore: DemoCacheMigrationMarkerStore {
    var isComplete: Bool
    private(set) var markCompleteCallCount = 0

    init(isComplete: Bool = false) {
        self.isComplete = isComplete
    }

    func markComplete() {
        isComplete = true
        markCompleteCallCount += 1
    }
}

private struct TestCacheFailure: Error {}
