package de.scoopsoftware.cardlink.demo.ui.screens

import android.app.Activity
import android.content.Context
import de.scoopsoftware.cardlink.demo.reporting.RocketChatReporter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.scoopsoftware.nfc.EgkReader
import de.scoopsoftware.cardlink.fhir.FhirBundleParser
import de.scoopsoftware.nfc.can.CanInputField
import de.scoopsoftware.cardlink.demo.ui.components.DeleteAllBar
import de.scoopsoftware.cardlink.demo.ui.components.DeleteStatusAction
import de.scoopsoftware.cardlink.demo.ui.components.DeleteUiState
import de.scoopsoftware.cardlink.demo.ui.components.KnownCardsList
import de.scoopsoftware.cardlink.demo.ui.components.TraceLogSheet
import de.scoopsoftware.cardlink.demo.ui.components.parsePrescriptionMetadata
import de.scoopsoftware.cardlink.demo.ui.components.rememberPrescriptionDeleteController
import de.scoopsoftware.cardlink.demo.auth.DemoCredentialStorage
import de.scoopsoftware.nfc.cache.FileCacheProvider
import de.scoopsoftware.nfc.cache.KnownCard
import de.scoopsoftware.nfc.cache.getKnownCards
import de.scoopsoftware.cardlink.demo.auth.CredentialManagerHelper
import de.scoopsoftware.cardlink.demo.auth.CredentialResult
import de.scoopsoftware.cardlink.demo.ui.model.ScanHistory
import de.scoopsoftware.cardlink.flow.CardlinkFlow
import de.scoopsoftware.cardlink.flow.CardlinkFlowConfig
import de.scoopsoftware.cardlink.flow.CardlinkFlowError
import de.scoopsoftware.cardlink.flow.CardlinkFlowState
import de.scoopsoftware.cardlink.flow.RecoveryAction
import de.scoopsoftware.cardlink.metrics.ScanRecord
import de.scoopsoftware.cardlink.serverdriven.ServerDrivenFlow
import de.scoopsoftware.nfc.vsd.InsuredPersonData
import de.scoopsoftware.cardlink.websocket.CardlinkEnvironment
import kotlinx.coroutines.launch
import java.util.UUID

private const val PREFS_NAME = "cardlink_app_prefs"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScanScreen(
    scanHistory: ScanHistory,
    activity: Activity?,
    username: String,
    onUsernameChange: (String) -> Unit,
    password: String,
    onPasswordChange: (String) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // Setup state (persisted across tab switches)
    var passwordVisible by remember { mutableStateOf(false) }
    var useServerFlow by remember { mutableStateOf(true) }
    var poppMode by remember { mutableStateOf(false) }
    var enableCache by remember { mutableStateOf(true) }
    var enableApduTracing by rememberSaveable { mutableStateOf(false) }
    var started by remember { mutableStateOf(false) }
    var knownCardsRefreshKey by remember { mutableStateOf(0) }

    // Flow input state (persisted)
    val prefs = remember { context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE) }
    var phone by remember { mutableStateOf(prefs.getString("lastPhone", "") ?: "") }
    var smsCode by remember { mutableStateOf("") }
    var can by remember { mutableStateOf(prefs.getString("lastCan", "") ?: "") }

    // Flow instance — only one is non-null at a time
    var flow by remember { mutableStateOf<CardlinkFlow?>(null) }
    var serverFlow by remember { mutableStateOf<ServerDrivenFlow?>(null) }

    // Observe flow state — collect from whichever flow is active
    val flowStateFromClient by flow?.state?.collectAsState()
        ?: remember { mutableStateOf<CardlinkFlowState>(CardlinkFlowState.Idle) }
    val flowStateFromServer by serverFlow?.state?.collectAsState()
        ?: remember { mutableStateOf<CardlinkFlowState>(CardlinkFlowState.Idle) }
    val flowState = if (serverFlow != null) flowStateFromServer else flowStateFromClient

    // Trace log
    val traceLog = remember { mutableStateListOf<String>() }
    var showTraceLog by remember { mutableStateOf(false) }

    // Credential helper — track saved credentials to avoid redundant save prompts
    val credentialHelper = remember { CredentialManagerHelper.create(context) }
    var savedUsername by rememberSaveable { mutableStateOf("") }
    var savedPassword by rememberSaveable { mutableStateOf("") }

    // Load credentials on first composition — only if empty
    LaunchedEffect(Unit) {
        if (activity != null && username.isEmpty() && password.isEmpty()) {
            when (val result = credentialHelper.getCredential(activity)) {
                is CredentialResult.Success -> {
                    onUsernameChange(result.username)
                    onPasswordChange(result.password)
                    savedUsername = result.username
                    savedPassword = result.password
                }
                else -> {}
            }
        }
    }

    // Collect trace events from whichever flow is active
    LaunchedEffect(flow) {
        flow?.traceEvents?.collect { event ->
            traceLog.add(0, event.toString())
            if (traceLog.size > 300) traceLog.removeAt(traceLog.lastIndex)
        }
    }
    LaunchedEffect(serverFlow) {
        serverFlow?.traceEvents?.collect { event ->
            traceLog.add(0, event.toString())
            if (traceLog.size > 300) traceLog.removeAt(traceLog.lastIndex)
        }
    }

    // Record metrics only on successful completion (failures skew charts)
    LaunchedEffect(flowState) {
        if (flowState is CardlinkFlowState.Completed || flowState is CardlinkFlowState.Error) {
            val snapshot = EgkReader.getPerformanceMetricsSnapshot()
            val record = ScanRecord(id = UUID.randomUUID().toString(), metrics = snapshot)
            if (flowState is CardlinkFlowState.Completed) {
                scanHistory.add(record)
                knownCardsRefreshKey++
            }

            // Post to RocketChat (fire-and-forget)
            val rcPrefs = context.getSharedPreferences("rocketchat_settings", Context.MODE_PRIVATE)
            if (rcPrefs.getBoolean("enabled", false)) {
                val serverUrl = rcPrefs.getString("serverUrl", "") ?: ""
                val rcSecure = run {
                    val mk = androidx.security.crypto.MasterKey.Builder(context)
                        .setKeyScheme(androidx.security.crypto.MasterKey.KeyScheme.AES256_GCM)
                        .build()
                    androidx.security.crypto.EncryptedSharedPreferences.create(
                        context, "rocketchat", mk,
                        androidx.security.crypto.EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                        androidx.security.crypto.EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
                    )
                }
                val rcUser = rcSecure.getString("username", "") ?: ""
                val rcPass = rcSecure.getString("password", "") ?: ""
                val rcChannel = rcPrefs.getString("channel", "") ?: ""
                if (serverUrl.isNotBlank() && rcUser.isNotBlank() && rcPass.isNotBlank() && rcChannel.isNotBlank()) {
                    val success = flowState is CardlinkFlowState.Completed
                    val log = if (rcPrefs.getBoolean("includeTrace", false)) traceLog.toList() else emptyList()
                    launch {
                        RocketChatReporter.report(serverUrl, rcUser, rcPass, rcChannel, record, success, log)
                    }
                }
            }
        }
    }

    // Helper functions to call the right flow
    fun submitPhoneNumber(value: String) {
        prefs.edit().putString("lastPhone", value).apply()
        serverFlow?.submitPhoneNumber(value) ?: flow?.submitPhoneNumber(value)
    }
    fun submitSmsCode(value: String) {
        serverFlow?.submitSmsCode(value) ?: flow?.submitSmsCode(value)
    }
    fun submitCan(value: String) {
        prefs.edit().putString("lastCan", value).apply()
        serverFlow?.submitCan(value) ?: flow?.submitCan(value)
    }
    fun retryFlow() {
        serverFlow?.retry() ?: flow?.retry()
    }
    fun cancelFlow() {
        serverFlow?.cancel() ?: flow?.cancel()
        started = false
        flow = null
        serverFlow = null
    }

    fun startFlow(knownCardCan: String? = null, knownCardIccsn: String? = null) {
        if (activity == null) return
        val credentialStorage = DemoCredentialStorage(context)
        val cacheProvider = if (enableCache) FileCacheProvider() else null

        val config = CardlinkFlowConfig(
            environment = CardlinkEnvironment.Default,
            username = username.trim(),
            password = password.trim(),
            credentialStorage = credentialStorage,
            cacheProvider = cacheProvider,
            poppMode = poppMode,
            enableApduTracing = enableApduTracing,
        )

        traceLog.clear()

        // Only save credentials if they differ from what was loaded
        val needsSave = username.trim() != savedUsername || password.trim() != savedPassword

        if (useServerFlow) {
            val sf = ServerDrivenFlow(config, activity)
            // Pre-set known card CAN+ICCSN so the flow skips the CAN dialog
            if (knownCardCan != null && knownCardIccsn != null) {
                sf.submitKnownCard(knownCardCan, knownCardIccsn)
            }
            serverFlow = sf
            flow = null
            started = true
            scope.launch {
                if (needsSave) {
                    credentialHelper.saveCredential(activity, username.trim(), password.trim())
                    savedUsername = username.trim()
                    savedPassword = password.trim()
                }
                sf.start()
            }
        } else {
            val cf = CardlinkFlow(config, activity)
            flow = cf
            serverFlow = null
            started = true
            scope.launch {
                if (needsSave) {
                    credentialHelper.saveCredential(activity, username.trim(), password.trim())
                    savedUsername = username.trim()
                    savedPassword = password.trim()
                }
                cf.start()
            }
        }
    }

    Column {
        // Top bar with flow mode badge and trace log button
        TopAppBar(
            title = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Cardlink Demo")
                    if (started) {
                        Spacer(modifier = Modifier.width(8.dp))
                        Card(
                            colors = CardDefaults.cardColors(
                                containerColor = if (useServerFlow)
                                    MaterialTheme.colorScheme.tertiary
                                else MaterialTheme.colorScheme.primary
                            )
                        ) {
                            Text(
                                text = if (useServerFlow) (if (poppMode) "PoPP" else "SERVER") else "CLIENT",
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                style = MaterialTheme.typography.labelSmall,
                                color = if (useServerFlow)
                                    MaterialTheme.colorScheme.onTertiary
                                else MaterialTheme.colorScheme.onPrimary,
                            )
                        }
                    }
                }
            },
            actions = {
                if (started) {
                    IconButton(onClick = { showTraceLog = true }) {
                        Text("Log", style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
        )

        if (!started) {
            SetupScreen(
                username = username,
                onUsernameChange = onUsernameChange,
                password = password,
                onPasswordChange = onPasswordChange,
                passwordVisible = passwordVisible,
                onPasswordVisibilityToggle = { passwordVisible = !passwordVisible },
                useServerFlow = useServerFlow,
                onUseServerFlowChange = { useServerFlow = it },
                poppMode = poppMode,
                onPoppModeChange = { poppMode = it },
                enableCache = enableCache,
                onEnableCacheChange = { enableCache = it },
                enableApduTracing = enableApduTracing,
                onEnableApduTracingChange = { enableApduTracing = it },
                onLoadCredentials = {
                    scope.launch {
                        if (activity != null) {
                            when (val result = credentialHelper.getCredential(activity)) {
                                is CredentialResult.Success -> {
                                    onUsernameChange(result.username)
                                    onPasswordChange(result.password)
                                    savedUsername = result.username
                                    savedPassword = result.password
                                }
                                else -> {}
                            }
                        }
                    }
                },
                onStart = { startFlow() },
                canStart = username.isNotBlank() && password.isNotBlank(),
                onSubmitKnownCard = { cardCan, iccsn ->
                    can = cardCan
                    startFlow(knownCardCan = cardCan, knownCardIccsn = iccsn)
                },
            )
        } else {
            FlowScreen(
                state = flowState,
                phone = phone,
                onPhoneChange = { phone = it },
                smsCode = smsCode,
                onSmsCodeChange = { smsCode = it },
                can = can,
                onCanChange = { can = it },
                onSubmitPhone = { submitPhoneNumber(phone.trim()) },
                onSubmitSmsCode = { submitSmsCode(smsCode.trim()) },
                onSubmitCan = { submitCan(can.trim()) },
                onSubmitKnownCard = { cardCan, iccsn ->
                    can = cardCan
                    prefs.edit().putString("lastCan", cardCan).apply()
                    serverFlow?.submitKnownCard(cardCan, iccsn)
                        ?: flow?.submitCan(cardCan)
                },
                onRetry = { retryFlow() },
                onCancel = { cancelFlow() },
                onTrace = { msg -> traceLog.add(0, msg) },
                username = username,
                password = password,
                onScanAnother = { scope.launch { serverFlow?.startNewCardTap() } },
                isServerFlow = useServerFlow,
                enableCache = enableCache,
                activity = activity,
            )
        }
    }

    // Trace log bottom sheet
    if (showTraceLog) {
        TraceLogSheet(
            traceLog = traceLog,
            onDismiss = { showTraceLog = false }
        )
    }
}

@Composable
private fun SetupScreen(
    username: String,
    onUsernameChange: (String) -> Unit,
    password: String,
    onPasswordChange: (String) -> Unit,
    passwordVisible: Boolean,
    onPasswordVisibilityToggle: () -> Unit,
    useServerFlow: Boolean,
    onUseServerFlowChange: (Boolean) -> Unit,
    poppMode: Boolean,
    onPoppModeChange: (Boolean) -> Unit,
    enableCache: Boolean,
    onEnableCacheChange: (Boolean) -> Unit,
    enableApduTracing: Boolean,
    onEnableApduTracingChange: (Boolean) -> Unit,
    onLoadCredentials: () -> Unit,
    onStart: () -> Unit,
    canStart: Boolean,
    onSubmitKnownCard: (can: String, iccsn: String) -> Unit,
) {
    Column(
        modifier = Modifier
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Toggles
        ToggleRow("File Cache", enableCache, onEnableCacheChange)
        ToggleRow("Record APDU exchanges", enableApduTracing, onEnableApduTracingChange)
        ToggleRow("Server-Driven Flow", useServerFlow, onUseServerFlowChange)
        if (useServerFlow) {
            ToggleRow("PoPP Mode", poppMode, onPoppModeChange)
        }

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            "Enter OAuth credentials to start the flow.",
            style = MaterialTheme.typography.bodyMedium,
        )

        OutlinedButton(
            onClick = onLoadCredentials,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Icon(Icons.Default.Person, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("Load Saved Account")
        }

        OutlinedTextField(
            value = username,
            onValueChange = onUsernameChange,
            label = { Text("Username") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )

        OutlinedTextField(
            value = password,
            onValueChange = onPasswordChange,
            label = { Text("Password") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
            trailingIcon = {
                IconButton(onClick = onPasswordVisibilityToggle) {
                    Icon(
                        painter = painterResource(
                            id = if (passwordVisible) android.R.drawable.ic_menu_view
                            else android.R.drawable.ic_secure
                        ),
                        contentDescription = if (passwordVisible) "Hide password" else "Show password"
                    )
                }
            },
        )

        Spacer(modifier = Modifier.height(8.dp))

        Button(
            onClick = onStart,
            enabled = canStart,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Start Flow")
        }

        // Known cards on setup page
        if (enableCache && canStart) {
            KnownCardsPicker(onSubmitKnownCard)
        }
    }
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun FlowScreen(
    state: CardlinkFlowState,
    phone: String,
    onPhoneChange: (String) -> Unit,
    smsCode: String,
    onSmsCodeChange: (String) -> Unit,
    can: String,
    onCanChange: (String) -> Unit,
    onSubmitPhone: () -> Unit,
    onSubmitSmsCode: () -> Unit,
    onSubmitCan: () -> Unit,
    onSubmitKnownCard: (can: String, iccsn: String) -> Unit,
    onRetry: () -> Unit,
    onCancel: () -> Unit,
    onScanAnother: () -> Unit,
    onTrace: (String) -> Unit,
    username: String,
    password: String,
    isServerFlow: Boolean,
    enableCache: Boolean,
    activity: Activity?,
) {
    when (state) {
        is CardlinkFlowState.Idle ->
            StatusCard("Idle", "Waiting to start...")

        is CardlinkFlowState.Cancelled ->
            StatusCard("Cancelled", "The flow was cancelled.")

        is CardlinkFlowState.Connecting ->
            StatusCard("Connecting", "Authenticating and connecting to server...", loading = true)

        is CardlinkFlowState.NeedsPhoneNumber ->
            PhoneInput(phone, onPhoneChange, onSubmitPhone)

        is CardlinkFlowState.SmsRequested ->
            StatusCard("SMS Requested", "Sending SMS to ${state.phoneNumber}...", loading = true)

        is CardlinkFlowState.NeedsSmsCode -> {
            val debugCode = state.debugSmsCode
            if (debugCode != null && smsCode.isEmpty()) {
                LaunchedEffect(debugCode) { onSmsCodeChange(debugCode) }
            }
            SmsCodeInput(smsCode, onSmsCodeChange, state.phoneNumber, debugCode, onSubmitSmsCode)
        }

        is CardlinkFlowState.NeedsCan ->
            CanInput(
                can = can,
                onCanChange = onCanChange,
                previousCan = state.previousCan,
                onSubmitCan = onSubmitCan,
                onSubmitKnownCard = onSubmitKnownCard,
                enableCache = enableCache,
                activity = activity,
            )

        is CardlinkFlowState.WaitingForCard ->
            StatusCard("Waiting for Card", "Please hold your eGK card to the device.", loading = true)

        is CardlinkFlowState.ReadingCard ->
            ReadingCardView(state.progress, state.stepLabel, state.patientData)

        is CardlinkFlowState.Registering ->
            StatusCard("Registering", "Registering card with server...", loading = true)

        is CardlinkFlowState.WaitingForPrescriptions ->
            StatusCard("Waiting", "Waiting for prescriptions...", loading = true)

        is CardlinkFlowState.Completed ->
            CompletedView(
                iccsn = state.iccsn,
                prescriptions = state.prescriptions,
                tokensXml = state.tokensXml,
                patientData = state.patientData,
                isServerFlow = isServerFlow,
                onScanAnother = onScanAnother,
                onNewSession = onCancel,
                username = username,
                password = password,
                onTrace = onTrace,
            )

        is CardlinkFlowState.Error ->
            ErrorView(error = state.error, onRetry = onRetry, onBack = onCancel)
    }
}

@Composable
private fun StatusCard(title: String, subtitle: String, loading: Boolean = false) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Spacer(modifier = Modifier.height(48.dp))
        Text(title, style = MaterialTheme.typography.headlineSmall)
        Text(subtitle, style = MaterialTheme.typography.bodyMedium)
        if (loading) {
            CircularProgressIndicator()
        }
    }
}

@Composable
private fun PhoneInput(phone: String, onPhoneChange: (String) -> Unit, onSubmit: () -> Unit) {
    Column(
        modifier = Modifier
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Spacer(modifier = Modifier.height(24.dp))
        Text("Enter Phone Number", style = MaterialTheme.typography.headlineSmall)
        Text("We will send you an SMS verification code.")

        OutlinedTextField(
            value = phone,
            onValueChange = onPhoneChange,
            label = { Text("Phone Number") },
            placeholder = { Text("+49...") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
            modifier = Modifier.fillMaxWidth(),
        )

        Button(onClick = onSubmit, modifier = Modifier.fillMaxWidth()) {
            Text("Submit")
        }
    }
}

@Composable
private fun SmsCodeInput(
    smsCode: String,
    onSmsCodeChange: (String) -> Unit,
    phoneNumber: String,
    debugSmsCode: String?,
    onSubmit: () -> Unit
) {
    Column(
        modifier = Modifier
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Spacer(modifier = Modifier.height(24.dp))
        Text("Enter SMS Code", style = MaterialTheme.typography.headlineSmall)
        Text("Code sent to $phoneNumber")
        if (debugSmsCode != null) {
            Text(
                "Debug: code received from server",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.tertiary,
            )
        }

        OutlinedTextField(
            value = smsCode,
            onValueChange = onSmsCodeChange,
            label = { Text("Verification Code") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.fillMaxWidth(),
        )

        Button(onClick = onSubmit, modifier = Modifier.fillMaxWidth()) {
            Text("Verify")
        }
    }
}

@Composable
private fun CanInput(
    can: String,
    onCanChange: (String) -> Unit,
    previousCan: String?,
    onSubmitCan: () -> Unit,
    onSubmitKnownCard: (can: String, iccsn: String) -> Unit,
    enableCache: Boolean,
    activity: Activity?,
) {
    Column(
        modifier = Modifier
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Spacer(modifier = Modifier.height(24.dp))
        Text("Enter CAN", style = MaterialTheme.typography.headlineSmall)
        Text("Enter the 6-digit Card Access Number from your eGK.")

        if (previousCan != null) {
            Text(
                "Previous CAN was incorrect.",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }

        CanInputField(
            can = can,
            onCanChange = onCanChange,
            activity = activity,
            onScan = { if (it.length == 6) onSubmitCan() },
        )

        Button(
            onClick = onSubmitCan,
            enabled = can.length == 6,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Submit")
        }

        // Known cards section
        if (enableCache) {
            KnownCardsPicker(onSubmitKnownCard)
        }
    }
}

@Composable
private fun KnownCardsPicker(onSubmitKnownCard: (can: String, iccsn: String) -> Unit, refreshKey: Int = 0) {
    var knownCards by remember { mutableStateOf<List<KnownCard>>(emptyList()) }

    LaunchedEffect(refreshKey) {
        val cacheProvider = FileCacheProvider()
        knownCards = cacheProvider.getKnownCards()
    }

    KnownCardsList(
        knownCards = knownCards,
        onCardClick = { card -> onSubmitKnownCard(card.can, card.iccsn) },
    )
}

@Composable
private fun ReadingCardView(progress: Float, stepLabel: String, patientData: InsuredPersonData?) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Spacer(modifier = Modifier.height(48.dp))
        Text("Reading Card", style = MaterialTheme.typography.headlineSmall)
        Text("Keep your card steady!")

        LinearProgressIndicator(
            progress = { progress },
            modifier = Modifier.fillMaxWidth(),
        )
        Text("${(progress * 100).toInt()}% — $stepLabel")

        if (patientData != null) {
            Text(
                "Patient: ${patientData.firstName} ${patientData.lastName}",
                style = MaterialTheme.typography.titleMedium,
            )
            patientData.insuranceId?.let {
                Text("KVNR: $it", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun CompletedView(
    iccsn: String,
    prescriptions: List<String>,
    tokensXml: String?,
    patientData: InsuredPersonData?,
    isServerFlow: Boolean,
    onScanAnother: () -> Unit,
    onNewSession: () -> Unit,
    username: String,
    password: String,
    onTrace: (String) -> Unit,
) {
    val isPoppResult = prescriptions.isNotEmpty() && tryDecodeJwt(prescriptions.first()) != null

    // Parse deletable metadata per prescription. Prefer the server-supplied tokens Bundle
    // (Task resources, parallel to `prescriptions` by index); fall back to parsing the
    // prescription XML itself for flows where the token metadata is inlined.
    // key = "$iccsn:$index" so the delete state stays stable across recompositions but is
    // scoped to this card read.
    val deletable = remember(iccsn, prescriptions, tokensXml) {
        val fromTokens = tokensXml?.let {
            de.scoopsoftware.cardlink.fhir.PrescriptionMetadataParser.parseAll(it)
        } ?: emptyList()
        prescriptions.mapIndexedNotNull { index, xml ->
            val meta = fromTokens.getOrNull(index) ?: parsePrescriptionMetadata(xml)
            meta?.let { "$iccsn:$index" to it }
        }
    }
    val deleteController = rememberPrescriptionDeleteController(
        environment = CardlinkEnvironment.Default,
        username = username,
        password = password,
        onTrace = onTrace,
    )
    val remaining = deletable.count { (key, _) ->
        deleteController.stateFor(key) !is DeleteUiState.Deleted
    }
    val title = if (isPoppResult) "PoPP Flow Completed!" else "Flow Completed!"
    val subtitle = if (isPoppResult)
        "PoPP Token received"
    else
        "${prescriptions.size} prescription(s) received"

    Column(
        modifier = Modifier
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer,
            ),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                modifier = Modifier.padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(title, style = MaterialTheme.typography.headlineSmall)
                Text("ICCSN: $iccsn", style = MaterialTheme.typography.bodySmall)
                Text(subtitle)
                if (patientData != null) {
                    Text(
                        "Patient: ${patientData.firstName} ${patientData.lastName}",
                        style = MaterialTheme.typography.titleMedium,
                    )
                    patientData.insuranceId?.let {
                        Text("KVNR: $it", style = MaterialTheme.typography.bodySmall)
                    }
                    patientData.insurerName?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }

        if (isServerFlow) {
            Button(onClick = onScanAnother, modifier = Modifier.fillMaxWidth()) {
                Text("Scan Another Card")
            }
        }
        OutlinedButton(onClick = onNewSession, modifier = Modifier.fillMaxWidth()) {
            Text("New Session")
        }

        if (deletable.isNotEmpty()) {
            DeleteAllBar(
                remaining = remaining,
                lastGoodEnv = deleteController.lastGoodEnv,
                onDeleteAll = { deleteController.deleteAll(deletable) },
            )
        }

        prescriptions.forEachIndexed { index, prescription ->
            val jwt = tryDecodeJwt(prescription)
            if (jwt != null) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(12.dp)) {
                        Text("PoPP Token ${index + 1}", style = MaterialTheme.typography.titleSmall)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            jwt,
                            style = MaterialTheme.typography.bodySmall.copy(
                                fontFamily = FontFamily.Monospace,
                                fontSize = 10.sp,
                            ),
                        )
                    }
                }
            } else {
                val key = "$iccsn:$index"
                val metadata = deletable.firstOrNull { it.first == key }?.second
                PrescriptionCard(
                    index = index,
                    xml = prescription,
                    deleteState = if (metadata != null) deleteController.stateFor(key) else null,
                    onDelete = if (metadata != null) {
                        { deleteController.delete(key, metadata) }
                    } else null,
                )
            }
        }
    }
}

@Composable
private fun ErrorView(error: CardlinkFlowError, onRetry: () -> Unit, onBack: () -> Unit) {
    val isCardDisconnect = error.recoveryAction == RecoveryAction.RETRY_CARD
    val title = when {
        isCardDisconnect -> "Card Disconnected"
        error.phase.name == "WEBSOCKET" -> "Server Connection Failed"
        else -> "Error"
    }
    val body = when {
        isCardDisconnect -> "The card was removed. Hold your eGK to the device again."
        else -> error.message
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Spacer(modifier = Modifier.height(48.dp))
        Text(title, style = MaterialTheme.typography.headlineSmall)
        Text(body, style = MaterialTheme.typography.bodyMedium)
        Text(
            "Phase: ${error.phase}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        if (!error.isTerminal) {
            Button(onClick = onRetry, modifier = Modifier.fillMaxWidth()) {
                Text(if (isCardDisconnect) "Hold Card Again" else "Retry")
            }
        }
        OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) {
            Text("Back to Setup")
        }
    }
}

@Composable
private fun PrescriptionCard(
    index: Int,
    xml: String,
    deleteState: DeleteUiState? = null,
    onDelete: (() -> Unit)? = null,
) {
    val parsed = remember(xml) { FhirBundleParser.parse(xml) }
    var showRawXml by remember { mutableStateOf(false) }
    val struckThrough = deleteState is DeleteUiState.Deleted

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (struckThrough)
                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
            else MaterialTheme.colorScheme.surfaceVariant
        ),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            // Header with optional delete icon
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("Prescription ${index + 1}", style = MaterialTheme.typography.titleMedium)
                if (onDelete != null && deleteState != null) {
                    DeleteStatusAction(state = deleteState, onDelete = onDelete)
                }
            }
            if (deleteState is DeleteUiState.Failed) {
                Text(
                    deleteState.message,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            if (parsed != null) {
                // Medication section
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                ) {
                    Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("Medication", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                        parsed.medication.name?.let {
                            Text(it, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            parsed.medication.pzn?.let {
                                Text("PZN: $it", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                            }
                            parsed.medication.form?.let {
                                Text(it, style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                            }
                            parsed.medication.normgroesse?.let {
                                Text(it, style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                            }
                        }
                        parsed.medication.ingredients.forEach { ingredient ->
                            Text(
                                "${ingredient.name ?: ""}${ingredient.strength?.let { " ($it)" } ?: ""}",
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                        parsed.dosage?.let {
                            Text("Dosage: $it", style = MaterialTheme.typography.bodySmall)
                        }
                        parsed.quantity?.let {
                            Text("Quantity: $it", style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }

                // Practitioner section
                parsed.practitioner?.let { doc ->
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    ) {
                        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text("Prescribing Doctor", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                            Text(
                                "${doc.prefix?.let { "$it " } ?: ""}${doc.name ?: "Unknown"}",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Bold,
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                doc.qualification?.let {
                                    Text(it, style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                                }
                                doc.lanr?.let {
                                    Text("LANR: $it", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                                }
                            }
                        }
                    }
                }

                parsed.authoredOn?.let {
                    Text("Issued: $it", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                }
            }

            // Toggle raw XML
            OutlinedButton(
                onClick = { showRawXml = !showRawXml },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (showRawXml) "Hide XML" else "Show XML")
            }
            if (showRawXml) {
                Text(
                    xml,
                    style = MaterialTheme.typography.bodySmall.copy(
                        fontFamily = FontFamily.Monospace,
                        fontSize = 10.sp,
                    ),
                )
            }
        }
    }
}

private fun tryDecodeJwt(token: String): String? {
    val parts = token.split(".")
    if (parts.size != 3) return null
    return try {
        var payload = parts[1]
        val mod = payload.length % 4
        if (mod > 0) payload += "=".repeat(4 - mod)
        val decoded = String(android.util.Base64.decode(payload, android.util.Base64.URL_SAFE))
        val json = org.json.JSONObject(decoded)
        json.toString(2)
    } catch (_: Exception) {
        null
    }
}
