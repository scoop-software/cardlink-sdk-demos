package de.scoopsoftware.cardlink.demo.auth

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import de.scoopsoftware.cardlink.auth.CredentialStorage
import de.scoopsoftware.cardlink.auth.TokenResponse

/**
 * Reference [CredentialStorage] implementation for the demo (the SDK ships none —
 * persistence is the host app's responsibility).
 *
 * Uses EncryptedSharedPreferences. Note: androidx.security-crypto is
 * deprecated without a 1:1 successor; this remains a pragmatic default until
 * the plugin migrates to an Android-Keystore-wrapped store. Integrators should
 * exclude `cardlink_secure_prefs` from Auto Backup via `dataExtractionRules` —
 * restored ciphertext is undecryptable on a new device (Keystore keys do not
 * transfer) and would otherwise surface as a corrupt store.
 */
class DemoCredentialStorage(context: Context) : CredentialStorage {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs: SharedPreferences = EncryptedSharedPreferences.create(
        context,
        PREFS_NAME,
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    override fun saveTokens(tokenResponse: TokenResponse) {
        prefs.edit()
            .putString(KEY_ACCESS_TOKEN, tokenResponse.accessToken)
            .putString(KEY_REFRESH_TOKEN, tokenResponse.refreshToken)
            .putString(KEY_ID_TOKEN, tokenResponse.idToken)
            .apply()
    }

    override fun getTokens(): TokenResponse? {
        val accessToken = prefs.getString(KEY_ACCESS_TOKEN, null) ?: return null
        return TokenResponse(
            accessToken = accessToken,
            tokenType = "Bearer",
            expiresIn = 0,
            refreshToken = prefs.getString(KEY_REFRESH_TOKEN, null),
            idToken = prefs.getString(KEY_ID_TOKEN, null),
            scope = null
        )
    }

    override fun clearTokens() {
        prefs.edit()
            .remove(KEY_ACCESS_TOKEN)
            .remove(KEY_REFRESH_TOKEN)
            .remove(KEY_ID_TOKEN)
            .apply()
    }

    override fun saveSession(sessionId: String, sessionExpiresAt: Long, userId: String) {
        prefs.edit()
            .putString(KEY_SESSION_ID, sessionId)
            .putLong(KEY_SESSION_EXPIRES_AT, sessionExpiresAt)
            .putString(KEY_SESSION_USER_ID, userId)
            .apply()
    }

    override fun getSession(): Triple<String, Long, String>? {
        val sessionId = prefs.getString(KEY_SESSION_ID, null) ?: return null
        val sessionExpiresAt = prefs.getLong(KEY_SESSION_EXPIRES_AT, 0)
        val userId = prefs.getString(KEY_SESSION_USER_ID, null) ?: return null
        if (sessionExpiresAt == 0L) return null
        return Triple(sessionId, sessionExpiresAt, userId)
    }

    override fun clearSession() {
        prefs.edit()
            .remove(KEY_SESSION_ID)
            .remove(KEY_SESSION_EXPIRES_AT)
            .remove(KEY_SESSION_USER_ID)
            .commit() // synchronous: session must be gone before a new one is created
    }

    private companion object {
        const val PREFS_NAME = "cardlink_secure_prefs"
        const val KEY_ACCESS_TOKEN = "access_token"
        const val KEY_REFRESH_TOKEN = "refresh_token"
        const val KEY_ID_TOKEN = "id_token"
        const val KEY_SESSION_ID = "session_id"
        const val KEY_SESSION_EXPIRES_AT = "session_expires_at"
        const val KEY_SESSION_USER_ID = "session_user_id"
    }
}
