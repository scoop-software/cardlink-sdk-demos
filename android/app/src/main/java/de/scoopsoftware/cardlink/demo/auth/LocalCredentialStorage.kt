package de.scoopsoftware.cardlink.demo.auth

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONObject

/**
 * Local credential storage using EncryptedSharedPreferences.
 * Used as a fallback when Credential Manager is not available (e.g., on degoogled phones).
 *
 * Stores multiple username:password pairs in encrypted storage.
 */
class LocalCredentialStorage(context: Context) {

    private val prefs: SharedPreferences = try {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

        EncryptedSharedPreferences.create(
            context,
            PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    } catch (cause: Exception) {
        throw IllegalStateException(
            "Credential storage is unavailable because encrypted storage could not be initialized.",
            cause
        )
    }

    /**
     * Save a credential (username/password pair).
     * If a credential with the same username exists, it will be updated.
     */
    fun saveCredential(username: String, password: String) {
        val credentials = loadAllCredentials().toMutableMap()
        credentials[username] = password
        saveAllCredentials(credentials)
    }

    /**
     * Get all saved usernames.
     */
    fun getSavedUsernames(): List<String> {
        return loadAllCredentials().keys.toList().sorted()
    }

    /**
     * Get the password for a specific username.
     */
    fun getPassword(username: String): String? {
        return loadAllCredentials()[username]
    }

    /**
     * Delete a specific credential.
     */
    fun deleteCredential(username: String) {
        val credentials = loadAllCredentials().toMutableMap()
        credentials.remove(username)
        saveAllCredentials(credentials)
    }

    /**
     * Clear all stored credentials.
     */
    fun clearAll() {
        prefs.edit().remove(KEY_CREDENTIALS).apply()
    }

    /**
     * Check if any credentials are stored.
     */
    fun hasCredentials(): Boolean {
        return loadAllCredentials().isNotEmpty()
    }

    private fun loadAllCredentials(): Map<String, String> {
        val json = prefs.getString(KEY_CREDENTIALS, null) ?: return emptyMap()
        return try {
            val jsonObject = JSONObject(json)
            val result = mutableMapOf<String, String>()
            jsonObject.keys().forEach { key ->
                result[key] = jsonObject.getString(key)
            }
            result
        } catch (e: Exception) {
            emptyMap()
        }
    }

    private fun saveAllCredentials(credentials: Map<String, String>) {
        val jsonObject = JSONObject()
        credentials.forEach { (username, password) ->
            jsonObject.put(username, password)
        }
        prefs.edit().putString(KEY_CREDENTIALS, jsonObject.toString()).apply()
    }

    companion object {
        private const val PREFS_NAME = "cardlink_local_credentials"
        private const val KEY_CREDENTIALS = "credentials"
    }
}
