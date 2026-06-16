# Cardlink SDK — API Reference

The **Cardlink SDK** is a Kotlin Multiplatform library for NFC-based German electronic
health‑card (eGK) authentication and eHealth workflows: **CardLink** eRezept retrieval,
**PoPP** (Proof of Patient Presence) check‑in, and **eRezept** upload/delete. This is the
consumer API reference. For a runnable end‑to‑end example, see the demo apps in this repo
(`ios/`, `android/`).

> The NFC primitives and the PoPP module are **bundled into this SDK** — on iOS they ship
> inside `ScoopCardlink`; on Android they resolve transitively. You normally depend on
> Cardlink only.
>
> **The SDK does all eGK card reading for you** — NFC discovery, PACE authentication,
> Secure Messaging, file reads. You never touch APDUs; you only plug in a ready-made
> platform NFC provider (`AndroidNfcTransceiverProvider(activity)`, or
> `IosNfcTransceiverProvider()` with a small standard CoreNFC bridge). See
> [CardLink Flow](#cardlink-flow).

## Platforms

| Platform | Import / coordinate | Requirements |
| --- | --- | --- |
| **Android** | `de.scoopsoftware.cardlink:shared-android:2.2.0` (public Maven, no token — `https://scoop-software.github.io/cardlink-packages/maven`) | `minSdk 26`, Java 17 |
| **iOS** | `import ScoopCardlink` (SPM: [`cardlink-packages`](https://github.com/scoop-software/cardlink-packages), `from: "2.2.0"`) | iOS 14+, **Xcode 26** with `SWIFT_ENABLE_EXPLICIT_MODULES = NO` |

> ⚠️ **The `Default` environment targets dev/demo backends**, and the eRezept
> upload/delete endpoints are demo hosts. Use `CardlinkEnvironment.Custom(...)` for your
> own deployment; treat eRezept upload/delete as a testing/demo feature.

## The consumption pattern

Most of the SDK is built around **suspendable flow objects that expose a Kotlin
`StateFlow` of typed states**. The shape is always the same:

1. construct a flow with a config,
2. `launch { flow.start() }` — `start()` is a `suspend` function that drives the machine,
3. observe `flow.state` and render UI per state,
4. feed user input back via non‑suspending `submitX(...)` methods.

```kotlin
scope.launch { flow.state.collect { state -> render(state) } }   // observe
scope.launch { flow.start() }                                    // drive
```

On **iOS**, SKIE exports `state` as a Swift `AsyncSequence` and `start()` as `async throws`:

```swift
Task { for await s in flow.state { render(s) } }
Task { try await flow.start() }
```

## Which API for which task

| You want to… | Use |
| --- | --- |
| Retrieve eRezepte via CardLink (OAuth → SMS → NFC → download) | [`CardlinkFlow`](#cardlink-flow) |
| Do a PoPP check‑in | [`PoppFlow`](#popp-check-in-proof-of-patient-presence) |
| Upload / delete an eRezept (demo/test) | [`ErezeptUploadFlow` / `ErezeptDeleteClient`](#erezept-upload--delete) |
| Read an eGK directly (advanced) | [`EgkReader` / `NfcReader`](#card-reading--nfc-primitives) |
| Capture / chart performance metrics | [Metrics & reporting](#performance-metrics-scan-records--reporting) |

## Contents

- [CardLink Flow](#cardlink-flow)
- [PoPP Check‑In (Proof of Patient Presence)](#popp-check-in-proof-of-patient-presence)
- [eRezept Upload & Delete](#erezept-upload--delete)
- [Card Reading & NFC Primitives](#card-reading--nfc-primitives)
- [Performance Metrics, Scan Records & Reporting](#performance-metrics-scan-records--reporting)


---

## CardLink Flow

`CardlinkFlow` is the main state machine that orchestrates the full CardLink eRezept-retrieval workflow in one object: **OAuth login → WebSocket connect → SMS verification → NFC card read → register → prescription download**. You drive it by observing a `StateFlow` of typed states and feeding it user input (phone number, SMS code, CAN) through non-blocking submit methods. Everything else — token refresh, WebSocket messaging, APDU relay, session persistence — happens internally.

> **iOS:** `import ScoopCardlink`. SKIE exports the `state` `StateFlow` as a Swift `AsyncSequence` (`for await s in flow.state`), and `start()` as an `async throws` function. The Kotlin types and method names below are identical in Swift.

### Constructing the flow

```kotlin
import de.scoopsoftware.cardlink.flow.CardlinkFlow
import de.scoopsoftware.cardlink.flow.CardlinkFlowConfig
import de.scoopsoftware.cardlink.flow.AndroidNfcTransceiverProvider   // SDK-provided (Android)
import de.scoopsoftware.cardlink.websocket.CardlinkEnvironment

val flow = CardlinkFlow(
    config = CardlinkFlowConfig(
        environment = CardlinkEnvironment.Default,   // dev/demo; use Custom(...) for your backend
        username = "my-client",                       // OAuth ROPC credentials
        password = "s3cr3t",
        credentialStorage = myCredentialStorage,      // optional — enables session persistence
    ),
    nfcProvider = AndroidNfcTransceiverProvider(activity)   // SDK-provided — just pass your Activity
)
```

> **You do not implement NFC or card reading.** The SDK reads the eGK end-to-end — NFC
> discovery, PACE authentication, Secure Messaging, eGK file reads; you never touch APDUs.
> You only hand the flow a ready-made `NfcTransceiverProvider`:
> - **Android:** `AndroidNfcTransceiverProvider(activity)` — the SDK owns NFC reader mode. That's the entire NFC integration.
> - **iOS:** `IosNfcTransceiverProvider()` — Apple requires the **app** to own the
>   `NFCTagReaderSession`, so you attach a small, standard CoreNFC delegate that forwards the
>   connected ISO 7816 tag via `provider.onTagConnected(tag:)` / `provider.onSessionInvalidated(message:)`.
>   Copy the demo's `NfcSessionManager` (`ios/CardlinkSample/CardlinkSample/ContentView.swift`) verbatim — ~60 lines, no card logic.

`CardlinkFlow(config, nfcProvider)` takes two arguments:

- **`config: CardlinkFlowConfig`** — environment + OAuth credentials and tuning knobs (see below).
- **`nfcProvider: NfcTransceiverProvider`** — pass the SDK's `AndroidNfcTransceiverProvider(activity)` or `IosNfcTransceiverProvider()`. (It *is* a `fun interface` — `suspend fun awaitTransceiver(): NfcTransceiver` — so you can supply your own, but you normally don't.) The SDK invokes it whenever it needs the card; it may be called more than once per flow (wrong CAN, card removed).

### CardlinkFlowConfig

```kotlin
data class CardlinkFlowConfig(
    val environment: CardlinkEnvironment,
    val username: String,                       // OAuth ROPC username (required)
    val password: String,                       // OAuth ROPC password (required)
    val smsSenderId: String = "Cardlink",       // 1–11 alphanumeric chars / spaces (validated)
    val smsTemplate: String = "Your Cardlink code: {0}",  // {0} = code placeholder
    val credentialStorage: CredentialStorage? = null,     // persists tokens + CL session
    val nfcTimeoutMs: Int = 2500,
    val enableApduTracing: Boolean = false,     // emit ApduExchange trace events
    val sessionValidityMs: Long = 15 * 60 * 1000,         // CL session window (15 min)
    val tokenRefreshBufferMs: Long = 60_000,    // refresh access token this early
    val cacheProvider: CacheProvider? = null,   // cache card files across reads
    val poppMode: Boolean = false,
    val uploadTargetEnv: String = "dev",
)
```

The constructor validates `smsSenderId` (1–11 alphanumeric characters or spaces) and throws `IllegalArgumentException` otherwise.

**`CardlinkEnvironment`** is a sealed class:
- `CardlinkEnvironment.Default` — the hosted dev server (WebSocket + OAuth + REST URLs preconfigured).
- `CardlinkEnvironment.Custom(websocketUrl, oauthConfig, restBaseUrl = "")` — point at your own deployment.

### Starting the flow

```kotlin
scope.launch {
    flow.start()   // suspends and drives the whole state machine
}
```

`suspend fun start()` runs the complete flow linearly through three internal phases (`connectPhase → smsPhase → nfcAndRegisterPhase`), suspending wherever user input is needed. It returns when the flow reaches `Completed`, hits a terminal `Error` (recovery `NONE`), or is cancelled. You normally do **not** await its result — drive your UI from `state` instead. The channels are re-initialized on each call, so `start()` can be re-invoked after `cancel()`.

### Observing state

```kotlin
val state: StateFlow<CardlinkFlowState>       // observe for UI navigation
val traceEvents: SharedFlow<CardlinkTraceEvent>  // observe for diagnostics/analytics
```

`state` always holds the current `CardlinkFlowState` (starts at `Idle`). `traceEvents` is a separate diagnostic stream (PACE steps, file reads, WebSocket messages, timing summaries, errors) — useful for logging/analytics, not required for the happy path.

### CardlinkFlowState cases

`CardlinkFlowState` is a sealed class. The flow emits these in roughly this order; input states pause until you call the matching submit method.

| State | Data | Meaning / what to show |
|-------|------|------------------------|
| `Idle` | — | Not started (initial state, and after `cancel()`). |
| `Connecting` | — | OAuth login + WebSocket connecting. No input. |
| `NeedsPhoneNumber` | — | Needs the user's phone number. **Call `submitPhoneNumber`.** Skipped when a valid session is restored from storage. |
| `SmsRequested` | `phoneNumber: String` | SMS being dispatched. No input. |
| `NeedsSmsCode` | `phoneNumber: String`, `debugSmsCode: String?` | Needs the 6-digit code. In dev/test the server echoes the code back in `debugSmsCode` (null in production) — pre-fill it. **Call `submitSmsCode`.** |
| `NeedsCan` | `previousCan: String?` | Needs the 6-digit CAN from the card. If `previousCan != null`, the last attempt was wrong — show an error. **Call `submitCan`.** |
| `WaitingForCard` | — | NFC reader active; prompt the user to hold the card to the device. |
| `ReadingCard` | `progress: Float` (0–1), `stepLabel: String`, `patientData: InsuredPersonData?` | Card detected; PACE auth + file reads. Updates continuously. `patientData` becomes non-null partway through (insurance data parsed early). The card must stay on the device. |
| `Registering` | — | Card read; uploading `registerEgk` to the server. |
| `WaitingForPrescriptions` | — | Registered; awaiting the server's prescription result (may involve APDU relay). Times out after 10s → recoverable `Error`. |
| `Completed` | `iccsn: String`, `prescriptions: List<String>`, `patientData: InsuredPersonData?`, `cardContactToResultMs: Long`, `tokensXml: String?` | Success. `prescriptions` are FHIR R4 XML bundles. `tokensXml` is a FHIR Bundle of Task resources (taskId + accessCode, parallel order to `prescriptions`), or null if the server didn't send it. Terminal. |
| `Error` | `error: CardlinkFlowError` | An error occurred — inspect for recoverability (see below). |

Each state also exposes a computed `nfcSessionHint: NfcSessionHint` (with `action: NfcSessionAction` of `NONE` / `UPDATE_MESSAGE` / `INVALIDATE` / `INVALIDATE_WITH_ERROR` plus a `message`). Platform plugins use it to drive the native NFC dialog without duplicating logic. States also provide `toMap()` for serialization across Flutter/RN platform channels.

### Advancing the flow

All input methods are non-suspend and safe to call from any thread (they `trySend` onto conflated channels):

```kotlin
fun submitPhoneNumber(phone: String)   // answer NeedsPhoneNumber (full number incl. country code)
fun submitSmsCode(code: String)        // answer NeedsSmsCode (6-digit code)
fun submitCan(can: String)             // answer NeedsCan (6-digit CAN)
fun retry()                            // resume after a recoverable Error (mainly RETRY_CARD)
fun cancel()                           // abort the flow; cancels deferreds, closes channels, returns to Idle
```

### How errors surface

Errors arrive as `CardlinkFlowState.Error(error)` carrying a `CardlinkFlowError`:

```kotlin
data class CardlinkFlowError(
    val message: String,
    val phase: FlowPhase,                 // OAUTH, WEBSOCKET, SMS, NFC, PACE, FILE_READ, REGISTER, PRESCRIPTION, UPLOAD
    val recoveryAction: RecoveryAction,   // NONE, RETRY_CAN, RETRY_SMS, RETRY_CARD
    val cause: Throwable? = null,
) {
    val isTerminal: Boolean get() = recoveryAction == RecoveryAction.NONE
}
```

Recovery behavior:

- **`RETRY_CAN`** — wrong/invalid CAN. The flow loops back to `NeedsCan(previousCan = <last>)` automatically; no `retry()` call needed.
- **`RETRY_SMS`** — CL session expired. The flow loops back to `NeedsPhoneNumber` to re-do SMS automatically.
- **`RETRY_CARD`** — card removed or prescription timeout. The flow waits for `retry()`, then loops back to read the card again (reusing the known-good CAN where possible). **Show a Retry button that calls `retry()`.**
- **`NONE`** (`isTerminal == true`) — auth failure, NFC unavailable, etc. The flow cannot continue; call `cancel()` and offer "start over".

Note: wrong-CAN and session-expired transitions happen automatically (they loop internally rather than surfacing a separate `Error` for the app to act on); the one error you must respond to with `retry()` is `RETRY_CARD`.

### Session persistence

When `credentialStorage` is supplied, the flow persists OAuth tokens and the verified CL session (id + expiry + user) across restarts. On `start()`, if a stored CL session is still within its validity window (default 15 min) and belongs to the same OAuth user, the flow skips SMS entirely — going straight from `Connecting` to `NeedsCan` — and emits a `SessionRestored` trace event with the remaining time. The underlying WebSocket lifecycle is managed by `CardlinkSession` internally (its `SessionState` enum — `DISCONNECTED`, `AWAITING_SMS`, `CONFIRMING_SMS`, `READY`, `EXPIRED`, `ERROR` — is observable via trace logs but consumers normally only watch `CardlinkFlowState`).

### Full usage snippet

```kotlin
val flow = CardlinkFlow(config, nfcProvider)

// Observe state for UI navigation
scope.launch {
    flow.state.collect { state ->
        when (state) {
            is CardlinkFlowState.NeedsPhoneNumber ->
                showPhoneInput { phone -> flow.submitPhoneNumber(phone) }

            is CardlinkFlowState.NeedsSmsCode ->
                showSmsInput(state.phoneNumber, prefill = state.debugSmsCode) { code ->
                    flow.submitSmsCode(code)
                }

            is CardlinkFlowState.NeedsCan ->
                showCanInput(wrong = state.previousCan != null) { can -> flow.submitCan(can) }

            is CardlinkFlowState.WaitingForCard -> showNfcPrompt()

            is CardlinkFlowState.ReadingCard ->
                showProgress(state.progress, state.stepLabel, state.patientData)

            is CardlinkFlowState.Completed ->
                showResult(state.prescriptions, state.patientData)

            is CardlinkFlowState.Error -> {
                showError(state.error.message)
                if (state.error.recoveryAction == RecoveryAction.RETRY_CARD) {
                    // user taps retry -> flow.retry()
                }
                // RETRY_CAN / RETRY_SMS loop back automatically; NONE is terminal -> flow.cancel()
            }

            else -> showLoading()  // Idle, Connecting, SmsRequested, Registering, WaitingForPrescriptions
        }
    }
}

// Kick off the flow
scope.launch { flow.start() }
```

---

## PoPP Check-In (Proof of Patient Presence)

The PoPP check-in flow lets a patient prove their physical presence at a Leistungserbringerinstitution (LEI, e.g. a pharmacy or practice) per gematik's PoPP module spec. The SDK entry point is **`PoppFlow`** (package `de.scoopsoftware.cardlink.popp`). It wraps the lower-level `PoppModule` and exposes a single observable `StateFlow<PoppFlowState>` plus a set of `submit*` callbacks — you observe the state to drive your UI/navigation, and call the matching submit method when the user responds.

On iOS (`import ScoopCardlink`) the same `PoppFlow` class and types are available with Swift-idiomatic names.

### Construction and start

`PoppFlow` is constructed with a `PoppFlowConfig`, then started via `startCheckIn(...)`:

```kotlin
val flow = PoppFlow(
    PoppFlowConfig(
        zetaClient = myZetaClient,        // PoppZetaClient — HTTP transport to PoPP-Service / VZD
        storage = myStorage,              // PoppStorage — favorites + history persistence
        moduleConfig = PoppConfig(
            poppServiceBaseUrl = "https://popp.ru.example",
            vzdBaseUrl = "https://vzd.ru.example",
            clientId = "my-client-id",
        ),
        nfcProvider = AndroidNfcTransceiverProvider(activity),  // SDK-provided; optional — enables eGK auth (null = GesundheitsID only)
        knownCards = previouslyReadCards, // optional: KnownCards with cached CAN for quick pick
        cacheProvider = myCache,          // optional: caches immutable eGK files by ICCSN
        appUserAgent = "de.scoopsoftware.app/1.0",
        uiContext = platformUiContext,    // optional: native consent sheet host
        onNfcMessage = { msg -> /* update NFC dialog text */ },
        onNfcDone = { /* NFC session closed */ },
        onTrace = { line -> /* debug log */ },
    )
)

flow.startCheckIn(
    telematikId = null,   // if known (e.g. from a Cardlink session), skips LEI selection
    workplaceId = null,
    preferEgk = false,    // true => default the auth choice to eGK
)
```

`startCheckIn` runs asynchronously and emits states on `flow.state`. Call `flow.cancel()` to abort (closes any NFC session and returns to `Idle`).

**`PoppFlowConfig`** fields: `zetaClient: PoppZetaClient`, `storage: PoppStorage`, `moduleConfig: PoppConfig` are required; `nfcProvider: NfcTransceiverProvider? = null`, `knownCards: List<KnownCard> = emptyList()`, `cacheProvider: CacheProvider? = null`, `onNfcDone`, `onNfcMessage`, `onTrace` callbacks, `appUserAgent: String? = null`, `uiContext: PoppUiContext? = null`.

### Driving the flow: observe state, then submit

Observe `flow.state` and react to each `PoppFlowState`. Most interactive states have a matching submit method. Passing `null`/`false` to a submit method generally cancels that step.

| `PoppFlowState` case | Meaning | Respond with |
|---|---|---|
| `Idle` | Not started | — |
| `Initializing` | ZETA/OAuth client init in progress | — |
| `NeedsLeiSelectionMethod(hasFavorites: Boolean)` | Choose how to find the LEI | `submitLeiSelectionMethod(LeiSelectionMethod)` |
| `ScanningQr` | QR scanner active | `submitQrScanResult(payload: String?)` |
| `NeedsVzdSearch` | Enter a VZD search query | `submitVzdSearch(query: String?)` |
| `NeedsFavoriteSelection(favorites: List<PoppFavorite>)` | Pick a saved LEI | `submitFavoriteSelection(PoppFavorite?)` |
| `NeedsConsent(lei: PoppLeiInfo)` | Show LEI info, ask consent (OS-mandatory) | `submitConsent(granted: Boolean)` |
| `NeedsAuthMethod(gidAvailable: Boolean)` | Choose eGK vs GesundheitsID | `submitAuthMethod(AuthMethod)` |
| `NeedsCan(knownCards: List<KnownCard>, errorMessage: String?)` | Enter CAN or pick a known card | `submitCan(can: String)` or `submitKnownCard(KnownCard)` |
| `WaitingForCard` | Hold the eGK to the device (NFC active) | — (resolved by `nfcProvider`) |
| `AuthenticatingEgk` | PACE + APDU relay with eGK | — |
| `AuthenticatingGid` | GesundheitsID authentication | — |
| `Completed(result: PoppCheckInResult)` | Terminal: success/pending | — |
| `Cancelled(message: String)` | Terminal: user cancelled / consent denied | — |
| `Error(message: String)` | Terminal: lookup/service/NFC failure | — |

Notes:
- If `telematikId` is passed to `startCheckIn`, the LEI-selection states (`NeedsLeiSelectionMethod` / `ScanningQr` / `NeedsVzdSearch` / `NeedsFavoriteSelection`) are skipped and the flow goes straight to `NeedsConsent`.
- `NeedsCan` can recur: a wrong CAN or PACE/NFC failure re-emits `NeedsCan` with a populated `errorMessage` (in German) — re-submit a CAN to retry.
- If `nfcProvider` is null, the flow never offers eGK and authenticates via GesundheitsID only (no `NeedsAuthMethod`/`NeedsCan`).
- `state.isOsMandatory` is `true` for `NeedsConsent`, `ScanningQr`, `Completed`, `Cancelled`, `Error` — per gematik AFOs these must be presented via native OS UI, not app-replaceable screens.

### Enums you choose from

```kotlin
enum class LeiSelectionMethod { QR_SCAN, VZD_SEARCH, FAVORITES }  // answer NeedsLeiSelectionMethod
enum class AuthMethod        { EGK, GESUNDHEITS_ID }              // answer NeedsAuthMethod
```

### Result type

`Completed`, and the terminal states, carry a **`PoppCheckInResult`** (package `de.scoopsoftware.popp.module`):

```kotlin
sealed class PoppCheckInResult {
    data class Success(val poppDatasetId: String)
    data class Pending(val poppDatasetId: String, val message: String)   // e.g. LEI offline; poll later
    data class Cancelled(val message: String)                            // surfaced as state Cancelled
    data class Error(val code: PoppErrorCode, val message: String)       // surfaced as state Error
}
```

`PoppFlow` maps results to states for you: `Success`/`Pending` → `Completed`, `Cancelled` (and `Error` with `code == CONSENT_DENIED`) → `Cancelled`, other `Error` → `Error`. A `Pending` result can be re-checked later via the module's status poll (keyed by `poppDatasetId`).

**`PoppErrorCode`**: `INVALID_QR_CODE`, `INVALID_WORKPLACE_ID`, `LEI_NOT_FOUND`, `CONSENT_DENIED`, `EGK_AUTH_FAILED`, `GID_AUTH_FAILED`, `NETWORK_ERROR`, `SERVICE_ERROR`, `GID_NOT_AVAILABLE`.

### Supporting data types

```kotlin
data class PoppLeiInfo(val type: String, val name: String, val alias: String?, val address: String?, val telematikId: String)
data class PoppFavorite(val telematikId: String, val name: String, val address: String?)
data class PoppHistoryEntry(val telematikId: String, val leiName: String, val leiAddress: String?, val timestamp: Long, val success: Boolean)
data class PoppConfig(val poppServiceBaseUrl: String, val vzdBaseUrl: String, val clientId: String)
```

`PoppStorage` (host-implemented) persists favorites and history: `getFavorites()`, `addFavorite(...)`, `removeFavorite(telematikId)`, `getHistory()`, `addHistoryEntry(...)`. `KnownCard` (from the NFC SDK) carries `iccsn`, `can`, and optional cardholder/insurance details for quick CAN-free selection.

### Minimal end-to-end usage

```kotlin
val flow = PoppFlow(config)

scope.launch {
    flow.state.collect { state ->
        when (state) {
            is PoppFlowState.NeedsLeiSelectionMethod ->
                flow.submitLeiSelectionMethod(LeiSelectionMethod.QR_SCAN)
            is PoppFlowState.ScanningQr ->
                flow.submitQrScanResult(scannedPayload)      // or null to cancel
            is PoppFlowState.NeedsConsent ->
                flow.submitConsent(granted = userTappedConfirm)
            is PoppFlowState.NeedsAuthMethod ->
                flow.submitAuthMethod(AuthMethod.EGK)
            is PoppFlowState.NeedsCan ->
                flow.submitCan("123456")                     // 6-digit CAN; errorMessage set on retry
            is PoppFlowState.Completed -> when (val r = state.result) {
                is PoppCheckInResult.Success -> show("Checked in: ${r.poppDatasetId}")
                is PoppCheckInResult.Pending -> show("Pending: ${r.message}")
                else -> {}
            }
            is PoppFlowState.Cancelled -> show("Cancelled: ${state.message}")
            is PoppFlowState.Error     -> show("Error: ${state.message}")
            else -> { /* Initializing, WaitingForCard, AuthenticatingEgk/Gid — show progress UI */ }
        }
    }
}

flow.startCheckIn()   // telematikId/workplaceId/preferEgk optional
```

---

## eRezept Upload & Delete

The SDK can upload sample e-prescription FHIR Bundles to the gematik E-Rezept-Fachdienst (personalized with the patient's eGK data) and delete prescriptions afterwards. Two independent entry points cover this: `ErezeptUploadFlow` (a state-machine driven by `StateFlow`, like `CardlinkFlow`) and `ErezeptDeleteClient` (a simple suspend-call client). Supporting FHIR parsers (`PrescriptionMetadataParser`, `FhirBundleParser`) extract the `taskId`/`accessCode` that delete requires.

> iOS: `import ScoopCardlink`; all types below are exposed under the same names via SKIE. Android: `de.scoopsoftware.cardlink:shared-android`.

### `ErezeptUploadFlow`

State machine for **Select Bundle → Select Card → NFC Read → OAuth + Upload**. Unlike `CardlinkFlow`, the initial state is already `NeedsBundle` — available sample medications are shown immediately, no start trigger needed for the first screen.

```kotlin
class ErezeptUploadFlow(
    config: CardlinkFlowConfig,
    nfcProvider: NfcTransceiverProvider
)
```

Public surface:

| Member | Description |
|--------|-------------|
| `val state: StateFlow<ErezeptUploadState>` | Observe to drive UI navigation. |
| `val traceEvents: SharedFlow<CardlinkTraceEvent>` | Diagnostics / analytics. |
| `suspend fun start()` | Runs the full flow; returns when `Completed`, `Error`, or cancelled. Re-runnable. |
| `fun submitBundle(bundleId: String)` | Choose a bundle (answers `NeedsBundle`). May also be called during `NeedsCard` to go back and re-select. |
| `fun submitCardInfo(can: String, iccsn: String? = null)` | Proceed with an NFC read using this CAN (answers `NeedsCard`). `iccsn` enables wrong-card verification. |
| `fun submitKnownCard(card: KnownCard)` | Use cached person data for a previously read card — **skips the NFC read entirely**. |
| `fun cancel()` | Abort; closes channels, OAuth helper, HTTP client. |
| `val failedBundles: List<String>` / `fun exportFailedBundles(): String` | Bundle IDs that failed to upload this session (newline-joined for export). |

`config` supplies OAuth ROPC `username`/`password`, the `environment`, an optional `cacheProvider` (enables the known-card picker and file caching), and `uploadTargetEnv` (`"dev"` or `"ru"`, the gematik target). `nfcProvider` is the SDK-provided `AndroidNfcTransceiverProvider(activity)` / `IosNfcTransceiverProvider()` (same as [CardLink Flow](#cardlink-flow) — you don't implement NFC; the SDK reads the card). During upload the flow personalizes the bundle XML with the card's `InsuredPersonData`, and if the first KBV profile version fails it automatically retries with an alternate version of the same medication when one exists.

#### `ErezeptUploadState`

Sealed class; switch on it to render the matching screen:

- `NeedsBundle(bundles: Map<ErezeptType, List<ErezeptBundleInfo>>)` — show medication picker grouped by type; answer with `submitBundle`.
- `NeedsCard(selectedBundle: ErezeptBundleInfo, knownCards: List<KnownCard>)` — pick a known card (`submitKnownCard`) or enter a CAN (`submitCardInfo`); or re-`submitBundle` to go back.
- `WaitingForCard` — NFC reader active; prompt user to hold card to device.
- `ReadingCard(progress: Float, stepLabel: String)` — PACE auth + file read in progress (`progress` 0..1).
- `Uploading` — card read done; personalizing + posting the bundle.
- `Completed(statusCode: Int, body: String, bundle: ErezeptBundleInfo?)` — success.
- `Error(message: String, phase: FlowPhase, bundle: ErezeptBundleInfo?, failedBundleId: String?)` — failure; `phase` is a `FlowPhase` (e.g. `NFC`, `PACE`, `OAUTH`, `UPLOAD`), `failedBundleId` set only for upload failures.

Helpers on each state: `toMap()` (platform-channel-friendly map) and `nfcSessionHint` (drives the native NFC dialog).

```kotlin
val config = CardlinkFlowConfig(
    environment = CardlinkEnvironment.Default,
    username = "user", password = "pass",
    uploadTargetEnv = "dev",
)
val flow = ErezeptUploadFlow(config, nfcProvider)

scope.launch {
    flow.state.collect { state ->
        when (state) {
            is ErezeptUploadState.NeedsBundle ->
                flow.submitBundle(state.bundles[ErezeptType.PZN]!!.first().id)
            is ErezeptUploadState.NeedsCard ->
                flow.submitCardInfo(can = "123456")   // or flow.submitKnownCard(card)
            is ErezeptUploadState.Completed ->
                println("Uploaded: HTTP ${state.statusCode}")
            is ErezeptUploadState.Error ->
                println("Failed in ${state.phase}: ${state.message}")
            else -> { /* WaitingForCard / ReadingCard / Uploading -> progress UI */ }
        }
    }
}
scope.launch { flow.start() }
```

### Sample bundles: `ErezeptBundles`, `ErezeptBundleInfo`, `ErezeptType`

`ErezeptBundles` is an object exposing the embedded sample FHIR Bundles the upload flow draws from:

- `fun all(): List<ErezeptBundleInfo>`
- `fun byType(): Map<ErezeptType, List<ErezeptBundleInfo>>`
- `fun getXml(id: String): String` — decompressed FHIR Bundle XML (throws `IllegalArgumentException` for unknown id).
- `fun personalize(xml: String, data: InsuredPersonData): String` — injects KVNR, name, birth date, insurer into the Patient/Coverage blocks.

`ErezeptBundleInfo(id, medicationName, type: ErezeptType, source, version)` describes one bundle (`version` is the KBV profile, e.g. `"1.3"`/`"1.4"`). `ErezeptType` is `PZN`, `WIRKSTOFF`, `FREITEXT`, `REZEPTUR`.

### `ErezeptDeleteClient`

Deletes a prescription from the E-Rezept-Fachdienst. The app does not know which gematik environment (`"risedev"` or `"riseru"`) a prescription lives in, so `delete` tries one and falls through to the other **only on HTTP 404** — any other failure (auth, network, non-404 HTTP) is reported immediately rather than masked as "wrong env".

```kotlin
class ErezeptDeleteClient(
    environment: CardlinkEnvironment,
    username: String,
    password: String,
)

suspend fun delete(
    taskId: String,
    accessCode: String,
    preferredEnv: String = DEFAULT_ENV,   // "risedev"; anything not "risedev"/"riseru" is normalized
): DeleteResult

fun close()   // releases OAuth helper + HTTP client
```

Auth uses the same OAuth ROPC credentials as the upload flow. For batch deletes, pass the env from a prior `Success.envUsed` as `preferredEnv` so subsequent calls skip the wrong environment.

#### `DeleteResult` (sealed)

- `Success(envUsed: String)` — deleted; `envUsed` is `"risedev"`/`"riseru"`.
- `NotFoundInAnyEnv(triedEnvs: List<String>)` — 404 in every environment tried.
- `HttpError(envUsed: String, statusCode: Int, body: String)` — non-404 HTTP error.
- `NetworkError(envUsed: String, message: String)` — DNS/TLS/timeout etc.
- `AuthFailed(message: String)` — OAuth login/refresh failed; no delete request was made.

### Getting `taskId`/`accessCode`: `PrescriptionMetadataParser`

Delete needs a `taskId` (FHIR `Task.id` / PrescriptionID) and `accessCode`. `PrescriptionMetadataParser` extracts these from FHIR XML containing one or more `Task` resources (single Task, a Bundle wrapping one, or a multi-Task relay response):

- `fun parseFirst(xml: String): PrescriptionMetadata?`
- `fun parseAll(xml: String): List<PrescriptionMetadata>` — in document order.

`PrescriptionMetadata(taskId: String, accessCode: String)`. (To render prescription details for the UI, `FhirBundleParser.parse(xml): ParsedPrescription?` separately extracts medication/practitioner/dosage/quantity/authoredOn — not required for delete.)

```kotlin
val meta = PrescriptionMetadataParser.parseFirst(taskXml) ?: return
val client = ErezeptDeleteClient(CardlinkEnvironment.Default, "user", "pass")
try {
    when (val r = client.delete(meta.taskId, meta.accessCode)) {
        is ErezeptDeleteClient.DeleteResult.Success         -> println("Deleted in ${r.envUsed}")
        is ErezeptDeleteClient.DeleteResult.NotFoundInAnyEnv -> println("Already gone (${r.triedEnvs})")
        is ErezeptDeleteClient.DeleteResult.HttpError        -> println("HTTP ${r.statusCode}: ${r.body}")
        is ErezeptDeleteClient.DeleteResult.NetworkError     -> println("Network: ${r.message}")
        is ErezeptDeleteClient.DeleteResult.AuthFailed       -> println("Auth: ${r.message}")
    }
} finally { client.close() }
```

---

## Card Reading & NFC Primitives

> **Most apps should use `CardlinkFlow` / `PoppFlow` instead.** Those drive the eGK read for you (CAN entry, NFC sheet, PACE, file reads, server handoff). The primitives below are for direct/advanced use: a standalone card read, a custom NFC UI, or low-level APDU exchange on the PACE-secured channel.

These types live in the bundled NFC SDK (package `de.scoopsoftware.nfc`, shipped inside both the Android artifact and the iOS `ScoopCardlink` framework). On iOS, `import ScoopCardlink` and the Kotlin types are exposed with the same names.

### One-shot read: `EgkReader.readCard`

`EgkReader` is a singleton that reads the essential files off a German electronic health card (eGK) over an already-connected NFC tag. It runs PACE authentication (using the 6-digit CAN), opens a Secure Messaging channel, and pulls the certificates plus insured-person data.

```kotlin
suspend fun EgkReader.readCard(
    can: String,                                  // 6-digit Card Access Number (printed on the card)
    transceiver: NfcTransceiver,                  // platform NFC connection (see below)
    nfcMessageListener: NfcMessageListener? = null,
    fileCacheProvider: FileCacheProvider? = null, // skip/cache files
    recordMetrics: Boolean = true,                // false for max performance
    vsdDataListener: VsdDataListener? = null,     // early PD/VD callback
    enableApduTracing: Boolean = false,           // emits NfcMessage.ApduExchange (debug)
    fileReadDataCallback: FileReadDataCallback? = null // stream each file as read
): EgkReadResult
```

A top-level `readCard(...)` function with the same signature is also exported. The result carries both the card data and the live PACE channel:

```kotlin
data class EgkReadResult(
    val cardData: EgkCardData,
    val secureMessaging: SecureMessaging  // reuse to wrap/unwrap further APDUs on the open channel
)
```

Supporting callback types (all defined in the `de.scoopsoftware.nfc` package):

- `typealias FileCacheProvider = (fileName: String) -> ByteArray?` — return `null` to read from card, `FILE_NOT_FOUND` (the exported empty `ByteArray`) to skip, or cached bytes to use instead.
- `typealias VsdDataListener = (pdXml: String?, vdXml: String?) -> Unit` — fires as soon as PD/VD are read, before certificates, so you can render the card visualization early.
- `typealias FileReadDataCallback = suspend (fileName: String, data: ByteArray) -> Unit` — called after each file (wire names like `"gdo"`, `"cvcAuth"`, `"hcaPD"`); used for streaming upload.

`EgkReader.getPerformanceMetrics(): String` and `getPerformanceMetricsSnapshot(): PerformanceMetricsSnapshot` return timing for the last read.

**Minimal Kotlin read** (assuming you already have a connected `NfcTransceiver`):

```kotlin
val result = EgkReader.readCard(
    can = "123456",
    transceiver = transceiver,
    nfcMessageListener = { msg ->
        when (msg) {
            is NfcMessage.ReadingFile -> println("Reading ${msg.name} (${msg.index}/${msg.total})")
            is NfcMessage.Success     -> println("Done in ${msg.totalDurationMs}ms")
            is NfcMessage.Error       -> println("Failed: ${msg.message}")
            else -> {}
        }
    }
)
val person = VsdXmlParser.parse(result.cardData.pdXml, result.cardData.vdXml)
println(person?.fullName)
```

### The data you get back: `EgkCardData`

```kotlin
data class EgkCardData(
    val atrCard: ByteArray?,    // ATR from the NFC layer
    val atr: ByteArray,         // EF.ATR (card capabilities)
    val gdo: ByteArray,         // EF.GDO — contains the ICCSN (card serial)
    val version: ByteArray?,    // EF.VERSION2
    val cvcAuth: ByteArray,     // eGK auth card-verifiable certificate (ECC)
    val cvcCA: ByteArray?,      // CA card-verifiable certificate
    val x509AuthRSA: ByteArray?,// X.509 auth cert (RSA 2048) — absent on newer cards
    val x509AuthECC: ByteArray?,// X.509 auth cert (ECC 256) — absent on older cards
    val pd: ByteArray?, val vd: ByteArray?, // raw EF.PD / EF.VD
    val pdXml: String?, val vdXml: String?  // decoded insurance XML (ISO-8859-15, gunzipped)
)
```

Higher-level insured-person extraction:

- `VsdXmlParser.parse(pdXml, vdXml): InsuredPersonData?` (also `parsePd` / `parseVd`).
- `InsuredPersonData` exposes `insuranceId` (KVNR), `firstName`, `lastName`, `dateOfBirth`, address/insurer fields, plus derived `fullName`, `formattedBirthDate`, `formattedAddress`, and `toMap()`.
- Standalone decoders if you only have raw bytes: `decodePdToXml(ByteArray): String?` and `decodeVdToXml(ByteArray): Pair<String?, String?>` (VD + GVD).

**Card visualization (SVG):** `EgkCardSvg` renders a credit-card-shaped eGK as an SVG string for any SVG-capable renderer:

```kotlin
val svg = EgkCardSvg.generate(data = person, can = "123456", showLogo = true) // InsuredPersonData overload
// also: generate(pdXml, vdXml, can), generate(fullName, insuranceId, insurerId, insurerName, can, ...)
```

### Progress messages: `NfcMessage` / `NfcMessageListener` / `NfcMessageProvider`

`NfcMessageListener` is a `fun interface` (`onMessage(NfcMessage)`). `NfcMessage` is a sealed hierarchy you switch over; each carries a stable `key` and an `isUserFacing` flag:

| Message | Notable fields | Facing |
|---|---|---|
| `WaitingForCard`, `Connected` | — | user |
| `PaceStep` | `step`, `label`, `durationMs` | user |
| `PaceComplete` | `durationMs` | user |
| `ReadingFile` | `name`, `index`, `total` | user |
| `FileRead` | `name`, `sizeBytes`, `durationMs` | user |
| `Success` | `totalDurationMs` | user |
| `Error` | `message`, `exception` | user |
| `Cancelled`, `NfcNotAvailable`, `NfcDisabled`, `PaceRecovery` | — | user |
| `VsdDataAvailable` | `pdXml`, `vdXml` | internal |
| `ApduExchange` | `command`, `response`, `durationMs`, `label` | internal (tracing) |

`NfcMessage.defaultMessage(msg)` returns the built-in English string. To localize/brand, supply an `NfcMessageProvider` (`fun interface`, `getMessage(NfcMessage): String?`): return a custom string, `null` for the SDK default, or `""` to suppress that update.

### Configuration: `NfcReadOptions`

The platform-level read entry points (below) take an `NfcReadOptions`, built via a fluent `Builder` (`NfcReadOptions.DEFAULT` for defaults):

```kotlin
val options = NfcReadOptions.Builder()
    .messageProvider { msg -> if (msg is NfcMessage.WaitingForCard) "Karte anhalten" else null }
    .fileCacheProvider { name -> if (name == "EF.C.CH.AUT.R2048") FILE_NOT_FOUND else null }
    .recordMetrics(false)
    .nfcTimeout(2500)            // ms; default DEFAULT_NFC_TIMEOUT_MS = 2500
    .showNfcSheet(true)          // Android only: built-in Material 3 sheet; iOS always uses system sheet
    .nfcMessageListener { msg -> /* detailed/typed progress */ }
    .enableApduTracing(false)
    .build()
```

Read-only properties mirror the builder: `messageProvider`, `fileCacheProvider`, `recordMetrics`, `nfcTimeoutMs`, `showNfcSheet`, `nfcSheetSuccessDismissDelayMs`, `nfcSheetErrorDismissDelayMs`, `vsdDataListener`, `nfcMessageListener`, `enableApduTracing`.

### Platform NFC setup (getting a connected card)

`NfcTransceiver` is the platform abstraction `EgkReader` consumes — an ISO-DEP (ISO 14443-4) channel: `suspend fun transceive(ByteArray): ByteArray`, `getAtr()`, `isConnected()`, plus optional `setTimeout` / `getMaxTransceiveLength` / `isExtendedLengthSupported`. The SDK provides the concrete implementations; you normally don't implement it yourself:

- **Android:** `AndroidNfcTransceiver(isoDep)` wraps `android.nfc.tech.IsoDep`. The high-level `NfcSession` manages the full lifecycle (reader-mode enable, tag discovery, connect, optional bottom sheet):
  ```kotlin
  val session = NfcSession()
  session.readCard(activity, can = "123456", options = NfcReadOptions.DEFAULT, callback = object : NfcReadCallback {
      override fun onMessage(message: String, nfcMessage: NfcMessage) { /* update UI */ }
      override fun onComplete(result: NfcResult) { /* see NfcResult below */ }
  })
  // later: session.sendCommand(apduBytes) for extra APDUs; session.cancel() in onPause()
  ```
- **iOS:** `IosNfcTransceiver(tag)` wraps a `NFCISO7816TagProtocol`. The `NfcHelper.readCard(tag, can, options, callback)` (or the `onProgress: (String)->Unit` overload) returns `EgkCardData` and keeps the channel open for follow-up `sendCommand`. Drive it from your `NFCTagReaderSessionDelegate`.

`NfcResult` (delivered to `NfcReadCallback.onComplete`):

```kotlin
sealed class NfcResult {
    data class Success(val data: EgkCardData) : NfcResult()
    data class Error(val message: String, val exception: Throwable) : NfcResult()
    data object Cancelled : NfcResult()
    data object NfcNotAvailable : NfcResult()
    data object NfcDisabled : NfcResult()
}
```

### Flow-based reader: `NfcReader` / `NfcReaderBuilder`

For interactive sessions where you stream your own APDUs over the PACE channel (rather than just reading eGK files), use `NfcReader`. It exposes Kotlin `Flow`s for state, APDU results, and progress, and auto-recovers from tag-lost errors.

Build it with the `nfcReader { }` DSL or `NfcReaderBuilder(can)`:

```kotlin
val reader = nfcReader("123456") {
    timeout(60_000)            // session timeout ms; 0 = none
    maxRetries(3)
    enablePaceRecovery(true)
    verboseProgress(true)      // emit PaceStep/PaceComplete/PaceRecovery
    coroutineContext(Dispatchers.IO)  // required
}
```

Underlying `NfcReaderConfig`: `can`, `timeoutMs`, `maxRetries`, `paceConfig: PaceConfiguration` (defaults to `PaceConfiguration.DEFAULT`), `enablePaceRecovery`, `verboseProgress`.

Public surface:

```kotlin
val state: StateFlow<NfcReaderState>
val apduResults: SharedFlow<ApduResult>
val messages: SharedFlow<NfcMessage>

fun start()                                            // -> WaitingForCard
suspend fun transceive(command: ByteArray): ApduResult // queues; SM applied automatically
suspend fun transceive(command: CommandApdu): ApduResult
suspend fun transceiveBulk(commands: List<ByteArray>): List<ApduResult>
suspend fun close(); suspend fun reset()
// platform callbacks, invoked by AndroidNfcReader / IosNfcReader when a tag is detected:
suspend fun onCardConnected(transceiver: NfcTransceiver)
fun onCardDisconnected(); suspend fun onCardReconnected(transceiver: NfcTransceiver)
```

`NfcReaderState` (sealed) — the states you observe:

```kotlin
Idle | WaitingForCard | Connecting | Authenticating(step, totalSteps=4) |
Connected | Recovering | Timeout | Error(exception: Throwable) | Closed
```

`ApduResult` (sealed): `Success(command, response: ResponseApdu, durationMs)` or `Failure(command, error, recoverable)`. Plain APDUs you pass are SM-wrapped automatically using the established PACE channel; already-wrapped APDUs pass through, and responses are unwrapped for wrapped commands.

Platform wrappers tie `NfcReader` to the OS NFC stack and feed it tags: **Android** `AndroidNfcReader(config)` / `androidNfcReader(can) { }` — `start(activity): StartResult` (`Success` / `NfcNotAvailable` / `NfcDisabled`), `stop()`, `close()`; access the flows via `androidReader.reader`. **iOS** `IosNfcReader(can)` / `iosNfcReader(can) { }` — `start()`, then call `onTagConnected(tag)` / `onTagDisconnected()` from your `NFCTagReaderSessionDelegate`; `transceive`/`transceiveBulk` are forwarded.

### CAN scanning via camera OCR: `CanScanner`

`CanScanner` reads the 6-digit CAN off the physical card with the camera (Android: CameraX + ML Kit; iOS: AVFoundation + Vision). It's an `expect class`, created per platform:

```kotlin
// Android
val scanner = CanScanner.create(activity)
val result = scanner.scan(CanScannerConfig(requiredReadings = 10, consensusRatio = 0.5f) { can, n, required ->
    // intermediate detection progress
})
when (result) {
    is CanScanResult.Success   -> useCan(result.can)     // also result.confidence
    is CanScanResult.Error     -> show(result.message)
    CanScanResult.Cancelled    -> {}
}
scanner.stop()
```

```swift
// iOS
let scanner = CanScanner.companion.create(viewController: vc)
let result = try await scanner.scan(config: .companion.DEFAULT)
```

Types: `CanScanResult` (`Success(can, confidence)` / `Cancelled` / `Error(message)`), `CanScannerConfig(requiredReadings = 10, consensusRatio = 0.5f, onDetection)`. Helpers `isValidCan(String): Boolean` and `extractCanCandidates(String): List<String>` are exported for custom OCR pipelines.

---

## Performance Metrics, Scan Records & Reporting

After every eGK read, the SDK exposes a fine-grained timing breakdown (NFC round-trips, crypto, gzip, per-APDU exchanges). The `de.scoopsoftware.cardlink.metrics` package wraps that snapshot in a chart-friendly `ScanRecord`, plus helpers for formatting, aggregate statistics, CSV export, and posting results to RocketChat. These types are the data model behind the demo apps' performance-charts tab and are shared verbatim across Android and iOS.

> Swift/iOS: `import ScoopCardlink`; all types below are exposed with the same names (e.g. `ScanRecord`, `MetricsFormatting`, `ScanStatistics`, `CsvExporter`, `RocketChatReporter`).

### Capturing a snapshot

The raw timing data comes from the NFC reader as an immutable `PerformanceMetricsSnapshot` (package `de.scoopsoftware.nfc.model`), reflecting the **last** `EgkReader.readCard()` call. All times are in milliseconds.

```kotlin
// From the NFC SDK — snapshot of the most recent read:
val snapshot: PerformanceMetricsSnapshot = EgkReader.getPerformanceMetricsSnapshot()
```

`PerformanceMetricsSnapshot` fields:

| Field | Type | Meaning |
|---|---|---|
| `timestampMs` | `Long` | Start time of the read (epoch ms) |
| `totalTimeMs` | `Long` | Wall-clock duration of the whole read |
| `nfcTimeMs` / `nfcCallCount` | `Long` / `Int` | Time spent in NFC transceive, and number of calls |
| `totalCryptoTimeMs` | `Long` | Sum of all crypto operations |
| `aesCbcEncryptTimeMs` / `aesCbcEncryptCount` | `Long` / `Int` | AES-CBC encrypt time and op count |
| `aesCbcDecryptTimeMs` / `aesCbcDecryptCount` | `Long` / `Int` | AES-CBC decrypt time and op count |
| `aesCmacTimeMs` / `aesCmacCount` | `Long` / `Int` | AES-CMAC time and op count |
| `sha1TimeMs` / `sha1Count` | `Long` / `Int` | SHA-1 time and op count |
| `sha256TimeMs` / `sha256Count` | `Long` / `Int` | SHA-256 time and op count |
| `ecKeyGenTimeMs` / `ecKeyGenCount` | `Long` / `Int` | EC key generation time/count |
| `ecScalarMultiplyTimeMs` / `ecScalarMultiplyCount` | `Long` / `Int` | EC scalar-multiply time/count |
| `ecPointAddTimeMs` / `ecPointAddCount` | `Long` / `Int` | EC point-addition time/count |
| `gzipDecompressTimeMs` / `gzipDecompressCount` | `Long` / `Int` | Gzip decompress time/count |
| `otherTimeMs` | `Long` | Time not attributed to NFC, crypto, or gzip |
| `apduExchanges` | `List<ApduExchangeRecord>` | Per-command APDU log |

Each `ApduExchangeRecord` holds `command: String` and `response: String` (hex), `durationMs: Long` (round-trip), and a human-readable `label: String` (e.g. `"SELECT MF"`, `"READ BINARY"`).

### ScanRecord — chart-ready wrapper

`ScanRecord` pairs a snapshot with a stable `id` and adds computed properties for charts. The convenience factory snapshots the current metrics directly:

```kotlin
// Capture the just-completed read as a record (generates a unique id):
val record: ScanRecord = ScanRecord.fromCurrentMetrics()
```

```kotlin
data class ScanRecord(val id: String, val metrics: PerformanceMetricsSnapshot)
```

Key public members:

- **Delegated**: `timestampMs`, `totalTimeMs`, `nfcTimeMs`, `nfcCallCount`, `cryptoTimeMs` (= `totalCryptoTimeMs`), `gzipTimeMs` (= `gzipDecompressTimeMs`), `otherTimeMs`, `apduExchanges` — plus all detailed crypto fields (`aesCbcEncryptTimeMs`, `sha256Count`, `ecKeyGenTimeMs`, …) used by the CSV export.
- **Computed percentages** (of `totalTimeMs`): `nfcPercentage`, `cryptoPercentage`, `gzipPercentage`, `otherPercentage` (`Double`, 0.0–100.0).
- **`avgNfcRoundtripMs: Long`** — `nfcTimeMs / nfcCallCount`.
- **`companion.fromCurrentMetrics(): ScanRecord`** — calls `EgkReader.getPerformanceMetricsSnapshot()` and assigns a `"<timestamp>-<counter>"` id.

Build records yourself only if you already hold a snapshot; otherwise use `fromCurrentMetrics()` right after a read.

### MetricsFormatting — display helpers

```kotlin
MetricsFormatting.formatMs(450L)   // "450ms"
MetricsFormatting.formatMs(2500L)  // "2.5s"  (>= 1000ms shown as seconds, 1 decimal)

val color: ApduColor = MetricsFormatting.colorForApduLabel("SELECT MF") // ApduColor.BLUE
```

`colorForApduLabel` returns a semantic, platform-neutral `ApduColor` so APDU bars/chips color consistently across Android and iOS:

```kotlin
enum class ApduColor { BLUE, GREEN, ORANGE, GRAY, PURPLE, CYAN }
```

Mapping: `SELECT` → `BLUE`, `MSE` → `PURPLE`, `GENERAL AUTHENTICATE` → `ORANGE`, `READ`/`SM:READ` → `GREEN`, `GET RESPONSE` → `CYAN`, otherwise `GRAY`. Each platform maps these enum values to its own native color.

### ScanStatistics — aggregate over many scans

```kotlin
object ScanStatistics {
    fun calculateStats(records: List<ScanRecord>): ScanStats
    fun aggregateApduData(records: List<ScanRecord>): List<AggregatedApduItem>
    fun createApduTimeline(record: ScanRecord): List<ApduTimelineItem>
}
```

- **`calculateStats`** → `ScanStats(totalScans, averageTotalTimeMs, minTotalTimeMs, maxTotalTimeMs, averageNfcTimeMs, averageCryptoTimeMs)` (all `Long` except `totalScans: Int`). Returns all-zero stats for an empty list.
- **`aggregateApduData`** → `List<AggregatedApduItem(label, totalMs, count, color)>` grouped by APDU label and sorted by `avgMs` (computed `totalMs / count`) descending — drives the "slowest commands" chart.
- **`createApduTimeline`** → `List<ApduTimelineItem(index, label, startMs, durationMs, color)>` for a single scan, with cumulative `startMs` offsets for a Gantt-style timeline.

### CsvExporter — flat export

```kotlin
val csv: String = CsvExporter.export(records) { ts -> ts.toIso8601(/* platform formatter */) }
```

`export(records: List<ScanRecord>, formatTimestamp: (Long) -> String): String` emits one metrics row per scan (full timing + op counts) followed by a `# APDU Exchanges` section listing every command/response with timing. Timestamp formatting is delegated to the platform because Kotlin Multiplatform `commonMain` has no date formatter — supply a function that turns epoch-ms into an ISO-8601 string.

### RocketChatReporter — post a scan to a channel

`RocketChatReporter` (a singleton `object`) logs into a RocketChat server and posts an ASCII bar-chart of the timing breakdown plus a collapsed APDU log; if a trace log is supplied it is uploaded as a `trace.log` file attachment. All failures are swallowed silently so reporting never interrupts the app flow.

```kotlin
suspend fun report(
    serverUrl: String,
    username: String,
    password: String,
    channel: String,
    record: ScanRecord,
    success: Boolean = true,
    traceLog: List<String> = emptyList(),
)

suspend fun testConnection(serverUrl: String, username: String, password: String): String? // null on success
fun clearAuth()                          // drop cached auth when settings change
const val DEFAULT_SERVER_URL = "https://rocketchat.scoop-gmbh.de/"
```

Auth tokens are cached after the first login and reused across scans (auto-cleared on auth failure). Call `clearAuth()` after changing credentials; use `testConnection()` to validate settings (returns `null` on success, an error message otherwise).

### End-to-end example

```kotlin
import de.scoopsoftware.cardlink.metrics.MetricsFormatting
import de.scoopsoftware.cardlink.metrics.ScanRecord
import de.scoopsoftware.cardlink.metrics.ScanStatistics
import de.scoopsoftware.cardlink.reporting.RocketChatReporter

// 1. Snapshot the read that just completed.
val record = ScanRecord.fromCurrentMetrics()

// 2. Display headline numbers.
println("Total: ${MetricsFormatting.formatMs(record.totalTimeMs)}")
println("NFC:   ${MetricsFormatting.formatMs(record.nfcTimeMs)} (${record.nfcPercentage.toInt()}%)")
println("Avg NFC round-trip: ${MetricsFormatting.formatMs(record.avgNfcRoundtripMs)}")

// 3. Aggregate across a history of scans for the charts tab.
val stats = ScanStatistics.calculateStats(history)   // history: List<ScanRecord>
println("Avg over ${stats.totalScans} scans: ${MetricsFormatting.formatMs(stats.averageTotalTimeMs)}")

// 4. Optionally report this scan to RocketChat (suspend).
RocketChatReporter.report(
    serverUrl = RocketChatReporter.DEFAULT_SERVER_URL,
    username = user, password = pass, channel = "#cardlink-scans",
    record = record, success = true,
)
```

---

## See also

- **Demo apps** — `ios/` and `android/` in this repository exercise every flow above.
- **iOS (SPM):** [`cardlink-packages`](https://github.com/scoop-software/cardlink-packages) ·
  [`nfc-sdk-spm`](https://github.com/scoop-software/nfc-sdk-spm) ·
  [`scoop-popp-module-spm`](https://github.com/scoop-software/scoop-popp-module-spm) — each README covers install + the required Xcode 26 build settings.
- **API docs in‑IDE:** on iOS, ⌥‑click any symbol for inline Quick Help (the KDoc ships in
  the XCFramework headers). This page is the cross‑platform written reference.

---

© Scoop Software GmbH. Proprietary. Generated for SDK **2.1.2** (nfc 2.0.1, popp 0.18.0) —
keep in sync with the published artifacts.
