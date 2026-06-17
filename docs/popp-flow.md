# PoPP Module Flow

```mermaid
flowchart TD
    %% Styling
    classDef state fill:#e1f5fe,stroke:#0288d1,color:#01579b
    classDef decision fill:#fff3e0,stroke:#f57c00,color:#e65100
    classDef error fill:#ffebee,stroke:#c62828,color:#b71c1c
    classDef success fill:#e8f5e9,stroke:#2e7d32,color:#1b5e20
    classDef async fill:#f3e5f5,stroke:#7b1fa2,color:#4a148c

    %% ===== Phase 1: Initialization =====
    IDLE([Idle]):::state
    INIT[Initializing<br/><i>ZETA client init</i>]:::state

    IDLE -->|startCheckIn| INIT
    INIT --> HAS_TEL{telematikId<br/>provided?}:::decision

    %% ===== Phase 2: LEI Selection =====
    LEI_SEL[NeedsLeiSelectionMethod<br/><i>QR / VZD Search / Favorites</i>]:::state
    QR[ScanningQr<br/><i>Camera active</i>]:::state
    VZD[NeedsVzdSearch<br/><i>Enter search query</i>]:::state
    FAV[NeedsFavoriteSelection<br/><i>Pick from list</i>]:::state

    HAS_TEL -->|Yes| VZD_LOOKUP
    HAS_TEL -->|No| LEI_SEL

    LEI_SEL -->|QR_SCAN| QR
    LEI_SEL -->|VZD_SEARCH| VZD
    LEI_SEL -->|FAVORITES| FAV

    QR -->|valid payload| VZD_LOOKUP
    QR -->|cancelled| CANCELLED
    VZD -->|search query| VZD_LOOKUP
    VZD -->|cancelled| CANCELLED
    FAV -->|favorite selected| VZD_LOOKUP
    FAV -->|cancelled| CANCELLED

    %% ===== Phase 3: VZD Lookup & Consent =====
    VZD_LOOKUP[VZD Lookup<br/><i>Resolve LEI by telematikId</i>]:::state
    CONSENT[NeedsConsent<br/><i>Show LEI info + consent sheet</i>]:::state

    VZD_LOOKUP -->|LEI found| CONSENT
    VZD_LOOKUP -->|not found| ERROR

    CONSENT -->|granted| AUTH_SEL
    CONSENT -->|denied| CANCELLED

    %% ===== Phase 4: Auth Method Selection =====
    AUTH_SEL{NeedsAuthMethod<br/><i>eGK or GesundheitsID?</i>}:::decision

    %% ===== eGK Path =====
    CAN[NeedsCan<br/><i>Enter CAN or pick known card</i>]:::state
    NFC_WAIT[WaitingForCard<br/><i>Hold eGK to device</i>]:::state
    AUTH_EGK[AuthenticatingEgk]:::async

    AUTH_SEL -->|eGK| CAN
    CAN -->|submitCan| NFC_WAIT
    NFC_WAIT -->|card detected| AUTH_EGK

    %% PACE substeps
    subgraph PACE_FLOW [PACE + APDU Relay]
        direction TB
        CARD_ACCESS[Read EF.CardAccess]:::async
        PACE[Execute PACE<br/><i>async — overlaps with HTTP</i>]:::async
        GDO[Read GDO → saveCan]:::async
        APDU_RELAY[APDU Relay Loop<br/><i>PoPP-Service ↔ eGK via SM</i>]:::async
        CARD_ACCESS --> PACE
        PACE -->|SM established| GDO
        GDO --> APDU_RELAY
    end

    AUTH_EGK --> CARD_ACCESS

    %% eGK error paths
    PACE -->|WrongCanException| CAN_ERR
    PACE -->|PaceException| CAN_ERR
    PACE -->|NfcException| CAN_ERR
    CAN_ERR[closeNfcSession]:::error -->|error message| CAN

    APDU_RELAY -->|final response| RESULT

    %% ===== GesundheitsID Path =====
    AUTH_GID[AuthenticatingGid<br/><i>GesundheitsID flow</i>]:::state

    AUTH_SEL -->|GesundheitsID| AUTH_GID
    AUTH_GID -->|result| RESULT
    AUTH_GID -->|not available| ERROR

    %% ===== Phase 5: Result =====
    RESULT{Parse tokenState}:::decision
    COMPLETED([Completed ✓]):::success
    CANCELLED([Cancelled]):::error
    ERROR([Error]):::error

    RESULT -->|success / pending| COMPLETED
    RESULT -->|canceled| CANCELLED
    RESULT -->|error| ERROR
```

## States

| State | Description |
|-------|-------------|
| **Idle** | Initial state, no activity |
| **Initializing** | ZETA/OAuth client initialization |
| **NeedsLeiSelectionMethod** | User chooses how to find the pharmacy (QR, search, favorites) |
| **ScanningQr** | Camera scanning QR code |
| **NeedsVzdSearch** | User enters pharmacy search query |
| **NeedsFavoriteSelection** | User picks from saved favorites |
| **NeedsConsent** | Native consent sheet with pharmacy info |
| **NeedsAuthMethod** | Choose eGK or GesundheitsID |
| **NeedsCan** | Enter 6-digit CAN or select known card |
| **WaitingForCard** | NFC — hold eGK to device |
| **AuthenticatingEgk** | PACE + APDU relay with eGK |
| **AuthenticatingGid** | GesundheitsID authentication |
| **Completed** | Check-in succeeded or pending |
| **Cancelled** | User cancelled or consent denied |
| **Error** | LEI not found, service error, etc. |

## Key Design Decisions

- **Async PACE overlap**: PACE runs in a `Deferred` while the PoPP module's initial HTTP request goes out in parallel (~200ms saved)
- **Early error detection**: If `paceDeferred.isCompleted` before returning, wrong CAN is caught immediately without losing the overlap on the happy path
- **APDU file caching**: Immutable card files (certificates, VERSION2) are cached by ICCSN — subsequent check-ins with the same card skip NFC reads
- **CAN persistence**: `saveCan()` after PACE stores the CAN so the card appears in known cards for future check-ins
