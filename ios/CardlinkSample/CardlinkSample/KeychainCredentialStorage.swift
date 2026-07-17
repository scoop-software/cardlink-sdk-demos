import Foundation
import ScoopCardlink
import Security

/// Default `CredentialStorage` for Flutter hosts (the plugin is the "host app"
/// from the SDK's perspective — Flutter integrators cannot supply a Swift
/// implementation themselves).
///
/// Stores tokens and the Cardlink session in the iOS Keychain with
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — items never leave the
/// device (no iCloud Keychain sync, no restore onto other devices).
final class KeychainCredentialStorage: CredentialStorage {

    private static let service = "de.scoopsoftware.cardlink"

    private enum Key {
        static let accessToken = "access_token"
        static let refreshToken = "refresh_token"
        static let idToken = "id_token"
        static let sessionId = "session_id"
        static let sessionExpiresAt = "session_expires_at"
        static let sessionUserId = "session_user_id"
    }

    // MARK: - CredentialStorage

    func saveTokens(tokenResponse: TokenResponse) {
        save(Key.accessToken, tokenResponse.accessToken)
        if let refresh = tokenResponse.refreshToken { save(Key.refreshToken, refresh) }
        if let id = tokenResponse.idToken { save(Key.idToken, id) }
    }

    func getTokens() -> TokenResponse? {
        guard let accessToken = read(Key.accessToken) else { return nil }
        return TokenResponse(
            accessToken: accessToken,
            tokenType: "Bearer",
            expiresIn: 0,
            refreshToken: read(Key.refreshToken),
            idToken: read(Key.idToken),
            scope: nil
        )
    }

    func clearTokens() {
        [Key.accessToken, Key.refreshToken, Key.idToken].forEach(delete)
    }

    func saveSession(sessionId: String, sessionExpiresAt: Int64, userId: String) {
        save(Key.sessionId, sessionId)
        save(Key.sessionExpiresAt, String(sessionExpiresAt))
        save(Key.sessionUserId, userId)
    }

    func getSession() -> KotlinTriple<NSString, KotlinLong, NSString>? {
        guard
            let sessionId = read(Key.sessionId),
            let expiresRaw = read(Key.sessionExpiresAt),
            let expires = Int64(expiresRaw),
            let userId = read(Key.sessionUserId)
        else { return nil }
        return KotlinTriple(
            first: sessionId as NSString,
            second: KotlinLong(value: expires),
            third: userId as NSString
        )
    }

    func clearSession() {
        [Key.sessionId, Key.sessionExpiresAt, Key.sessionUserId].forEach(delete)
    }

    func hasValidSessionForUser(currentTimeMs: Int64, userId: String) -> Bool {
        guard let session = getSession() else { return false }
        if currentTimeMs >= session.second!.int64Value { return false }
        return (session.third! as String) == userId
    }

    // MARK: - Keychain plumbing

    private func save(_ key: String, _ value: String) {
        delete(key)
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
