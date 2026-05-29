package de.scoopsoftware.cardlink.demo.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import de.scoopsoftware.cardlink.fhir.PrescriptionMetadata
import de.scoopsoftware.cardlink.fhir.PrescriptionMetadataParser
import de.scoopsoftware.cardlink.flow.ErezeptDeleteClient
import de.scoopsoftware.cardlink.websocket.CardlinkEnvironment
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Per-prescription delete UI state. */
sealed class DeleteUiState {
    data object Idle : DeleteUiState()
    data object Deleting : DeleteUiState()
    data class Deleted(val envUsed: String) : DeleteUiState()
    data class Failed(val message: String) : DeleteUiState()
}

/**
 * Shared controller for the "delete prescription" feature used by both the
 * CardLink and PoPP screens at the conference demo.
 *
 * The demo device does not know which gematik env (DEV or RU) a prescription
 * lives in — the upload flow has a separate toggle for that. The controller
 * memoizes the env returned by the first successful delete and uses it for
 * subsequent deletes in the same session, avoiding wasted round-trips.
 *
 * Construct with [rememberPrescriptionDeleteController] so state survives
 * recomposition.
 */
class PrescriptionDeleteController internal constructor(
    private val client: ErezeptDeleteClient,
    private val scope: CoroutineScope,
    private val onTrace: (String) -> Unit,
) {
    private val _states = mutableStateMapOf<String, DeleteUiState>()
    private var _lastGoodEnv = mutableStateOf<String?>(null)
    private var _isDeletingAll = mutableStateOf(false)

    val lastGoodEnv: String? get() = _lastGoodEnv.value
    val isDeletingAll: Boolean get() = _isDeletingAll.value

    fun stateFor(key: String): DeleteUiState = _states[key] ?: DeleteUiState.Idle

    /** Number of entries successfully deleted so far. */
    fun deletedCount(keys: Iterable<String>): Int =
        keys.count { _states[it] is DeleteUiState.Deleted }

    fun delete(key: String, metadata: PrescriptionMetadata) {
        if (_states[key] is DeleteUiState.Deleting || _states[key] is DeleteUiState.Deleted) return
        _states[key] = DeleteUiState.Deleting
        scope.launch {
            val result = withContext(Dispatchers.Default) {
                client.delete(
                    metadata.taskId,
                    metadata.accessCode,
                    preferredEnv = _lastGoodEnv.value ?: ErezeptDeleteClient.DEFAULT_ENV,
                )
            }
            _states[key] = mapResult(key, metadata, result)
        }
    }

    /**
     * Delete every prescription in [items] sequentially. The first success sets the
     * preferred env for the remainder of the batch.
     */
    fun deleteAll(items: List<Pair<String, PrescriptionMetadata>>) {
        if (_isDeletingAll.value) return
        _isDeletingAll.value = true
        scope.launch {
            try {
                for ((key, meta) in items) {
                    val existing = _states[key]
                    if (existing is DeleteUiState.Deleting || existing is DeleteUiState.Deleted) continue
                    _states[key] = DeleteUiState.Deleting
                    val result = withContext(Dispatchers.Default) {
                        client.delete(
                            meta.taskId,
                            meta.accessCode,
                            preferredEnv = _lastGoodEnv.value ?: ErezeptDeleteClient.DEFAULT_ENV,
                        )
                    }
                    _states[key] = mapResult(key, meta, result)
                }
            } finally {
                _isDeletingAll.value = false
            }
        }
    }

    private fun mapResult(
        key: String,
        metadata: PrescriptionMetadata,
        result: ErezeptDeleteClient.DeleteResult,
    ): DeleteUiState = when (result) {
        is ErezeptDeleteClient.DeleteResult.Success -> {
            _lastGoodEnv.value = result.envUsed
            onTrace("Deleted ${metadata.taskId.take(12)}… on ${result.envUsed}")
            DeleteUiState.Deleted(result.envUsed)
        }
        is ErezeptDeleteClient.DeleteResult.NotFoundInAnyEnv -> {
            onTrace("Not found in ${result.triedEnvs.joinToString("+")} for ${metadata.taskId.take(12)}…")
            DeleteUiState.Failed("Not found in DEV or RU")
        }
        is ErezeptDeleteClient.DeleteResult.HttpError -> {
            onTrace("HTTP ${result.statusCode} on ${result.envUsed}: ${result.body.take(160)}")
            DeleteUiState.Failed("HTTP ${result.statusCode} (${result.envUsed})")
        }
        is ErezeptDeleteClient.DeleteResult.NetworkError -> {
            onTrace("Network error on ${result.envUsed}: ${result.message}")
            DeleteUiState.Failed("Network: ${result.message.take(80)}")
        }
        is ErezeptDeleteClient.DeleteResult.AuthFailed -> {
            onTrace("Auth failed: ${result.message}")
            DeleteUiState.Failed("Auth: ${result.message.take(80)}")
        }
    }

    fun close() {
        client.close()
    }
}

/**
 * Create a [PrescriptionDeleteController] bound to the current composition.
 *
 * [onTrace] receives one-line human-readable trace entries for the screen's log.
 */
@Composable
fun rememberPrescriptionDeleteController(
    environment: CardlinkEnvironment,
    username: String,
    password: String,
    onTrace: (String) -> Unit = {},
): PrescriptionDeleteController {
    val scope = rememberCoroutineScope()
    val controller = remember(environment, username, password) {
        PrescriptionDeleteController(
            client = ErezeptDeleteClient(environment, username, password),
            scope = scope,
            onTrace = onTrace,
        )
    }
    DisposableEffect(controller) {
        onDispose { controller.close() }
    }
    return controller
}

/**
 * Parse [xml] for task metadata. Returns null when the prescription doesn't embed
 * a Task resource (which happens for some CardLink bundle variants) — in that case
 * the delete icon should be omitted.
 */
fun parsePrescriptionMetadata(xml: String): PrescriptionMetadata? =
    PrescriptionMetadataParser.parseFirst(xml)

/** Inline delete icon button; renders a status indicator when busy/done/failed. */
@Composable
fun DeleteStatusAction(
    state: DeleteUiState,
    onDelete: () -> Unit,
) {
    when (state) {
        DeleteUiState.Idle -> IconButton(onClick = onDelete) {
            Icon(
                Icons.Default.Delete,
                contentDescription = "Delete prescription",
                tint = MaterialTheme.colorScheme.error,
            )
        }
        DeleteUiState.Deleting -> CircularProgressIndicator(
            modifier = Modifier.size(20.dp).padding(6.dp),
            strokeWidth = 2.dp,
        )
        is DeleteUiState.Deleted -> Icon(
            Icons.Default.CheckCircle,
            contentDescription = "Deleted on ${state.envUsed}",
            tint = Color(0xFF4CAF50),
            modifier = Modifier.padding(8.dp),
        )
        is DeleteUiState.Failed -> Icon(
            Icons.Default.Delete,
            contentDescription = "Delete failed: ${state.message}",
            // Material "disabled" tint — signals the button won't respond to another tap.
            tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f),
            modifier = Modifier.padding(8.dp),
        )
    }
}

/**
 * "Delete all N prescriptions" row shown above the list. Rendered only when there
 * are deletable entries that aren't already deleted.
 */
@Composable
fun DeleteAllBar(
    remaining: Int,
    lastGoodEnv: String?,
    isDeletingAll: Boolean = false,
    onDeleteAll: () -> Unit,
) {
    if (remaining <= 0) return
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            if (lastGoodEnv != null) "Env: ${lastGoodEnv.uppercase()}" else "Env: auto-detect",
            style = MaterialTheme.typography.labelSmall,
            color = Color.Gray,
        )
        Spacer(modifier = Modifier.width(8.dp))
        OutlinedButton(onClick = onDeleteAll, enabled = !isDeletingAll) {
            if (isDeletingAll) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.error,
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text("Deleting…", color = MaterialTheme.colorScheme.error)
            } else {
                Text("Delete all ($remaining)", color = MaterialTheme.colorScheme.error)
            }
        }
    }
}
