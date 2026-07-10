package de.scoopsoftware.cardlink.demo.ui.screens

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.PasswordVisualTransformation
import coil.compose.AsyncImage
import coil.request.ImageRequest
import de.scoopsoftware.cardlink.DeviceInfo
import de.scoopsoftware.nfc.cache.FileCacheProvider
import de.scoopsoftware.nfc.cache.KnownCard
import de.scoopsoftware.nfc.cache.getKnownCards
import de.scoopsoftware.cardlink.demo.ui.components.KnownCardsList
import de.scoopsoftware.cardlink.deviceInfo
import de.scoopsoftware.nfc.util.md5
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import de.scoopsoftware.cardlink.auth.JwtDecoder
import de.scoopsoftware.cardlink.demo.auth.CredentialHelper
import de.scoopsoftware.cardlink.demo.auth.CredentialManagerHelper
import de.scoopsoftware.cardlink.demo.reporting.RocketChatReporter
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Data class representing a stored preference entry.
 */
private data class StorageEntry(
    val key: String,
    val value: String,
    val displayValue: String,
    val category: StorageCategory
)

/**
 * Categories for grouping storage entries.
 */
private enum class StorageCategory(val displayName: String, val order: Int) {
    TOKENS("OAuth Tokens", 0),
    SESSION("Session", 1),
    ROCKETCHAT("RocketChat", 2)
}

/**
 * Account data containing all related storage entries.
 */
private data class AccountData(
    val username: String,
    val pictureUrl: String?,
    val tokens: List<StorageEntry>,
    val session: List<StorageEntry>,
    val rocketchat: List<StorageEntry> = emptyList()
) {
    val allEntries: List<StorageEntry>
        get() = tokens + session + rocketchat

    val isEmpty: Boolean
        get() = tokens.isEmpty() && session.isEmpty() && rocketchat.isEmpty()
}

/**
 * Settings screen showing device info and secure storage contents.
 */
@Composable
fun SettingsScreen(
    onThemeChanged: (de.scoopsoftware.cardlink.demo.ui.theme.BrandTheme) -> Unit = {},
) {
    val context = LocalContext.current
    val activity = context as? Activity
    val scope = rememberCoroutineScope()

    // Credential helper (system Credential Manager or local fallback)
    val credentialHelper = remember { CredentialManagerHelper.create(context) }

    // State for storage entries
    var accountData by remember { mutableStateOf<AccountData?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var showClearAllDialog by remember { mutableStateOf(false) }
    var keyToDelete by remember { mutableStateOf<String?>(null) }
    var refreshTrigger by remember { mutableIntStateOf(0) }

    // Known cards state
    var knownCards by remember { mutableStateOf<List<KnownCard>>(emptyList()) }
    var knownCardsRefreshTrigger by remember { mutableIntStateOf(0) }
    val snackbarHostState = remember { SnackbarHostState() }
    var undoneIccsns by remember { mutableStateOf(setOf<String>()) }

    LaunchedEffect(knownCardsRefreshTrigger) {
        val cacheProvider = FileCacheProvider()
        knownCards = cacheProvider.getKnownCards()
    }

    // Collapsible section states (persisted across recompositions)
    var deviceInfoExpanded by rememberSaveable { mutableStateOf(true) }
    var knownCardsExpanded by rememberSaveable { mutableStateOf(true) }
    var appPrefsExpanded by rememberSaveable { mutableStateOf(false) }
    var secureStorageExpanded by rememberSaveable { mutableStateOf(true) }

    // Load entries when screen is shown or refresh is triggered
    LaunchedEffect(refreshTrigger) {
        val result = loadStorageEntries(context)
        accountData = result.first
        errorMessage = result.second
    }

    val hasEntries = accountData?.let { !it.isEmpty } ?: false

    val info = deviceInfo

    Box(modifier = Modifier.fillMaxSize()) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
            .verticalScroll(rememberScrollState())
    ) {
        // App name as screen title, app ID as subtitle
        Text(
            text = info.appName,
            style = MaterialTheme.typography.headlineMedium
        )
        SelectionContainer {
            Text(
                text = info.appId,
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Device & SDK Info Section
        CollapsibleSection(
            title = "Device & SDK",
            expanded = deviceInfoExpanded,
            onToggle = { deviceInfoExpanded = !deviceInfoExpanded },
            action = {
                TextButton(
                    onClick = {
                        copyDeviceInfoToClipboard(context, info)
                        Toast.makeText(context, "Device info copied", Toast.LENGTH_SHORT).show()
                    }
                ) {
                    Text("Copy")
                }
            }
        ) {
            DeviceInfoContent()
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Brand Theme Picker
        val currentTheme = de.scoopsoftware.cardlink.demo.ui.theme.LocalBrandTheme.current.value
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("App Theme", style = MaterialTheme.typography.titleMedium)
                Spacer(modifier = Modifier.height(12.dp))
                @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
                androidx.compose.foundation.layout.FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    de.scoopsoftware.cardlink.demo.ui.theme.BrandTheme.entries.forEach { theme ->
                        val selected = theme == currentTheme
                        androidx.compose.material3.FilterChip(
                            selected = selected,
                            onClick = { onThemeChanged(theme) },
                            label = { Text(theme.displayName) },
                            leadingIcon = {
                                Box(
                                    modifier = Modifier
                                        .size(12.dp)
                                        .clip(CircleShape)
                                        .background(theme.previewColor)
                                )
                            },
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // PoPP Settings
        val poppPrefs = context.getSharedPreferences("popp_settings", Context.MODE_PRIVATE)
        var scoopSignatureMode by remember {
            mutableStateOf(poppPrefs.getBoolean("scoopSignatureMode", false))
        }
        CollapsibleSection(
            title = "PoPP",
            expanded = true,
            onToggle = {},
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("SCOOP Signature Mode", modifier = Modifier.weight(1f))
                androidx.compose.material3.Switch(
                    checked = scoopSignatureMode,
                    onCheckedChange = {
                        scoopSignatureMode = it
                        poppPrefs.edit().putBoolean("scoopSignatureMode", it).apply()
                    }
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // RocketChat Integration
        val rcPrefs = context.getSharedPreferences("rocketchat_settings", Context.MODE_PRIVATE)
        val rcSecurePrefs = remember {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            EncryptedSharedPreferences.create(
                context,
                "rocketchat",
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        }
        var rcEnabled by remember { mutableStateOf(rcPrefs.getBoolean("enabled", false)) }
        var rcServerUrl by remember {
            val stored = rcPrefs.getString("serverUrl", "") ?: ""
            mutableStateOf(stored.ifBlank { RocketChatReporter.DEFAULT_SERVER_URL })
        }
        var rcUsername by remember { mutableStateOf(rcSecurePrefs.getString("username", "") ?: "") }
        var rcPassword by remember { mutableStateOf(rcSecurePrefs.getString("password", "") ?: "") }
        var rcChannel by remember { mutableStateOf(rcPrefs.getString("channel", "PoPP-Demo") ?: "PoPP-Demo") }
        var rcExpanded by rememberSaveable { mutableStateOf(false) }

        // Migrate credentials from plain prefs to secure storage
        LaunchedEffect(Unit) {
            val oldUser = rcPrefs.getString("username", null)
            if (oldUser != null) {
                val oldPass = rcPrefs.getString("password", null) ?: ""
                rcSecurePrefs.edit().putString("username", oldUser).putString("password", oldPass).apply()
                rcPrefs.edit().remove("username").remove("password").apply()
                rcUsername = oldUser
                rcPassword = oldPass
            }
        }

        fun saveRcPrefs() {
            rcPrefs.edit()
                .putBoolean("enabled", rcEnabled)
                .putString("serverUrl", rcServerUrl)
                .putString("channel", rcChannel)
                .apply()
            rcSecurePrefs.edit()
                .putString("username", rcUsername)
                .putString("password", rcPassword)
                .apply()
            RocketChatReporter.clearAuth()
        }

        CollapsibleSection(
            title = "RocketChat",
            expanded = rcExpanded,
            onToggle = { rcExpanded = !rcExpanded }
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Post scan results", modifier = Modifier.weight(1f))
                    androidx.compose.material3.Switch(
                        checked = rcEnabled,
                        onCheckedChange = { rcEnabled = it; saveRcPrefs() }
                    )
                }
                OutlinedTextField(
                    value = rcServerUrl,
                    onValueChange = { rcServerUrl = it; saveRcPrefs() },
                    label = { Text("Server URL") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = rcUsername,
                    onValueChange = { rcUsername = it; saveRcPrefs() },
                    label = { Text("Username") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = rcPassword,
                    onValueChange = { rcPassword = it; saveRcPrefs() },
                    label = { Text("Password") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = rcChannel,
                    onValueChange = { rcChannel = it; saveRcPrefs() },
                    label = { Text("Channel") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                var testResult by remember { mutableStateOf<String?>(null) }
                var testing by remember { mutableStateOf(false) }
                OutlinedButton(
                    onClick = {
                        testing = true
                        testResult = null
                        scope.launch {
                            val error = RocketChatReporter.testConnection(rcServerUrl, rcUsername, rcPassword)
                            testResult = error ?: "Connected"
                            testing = false
                        }
                    },
                    enabled = !testing && rcServerUrl.isNotBlank() && rcUsername.isNotBlank(),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    if (testing) {
                        androidx.compose.material3.CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    Text(if (testing) "Testing…" else "Test Connection")
                }
                testResult?.let { result ->
                    Text(
                        result,
                        color = if (result == "Connected") Color(0xFF4CAF50) else MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Known Cards Section
        if (knownCards.isNotEmpty()) {
            CollapsibleSection(
                title = "Known Cards",
                expanded = knownCardsExpanded,
                onToggle = { knownCardsExpanded = !knownCardsExpanded },
                action = {
                    TextButton(
                        onClick = {
                            scope.launch {
                                FileCacheProvider().clear()
                                knownCards = emptyList()
                                Toast.makeText(context, "All cards removed", Toast.LENGTH_SHORT).show()
                            }
                        }
                    ) {
                        Text("Remove All", color = MaterialTheme.colorScheme.error)
                    }
                }
            ) {
                KnownCardsList(
                    knownCards = knownCards,
                    undoneIccsns = undoneIccsns,
                    onUndoneAnimated = { iccsn -> undoneIccsns = undoneIccsns - iccsn },
                    onSwipeDismiss = { card ->
                        val iccsn = card.iccsn
                        val removedCard = knownCards.find { it.iccsn == iccsn } ?: return@KnownCardsList
                        val removedIndex = knownCards.indexOf(removedCard)
                        knownCards = knownCards.filter { it.iccsn != iccsn }
                        scope.launch {
                            val result = snackbarHostState.showSnackbar(
                                message = "Card removed",
                                actionLabel = "Undo",
                                duration = SnackbarDuration.Short
                            )
                            if (result == SnackbarResult.ActionPerformed) {
                                undoneIccsns = undoneIccsns + iccsn
                                knownCards = knownCards.toMutableList().apply {
                                    add(removedIndex.coerceAtMost(size), removedCard)
                                }
                            } else {
                                FileCacheProvider().remove(iccsn)
                            }
                        }
                    }
                )
            }

            Spacer(modifier = Modifier.height(16.dp))
        }

        // App Preferences Section
        CollapsibleSection(
            title = "App Preferences",
            expanded = appPrefsExpanded,
            onToggle = { appPrefsExpanded = !appPrefsExpanded }
        ) {
            AppPreferencesContent()
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Secure Storage Section
        CollapsibleSection(
            title = "Secure Storage",
            expanded = secureStorageExpanded,
            onToggle = { secureStorageExpanded = !secureStorageExpanded },
            action = if (hasEntries) {
                {
                    TextButton(
                        onClick = {
                            accountData?.let { data ->
                                copySecureStorageToClipboard(context, data)
                                Toast.makeText(context, "Storage info copied", Toast.LENGTH_SHORT).show()
                            }
                        }
                    ) {
                        Text("Copy")
                    }
                }
            } else null
        ) {
            SecureStorageContent(
                activity = activity,
                credentialHelper = credentialHelper,
                accountData = accountData,
                errorMessage = errorMessage,
                hasEntries = hasEntries,
                onRefresh = { refreshTrigger++ },
                onClearAll = { showClearAllDialog = true },
                onDeleteKey = { keyToDelete = it },
                scope = scope
            )
        }
    }
    SnackbarHost(
        hostState = snackbarHostState,
        modifier = Modifier.align(Alignment.BottomCenter)
    )
    }

    // Clear All confirmation dialog
    if (showClearAllDialog) {
        AlertDialog(
            onDismissRequest = { showClearAllDialog = false },
            title = { Text("Clear All Data") },
            text = { Text("Are you sure you want to delete all stored data? This will clear tokens and session data.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        clearAllStorage(context)
                        showClearAllDialog = false
                        refreshTrigger++
                        Toast.makeText(context, "All data cleared", Toast.LENGTH_SHORT).show()
                    }
                ) {
                    Text("Clear All", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showClearAllDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Delete single key confirmation dialog
    keyToDelete?.let { key ->
        AlertDialog(
            onDismissRequest = { keyToDelete = null },
            title = { Text("Delete Entry") },
            text = { Text("Delete \"$key\" from secure storage?") },
            confirmButton = {
                TextButton(
                    onClick = {
                        deleteKey(context, key)
                        keyToDelete = null
                        refreshTrigger++
                        Toast.makeText(context, "\"$key\" deleted", Toast.LENGTH_SHORT).show()
                    }
                ) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { keyToDelete = null }) {
                    Text("Cancel")
                }
            }
        )
    }
}

/**
 * Collapsible section with animated expand/collapse.
 */
@Composable
private fun CollapsibleSection(
    title: String,
    expanded: Boolean,
    onToggle: () -> Unit,
    action: (@Composable () -> Unit)? = null,
    content: @Composable () -> Unit
) {
    Column {
        // Section header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onToggle)
                .padding(vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.headlineSmall
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                action?.invoke()
                Icon(
                    imageVector = if (expanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                    contentDescription = if (expanded) "Collapse" else "Expand",
                    tint = MaterialTheme.colorScheme.onSurface
                )
            }
        }

        // Animated content
        AnimatedVisibility(
            visible = expanded,
            enter = expandVertically(),
            exit = shrinkVertically()
        ) {
            content()
        }
    }
}

/**
 * Device & SDK Info section content with compact horizontal layout.
 */
@Composable
private fun DeviceInfoContent() {
    val info = deviceInfo

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // Device info card - horizontal layout
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant
            )
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                InfoItem(label = "Manufacturer", value = info.deviceVendor)
                InfoItem(label = "Model", value = info.deviceType, alignment = Alignment.CenterHorizontally)
                InfoItem(label = "Platform", value = info.platform, alignment = Alignment.End)
            }
        }

        // SDK info card - horizontal layout
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant
            )
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                InfoItem(label = "SDK Version", value = info.sdkVersion)
                InfoItem(label = "SDK Type", value = info.sdkType, alignment = Alignment.End)
            }
        }
    }
}

/**
 * Single info item with label and value stacked vertically.
 */
@Composable
private fun InfoItem(
    label: String,
    value: String,
    alignment: Alignment.Horizontal = Alignment.Start
) {
    Column(horizontalAlignment = alignment) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        SelectionContainer {
            Text(
                text = value,
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/**
 * Secure Storage section content.
 */
@Composable
private fun SecureStorageContent(
    activity: Activity?,
    credentialHelper: CredentialHelper,
    accountData: AccountData?,
    errorMessage: String?,
    hasEntries: Boolean,
    onRefresh: () -> Unit,
    onClearAll: () -> Unit,
    onDeleteKey: (String) -> Unit,
    scope: kotlinx.coroutines.CoroutineScope
) {
    val context = LocalContext.current

    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        // Credential Manager section
        if (activity != null) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                )
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(
                        text = if (credentialHelper.isSystemCredentialManager) "Credential Manager" else "Local Credential Storage",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = if (credentialHelper.isSystemCredentialManager)
                            "Passwords are managed by Google Password Manager and sync across devices."
                        else
                            "Passwords are stored locally in encrypted storage (Credential Manager not available).",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f)
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedButton(
                        onClick = {
                            scope.launch {
                                credentialHelper.clearCredentialState(activity)
                                Toast.makeText(context, "Credential state cleared", Toast.LENGTH_SHORT).show()
                            }
                        }
                    ) {
                        Text("Clear Credential State")
                    }
                }
            }
        }

        // Action buttons row
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Button(onClick = onRefresh) {
                Text("Refresh")
            }
            Spacer(modifier = Modifier.weight(1f))
            Button(
                onClick = onClearAll,
                enabled = hasEntries
            ) {
                Text("Clear All")
            }
        }

        // Show error if any
        errorMessage?.let { error ->
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer
                )
            ) {
                Text(
                    text = error,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    modifier = Modifier.padding(16.dp)
                )
            }
        }

        if (!hasEntries && errorMessage == null) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                )
            ) {
                Text(
                    text = "No data stored",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(16.dp)
                )
            }
        } else if (hasEntries) {
            accountData?.let { account ->
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    // Account header with username and avatar
                    AccountHeader(username = account.username, pictureUrl = account.pictureUrl)

                    // Tokens subsection
                    account.tokens.forEach { entry ->
                        StorageEntryCard(
                            entry = entry,
                            onDelete = { onDeleteKey(entry.key) }
                        )
                    }

                    // Session subsection
                    if (account.session.isNotEmpty()) {
                        SubsectionHeader(title = StorageCategory.SESSION.displayName)
                        account.session.forEach { entry ->
                            StorageEntryCard(
                                entry = entry,
                                onDelete = { onDeleteKey(entry.key) }
                            )
                        }
                    }

                    // RocketChat subsection
                    if (account.rocketchat.isNotEmpty()) {
                        SubsectionHeader(title = StorageCategory.ROCKETCHAT.displayName)
                        account.rocketchat.forEach { entry ->
                            StorageEntryCard(
                                entry = entry,
                                onDelete = null
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AccountHeader(username: String, pictureUrl: String?) {
    val context = LocalContext.current
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.secondaryContainer
        )
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Avatar image with white background for contrast with dark SVGs
            if (pictureUrl != null) {
                AsyncImage(
                    model = ImageRequest.Builder(context)
                        .data(pictureUrl)
                        .crossfade(true)
                        .build(),
                    contentDescription = "User avatar",
                    modifier = Modifier
                        .size(48.dp)
                        .background(MaterialTheme.colorScheme.primary, CircleShape)
                        .padding(8.dp)
                        .clip(CircleShape)
                )
                Spacer(modifier = Modifier.width(12.dp))
            }
            Column {
                Text(
                    text = "Account",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.7f)
                )
                Text(
                    text = username,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSecondaryContainer
                )
            }
        }
    }
}

@Composable
private fun SubsectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 4.dp, top = 8.dp, bottom = 4.dp)
    )
}

@Composable
private fun StorageEntryCard(
    entry: StorageEntry,
    onDelete: (() -> Unit)? = null
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier.padding(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = entry.key,
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary
                )
                if (onDelete != null) {
                    TextButton(onClick = onDelete) {
                        Text("Delete", color = MaterialTheme.colorScheme.error)
                    }
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))

            SelectionContainer {
                Text(
                    text = entry.displayValue,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    maxLines = 10,
                    overflow = TextOverflow.Ellipsis,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

/**
 * App Preferences section showing values from regular SharedPreferences.
 */
@Composable
private fun AppPreferencesContent() {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("cardlink_app_prefs", Context.MODE_PRIVATE) }
    val entries = remember(prefs) {
        prefs.all
            .filter { (_, value) -> value != null }
            .toSortedMap()
            .map { (key, value) -> key to value.toString() }
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (entries.isEmpty()) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                )
            ) {
                Text(
                    text = "No preferences stored",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(16.dp)
                )
            }
        } else {
            entries.forEach { (key, value) ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant
                    )
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.Top,
                    ) {
                        Text(
                            text = key,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.weight(0.4f)
                        )
                        SelectionContainer(modifier = Modifier.weight(0.6f)) {
                            Text(
                                text = value,
                                style = MaterialTheme.typography.bodySmall,
                                fontFamily = FontFamily.Monospace,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        }
    }
}


/**
 * Categorize a key into its storage category.
 */
private fun categorizeKey(key: String): StorageCategory {
    return when (key) {
        "access_token", "refresh_token", "id_token" -> StorageCategory.TOKENS
        "session_expires_at", "session_user_id" -> StorageCategory.SESSION
        else -> StorageCategory.SESSION // Default to session for unknown keys
    }
}

/**
 * Load all entries from EncryptedSharedPreferences grouped by account.
 * Returns a Pair of (AccountData, errorMessage).
 */
private fun loadStorageEntries(context: Context): Pair<AccountData?, String?> {
    return try {
        val prefs = getEncryptedPrefs(context)
        val allEntries = prefs.all

        val entries = allEntries.map { (key, value) ->
            val category = categorizeKey(key)
            val displayValue = formatValue(key, value)
            StorageEntry(
                key = key,
                value = value?.toString() ?: "null",
                displayValue = displayValue,
                category = category
            )
        }

        val tokens = entries.filter { it.category == StorageCategory.TOKENS }.sortedBy { it.key }
        val session = entries.filter { it.category == StorageCategory.SESSION }.sortedBy { it.key }

        // Load RocketChat secure storage
        val rcEntries = try {
            val rcPrefs = getRocketChatEncryptedPrefs(context)
            rcPrefs.all.map { (key, value) ->
                StorageEntry(
                    key = key,
                    value = if (key == "password") "••••••••" else value?.toString() ?: "null",
                    displayValue = if (key == "password") "••••••••" else value?.toString() ?: "null",
                    category = StorageCategory.ROCKETCHAT
                )
            }.sortedBy { it.key }
        } catch (_: Exception) { emptyList() }

        // Get username from access_token JWT claims (preferred_username, email, or sub)
        // Fall back to id_token if access_token doesn't have user info
        val username = (allEntries["access_token"] as? String)?.let { extractUsernameFromJwt(it) }
            ?: (allEntries["id_token"] as? String)?.let { extractUsernameFromJwt(it) }
            ?: (allEntries["session_user_id"] as? String)
            ?: if (tokens.isNotEmpty()) "(logged in)" else "(no account)"

        // Get picture URL from id_token, with Gravatar fallback based on email
        val idTokenPicture = (allEntries["id_token"] as? String)?.let { extractPictureFromJwt(it) }
        val email = (allEntries["id_token"] as? String)?.let { extractEmailFromJwt(it) }
            ?: (allEntries["access_token"] as? String)?.let { extractEmailFromJwt(it) }
        val pictureUrl = if (!idTokenPicture.isNullOrBlank()) {
            idTokenPicture
        } else {
            email?.let { "https://www.gravatar.com/avatar/${it.trim().lowercase().md5()}?s=96&d=identicon" }
        }

        AccountData(
            username = username,
            pictureUrl = pictureUrl,
            tokens = tokens,
            session = session,
            rocketchat = rcEntries
        ) to null
    } catch (e: Exception) {
        null to "Error loading storage: ${e.message}"
    }
}

/**
 * Format value for display, with special handling for certain types.
 */
private fun formatValue(key: String, value: Any?): String {
    return when {
        value == null -> "null"
        key.endsWith("_token") && value is String -> {
            // Try to decode JWT tokens
            decodeJwtForDisplay(value.toString())
        }
        key.contains("expires", ignoreCase = true) && value is Long -> {
            // Format timestamp
            val timestamp = value
            if (timestamp > 1000000000000L) {
                // Milliseconds timestamp
                val date = Date(timestamp)
                val formatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                "${formatter.format(date)} ($timestamp)"
            } else if (timestamp > 1000000000L) {
                // Seconds timestamp (epoch)
                val date = Date(timestamp * 1000)
                val formatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                "${formatter.format(date)} ($timestamp)"
            } else {
                timestamp.toString()
            }
        }
        else -> value.toString()
    }
}

/**
 * Decode JWT token and format for display using the SDK's JwtDecoder.
 */
private fun decodeJwtForDisplay(token: String): String {
    return try {
        val decoded = JwtDecoder.decode(token)
        val payload = decoded.payload
        val dateFormatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())

        buildString {
            payload.subject?.let { appendLine("Subject: $it") }
            payload.name?.let { appendLine("Name: $it") }
            payload.email?.let { appendLine("Email: $it") }
            payload.preferredUsername?.let { appendLine("Username: $it") }
            payload.picture?.let { appendLine("Picture: $it") }
            payload.issuedAt?.let {
                appendLine("Issued: ${dateFormatter.format(Date(it * 1000))}")
            }
            payload.expirationTime?.let {
                appendLine("Expires: ${dateFormatter.format(Date(it * 1000))}")
            }
            payload.issuer?.let { appendLine("Issuer: $it") }
            payload.audience?.let { appendLine("Audience: $it") }
        }.trimEnd().ifEmpty {
            if (token.length > 50) "${token.take(25)}...${token.takeLast(10)}" else token
        }
    } catch (e: Exception) {
        // If decoding fails, just truncate
        if (token.length > 50) "${token.take(25)}...${token.takeLast(10)}" else token
    }
}

/**
 * Extract username from JWT token using the SDK's JwtDecoder.
 */
private fun extractUsernameFromJwt(token: String): String? {
    return try {
        val payload = JwtDecoder.decode(token).payload
        payload.preferredUsername ?: payload.email ?: payload.subject
    } catch (e: Exception) {
        null
    }
}

/**
 * Extract picture URL from JWT token using the SDK's JwtDecoder.
 */
private fun extractPictureFromJwt(token: String): String? {
    return try {
        JwtDecoder.decode(token).payload.picture
    } catch (e: Exception) {
        null
    }
}

/**
 * Extract email from JWT token using the SDK's JwtDecoder.
 */
private fun extractEmailFromJwt(token: String): String? {
    return try {
        JwtDecoder.decode(token).payload.email
    } catch (e: Exception) {
        null
    }
}

/**
 * Get EncryptedSharedPreferences instance.
 */
private fun getEncryptedPrefs(context: Context): SharedPreferences {
    val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    return EncryptedSharedPreferences.create(
        context,
        "cardlink_secure_prefs",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )
}

/**
 * Get EncryptedSharedPreferences for RocketChat credentials.
 */
private fun getRocketChatEncryptedPrefs(context: Context): SharedPreferences {
    val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    return EncryptedSharedPreferences.create(
        context,
        "rocketchat",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )
}

/**
 * Delete a single key from storage.
 */
private fun deleteKey(context: Context, key: String) {
    try {
        val prefs = getEncryptedPrefs(context)
        prefs.edit().remove(key).apply()
    } catch (e: Exception) {
        // Ignore errors
    }
}

/**
 * Clear all data from storage.
 */
private fun clearAllStorage(context: Context) {
    try {
        val prefs = getEncryptedPrefs(context)
        prefs.edit().clear().apply()
    } catch (e: Exception) {
        // Ignore errors
    }
}

/**
 * Copy device info to clipboard in plain text format for support emails.
 */
private fun copyDeviceInfoToClipboard(context: Context, info: DeviceInfo) {
    val text = buildString {
        appendLine("App: ${info.appName}")
        appendLine("App ID: ${info.appId}")
        appendLine("App Version: ${info.appVersion}")
        appendLine("Device: ${info.deviceVendor} ${info.deviceType}")
        appendLine("Platform: ${info.platform}")
        appendLine("SDK Version: ${info.sdkVersion}")
        appendLine("SDK Type: ${info.sdkType}")
    }.trim()

    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val clip = ClipData.newPlainText("Device Info", text)
    clipboard.setPrimaryClip(clip)
}

/**
 * Copy secure storage info to clipboard in plain text format for support emails.
 * Includes both human-readable decoded info and raw JWT tokens with decoded JSON.
 */
private fun copySecureStorageToClipboard(context: Context, accountData: AccountData) {
    val text = buildString {
        appendLine("Account: ${accountData.username}")
        appendLine()
        if (accountData.tokens.isNotEmpty()) {
            appendLine("=== OAuth Tokens ===")
            accountData.tokens.forEach { entry ->
                appendLine("${entry.key}:")
                // Human-readable decoded info
                appendLine(entry.displayValue.prependIndent("  "))
                appendLine()
                // Raw JWT token
                appendLine("  Raw Token:")
                appendLine(entry.value.prependIndent("  "))
                appendLine()
                // Pretty-printed decoded JWT
                val decodedJwt = decodeJwtToPrettyJson(entry.value)
                if (decodedJwt != null) {
                    appendLine("  Decoded JWT:")
                    appendLine(decodedJwt.prependIndent("  "))
                    appendLine()
                }
            }
        }
        if (accountData.session.isNotEmpty()) {
            appendLine("=== Session ===")
            accountData.session.forEach { entry ->
                appendLine("${entry.key}: ${entry.displayValue}")
            }
        }
    }.trim()

    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val clip = ClipData.newPlainText("Secure Storage", text)
    clipboard.setPrimaryClip(clip)
}

/**
 * Decode a JWT token and return pretty-printed JSON for header and payload.
 */
private fun decodeJwtToPrettyJson(token: String): String? {
    return try {
        val parts = token.split(".")
        if (parts.size != 3) return null

        val header = decodeBase64UrlToJson(parts[0])
        val payload = decodeBase64UrlToJson(parts[1])

        buildString {
            appendLine("Header:")
            appendLine(header?.prependIndent("  ") ?: "  (decode error)")
            appendLine("Payload:")
            append(payload?.prependIndent("  ") ?: "  (decode error)")
        }
    } catch (e: Exception) {
        null
    }
}

/**
 * Decode a Base64URL-encoded string to pretty-printed JSON.
 */
private fun decodeBase64UrlToJson(input: String): String? {
    return try {
        // Add padding if necessary
        val padded = when (input.length % 4) {
            2 -> "$input=="
            3 -> "$input="
            else -> input
        }
        // Convert Base64URL to standard Base64
        val base64 = padded.replace('-', '+').replace('_', '/')
        val decoded = android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
        val jsonString = String(decoded, Charsets.UTF_8)
        // Pretty-print using Gson
        val gson = com.google.gson.GsonBuilder().setPrettyPrinting().create()
        val jsonElement = gson.fromJson(jsonString, com.google.gson.JsonElement::class.java)
        gson.toJson(jsonElement)
    } catch (e: Exception) {
        null
    }
}
