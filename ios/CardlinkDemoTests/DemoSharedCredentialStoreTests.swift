import XCTest
import ScoopCardlink
@testable import CardlinkDemo

final class DemoSharedCredentialStoreTests: XCTestCase {
    private let accessGroup = "TESTTEAM.group.de.scoopsoftware.nfc.healthcard"
    private let keycloakCredential = DemoInternetCredential(
        baseURL: URL(string: "https://login.example.test:8443/realms/demo")!,
        username: "test-user",
        password: "test-password"
    )

    func testWriteUsesOneCanonicalInternetPasswordItem() throws {
        let client = RecordingDemoInternetPasswordClient()
        let store = try DemoSharedCredentialStore(
            keychainAccessGroup: accessGroup,
            client: client
        )

        try store.write(keycloakCredential, for: .keycloak)

        XCTAssertEqual(
            client.writes,
            [
                DemoInternetPasswordRecord(
                    label: "de.scoopsoftware.cardlink.demo.keycloak",
                    accessGroup: accessGroup,
                    server: "login.example.test",
                    protocolType: .https,
                    port: 8443,
                    path: "/realms/demo",
                    account: "test-user",
                    passwordData: Data("test-password".utf8),
                    accessibility: .whenUnlockedThisDeviceOnly,
                    synchronizable: false
                )
            ]
        )
    }

    func testWriteRoundTripsACompleteCredentialWithOneMutation() throws {
        let client = RecordingDemoInternetPasswordClient()
        let store = try DemoSharedCredentialStore(
            keychainAccessGroup: accessGroup,
            client: client
        )

        try store.write(keycloakCredential, for: .keycloak)

        XCTAssertEqual(try store.read(.keycloak), keycloakCredential)
        XCTAssertEqual(client.writes.count, 1)
    }

    func testReadReturnsNilWhenCredentialDoesNotExist() throws {
        let store = try DemoSharedCredentialStore(
            keychainAccessGroup: accessGroup,
            client: RecordingDemoInternetPasswordClient()
        )

        XCTAssertNil(try store.read(.rocketChat))
    }

    func testInitializationRejectsMissingUnexpandedAndLegacyAccessGroups() {
        let client = RecordingDemoInternetPasswordClient()

        XCTAssertThrowsError(
            try DemoSharedCredentialStore(keychainAccessGroup: "", client: client)
        )
        XCTAssertThrowsError(
            try DemoSharedCredentialStore(
                keychainAccessGroup: "$(AppIdentifierPrefix)group.de.scoopsoftware.nfc.healthcard",
                client: client
            )
        )
        XCTAssertThrowsError(
            try DemoSharedCredentialStore(
                keychainAccessGroup: "TESTTEAM.group.de.scoopsoftware.nfc",
                client: client
            )
        )
    }

    func testWriteRejectsInvalidURLsBeforeMutatingKeychain() throws {
        let invalidURLs = [
            "http://login.example.test/realms/demo",
            "https://login.example.test/realms/demo?tenant=one",
            "https://login.example.test/realms/demo#fragment",
        ]

        for invalidURL in invalidURLs {
            let client = RecordingDemoInternetPasswordClient()
            let store = try DemoSharedCredentialStore(
                keychainAccessGroup: accessGroup,
                client: client
            )
            let credential = DemoInternetCredential(
                baseURL: URL(string: invalidURL)!,
                username: "test-user",
                password: "test-password"
            )

            XCTAssertThrowsError(try store.write(credential, for: .keycloak))
            XCTAssertTrue(client.writes.isEmpty)
        }
    }

    func testWriteRejectsIncompleteCredentialBeforeMutatingKeychain() throws {
        let client = RecordingDemoInternetPasswordClient()
        let store = try DemoSharedCredentialStore(
            keychainAccessGroup: accessGroup,
            client: client
        )

        XCTAssertThrowsError(
            try store.write(
                DemoInternetCredential(
                    baseURL: URL(string: "https://login.example.test")!,
                    username: "test-user",
                    password: ""
                ),
                for: .keycloak
            )
        )
        XCTAssertTrue(client.writes.isEmpty)
    }

    func testWriteFailurePreservesThePreviousCompleteItem() throws {
        let client = RecordingDemoInternetPasswordClient()
        let store = try DemoSharedCredentialStore(
            keychainAccessGroup: accessGroup,
            client: client
        )
        try store.write(keycloakCredential, for: .keycloak)
        client.writeError = TestCredentialError.writeFailed

        XCTAssertThrowsError(
            try store.write(
                DemoInternetCredential(
                    baseURL: URL(string: "https://other.example.test/realms/demo")!,
                    username: "new-user",
                    password: "new-password"
                ),
                for: .keycloak
            )
        )
        XCTAssertEqual(try store.read(.keycloak), keycloakCredential)
    }

    func testWriteFailsWhenReadBackDoesNotMatch() throws {
        let client = RecordingDemoInternetPasswordClient()
        client.ignoreWrites = true
        let store = try DemoSharedCredentialStore(
            keychainAccessGroup: accessGroup,
            client: client
        )

        XCTAssertThrowsError(try store.write(keycloakCredential, for: .keycloak))
    }

    func testSchemaKeepsOAuthClientIdFixedOutsideTheKeychain() {
        XCTAssertEqual(DemoSharedCredentialSchema.oauthClientId, "cardlink-app")
        XCTAssertEqual(
            DemoSharedCredentialSchema.defaultKeycloakBaseURL.absoluteString,
            "https://auth-cardlink-dev.demo.scoop-gmbh.de/realms/cardlinkdemo/protocol/openid-connect"
        )
    }

    func testCardlinkEnvironmentUsesSharedOAuthURLAndFixedClientID() throws {
        let baseURL = URL(string: "https://login.example.test/realms/customer")!

        let environment = DemoCardlinkEnvironmentFactory.make(oauthBaseURL: baseURL)

        XCTAssertEqual(environment.oauthConfig.baseUrl, baseURL.absoluteString)
        XCTAssertEqual(environment.oauthConfig.clientId, "cardlink-app")
        XCTAssertEqual(
            environment.websocketUrl,
            CardlinkEnvironment.Default.shared.websocketUrl
        )
        XCTAssertEqual(
            environment.restBaseUrl,
            CardlinkEnvironment.Default.shared.restBaseUrl
        )
    }

    func testCardlinkEnvironmentRejectsAnUnvalidatedEditedURL() {
        let environment = DemoCardlinkEnvironmentFactory.make(
            oauthBaseURLString: "http://login.example.test/realms/customer"
        )

        XCTAssertEqual(
            environment.oauthConfig.baseUrl,
            DemoSharedCredentialSchema.defaultKeycloakBaseURL.absoluteString
        )
    }
}

final class DemoCredentialMigratorTests: XCTestCase {
    private let keycloakCredential = DemoInternetCredential(
        baseURL: DemoSharedCredentialSchema.defaultKeycloakBaseURL,
        username: "legacy-cardlink-user",
        password: "legacy-cardlink-password"
    )
    private let rocketChatCredential = DemoInternetCredential(
        baseURL: URL(string: "https://chat.example.test")!,
        username: "legacy-rocketchat-user",
        password: "legacy-rocketchat-password"
    )

    func testCompleteCanonicalCredentialWinsWithoutReadingLegacy() throws {
        let canonical = RecordingInternetCredentialStore(
            credentials: [.keycloak: keycloakCredential]
        )
        let legacy = RecordingMigrationCandidateReader(candidates: [
            .keycloak: DemoLegacyCredentialCandidate(
                baseURLString: "https://other.example.test",
                username: "different-user",
                password: "different-password"
            )
        ])
        let markers = RecordingCredentialMigrationMarkerStore()
        let migrator = DemoCredentialMigrator(
            canonical: canonical,
            legacy: legacy,
            markers: markers
        )

        try migrator.migrate(.keycloak)

        XCTAssertTrue(canonical.writes.isEmpty)
        XCTAssertTrue(legacy.reads.isEmpty)
        XCTAssertEqual(markers.completedKinds, [.keycloak])
    }

    func testCompleteLegacyCredentialMigratesAndIsVerified() throws {
        let canonical = RecordingInternetCredentialStore()
        let legacy = RecordingMigrationCandidateReader(candidates: [
            .keycloak: DemoLegacyCredentialCandidate(
                baseURLString: keycloakCredential.baseURL.absoluteString,
                username: keycloakCredential.username,
                password: keycloakCredential.password
            )
        ])
        let markers = RecordingCredentialMigrationMarkerStore()
        let migrator = DemoCredentialMigrator(
            canonical: canonical,
            legacy: legacy,
            markers: markers
        )

        try migrator.migrate(.keycloak)

        XCTAssertEqual(
            canonical.writes,
            [.init(kind: .keycloak, credential: keycloakCredential)]
        )
        XCTAssertEqual(markers.completedKinds, [.keycloak])
    }

    func testIncompleteLegacyCredentialIsRejectedWithoutMutationOrMarker() {
        let canonical = RecordingInternetCredentialStore()
        let markers = RecordingCredentialMigrationMarkerStore()
        let migrator = DemoCredentialMigrator(
            canonical: canonical,
            legacy: RecordingMigrationCandidateReader(candidates: [
                .rocketChat: DemoLegacyCredentialCandidate(
                    baseURLString: "",
                    username: "legacy-user",
                    password: "legacy-password"
                )
            ]),
            markers: markers
        )

        XCTAssertThrowsError(try migrator.migrate(.rocketChat))
        XCTAssertTrue(canonical.writes.isEmpty)
        XCTAssertTrue(markers.completedKinds.isEmpty)
    }

    func testInvalidLegacyURLIsRejectedBeforeKeychainMutation() throws {
        let client = RecordingDemoInternetPasswordClient()
        let canonical = try DemoSharedCredentialStore(
            keychainAccessGroup: "TESTTEAM.group.de.scoopsoftware.nfc.healthcard",
            client: client
        )
        let markers = RecordingCredentialMigrationMarkerStore()
        let migrator = DemoCredentialMigrator(
            canonical: canonical,
            legacy: RecordingMigrationCandidateReader(candidates: [
                .keycloak: DemoLegacyCredentialCandidate(
                    baseURLString: "http://login.example.test",
                    username: "legacy-user",
                    password: "legacy-password"
                )
            ]),
            markers: markers
        )

        XCTAssertThrowsError(try migrator.migrate(.keycloak))
        XCTAssertTrue(client.writes.isEmpty)
        XCTAssertTrue(markers.completedKinds.isEmpty)
    }

    func testWriteFailureAndReadBackMismatchLeaveMarkerUnset() {
        let failingStore = RecordingInternetCredentialStore()
        failingStore.writeError = TestCredentialError.writeFailed
        let ignoredStore = RecordingInternetCredentialStore()
        ignoredStore.ignoreWrites = true
        let candidate = RecordingMigrationCandidateReader(candidates: [
            .keycloak: DemoLegacyCredentialCandidate(
                baseURLString: keycloakCredential.baseURL.absoluteString,
                username: keycloakCredential.username,
                password: keycloakCredential.password
            )
        ])

        for store in [failingStore, ignoredStore] {
            let markers = RecordingCredentialMigrationMarkerStore()
            let migrator = DemoCredentialMigrator(
                canonical: store,
                legacy: candidate,
                markers: markers
            )
            XCTAssertThrowsError(try migrator.migrate(.keycloak))
            XCTAssertTrue(markers.completedKinds.isEmpty)
        }
    }

    func testSuccessfulMigrationUsesIndependentMarkerAndIsIdempotent() throws {
        let canonical = RecordingInternetCredentialStore()
        let legacy = RecordingMigrationCandidateReader(candidates: [
            .rocketChat: DemoLegacyCredentialCandidate(
                baseURLString: rocketChatCredential.baseURL.absoluteString,
                username: rocketChatCredential.username,
                password: rocketChatCredential.password
            )
        ])
        let markers = RecordingCredentialMigrationMarkerStore()
        let migrator = DemoCredentialMigrator(
            canonical: canonical,
            legacy: legacy,
            markers: markers
        )

        try migrator.migrate(.rocketChat)
        let readsAfterFirstRun = legacy.reads
        try migrator.migrate(.rocketChat)

        XCTAssertEqual(canonical.writes.count, 1)
        XCTAssertEqual(legacy.reads, readsAfterFirstRun)
        XCTAssertEqual(markers.completedKinds, [.rocketChat])
        XCTAssertFalse(markers.isComplete(.keycloak))
    }

    func testNativeLegacyKeycloakReaderUsesFixedDevURL() throws {
        let client = RecordingLegacyCredentialKeychainClient()
        client.cardlinkPair = DemoLegacyUsernamePassword(
            username: "legacy-user",
            password: "legacy-password"
        )
        let reader = DemoNativeLegacyCredentialReader(
            keychainClient: client,
            defaults: isolatedUserDefaults().0
        )

        XCTAssertEqual(
            try reader.read(.keycloak),
            DemoLegacyCredentialCandidate(
                baseURLString: DemoSharedCredentialSchema.defaultKeycloakBaseURL.absoluteString,
                username: "legacy-user",
                password: "legacy-password"
            )
        )
    }

    func testNativeLegacyRocketChatReaderRequiresURLAndPreservesDefaults() throws {
        let (defaults, suiteName) = isolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("https://chat.example.test", forKey: "rcServerUrl")
        defaults.set("defaults-user", forKey: "rcUsername")
        defaults.set("defaults-password", forKey: "rcPassword")
        let reader = DemoNativeLegacyCredentialReader(
            keychainClient: RecordingLegacyCredentialKeychainClient(),
            defaults: defaults
        )

        XCTAssertEqual(
            try reader.read(.rocketChat),
            DemoLegacyCredentialCandidate(
                baseURLString: "https://chat.example.test",
                username: "defaults-user",
                password: "defaults-password"
            )
        )
        XCTAssertEqual(defaults.string(forKey: "rcServerUrl"), "https://chat.example.test")
        XCTAssertEqual(defaults.string(forKey: "rcUsername"), "defaults-user")
        XCTAssertEqual(defaults.string(forKey: "rcPassword"), "defaults-password")
    }

    func testPartialRocketChatKeychainPairIsPreservedForMigrationRejection() throws {
        let (defaults, suiteName) = isolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("https://chat.example.test", forKey: "rcServerUrl")
        defaults.set("defaults-user", forKey: "rcUsername")
        defaults.set("defaults-password", forKey: "rcPassword")
        let client = RecordingLegacyCredentialKeychainClient()
        client.rocketChatValues["rcUsername"] = Data("keychain-user".utf8)
        let reader = DemoNativeLegacyCredentialReader(
            keychainClient: client,
            defaults: defaults
        )

        XCTAssertEqual(
            try reader.read(.rocketChat),
            DemoLegacyCredentialCandidate(
                baseURLString: "https://chat.example.test",
                username: "keychain-user",
                password: ""
            )
        )
    }

    func testUserDefaultsMarkersUseStableIndependentKeys() {
        let (defaults, suiteName) = isolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let markers = UserDefaultsDemoCredentialMigrationMarkerStore(defaults: defaults)

        markers.markComplete(.keycloak)

        XCTAssertTrue(markers.isComplete(.keycloak))
        XCTAssertFalse(markers.isComplete(.rocketChat))
        XCTAssertTrue(defaults.bool(forKey: "demo.shared-storage.credentials.keycloak.v1"))
        XCTAssertFalse(defaults.bool(forKey: "demo.shared-storage.credentials.rocketchat.v1"))
    }

    private func isolatedUserDefaults() -> (UserDefaults, String) {
        let suiteName = "DemoCredentialMigratorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

private final class RecordingDemoInternetPasswordClient: DemoInternetPasswordClient {
    var records: [String: DemoInternetPasswordRecord] = [:]
    var writes: [DemoInternetPasswordRecord] = []
    var writeError: Error?
    var ignoreWrites = false

    func read(label: String, accessGroup: String) throws -> DemoInternetPasswordRecord? {
        records[label]
    }

    func upsert(_ record: DemoInternetPasswordRecord) throws {
        writes.append(record)
        if let writeError {
            throw writeError
        }
        if !ignoreWrites {
            records[record.label] = record
        }
    }
}

private enum TestCredentialError: Error {
    case writeFailed
}

private final class RecordingInternetCredentialStore: DemoInternetCredentialStore {
    struct Write: Equatable {
        let kind: DemoCredentialKind
        let credential: DemoInternetCredential
    }

    var credentials: [DemoCredentialKind: DemoInternetCredential]
    var reads: [DemoCredentialKind] = []
    var writes: [Write] = []
    var writeError: Error?
    var ignoreWrites = false

    init(credentials: [DemoCredentialKind: DemoInternetCredential] = [:]) {
        self.credentials = credentials
    }

    func read(_ kind: DemoCredentialKind) throws -> DemoInternetCredential? {
        reads.append(kind)
        return credentials[kind]
    }

    func write(_ credential: DemoInternetCredential, for kind: DemoCredentialKind) throws {
        writes.append(Write(kind: kind, credential: credential))
        if let writeError {
            throw writeError
        }
        if !ignoreWrites {
            credentials[kind] = credential
        }
    }
}

private final class RecordingMigrationCandidateReader: DemoLegacyCredentialCandidateReader {
    let candidates: [DemoCredentialKind: DemoLegacyCredentialCandidate]
    var reads: [DemoCredentialKind] = []

    init(candidates: [DemoCredentialKind: DemoLegacyCredentialCandidate] = [:]) {
        self.candidates = candidates
    }

    func read(_ kind: DemoCredentialKind) throws -> DemoLegacyCredentialCandidate? {
        reads.append(kind)
        return candidates[kind]
    }
}

private final class RecordingCredentialMigrationMarkerStore: DemoCredentialMigrationMarkerStore {
    private(set) var completedKinds: Set<DemoCredentialKind> = []

    func isComplete(_ kind: DemoCredentialKind) -> Bool {
        completedKinds.contains(kind)
    }

    func markComplete(_ kind: DemoCredentialKind) {
        completedKinds.insert(kind)
    }
}

private final class RecordingLegacyCredentialKeychainClient: DemoLegacyCredentialKeychainClient {
    var cardlinkPair: DemoLegacyUsernamePassword?
    var rocketChatValues: [String: Data] = [:]

    func readCardlinkPair() throws -> DemoLegacyUsernamePassword? {
        cardlinkPair
    }

    func readRocketChatValue(account: String) throws -> Data? {
        rocketChatValues[account]
    }
}
