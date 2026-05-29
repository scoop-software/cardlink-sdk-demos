package de.scoopsoftware.cardlink.demo.auth

import android.app.Activity
import android.content.Context
import android.util.Log
import androidx.credentials.CreatePasswordRequest
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetPasswordOption
import androidx.credentials.PasswordCredential
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException

/**
 * Result of a credential operation.
 */
sealed class CredentialResult {
    data class Success(val username: String, val password: String) : CredentialResult()
    data object Cancelled : CredentialResult()
    data object NoCredentials : CredentialResult()
    data class Error(val message: String) : CredentialResult()
}

/**
 * Interface for credential storage operations.
 * Implemented by both CredentialManager-based and local fallback storage.
 */
interface CredentialHelper {
    /**
     * Save credentials.
     * @return true if saved successfully
     */
    suspend fun saveCredential(activity: Activity, username: String, password: String): Boolean

    /**
     * Get saved credentials.
     * May show a picker UI if multiple accounts are available.
     */
    suspend fun getCredential(activity: Activity): CredentialResult

    /**
     * Clear credential state / all stored credentials.
     */
    suspend fun clearCredentialState(activity: Activity)

    /**
     * Whether this implementation uses the system Credential Manager.
     * If false, it uses local encrypted storage.
     */
    val isSystemCredentialManager: Boolean
}

/**
 * Credential Manager implementation using Android's Credential Manager API.
 * Credentials sync across devices via Google account.
 */
private class SystemCredentialHelper(
    private val credentialManager: CredentialManager
) : CredentialHelper {

    override val isSystemCredentialManager: Boolean = true

    override suspend fun saveCredential(
        activity: Activity,
        username: String,
        password: String
    ): Boolean {
        return try {
            val request = CreatePasswordRequest(username, password)
            credentialManager.createCredential(activity, request)
            Log.d(TAG, "Credential saved successfully for user: $username")
            true
        } catch (e: CreateCredentialCancellationException) {
            Log.d(TAG, "User cancelled credential save")
            false
        } catch (e: CreateCredentialException) {
            Log.e(TAG, "Failed to save credential: ${e.message}")
            false
        }
    }

    override suspend fun getCredential(activity: Activity): CredentialResult {
        return try {
            val request = GetCredentialRequest(
                listOf(GetPasswordOption())
            )
            val result = credentialManager.getCredential(activity, request)
            val credential = result.credential

            if (credential is PasswordCredential) {
                Log.d(TAG, "Retrieved credential for user: ${credential.id}")
                CredentialResult.Success(credential.id, credential.password)
            } else {
                Log.w(TAG, "Unexpected credential type: ${credential.type}")
                CredentialResult.Error("Unexpected credential type")
            }
        } catch (e: GetCredentialCancellationException) {
            Log.d(TAG, "User cancelled credential selection")
            CredentialResult.Cancelled
        } catch (e: NoCredentialException) {
            Log.d(TAG, "No credentials found")
            CredentialResult.NoCredentials
        } catch (e: GetCredentialException) {
            Log.e(TAG, "Failed to get credential: ${e.message}")
            CredentialResult.Error(e.message ?: "Unknown error")
        }
    }

    override suspend fun clearCredentialState(activity: Activity) {
        try {
            credentialManager.clearCredentialState(
                androidx.credentials.ClearCredentialStateRequest()
            )
            Log.d(TAG, "Credential state cleared")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear credential state: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "SystemCredentialHelper"
    }
}

/**
 * Local fallback implementation using EncryptedSharedPreferences.
 * Used on devices without Google Play Services.
 */
private class LocalCredentialHelper(
    private val storage: LocalCredentialStorage
) : CredentialHelper {

    override val isSystemCredentialManager: Boolean = false

    // Track the last selected username for the picker simulation
    private var lastSelectedUsername: String? = null

    override suspend fun saveCredential(
        activity: Activity,
        username: String,
        password: String
    ): Boolean {
        return try {
            storage.saveCredential(username, password)
            Log.d(TAG, "Credential saved locally for user: $username")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save credential locally: ${e.message}")
            false
        }
    }

    override suspend fun getCredential(activity: Activity): CredentialResult {
        val usernames = storage.getSavedUsernames()

        return when {
            usernames.isEmpty() -> {
                Log.d(TAG, "No local credentials found")
                CredentialResult.NoCredentials
            }
            usernames.size == 1 -> {
                // Single account - return it directly
                val username = usernames.first()
                val password = storage.getPassword(username)
                if (password != null) {
                    Log.d(TAG, "Retrieved single local credential for user: $username")
                    CredentialResult.Success(username, password)
                } else {
                    CredentialResult.Error("Password not found")
                }
            }
            else -> {
                // Multiple accounts - cycle through them
                // This simulates the picker behavior by returning a different account each time
                val currentIndex = lastSelectedUsername?.let { usernames.indexOf(it) } ?: -1
                val nextIndex = (currentIndex + 1) % usernames.size
                val username = usernames[nextIndex]
                lastSelectedUsername = username

                val password = storage.getPassword(username)
                if (password != null) {
                    Log.d(TAG, "Retrieved local credential for user: $username (${nextIndex + 1}/${usernames.size})")
                    CredentialResult.Success(username, password)
                } else {
                    CredentialResult.Error("Password not found")
                }
            }
        }
    }

    override suspend fun clearCredentialState(activity: Activity) {
        try {
            storage.clearAll()
            lastSelectedUsername = null
            Log.d(TAG, "Local credentials cleared")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear local credentials: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "LocalCredentialHelper"
    }
}

/**
 * Factory for creating the appropriate credential helper.
 * Tries Credential Manager first, falls back to local storage.
 */
object CredentialManagerHelper {
    private const val TAG = "CredentialManagerHelper"

    /**
     * Create a CredentialHelper instance.
     * Returns a system Credential Manager if available, otherwise a local fallback.
     * Always returns a non-null implementation.
     */
    fun create(context: Context): CredentialHelper {
        return try {
            val credentialManager = CredentialManager.create(context)
            Log.d(TAG, "Using system Credential Manager")
            SystemCredentialHelper(credentialManager)
        } catch (e: Exception) {
            Log.w(TAG, "Credential Manager not available, using local storage: ${e.message}")
            LocalCredentialHelper(LocalCredentialStorage(context))
        }
    }
}
