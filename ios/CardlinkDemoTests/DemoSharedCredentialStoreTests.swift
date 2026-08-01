import XCTest
@testable import CardlinkDemo

final class DemoSharedCredentialStoreTests: XCTestCase {
    private let accessGroup = "TESTTEAM.group.de.scoopsoftware.nfc.healthcard"

    func testWriteUsesCanonicalServiceAccountsAndDeviceOnlyProtection() throws {
        let client = RecordingDemoKeychainClient()
        let store = try DemoSharedCredentialStore(
            keychainAccessGroup: accessGroup,
            client: client
        )

        try store.write(
            DemoCredentialPair(username: "test-user", password: "test-password"),
            for: .cardlink
        )

        XCTAssertEqual(
            client.writes.map(\.item),
            [
                DemoKeychainItem(
                    service: "de.scoopsoftware.cardlink.demo.shared",
                    account: "cardlink.username",
                    accessGroup: accessGroup,
                    accessibility: .whenUnlockedThisDeviceOnly,
                    synchronizable: false
                ),
                DemoKeychainItem(
                    service: "de.scoopsoftware.cardlink.demo.shared",
                    account: "cardlink.password",
                    accessGroup: accessGroup,
                    accessibility: .whenUnlockedThisDeviceOnly,
                    synchronizable: false
                ),
            ]
        )
    }

    func testWriteRoundTripsACompleteCredentialPair() throws {
        let client = RecordingDemoKeychainClient()
        let store = try DemoSharedCredentialStore(
            keychainAccessGroup: accessGroup,
            client: client
        )
        let expected = DemoCredentialPair(
            username: "round-trip-user",
            password: "round-trip-password"
        )

        try store.write(expected, for: .rocketChat)

        XCTAssertEqual(try store.read(.rocketChat), expected)
    }

    func testReadReturnsNilWhenNeitherCredentialItemExists() throws {
        let store = try DemoSharedCredentialStore(
            keychainAccessGroup: accessGroup,
            client: RecordingDemoKeychainClient()
        )

        XCTAssertNil(try store.read(.cardlink))
    }

    func testInitializationRejectsMissingOrUnexpandedAccessGroups() {
        let client = RecordingDemoKeychainClient()

        XCTAssertThrowsError(
            try DemoSharedCredentialStore(keychainAccessGroup: "", client: client)
        )
        XCTAssertThrowsError(
            try DemoSharedCredentialStore(
                keychainAccessGroup: "$(AppIdentifierPrefix)group.de.scoopsoftware.nfc.healthcard",
                client: client
            )
        )
    }

    func testWriteFailsWhenReadBackDoesNotMatch() throws {
        let client = RecordingDemoKeychainClient()
        client.readOverrides["cardlink.password"] = Data("different".utf8)
        let store = try DemoSharedCredentialStore(
            keychainAccessGroup: accessGroup,
            client: client
        )

        XCTAssertThrowsError(
            try store.write(
                DemoCredentialPair(username: "test-user", password: "test-password"),
                for: .cardlink
            )
        )
    }
}

private final class RecordingDemoKeychainClient: DemoKeychainClient {
    struct Write: Equatable {
        let data: Data
        let item: DemoKeychainItem
    }

    var writes: [Write] = []
    var readOverrides: [String: Data] = [:]
    private var values: [DemoKeychainItem: Data] = [:]

    func read(_ item: DemoKeychainItem) throws -> Data? {
        readOverrides[item.account] ?? values[item]
    }

    func write(_ data: Data, to item: DemoKeychainItem) throws {
        writes.append(Write(data: data, item: item))
        values[item] = data
    }
}
