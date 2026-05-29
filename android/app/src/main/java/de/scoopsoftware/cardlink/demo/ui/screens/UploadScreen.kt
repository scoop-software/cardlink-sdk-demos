package de.scoopsoftware.cardlink.demo.ui.screens

import android.app.Activity
import androidx.compose.foundation.clickable
import androidx.compose.foundation.text.selection.SelectionContainer
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import de.scoopsoftware.cardlink.auth.CredentialStorageFactory
import de.scoopsoftware.nfc.cache.FileCacheProvider
import de.scoopsoftware.nfc.cache.KnownCard
import de.scoopsoftware.nfc.can.CanInputField
import de.scoopsoftware.cardlink.demo.ui.components.KnownCardsList
import de.scoopsoftware.cardlink.demo.ui.components.TraceLogSheet
import de.scoopsoftware.cardlink.fhir.ErezeptBundleInfo
import de.scoopsoftware.cardlink.fhir.ErezeptBundles
import de.scoopsoftware.cardlink.fhir.ErezeptType
import de.scoopsoftware.cardlink.flow.AndroidNfcTransceiverProvider
import de.scoopsoftware.cardlink.flow.CardlinkFlowConfig
import de.scoopsoftware.cardlink.flow.ErezeptUploadFlow
import de.scoopsoftware.cardlink.flow.ErezeptUploadState
import de.scoopsoftware.cardlink.websocket.CardlinkEnvironment
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UploadScreen(
    activity: Activity?,
    username: String,
    password: String
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // Trace log
    val traceLog = remember { mutableStateListOf<String>() }

    // CAN input state (persisted separately since it's used across flow restarts)
    var can by remember { mutableStateOf("") }
    var showTraceLog by remember { mutableStateOf(false) }

    // Gematik target environment for prescription uploads (DEV or RU)
    var uploadTargetRU by remember { mutableStateOf(false) }

    // Flow instance
    var uploadFlow by remember { mutableStateOf<ErezeptUploadFlow?>(null) }

    // Track selections across state transitions
    var selectedBundle by remember { mutableStateOf<ErezeptBundleInfo?>(null) }
    var selectedCardLabel by remember { mutableStateOf<String?>(null) }

    fun startFlow() {
        if (activity == null) return
        if (username.isBlank() || password.isBlank()) return

        uploadFlow?.cancel()

        val nfcProvider = AndroidNfcTransceiverProvider(activity)
        val credentialStorage = CredentialStorageFactory.create(context)
        val cacheProvider = FileCacheProvider()

        val config = CardlinkFlowConfig(
            environment = CardlinkEnvironment.Default,
            username = username.trim(),
            password = password.trim(),
            credentialStorage = credentialStorage,
            cacheProvider = cacheProvider,
            uploadTargetEnv = if (uploadTargetRU) "ru" else "dev",
        )

        traceLog.clear()
        selectedBundle = null
        selectedCardLabel = null

        val flow = ErezeptUploadFlow(config, nfcProvider)
        uploadFlow = flow

        scope.launch { flow.start() }
    }

    // Auto-start when credentials are available
    LaunchedEffect(username, password, uploadTargetRU) {
        if (username.isNotBlank() && password.isNotBlank() && uploadFlow == null) {
            startFlow()
        }
    }

    // Observe flow state
    val flowState by uploadFlow?.state?.collectAsState()
        ?: remember { mutableStateOf<ErezeptUploadState>(ErezeptUploadState.NeedsBundle(emptyMap())) }

    // Update selections from state
    LaunchedEffect(flowState) {
        when (val s = flowState) {
            is ErezeptUploadState.NeedsBundle -> {
                selectedBundle = null
                selectedCardLabel = null
            }
            is ErezeptUploadState.NeedsCard -> {
                selectedBundle = s.selectedBundle
            }
            is ErezeptUploadState.WaitingForCard,
            is ErezeptUploadState.ReadingCard,
            is ErezeptUploadState.Uploading -> {
                if (selectedCardLabel == null) selectedCardLabel = "eGK"
            }
            is ErezeptUploadState.Completed -> {
                if (selectedCardLabel == null) selectedCardLabel = "eGK"
                s.bundle?.let { selectedBundle = it }
            }
            is ErezeptUploadState.Error -> {
                if (selectedCardLabel == null) selectedCardLabel = "eGK"
                s.bundle?.let { selectedBundle = it }
            }
        }
    }

    // Collect trace events
    LaunchedEffect(uploadFlow) {
        uploadFlow?.traceEvents?.collect { event ->
            traceLog.add(0, event.toString())
            if (traceLog.size > 300) traceLog.removeAt(traceLog.lastIndex)
        }
    }

    val pastBundleSelection = flowState !is ErezeptUploadState.NeedsBundle
    val pastCardSelection = flowState is ErezeptUploadState.WaitingForCard ||
            flowState is ErezeptUploadState.ReadingCard ||
            flowState is ErezeptUploadState.Uploading ||
            flowState is ErezeptUploadState.Completed ||
            flowState is ErezeptUploadState.Error

    Column(modifier = Modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text("eRezept Upload") },
            actions = {
                SingleChoiceSegmentedButtonRow(modifier = Modifier.padding(end = 8.dp)) {
                    SegmentedButton(
                        selected = !uploadTargetRU,
                        onClick = { if (uploadTargetRU) { uploadTargetRU = false; uploadFlow?.cancel(); uploadFlow = null } },
                        shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2)
                    ) { Text("DEV", style = MaterialTheme.typography.labelSmall) }
                    SegmentedButton(
                        selected = uploadTargetRU,
                        onClick = { if (!uploadTargetRU) { uploadTargetRU = true; uploadFlow?.cancel(); uploadFlow = null } },
                        shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2)
                    ) { Text("RU", style = MaterialTheme.typography.labelSmall) }
                }
                IconButton(onClick = { showTraceLog = true }) {
                    Text("Log", style = MaterialTheme.typography.labelSmall)
                }
            }
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
        ) {
            // Step 1: Prescription
            StepHeader("1. Prescription", done = pastBundleSelection)
            Spacer(modifier = Modifier.height(8.dp))

            if (pastBundleSelection && selectedBundle != null) {
                BundleSummaryRow(selectedBundle!!)
            } else if (flowState is ErezeptUploadState.NeedsBundle) {
                BundleSelector(
                    grouped = (flowState as ErezeptUploadState.NeedsBundle).bundles,
                    onSelected = { bundle -> uploadFlow?.submitBundle(bundle.id) }
                )
            }

            // Step 2: Card
            if (pastBundleSelection) {
                Spacer(modifier = Modifier.height(16.dp))
                StepHeader("2. Card", done = pastCardSelection)
                Spacer(modifier = Modifier.height(8.dp))

                if (pastCardSelection) {
                    CardSummaryRow(selectedCardLabel ?: "eGK")
                } else if (flowState is ErezeptUploadState.NeedsCard) {
                    val state = flowState as ErezeptUploadState.NeedsCard
                    CardSelector(
                        state = state,
                        can = can,
                        onCanChange = { can = it },
                        activity = activity,
                        onKnownCard = { card ->
                            can = card.can
                            selectedCardLabel = card.displayName?.ifEmpty { null } ?: "CAN ${card.can}"
                            uploadFlow?.submitKnownCard(card)
                        },
                        onNewCard = {
                            selectedCardLabel = "CAN $can"
                            uploadFlow?.submitCardInfo(can.trim())
                        }
                    )
                }
            }

            // Step 3: Upload
            if (pastCardSelection) {
                Spacer(modifier = Modifier.height(16.dp))
                StepHeader("3. Upload", done = flowState is ErezeptUploadState.Completed)
                Spacer(modifier = Modifier.height(8.dp))

                when (val state = flowState) {
                    is ErezeptUploadState.WaitingForCard -> {
                        StatusRow("Hold your eGK to the phone...", loading = true)
                    }
                    is ErezeptUploadState.ReadingCard -> {
                        Column {
                            LinearProgressIndicator(
                                progress = { state.progress },
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(state.stepLabel, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    is ErezeptUploadState.Uploading -> {
                        StatusRow("Sending prescription to server...", loading = true)
                    }
                    is ErezeptUploadState.Completed -> {
                        CompletedContent(state = state, onStartOver = { startFlow() })
                    }
                    is ErezeptUploadState.Error -> {
                        ErrorContent(
                            state = state,
                            onStartOver = { startFlow() },
                            onCopyFailed = {
                                uploadFlow?.exportFailedBundles() ?: ""
                            }
                        )
                    }
                    else -> {}
                }
            }
        }
    }

    if (showTraceLog) {
        TraceLogSheet(
            traceLog = traceLog,
            onDismiss = { showTraceLog = false }
        )
    }
}

@Composable
private fun StepHeader(title: String, done: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (done) {
            Icon(
                Icons.Default.CheckCircle,
                contentDescription = "Done",
                tint = Color(0xFF4CAF50),
                modifier = Modifier.size(20.dp)
            )
        }
        Text(
            title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = if (done) Color.Gray else MaterialTheme.colorScheme.onSurface
        )
    }
}

@Composable
private fun BundleSummaryRow(bundle: ErezeptBundleInfo) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(bundle.medicationName, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text("${bundle.type.name} · KBV ${bundle.version} · ${bundle.source}", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
        }
    }
}

@Composable
private fun CardSummaryRow(label: String) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Person, contentDescription = null, tint = Color.Gray, modifier = Modifier.size(20.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text(label, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun StatusRow(text: String, loading: Boolean = false) {
    Row(
        modifier = Modifier.padding(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (loading) CircularProgressIndicator(modifier = Modifier.size(16.dp))
        Text(text, style = MaterialTheme.typography.bodySmall, color = Color.Gray)
    }
}

@Composable
private fun CompletedContent(state: ErezeptUploadState.Completed, onStartOver: () -> Unit) {
    var showResponse by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Default.CheckCircle, contentDescription = "Success", tint = Color(0xFF4CAF50), modifier = Modifier.size(20.dp))
            Text("Upload Successful (${state.statusCode})", style = MaterialTheme.typography.bodyMedium, color = Color(0xFF4CAF50))
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (state.body.isNotBlank() && !showResponse) {
                Text(
                    "Show Response",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier
                        .clickable { showResponse = true }
                        .padding(vertical = 4.dp)
                )
            } else {
                Spacer(modifier = Modifier.width(1.dp))
            }
            OutlinedButton(onClick = onStartOver) {
                Text("Start Over")
            }
        }
        if (showResponse && state.body.isNotBlank()) {
            SelectionContainer {
                Text(state.body, style = MaterialTheme.typography.bodySmall, color = Color.Gray)
            }
        }
    }
}

@Composable
private fun ErrorContent(
    state: ErezeptUploadState.Error,
    onStartOver: () -> Unit,
    onCopyFailed: () -> String
) {
    val clipboardManager = LocalClipboardManager.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            "Error (${state.phase.name})",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.error
        )
        SelectionContainer {
            Text(
                state.message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onStartOver) {
                Text("Start Over")
            }
            val failed = onCopyFailed()
            if (failed.isNotBlank()) {
                OutlinedButton(onClick = {
                    clipboardManager.setText(AnnotatedString(failed))
                }) {
                    Text("Copy Failed Bundles")
                }
            }
        }
    }
}

@Composable
private fun BundleSelector(
    grouped: Map<ErezeptType, List<ErezeptBundleInfo>>,
    onSelected: (ErezeptBundleInfo) -> Unit
) {
    val typeOrder = listOf(ErezeptType.PZN, ErezeptType.WIRKSTOFF, ErezeptType.FREITEXT, ErezeptType.REZEPTUR)

    typeOrder.forEach { type ->
        val bundles = grouped[type] ?: return@forEach
        Text(
            type.name,
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(top = 8.dp, bottom = 4.dp)
        )
        bundles.forEach { bundle ->
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 2.dp)
                    .clickable { onSelected(bundle) },
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
            ) {
                Row(
                    modifier = Modifier.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(bundle.medicationName, style = MaterialTheme.typography.bodyMedium)
                        Text("KBV ${bundle.version} · ${bundle.source}", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                    }
                }
            }
        }
    }
}

@Composable
private fun CardSelector(
    state: ErezeptUploadState.NeedsCard,
    can: String,
    onCanChange: (String) -> Unit,
    activity: Activity?,
    onKnownCard: (KnownCard) -> Unit,
    onNewCard: () -> Unit
) {
    if (state.knownCards.isNotEmpty()) {
        KnownCardsList(
            knownCards = state.knownCards,
            onCardClick = { card -> onKnownCard(card) },
        )

        HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))
        Text(
            "Or use a new card",
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(bottom = 4.dp)
        )
    }

    CanInputField(
        can = can,
        onCanChange = onCanChange,
        activity = activity,
        persistKey = "lastCan",
        onScan = { if (it.length == 6) onNewCard() },
    )

    Spacer(modifier = Modifier.height(8.dp))

    Button(
        onClick = onNewCard,
        enabled = can.length == 6
    ) {
        Text("Use New Card")
    }
}
