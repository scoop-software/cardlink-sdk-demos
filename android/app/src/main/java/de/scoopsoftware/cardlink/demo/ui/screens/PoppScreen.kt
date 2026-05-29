package de.scoopsoftware.cardlink.demo.ui.screens

import android.app.Activity
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import androidx.compose.foundation.background
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Star
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.res.painterResource
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import de.scoopsoftware.nfc.can.CanInputField
import de.scoopsoftware.cardlink.demo.ui.components.DeleteAllBar
import de.scoopsoftware.cardlink.demo.ui.components.DeleteStatusAction
import de.scoopsoftware.cardlink.demo.ui.components.DeleteUiState
import de.scoopsoftware.cardlink.demo.ui.components.KnownCardsList
import de.scoopsoftware.cardlink.demo.ui.components.TraceLogSheet
import de.scoopsoftware.cardlink.demo.ui.components.rememberPrescriptionDeleteController
import de.scoopsoftware.cardlink.flow.AndroidNfcTransceiverProvider
import de.scoopsoftware.cardlink.popp.PoppFlow
import de.scoopsoftware.cardlink.popp.PoppFlowConfig
import de.scoopsoftware.cardlink.popp.PoppFlowState
import de.scoopsoftware.cardlink.popp.PoppStorageImpl
import de.scoopsoftware.cardlink.popp.ui.PoppStrings
import de.scoopsoftware.cardlink.demo.ui.model.ScanHistory
import de.scoopsoftware.cardlink.fhir.FhirBundleParser
import de.scoopsoftware.cardlink.fhir.PrescriptionMetadata
import de.scoopsoftware.cardlink.fhir.PrescriptionMetadataParser
import de.scoopsoftware.cardlink.websocket.CardlinkEnvironment
import de.scoopsoftware.nfc.EgkReader
import de.scoopsoftware.nfc.cache.FileCacheProvider
import de.scoopsoftware.nfc.metrics.ScanRecord
import de.scoopsoftware.nfc.cache.KnownCard
import de.scoopsoftware.nfc.cache.getKnownCards
import de.scoopsoftware.popp.module.*
import kotlinx.coroutines.*
import com.google.gson.Gson
import com.google.gson.JsonParser
import com.google.gson.GsonBuilder
import java.net.HttpURLConnection
import java.net.URL
import java.util.*
import kotlin.math.sin
import kotlin.math.cos

private const val POPP_SERVICE_URL = "https://popp-sample-server-dev.demo.scoop-gmbh.de"
private const val TICONNECT_URL = "https://ticonnect-dev.demo.scoop-gmbh.de"
private const val OAUTH_TOKEN_URL = "https://auth-cardlink-dev.demo.scoop-gmbh.de/realms/cardlinkdemo/protocol/openid-connect/token"
private const val TELEMATIK_ID = "3-SMC-B-Testkarte--883110000153556"

@Composable
fun PoppScreen(
    activity: Activity?,
    username: String,
    onUsernameChange: (String) -> Unit,
    password: String,
    onPasswordChange: (String) -> Unit,
    scanHistory: ScanHistory? = null,
) {
    val currentBrandTheme = de.scoopsoftware.cardlink.demo.ui.theme.LocalBrandTheme.current.value
    var useFakeErezept by rememberSaveable {
        val cutoff = Calendar.getInstance(TimeZone.getTimeZone("Europe/Berlin")).apply {
            set(2026, Calendar.MARCH, 23, 9, 0, 0)
        }.timeInMillis
        mutableStateOf(System.currentTimeMillis() < cutoff)
    }
    val context = LocalContext.current
    val poppPrefs = context.getSharedPreferences("popp_settings", android.content.Context.MODE_PRIVATE)
    var useFileCache by remember { mutableStateOf(poppPrefs.getBoolean("scoopSignatureMode", false)) }
    var useRisePoppService by rememberSaveable { mutableStateOf(true) }

    var flowState by remember { mutableStateOf<PoppFlowState>(PoppFlowState.Idle) }
    var traceLog by remember { mutableStateOf(listOf<String>()) }
    var poppFlow by remember { mutableStateOf<PoppFlow?>(null) }
    var accessToken by remember { mutableStateOf<String?>(null) }
    var showLog by remember { mutableStateOf(false) }

    // Token + prescription state
    var tokenEntries by remember { mutableStateOf<List<TokenEntry>?>(null) }
    var hasPrescriptions by remember { mutableStateOf(false) }
    var showConfetti by remember { mutableStateOf(false) }
    var fetchingTokens by remember { mutableStateOf(false) }
    var knownCards by remember { mutableStateOf<List<KnownCard>>(emptyList()) }

    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        knownCards = FileCacheProvider().getKnownCards()
    }

    fun addTrace(msg: String) {
        println("[PoPP] $msg")
        traceLog = traceLog + msg
    }

    fun cancel() {
        poppFlow?.cancel()
        poppFlow = null
        flowState = PoppFlowState.Idle
        tokenEntries = null
        hasPrescriptions = false
        showConfetti = false
        fetchingTokens = false
    }

    fun startCheckIn(telematikId: String? = TELEMATIK_ID) {
        traceLog = emptyList()
        tokenEntries = null
        hasPrescriptions = false
        showConfetti = false
        fetchingTokens = false

        val nfcProvider = activity?.let { AndroidNfcTransceiverProvider(it) }

        val config = PoppFlowConfig(
            zetaClient = MockVzdRealPoppClient(
                oauthTokenUrl = OAUTH_TOKEN_URL,
                username = username,
                password = password,
                trace = { msg -> addTrace(msg) },
                onTokenAcquired = { token -> accessToken = token },
                extraHeaders = if (useRisePoppService) mapOf("X-PoPP-Service" to "RISE-DEV") else emptyMap(),
            ),
            storage = PoppStorageImpl(),
            moduleConfig = PoppConfig(
                poppServiceBaseUrl = POPP_SERVICE_URL,
                vzdBaseUrl = POPP_SERVICE_URL,
                clientId = "scoop-cardlink-demo",
            ),
            nfcProvider = nfcProvider,
            knownCards = knownCards,
            cacheProvider = if (useFileCache) FileCacheProvider() else null,
            onNfcDone = { nfcProvider?.stop() },
            onNfcMessage = { msg -> addTrace("NFC: $msg") },
            onTrace = { msg -> addTrace(msg) },
            appUserAgent = "${activity?.packageName ?: "unknown"}/${de.scoopsoftware.cardlink.demo.BuildConfig.VERSION_NAME}",
            uiContext = activity?.let { act ->
                de.scoopsoftware.popp.module.PoppUiContext(
                    activity = act,
                    composeTheme = { content ->
                        de.scoopsoftware.cardlink.demo.ui.theme.CardlinkDemoTheme(brandTheme = currentBrandTheme) {
                            content()
                        }
                    },
                )
            },
        )

        val flow = PoppFlow(config)
        poppFlow = flow

        scope.launch {
            flow.state.collect { state ->
                flowState = state

                // Record performance metrics for charts — only on successful completion
                if (state is PoppFlowState.Completed) {
                    val metrics = flow.lastMetricsSnapshot ?: EgkReader.getPerformanceMetricsSnapshot()
                    val record = ScanRecord(id = UUID.randomUUID().toString(), metrics = metrics)
                    scanHistory?.add(record)

                    // Post to RocketChat (fire-and-forget)
                    val rcPrefs = context.getSharedPreferences("rocketchat_settings", android.content.Context.MODE_PRIVATE)
                    if (rcPrefs.getBoolean("enabled", false)) {
                        val serverUrl = (rcPrefs.getString("serverUrl", "") ?: "").ifBlank { de.scoopsoftware.cardlink.reporting.RocketChatReporter.DEFAULT_SERVER_URL }
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
                        val rcChannel = rcPrefs.getString("channel", "PoPP-Demo") ?: "PoPP-Demo"
                        if (serverUrl.isNotBlank() && rcUser.isNotBlank()) {
                            val success = state is PoppFlowState.Completed
                            val log = traceLog.toList()
                            launch {
                                de.scoopsoftware.cardlink.reporting.RocketChatReporter.report(serverUrl, rcUser, rcPass, rcChannel, record, success, log)
                            }
                        }
                    }
                }

                // After check-in completes, fetch tokens
                if (state is PoppFlowState.Completed &&
                    (state.result is PoppCheckInResult.Success || state.result is PoppCheckInResult.Pending)
                ) {
                    fetchingTokens = true
                    val tokens = fetchPoppTokens(accessToken, ::addTrace)
                    if (tokens != null) {
                        val entries = tokens.mapIndexed { i, jwt -> TokenEntry(i, jwt) }
                        tokenEntries = entries
                        fetchingTokens = false

                        // Fetch prescriptions per token
                        for ((idx, entry) in entries.withIndex()) {
                            tokenEntries = tokenEntries?.toMutableList()?.also {
                                it[idx] = entry.copy(prescriptionState = PrescriptionState.Loading)
                            }
                            val result = fetchPrescriptions(accessToken, entry.raw, useFakeErezept, ::addTrace)
                            tokenEntries = tokenEntries?.toMutableList()?.also {
                                it[idx] = entry.copy(prescriptionState = result)
                            }
                            if (result is PrescriptionState.Loaded && result.xmls.isNotEmpty()) {
                                hasPrescriptions = true
                            }
                        }
                        if (hasPrescriptions) {
                            showConfetti = true
                        }
                    } else {
                        fetchingTokens = false
                    }
                }
            }
        }

        flow.startCheckIn(telematikId = telematikId)
    }

    @OptIn(ExperimentalMaterial3Api::class)
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("PoPP Check-in") },
                actions = {
                    if (traceLog.isNotEmpty()) {
                        IconButton(onClick = { showLog = true }) {
                            Icon(Icons.Default.Search, contentDescription = "Trace Log")
                        }
                    }
                }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            when {
                tokenEntries != null -> TokensScreen(
                    entries = tokenEntries!!,
                    hasPrescriptions = hasPrescriptions,
                    onDone = { cancel() },
                    username = username,
                    password = password,
                    onTrace = { msg -> addTrace(msg) },
                )
                fetchingTokens -> FetchingTokensScreen()
                else -> when (val s = flowState) {
                    is PoppFlowState.Idle -> IdleScreen(
                        username = username,
                        onUsernameChange = onUsernameChange,
                        password = password,
                        onPasswordChange = onPasswordChange,
                        useFakeErezept = useFakeErezept,
                        onFakeToggle = { useFakeErezept = it },
                        useRisePoppService = useRisePoppService,
                        onRiseToggle = { useRisePoppService = it },
                        canStart = username.isNotEmpty() && password.isNotEmpty(),
                        onStart = { startCheckIn() },
                        onQrScan = { startCheckIn(telematikId = null) },
                    )
                    is PoppFlowState.Initializing -> LoadingScreen(PoppStrings.INITIALIZING)
                    is PoppFlowState.NeedsLeiSelectionMethod -> LeiSelectionScreen(s.hasFavorites, poppFlow)
                    is PoppFlowState.ScanningQr -> QrScannerScreen(
                        onResult = { payload -> poppFlow?.submitQrScanResult(payload) },
                        onCancel = { poppFlow?.submitQrScanResult(null) },
                    )
                    is PoppFlowState.NeedsVzdSearch -> VzdSearchScreen(poppFlow)
                    is PoppFlowState.NeedsFavoriteSelection -> FavoritesScreen(s.favorites, poppFlow)
                    is PoppFlowState.NeedsConsent -> {
                        // Consent handled natively by the PoPP module via showConsentSheet
                        LoadingScreen("Warte auf Bestätigung...")
                    }
                    is PoppFlowState.NeedsAuthMethod -> AuthMethodScreen(s.gidAvailable, poppFlow)
                    is PoppFlowState.NeedsCan -> CanScreen(s.knownCards, s.errorMessage, poppFlow)
                    is PoppFlowState.WaitingForCard -> LoadingScreen(PoppStrings.EGK_HOLD_CARD)
                    is PoppFlowState.AuthenticatingEgk -> LoadingScreen(PoppStrings.EGK_READING)
                    is PoppFlowState.AuthenticatingGid -> LoadingScreen(PoppStrings.GID_WAITING)
                    is PoppFlowState.Completed -> CompletedScreen(s.result, { cancel() })
                    is PoppFlowState.Cancelled -> CancelledScreen(s.message, { cancel() })
                    is PoppFlowState.Error -> ErrorScreen(s.message, { cancel() })
                }
            }

            if (showConfetti) {
                ConfettiEffect()
            }
        }
    }

    // Trace log dialog
    if (showLog) {
        TraceLogSheet(traceLog = traceLog, onDismiss = { showLog = false })
    }

    DisposableEffect(Unit) {
        onDispose { poppFlow?.cancel() }
    }
}

// ---- Data models ----

data class TokenEntry(
    val index: Int,
    val raw: String,
    val header: String = decodeJwtPart(raw, 0),
    val payload: String = decodeJwtPart(raw, 1),
    val prescriptionState: PrescriptionState = PrescriptionState.Idle,
)

sealed class PrescriptionState {
    data object Idle : PrescriptionState()
    data object Loading : PrescriptionState()
    /** [metadata] is parallel to [xmls]; an entry is null when taskId/accessCode can't be parsed. */
    data class Loaded(
        val xmls: List<String>,
        val metadata: List<PrescriptionMetadata?> = emptyList(),
    ) : PrescriptionState()
    data class Error(val message: String) : PrescriptionState()
}

private fun decodeJwtPart(jwt: String, part: Int): String {
    val parts = jwt.split(".")
    if (parts.size <= part) return "Invalid JWT"
    return try {
        val decoded = String(Base64.getUrlDecoder().decode(parts[part]))
        val json = JsonParser.parseString(decoded)
        GsonBuilder().setPrettyPrinting().create().toJson(json)
    } catch (e: Exception) { parts[part] }
}

// ---- Network helpers ----

private suspend fun fetchPoppTokens(
    accessToken: String?,
    trace: (String) -> Unit,
): List<String>? = withContext(Dispatchers.IO) {
    val url = "$TICONNECT_URL/internal/popp/token-via-popp-module?telematikId=$TELEMATIK_ID"
    trace(">>> GET $url")
    try {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.requestMethod = "GET"
        accessToken?.let { conn.setRequestProperty("Authorization", "Bearer $it") }
        val body = conn.inputStream.bufferedReader().readText()
        trace("<<< ${conn.responseCode}: $body")
        val json = JsonParser.parseString(body).asJsonObject
        val tokens = json.getAsJsonArray("poppTokens")?.map { it.asString } ?: emptyList()
        trace("Received ${tokens.size} token(s)")
        tokens
    } catch (e: Exception) {
        trace("Token fetch error: ${e.message}")
        null
    }
}

private suspend fun fetchPrescriptions(
    accessToken: String?,
    poppToken: String,
    useFake: Boolean,
    trace: (String) -> Unit,
): PrescriptionState = withContext(Dispatchers.IO) {
    val url = "$TICONNECT_URL/internal/popp/erezept"
    trace(">>> GET $url")
    try {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.requestMethod = "GET"
        accessToken?.let { conn.setRequestProperty("Authorization", "Bearer $it") }
        conn.setRequestProperty("X-PoPP-Token", poppToken)
        if (useFake) conn.setRequestProperty("PRezept", "0xdeadbead")
        val body = conn.inputStream.bufferedReader().readText()
        trace("<<< ${conn.responseCode}: $body")
        val json = JsonParser.parseString(body).asJsonObject
        val meds = json.getAsJsonArray("medicationXMLs")?.map { it.asString } ?: emptyList()
        val taskXml = json.get("taskXML")?.takeIf { !it.isJsonNull }?.asString
        val taskMetadata = taskXml?.let { PrescriptionMetadataParser.parseAll(it) } ?: emptyList()
        val metadata: List<PrescriptionMetadata?> = meds.mapIndexed { i, xml ->
            taskMetadata.getOrNull(i) ?: PrescriptionMetadataParser.parseFirst(xml)
        }
        trace("Received ${meds.size} prescription(s); deletable=${metadata.count { it != null }}")
        PrescriptionState.Loaded(meds, metadata)
    } catch (e: Exception) {
        trace("eRezept error: ${e.message}")
        PrescriptionState.Error(e.message ?: "Unknown error")
    }
}

// ---- Mock VZD + Real PoPP Client ----

private class MockVzdRealPoppClient(
    private val oauthTokenUrl: String,
    private val username: String,
    private val password: String,
    private val trace: (String) -> Unit,
    private val onTokenAcquired: (String) -> Unit,
    private val extraHeaders: Map<String, String> = emptyMap(),
) : PoppZetaClient {
    private var accessToken: String? = null

    override suspend fun init() {
        trace("OAuth: Logging in as $username...")
        val conn = URL(oauthTokenUrl).openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
        conn.doOutput = true
        conn.outputStream.write("grant_type=password&client_id=cardlink-app&username=$username&password=$password&scope=openid".toByteArray())
        val body = conn.inputStream.bufferedReader().readText()
        val json = JsonParser.parseString(body).asJsonObject
        accessToken = json.get("access_token")?.asString
        trace("OAuth: Token acquired (${accessToken?.take(20)}...)")
        accessToken?.let { onTokenAcquired(it) }
    }

    override suspend fun executeVzdRequest(request: PoppHttpRequest): PoppHttpResponse {
        // Transform module's FHIR-VZD request into PoPP Service practitioner-information call.
        // Module sends: GET ${vzdBaseUrl}/Organization?identifier=<tid> or ?name=<query>
        // PoPP Service: GET /popp/patient/api/practitioner/v1/practitioner-information?searchrequest=<query>
        // Extract the value from identifier=<tid> or name=<query>
        val queryString = request.url.substringAfter("Organization?", "")
        if (queryString.isEmpty()) {
            return PoppHttpResponse(400, """{"errorCode":"INVALID_REQUEST"}""", emptyMap())
        }
        val searchValue = queryString.substringAfter("=", "")
        val searchRequest = java.net.URLEncoder.encode(searchValue, "UTF-8")
        val poppUrl = "$POPP_SERVICE_URL/popp/patient/api/practitioner/v1/practitioner-information?searchrequest=$searchRequest"
        trace("VZD resolve: $poppUrl")
        val poppRequest = PoppHttpRequest(url = poppUrl, method = "GET", headers = request.headers, body = null)
        val response = executeHttp(poppRequest)

        // Transform response: PoPP returns { "searchresult": { displayName, address, ... } }
        // Module expects a FHIR Bundle with Organization entries
        return try {
            val wrapper = JsonParser.parseString(response.body).asJsonObject
            val result = wrapper.getAsJsonObject("searchresult")
            if (result != null) {
                val displayName = result.get("displayName")?.asString ?: ""
                val address = result.get("address")?.asString ?: ""
                val specialty = result.get("specialty")?.asString ?: ""
                val tid = result.get("telematikId")?.asString ?: ""
                // Build a minimal FHIR Bundle that the module's parseVzdResponse can understand
                val fhirBundle = Gson().toJson(mapOf(
                    "entry" to listOf(mapOf(
                        "resource" to mapOf(
                            "name" to displayName,
                            "type" to listOf(mapOf("coding" to listOf(mapOf("display" to specialty)))),
                            "address" to listOf(mapOf("text" to address)),
                            "identifier" to listOf(mapOf("value" to tid)),
                        )
                    ))
                ))
                PoppHttpResponse(200, fhirBundle, emptyMap())
            } else {
                response
            }
        } catch (_: Exception) {
            response
        }
    }

    override suspend fun executeEgkCheckIn(request: PoppHttpRequest, authorizationDetails: String): PoppHttpResponse {
        return executeHttp(request)
    }

    override suspend fun executeGidCheckIn(request: PoppHttpRequest, authorizationDetails: String): PoppHttpResponse {
        return executeHttp(request)
    }

    override suspend fun executeStatusRequest(request: PoppHttpRequest): PoppHttpResponse {
        return executeHttp(request)
    }

    private fun executeHttp(request: PoppHttpRequest): PoppHttpResponse {
        trace(">>> ${request.method} ${request.url}")
        val conn = URL(request.url).openConnection() as HttpURLConnection
        conn.requestMethod = request.method
        request.headers.forEach { (k, v) -> conn.setRequestProperty(k, v) }
        extraHeaders.forEach { (k, v) -> conn.setRequestProperty(k, v) }
        accessToken?.let { conn.setRequestProperty("Authorization", "Bearer $it") }
        if (request.body != null) {
            conn.doOutput = true
            conn.outputStream.write(request.body!!.toByteArray())
        }
        val body = conn.inputStream.bufferedReader().readText()
        trace("<<< ${conn.responseCode}: $body")
        val headers = conn.headerFields.mapValues { it.value.firstOrNull() ?: "" }.filterKeys { it != null }.mapKeys { it.key!! }
        return PoppHttpResponse(conn.responseCode, body, headers)
    }
}

// ---- Screens ----

@Composable
private fun IdleScreen(
    username: String,
    onUsernameChange: (String) -> Unit,
    password: String,
    onPasswordChange: (String) -> Unit,
    useFakeErezept: Boolean,
    onFakeToggle: (Boolean) -> Unit,
    useRisePoppService: Boolean,
    onRiseToggle: (Boolean) -> Unit,
    canStart: Boolean,
    onStart: () -> Unit,
    onQrScan: () -> Unit,
) {
    var passwordVisible by remember { mutableStateOf(false) }
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Default.Place, null, Modifier.size(64.dp), tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.height(16.dp))
        Text("PoPP Check-in", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(8.dp))
        Text(
            "Proof of Patient Presence",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(24.dp))
        OutlinedTextField(
            value = username,
            onValueChange = onUsernameChange,
            label = { Text("Username") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(
            value = password,
            onValueChange = onPasswordChange,
            label = { Text("Password") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
            trailingIcon = {
                IconButton(onClick = { passwordVisible = !passwordVisible }) {
                    Icon(
                        painter = painterResource(
                            id = if (passwordVisible) android.R.drawable.ic_menu_view
                            else android.R.drawable.ic_secure,
                        ),
                        contentDescription = if (passwordVisible) "Hide password" else "Show password",
                    )
                }
            },
        )
        Spacer(Modifier.height(16.dp))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
            Text("Fake E-Rezept", modifier = Modifier.weight(1f))
            Switch(checked = useFakeErezept, onCheckedChange = onFakeToggle)
        }
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
            Text("RISE PoPP Service", modifier = Modifier.weight(1f))
            Switch(checked = useRisePoppService, onCheckedChange = onRiseToggle)
        }
        Spacer(Modifier.height(24.dp))
        Button(
            onClick = onStart,
            enabled = canStart,
            modifier = Modifier.fillMaxWidth().height(56.dp),
        ) { Text("Check-in starten") }
        Spacer(Modifier.height(12.dp))
        OutlinedButton(
            onClick = onQrScan,
            enabled = canStart,
            modifier = Modifier.fillMaxWidth().height(56.dp),
        ) {
            Icon(Icons.Default.Place, contentDescription = null, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
            Text("QR-Code scannen")
        }
    }
}

@OptIn(ExperimentalGetImage::class)
@Composable
private fun QrScannerScreen(onResult: (String) -> Unit, onCancel: () -> Unit) {
    val lifecycleOwner = LocalLifecycleOwner.current
    var scanned by remember { mutableStateOf(false) }
    var useFrontCamera by rememberSaveable { mutableStateOf(false) }

    Box(Modifier.fillMaxSize()) {
        key(useFrontCamera) {
            AndroidView(
                factory = { ctx ->
                    val previewView = PreviewView(ctx)
                    val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
                    cameraProviderFuture.addListener({
                        val cameraProvider = cameraProviderFuture.get()
                        val preview = Preview.Builder().build().also {
                            it.setSurfaceProvider(previewView.surfaceProvider)
                        }

                        val barcodeScanner = BarcodeScanning.getClient(
                            BarcodeScannerOptions.Builder()
                                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                                .build()
                        )

                        val analysis = ImageAnalysis.Builder()
                            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                            .build().also { imageAnalysis ->
                                imageAnalysis.setAnalyzer(java.util.concurrent.Executors.newSingleThreadExecutor()) { imageProxy ->
                                    val mediaImage = imageProxy.image
                                    if (mediaImage != null && !scanned) {
                                        val inputImage = InputImage.fromMediaImage(
                                            mediaImage, imageProxy.imageInfo.rotationDegrees
                                        )
                                        barcodeScanner.process(inputImage)
                                            .addOnSuccessListener { barcodes ->
                                                val qrValue = barcodes.firstOrNull()?.rawValue
                                                if (qrValue != null && !scanned) {
                                                    scanned = true
                                                    onResult(qrValue)
                                                }
                                            }
                                            .addOnCompleteListener { imageProxy.close() }
                                    } else {
                                        imageProxy.close()
                                    }
                                }
                            }

                        val selector = if (useFrontCamera) CameraSelector.DEFAULT_FRONT_CAMERA
                            else CameraSelector.DEFAULT_BACK_CAMERA

                        cameraProvider.unbindAll()
                        cameraProvider.bindToLifecycle(lifecycleOwner, selector, preview, analysis)
                    }, ContextCompat.getMainExecutor(ctx))
                    previewView
                },
                modifier = Modifier.fillMaxSize(),
            )
        }

        // Overlay
        Column(
            Modifier.fillMaxSize().padding(24.dp),
            verticalArrangement = Arrangement.SpaceBetween,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.Black.copy(alpha = 0.6f))
                    .padding(16.dp),
            ) {
                Text("LEI QR-Code scannen", style = MaterialTheme.typography.titleMedium, color = Color.White)
                Spacer(Modifier.height(8.dp))
                Row {
                    TextButton(
                        onClick = onCancel,
                        colors = ButtonDefaults.textButtonColors(contentColor = Color.White),
                    ) { Text("Abbrechen") }
                    Spacer(Modifier.width(16.dp))
                    Button(onClick = { useFrontCamera = !useFrontCamera }) {
                        Text(if (useFrontCamera) "Back Camera" else "Front Camera")
                    }
                }
            }
            Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
private fun LoadingScreen(message: String) {
    Column(Modifier.fillMaxSize(), Arrangement.Center, Alignment.CenterHorizontally) {
        CircularProgressIndicator()
        Spacer(Modifier.height(16.dp))
        Text(message, style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable
private fun CanScreen(knownCards: List<KnownCard>, errorMessage: String?, flow: PoppFlow?, activity: Activity? = LocalContext.current as? Activity) {
    var can by remember { mutableStateOf("") }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Spacer(Modifier.height(16.dp))
        Text("CAN eingeben", style = MaterialTheme.typography.headlineSmall)
        Text("6-stellige CAN Ihrer Gesundheitskarte", color = MaterialTheme.colorScheme.onSurfaceVariant)

        if (errorMessage != null) {
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
                shape = MaterialTheme.shapes.medium,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = errorMessage,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(16.dp),
                )
            }
        }
        CanInputField(can = can, onCanChange = { can = it }, activity = activity, persistKey = "lastCan")
        Button(
            onClick = { flow?.submitCan(can.trim()) },
            enabled = can.length == 6,
            modifier = Modifier.fillMaxWidth().height(56.dp),
            shape = RoundedCornerShape(16.dp),
        ) { Text("Weiter") }

        KnownCardsList(
            knownCards = knownCards,
            onCardClick = { card -> flow?.submitCan(card.can) },
        )

        OutlinedButton(
            onClick = { flow?.cancel() },
            modifier = Modifier.fillMaxWidth().height(56.dp),
            shape = RoundedCornerShape(16.dp),
        ) { Text(PoppStrings.CANCEL) }
    }
}

@Composable
private fun LeiSelectionScreen(hasFavorites: Boolean, flow: PoppFlow?) {
    Column(Modifier.fillMaxSize().padding(24.dp), Arrangement.Center, Alignment.CenterHorizontally) {
        Text(PoppStrings.LEI_SELECTION_TITLE, style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(24.dp))
        ElevatedCard(onClick = { flow?.submitLeiSelectionMethod(LeiSelectionMethod.QR_SCAN) }, Modifier.fillMaxWidth()) {
            Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Place, null, Modifier.size(32.dp)); Spacer(Modifier.width(16.dp))
                Text(PoppStrings.LEI_SCAN_QR, style = MaterialTheme.typography.titleMedium)
            }
        }
        Spacer(Modifier.height(12.dp))
        ElevatedCard(onClick = { flow?.submitLeiSelectionMethod(LeiSelectionMethod.VZD_SEARCH) }, Modifier.fillMaxWidth()) {
            Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Search, null, Modifier.size(32.dp)); Spacer(Modifier.width(16.dp))
                Text(PoppStrings.LEI_SEARCH_VZD, style = MaterialTheme.typography.titleMedium)
            }
        }
        if (hasFavorites) {
            Spacer(Modifier.height(12.dp))
            ElevatedCard(onClick = { flow?.submitLeiSelectionMethod(LeiSelectionMethod.FAVORITES) }, Modifier.fillMaxWidth()) {
                Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Star, null, Modifier.size(32.dp)); Spacer(Modifier.width(16.dp))
                    Text(PoppStrings.LEI_FAVORITES, style = MaterialTheme.typography.titleMedium)
                }
            }
        }
        Spacer(Modifier.height(24.dp))
        TextButton(onClick = { flow?.cancel() }) { Text(PoppStrings.CANCEL) }
    }
}

@Composable
private fun VzdSearchScreen(flow: PoppFlow?) {
    var query by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(48.dp))
        Text(PoppStrings.VZD_SEARCH_TITLE, style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(24.dp))
        OutlinedTextField(query, { query = it }, label = { Text(PoppStrings.VZD_SEARCH_HINT) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(12.dp)) {
            OutlinedButton({ flow?.submitVzdSearch(null) }, Modifier.weight(1f)) { Text(PoppStrings.CANCEL) }
            Button({ flow?.submitVzdSearch(query.takeIf { it.isNotBlank() }) }, Modifier.weight(1f), enabled = query.isNotBlank()) { Text(PoppStrings.VZD_SEARCH_BUTTON) }
        }
    }
}

@Composable
private fun FavoritesScreen(favorites: List<PoppFavorite>, flow: PoppFlow?) {
    Column(Modifier.fillMaxSize().padding(24.dp)) {
        Text(PoppStrings.FAVORITES_TITLE, style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(16.dp))
        if (favorites.isEmpty()) {
            Box(Modifier.weight(1f).fillMaxWidth(), Alignment.Center) { Text(PoppStrings.FAVORITES_EMPTY) }
        } else {
            LazyColumn(Modifier.weight(1f)) {
                itemsIndexed(favorites) { _, fav ->
                    Card(onClick = { flow?.submitFavoriteSelection(fav) }, Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                        Column(Modifier.padding(16.dp)) {
                            Text(fav.name, style = MaterialTheme.typography.titleMedium)
                            fav.address?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        }
                    }
                }
            }
        }
        TextButton(onClick = { flow?.submitFavoriteSelection(null) }, Modifier.align(Alignment.CenterHorizontally)) { Text(PoppStrings.CANCEL) }
    }
}

@Composable
private fun AuthMethodScreen(gidAvailable: Boolean, flow: PoppFlow?) {
    Column(Modifier.fillMaxSize().padding(24.dp), Arrangement.Center, Alignment.CenterHorizontally) {
        Text(PoppStrings.AUTH_METHOD_TITLE, style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(24.dp))
        ElevatedCard(onClick = { flow?.submitAuthMethod(AuthMethod.EGK) }, Modifier.fillMaxWidth()) {
            Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.CreditCard,
                    contentDescription = null,
                    modifier = Modifier.size(32.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text(PoppStrings.AUTH_EGK, style = MaterialTheme.typography.titleMedium)
                    Text(PoppStrings.AUTH_EGK_SUBTITLE, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Icon(Icons.Default.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Spacer(Modifier.height(12.dp))
        ElevatedCard(
            onClick = { /* GesundheitsID not yet implemented */ },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.Fingerprint,
                    contentDescription = null,
                    modifier = Modifier.size(32.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(PoppStrings.AUTH_GID, style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Coming soon",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier
                                .background(MaterialTheme.colorScheme.surfaceVariant, MaterialTheme.shapes.small)
                                .padding(horizontal = 6.dp, vertical = 2.dp),
                        )
                    }
                    Text(PoppStrings.AUTH_GID_SUBTITLE, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun CompletedScreen(result: PoppCheckInResult, onDone: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp), Arrangement.Center, Alignment.CenterHorizontally) {
        when (result) {
            is PoppCheckInResult.Success -> {
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = null,
                    modifier = Modifier.size(64.dp),
                    tint = Color(0xFF4CAF50),
                )
                Spacer(Modifier.height(16.dp))
                Text(PoppStrings.RESULT_SUCCESS_TITLE, style = MaterialTheme.typography.headlineSmall)
            }
            is PoppCheckInResult.Pending -> {
                CircularProgressIndicator(modifier = Modifier.size(64.dp))
                Spacer(Modifier.height(16.dp))
                Text(PoppStrings.RESULT_PENDING_TITLE, style = MaterialTheme.typography.headlineSmall)
                Spacer(Modifier.height(8.dp))
                Text(result.message, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            }
            else -> {
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = null,
                    modifier = Modifier.size(64.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.height(16.dp))
                Text("Check-in abgeschlossen", style = MaterialTheme.typography.headlineSmall)
            }
        }
        Spacer(Modifier.height(32.dp))
        Button(
            onClick = onDone,
            modifier = Modifier.fillMaxWidth().height(56.dp),
            shape = RoundedCornerShape(16.dp),
        ) { Text("Fertig") }
    }
}

@Composable
private fun CancelledScreen(message: String, onDone: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp), Arrangement.Center, Alignment.CenterHorizontally) {
        Icon(
            imageVector = Icons.Default.Cancel,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = Color(0xFFFF9800),
        )
        Spacer(Modifier.height(16.dp))
        Text("Check-in vom Benutzer abgebrochen", style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center)
        if (message.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        }
        Spacer(Modifier.height(32.dp))
        Button(
            onClick = onDone,
            modifier = Modifier.fillMaxWidth().height(56.dp),
            shape = RoundedCornerShape(16.dp),
        ) { Text("OK") }
    }
}

@Composable
private fun ErrorScreen(message: String, onDone: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp), Arrangement.Center, Alignment.CenterHorizontally) {
        Icon(
            imageVector = Icons.Default.Warning,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.error,
        )
        Spacer(Modifier.height(16.dp))
        Text(PoppStrings.RESULT_ERROR_TITLE, style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        Spacer(Modifier.height(32.dp))
        Button(
            onClick = onDone,
            modifier = Modifier.fillMaxWidth().height(56.dp),
            shape = RoundedCornerShape(16.dp),
        ) { Text("Schade") }
    }
}

@Composable
private fun FetchingTokensScreen() {
    Column(Modifier.fillMaxSize(), Arrangement.Center, Alignment.CenterHorizontally) {
        CircularProgressIndicator()
        Spacer(Modifier.height(16.dp))
        Text("PoPP-Token wird abgerufen...", style = MaterialTheme.typography.bodyLarge)
    }
}

// ---- Token + Prescription Display ----

@Composable
private fun TokensScreen(
    entries: List<TokenEntry>,
    hasPrescriptions: Boolean,
    onDone: () -> Unit,
    username: String,
    password: String,
    onTrace: (String) -> Unit,
) {
    val deleteController = rememberPrescriptionDeleteController(
        environment = CardlinkEnvironment.Default,
        username = username,
        password = password,
        onTrace = onTrace,
    )

    // Flatten all deletable items across every token for the "Delete all" button.
    val allDeletable = entries.flatMap { entry ->
        val loaded = entry.prescriptionState as? PrescriptionState.Loaded ?: return@flatMap emptyList()
        loaded.xmls.indices.mapNotNull { i ->
            loaded.metadata.getOrNull(i)?.let { meta -> "${entry.index}:$i" to meta }
        }
    }
    val remaining = allDeletable.count { (key, _) ->
        deleteController.stateFor(key) !is DeleteUiState.Deleted
    }

    LazyColumn(Modifier.fillMaxSize().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("✓", fontSize = 28.sp, color = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(8.dp))
                Text("PoPP Check-in erfolgreich", style = MaterialTheme.typography.headlineSmall)
            }
            Text("${entries.size} Token", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        if (allDeletable.isNotEmpty()) {
            item {
                DeleteAllBar(
                    remaining = remaining,
                    lastGoodEnv = deleteController.lastGoodEnv,
                    isDeletingAll = deleteController.isDeletingAll,
                    onDeleteAll = { deleteController.deleteAll(allDeletable) },
                )
            }
        }

        itemsIndexed(entries) { _, entry ->
            TokenSection(entry, deleteController)
        }

        item {
            Spacer(Modifier.height(8.dp))
            Button(
                onClick = onDone,
                modifier = Modifier.fillMaxWidth().height(56.dp),
            ) { Text(if (hasPrescriptions) "Great Scott!" else "Try again") }
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun TokenSection(
    entry: TokenEntry,
    deleteController: de.scoopsoftware.cardlink.demo.ui.components.PrescriptionDeleteController? = null,
) {
    var expanded by remember { mutableStateOf(true) }
    var selectedTab by remember { mutableIntStateOf(0) }

    Card(Modifier.fillMaxWidth()) {
        Column {
            // Header
            Row(
                Modifier.fillMaxWidth().clickable { expanded = !expanded }.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(if (expanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown, null)
                Spacer(Modifier.width(8.dp))
                Text("Token ${entry.index + 1}", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                PrescriptionBadge(entry, deleteController)
            }

            if (expanded) {
                TabRow(selectedTab) {
                    Tab(selectedTab == 0, { selectedTab = 0 }) { Text("Prescriptions", Modifier.padding(12.dp)) }
                    Tab(selectedTab == 1, { selectedTab = 1 }) { Text("Token", Modifier.padding(12.dp)) }
                }

                when (selectedTab) {
                    0 -> PrescriptionContent(entry, deleteController)
                    1 -> TokenContent(entry)
                }
            }
        }
    }
}

@Composable
private fun PrescriptionBadge(
    entry: TokenEntry,
    deleteController: de.scoopsoftware.cardlink.demo.ui.components.PrescriptionDeleteController? = null,
) {
    val state = entry.prescriptionState
    when (state) {
        is PrescriptionState.Loading -> CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
        is PrescriptionState.Loaded -> {
            val remaining = if (deleteController != null) {
                state.xmls.indices.count { i ->
                    deleteController.stateFor("${entry.index}:$i") !is DeleteUiState.Deleted
                }
            } else state.xmls.size
            Badge { Text("$remaining") }
        }
        is PrescriptionState.Error -> Text("⚠", fontSize = 14.sp)
        else -> {}
    }
}

@Composable
private fun PrescriptionContent(
    entry: TokenEntry,
    deleteController: de.scoopsoftware.cardlink.demo.ui.components.PrescriptionDeleteController?,
) {
    when (val state = entry.prescriptionState) {
        is PrescriptionState.Idle -> Text("Warte...", Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        is PrescriptionState.Loading -> Box(Modifier.fillMaxWidth().padding(16.dp), Alignment.Center) {
            CircularProgressIndicator(Modifier.size(24.dp))
        }
        is PrescriptionState.Loaded -> {
            if (state.xmls.isEmpty()) {
                Text("Keine Rezepte", Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                Column(Modifier.padding(8.dp), Arrangement.spacedBy(8.dp)) {
                    state.xmls.forEachIndexed { i, xml ->
                        val key = "${entry.index}:$i"
                        val metadata = state.metadata.getOrNull(i)
                        val deleteState = if (metadata != null && deleteController != null)
                            deleteController.stateFor(key) else null
                        androidx.compose.animation.AnimatedVisibility(
                            visible = deleteState !is DeleteUiState.Deleted,
                            exit = androidx.compose.animation.fadeOut(
                                animationSpec = androidx.compose.animation.core.tween(durationMillis = 500),
                            ) + androidx.compose.animation.shrinkVertically(
                                animationSpec = androidx.compose.animation.core.tween(durationMillis = 500),
                            ),
                        ) {
                            PrescriptionCardCompose(
                                index = i,
                                xml = xml,
                                deleteState = deleteState,
                                onDelete = if (metadata != null && deleteController != null) {
                                    { deleteController.delete(key, metadata) }
                                } else null,
                            )
                        }
                    }
                }
            }
        }
        is PrescriptionState.Error -> Column(Modifier.padding(16.dp)) {
            Text("⚠ Rezeptabruf fehlgeschlagen", style = MaterialTheme.typography.labelMedium)
            Text(state.message, fontSize = 10.sp, fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun PrescriptionCardCompose(
    index: Int,
    xml: String,
    deleteState: DeleteUiState? = null,
    onDelete: (() -> Unit)? = null,
) {
    val parsed = remember(xml) { FhirBundleParser.parse(xml) }
    var showXml by remember { mutableStateOf(false) }
    val struckThrough = deleteState is DeleteUiState.Deleted

    Card(
        Modifier.fillMaxWidth(),
        colors = if (struckThrough)
            CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
        else CardDefaults.cardColors(),
    ) {
        Column(Modifier.padding(16.dp), Arrangement.spacedBy(12.dp)) {
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
                Text(deleteState.message, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }

            if (parsed != null) {
                // Medication section
                Card(
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                ) {
                    Column(Modifier.fillMaxWidth().padding(10.dp), Arrangement.spacedBy(4.dp)) {
                        Text("Medication", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                        parsed.medication.name?.let {
                            Text(it, style = MaterialTheme.typography.bodyMedium, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            parsed.medication.pzn?.let { Text("PZN: $it", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            parsed.medication.form?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            parsed.medication.normgroesse?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        }
                        parsed.medication.ingredients.forEach { ingredient ->
                            Text(
                                "${ingredient.name ?: ""}${ingredient.strength?.let { " ($it)" } ?: ""}",
                                style = MaterialTheme.typography.labelSmall,
                            )
                        }
                        parsed.dosage?.let { Text("Dosage: $it", style = MaterialTheme.typography.labelSmall) }
                        parsed.quantity?.let { Text("Quantity: $it", style = MaterialTheme.typography.labelSmall) }
                    }
                }

                // Practitioner section
                parsed.practitioner?.let { doc ->
                    Card(
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    ) {
                        Column(Modifier.fillMaxWidth().padding(10.dp), Arrangement.spacedBy(4.dp)) {
                            Text("Prescribing Doctor", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                            Text(
                                "${doc.prefix?.let { "$it " } ?: ""}${doc.name ?: "Unknown"}",
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                doc.qualification?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                                doc.lanr?.let { Text("LANR: $it", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            }
                        }
                    }
                }

                parsed.authoredOn?.let {
                    Text("Issued: $it", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            OutlinedButton(onClick = { showXml = !showXml }) {
                Text(if (showXml) "Hide XML" else "Show XML", fontSize = 10.sp)
            }
            if (showXml) {
                SelectionContainer {
                    Text(xml, fontSize = 8.sp, fontFamily = FontFamily.Monospace)
                }
            }
        }
    }
}

@Composable
private fun TokenContent(entry: TokenEntry) {
    Column(Modifier.padding(12.dp)) {
        Text("Header", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        SelectionContainer {
            Text(entry.header, fontSize = 10.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.padding(vertical = 4.dp))
        }
        Text("Payload", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        SelectionContainer {
            Text(entry.payload, fontSize = 10.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.padding(vertical = 4.dp))
        }
    }
}

// ---- Confetti ----

@Composable
private fun ConfettiEffect() {
    val composition by com.airbnb.lottie.compose.rememberLottieComposition(
        com.airbnb.lottie.compose.LottieCompositionSpec.Asset("confetti.json")
    )
    com.airbnb.lottie.compose.LottieAnimation(
        composition = composition,
        iterations = 1,
        modifier = Modifier.fillMaxSize(),
    )
}

// ---- Native Dialogs ----

private fun showConsentDialog(activity: Activity, lei: PoppLeiInfo, flow: PoppFlow) {
    activity.runOnUiThread {
        MaterialAlertDialogBuilder(activity)
            .setTitle(PoppStrings.CONSENT_TITLE)
            .setMessage(PoppStrings.consentMessage(lei))
            .setPositiveButton(PoppStrings.CONSENT_CONFIRM) { _, _ -> flow.submitConsent(true) }
            .setNegativeButton(PoppStrings.CONSENT_CANCEL) { _, _ -> flow.submitConsent(false) }
            .setCancelable(false)
            .show()
    }
}
