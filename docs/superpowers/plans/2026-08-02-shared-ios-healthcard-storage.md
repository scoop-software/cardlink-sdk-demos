# Shared iOS Health-Card Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native Cardlink iOS demo, Flutter `cardlink_demo`, and Flutter `full_demo` share the encrypted health-card cache plus Cardlink/PoPP and RocketChat credentials through `group.de.scoopsoftware.nfc.healthcard`, while safely migrating the already deployed native demo.

**Architecture:** The customer-facing SDK APIs stay unchanged. The native demo owns an idempotent bootstrap that migrates credentials through Keychain abstractions and cache entries through public `CacheProvider` operations. Flutter `demo_core` owns a demo-only SwiftPM plugin that reads and writes the same two Internet-password records. App-private preferences remain app-private; only the SDK cache, Keycloak URL/credentials, and RocketChat URL/credentials cross app boundaries.

**Tech Stack:** Swift 5 / SwiftUI / Security.framework / XCTest, Kotlin Multiplatform `ScoopNfc` cache API, Flutter 3.44 / Dart 3.12 / MethodChannel / SwiftPM, shell repository guards, the currently selected Xcode toolchain, physical iPhone 13 Pro `00008110-000111CA11A0401E`.

## Global Constraints

- Work only in `/Users/pkursawe/projects/cardlink-sdk-demos`; do not add demo migration APIs to NFC, Cardlink, PoPP, or their Flutter bridges.
- Canonical App Group: `group.de.scoopsoftware.nfc.healthcard`.
- Canonical Keychain access group: `$(AppIdentifierPrefix)group.de.scoopsoftware.nfc.healthcard`; never hard-code Apple Team ID `845RN736HR` in source code.
- Native cache migration sources are `group.de.scoopsoftware.nfc` plus its corresponding fully qualified Keychain group, followed by the historical app-private encrypted `FileCacheProvider` fallback.
- Canonical destination values always win. Never delete legacy credentials, legacy cache entries, or legacy entitlements in this transition release.
- Never log credentials, CANs, ICCSNs, cached file data, tokens, or raw Keychain queries.
- OAuth/session state, WebSocket/REST URLs, RocketChat channel, other settings, switches, history, timings, and `CanKeychain` stay app-private.
- Flutter Runner projects remain SwiftPM-only. Do not restore Podfiles, podspec integration, or `[CP]` build phases.
- Run builds and device acceptance only against Philipp's physical iPhone 13 Pro. Host-side Dart and shell tests are allowed.
- Use Conventional Commits at the listed boundaries, but create each commit only after explicit user approval. Do not push, tag, publish, or release without a separate explicit request.

---

## Task 1: Establish a Working Native Test Harness and Shared Credential Schema

**Files:**

- Create: `ios/CardlinkSample/CardlinkSample/DemoSharedCredentialStore.swift`
- Create: `ios/CardlinkDemoTests/DemoSharedCredentialStoreTests.swift`
- Modify: `ios/CardlinkDemo.xcodeproj/project.pbxproj`
- Modify: `ios/CardlinkDemoDev.xcodeproj/project.pbxproj`

- [ ] **Step 1: Replace the native test target's dangling references**

  Both Xcode projects currently reference missing `FileCacheProviderTests.swift`, `MemoryCacheProviderTests.swift`, and `SettingsCacheProviderTests.swift`. Remove those PBX file/build references and add `DemoSharedCredentialStoreTests.swift` to `CardlinkDemoTests`. Correct the Dev project's Debug `TEST_HOST` from `Cardlink Dev.app` to `Cardlink DevSDK.app`, and stabilize the app module as `PRODUCT_MODULE_NAME = CardlinkDemo` in both projects so the same test source can import every configuration. Do not add production source membership until after the RED compile failure. Keep the main project as source of truth and verify app source parity with:

  ```bash
  ruby scripts/sync-ios-projects.rb --check
  ```

- [ ] **Step 2: Write failing schema and migration-policy tests**

  Define test doubles around this pure Swift boundary:

  ```swift
  struct DemoInternetCredential: Equatable {
      let baseURL: URL
      let username: String
      let password: String
  }

  enum DemoCredentialKind: String, CaseIterable {
      case keycloak
      case rocketChat
  }

  protocol DemoInternetCredentialStore {
      func read(_ kind: DemoCredentialKind) throws -> DemoInternetCredential?
      func write(_ credential: DemoInternetCredential, for kind: DemoCredentialKind) throws
  }
  ```

  Tests must initially fail for:

  - Internet-password labels `de.scoopsoftware.cardlink.demo.keycloak` and `de.scoopsoftware.cardlink.demo.rocketchat`;
  - HTTPS base-URL mapping to server/protocol/port/path attributes;
  - username mapping to account and password mapping to value data;
  - complete record add/update/read-back round-trip;
  - invalid, query-bearing, fragmented, or incomplete URLs rejected before mutation;
  - missing or unexpanded `ScoopKeychainAccessGroup` rejection;
  - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and no synchronizable flag;
  - destination read-back mismatch producing an error.

- [ ] **Step 3: Confirm the red test state on the physical device**

  ```bash
  xcodebuild \
    -project ios/CardlinkDemoDev.xcodeproj \
    -scheme CardlinkDemoDev \
    -destination 'platform=iOS,id=00008110-000111CA11A0401E' \
    -only-testing:CardlinkDemoTests/DemoSharedCredentialStoreTests \
    test
  ```

  Expected: compile/test failures because the shared schema and store do not exist yet. Use a fresh `-derivedDataPath /tmp/cardlink-demo-healthcard-tests`; the Dev project intentionally resolves the local sibling SDK packages and does not depend on customer-registry authentication.

- [ ] **Step 4: Implement the Keychain-backed store minimally**

  Add `DemoSharedCredentialStore.swift` to both app targets, then add:

  ```swift
  enum DemoSharedCredentialSchema {
      static let keycloakLabel = "de.scoopsoftware.cardlink.demo.keycloak"
      static let rocketChatLabel = "de.scoopsoftware.cardlink.demo.rocketchat"
      static let defaultKeycloakBaseURL = URL(
          string: "https://auth-cardlink-dev.demo.scoop-gmbh.de/realms/cardlinkdemo/protocol/openid-connect"
      )!
      static let oauthClientId = "cardlink-app"
  }
  ```

  `DemoSharedCredentialStore` must:

  - read its fully qualified access group from `ScoopKeychainAccessGroup` in the supplied `Bundle`;
  - use `kSecClassInternetPassword`, a stable label, explicit access group, and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`;
  - store URL components, account, and password as one item and compare the complete read-back;
  - locate updates by class, label, access group, and non-synchronizable status so changing URL/account updates the same item;
  - return `nil` only for genuinely absent items; surface entitlement, decoding, and Security errors;
  - avoid printing values or query dictionaries.

  Inject a small `DemoKeychainClient` protocol so XCTest uses an in-memory fake rather than the device Keychain for behavior tests.

- [ ] **Step 5: Confirm green tests and both project builds**

  Run the focused Dev-project test command again, then:

  ```bash
  ruby scripts/sync-ios-projects.rb --check
  xcodebuild -project ios/CardlinkDemoDev.xcodeproj -scheme CardlinkDemoDev -destination 'platform=iOS,id=00008110-000111CA11A0401E' build
  ```

- [ ] **Step 6: Review and checkpoint**

  Check that no credential value appears in a diagnostic string. After explicit approval:

  ```bash
  git add ios/CardlinkSample/CardlinkSample/DemoSharedCredentialStore.swift ios/CardlinkDemoTests/DemoSharedCredentialStoreTests.swift ios/CardlinkDemo.xcodeproj/project.pbxproj ios/CardlinkDemoDev.xcodeproj/project.pbxproj
  git commit -m "feat(ios): add shared demo credential store"
  ```

---

## Task 2: Migrate Native Cardlink and RocketChat Credentials

**Files:**

- Modify: `ios/CardlinkSample/CardlinkSample/DemoSharedCredentialStore.swift`
- Modify: `ios/CardlinkSample/CardlinkSample/CardlinkSampleApp.swift`
- Modify: `ios/CardlinkSample/CardlinkSample/ContentView.swift`
- Modify: `ios/CardlinkSample/CardlinkSample/UploadView.swift`
- Modify: `ios/CardlinkSample/CardlinkSample/PoppCheckInView.swift`
- Modify: `ios/CardlinkSample/CardlinkSample/SettingsView.swift`
- Modify: `ios/CardlinkSample/CardlinkSample/Models/RocketChatHelper.swift`
- Modify: `ios/CardlinkDemoTests/DemoSharedCredentialStoreTests.swift`
- Modify: `scripts/test-native-customer-demo-safety.sh`

- [ ] **Step 1: Add failing migration tests**

  Test an idempotent `DemoCredentialMigrator` with fake canonical, legacy, URL-source, and marker stores:

  ```swift
  struct DemoCredentialMigrator {
      func migrate(_ kind: DemoCredentialKind) throws
  }
  ```

  Cover:

  - complete canonical Internet credential wins and legacy is not read or written over it;
  - legacy Cardlink credentials migrate with the fixed Dev Keycloak base URL;
  - legacy RocketChat credentials migrate only with a valid nonempty `rcServerUrl`;
  - incomplete legacy records and invalid URLs are rejected;
  - write failure or read-back mismatch leaves the marker unset;
  - a successful or already-canonical record sets only that record's app-private marker;
  - rerunning migration is harmless;
  - RocketChat legacy `UserDefaults` fallback participates only when username and password form a complete pair.

- [ ] **Step 2: Confirm the tests fail**

  Run the Task 1 focused Dev-project XCTest command. Expected: missing migrator/legacy adapter failures.

- [ ] **Step 3: Implement legacy readers and the migrator**

  Move the old behavior into private legacy adapters:

  - Cardlink/PoPP: the existing synchronizable HTTPS internet-password item for `cardlink.scoopsoftware.de`;
  - RocketChat: existing generic-password service `de.scoopsoftware.cardlink.rocketchat`, accounts `rcUsername` and `rcPassword`, with the existing standard-`UserDefaults` fallback;
  - RocketChat base URL: existing app-private `rcServerUrl` in `UserDefaults.standard`;
  - marker keys `demo.shared-storage.credentials.keycloak.v1` and `demo.shared-storage.credentials.rocketchat.v1` in `UserDefaults.standard`.

  Do not delete or update legacy values. `KeychainHelper` and `RocketChatKeychain` become compatibility facades whose normal reads/writes use `DemoSharedCredentialStore` only.

- [ ] **Step 4: Wire native startup and foreground refresh**

  Add a bootstrap state to `CardlinkSampleApp` that completes credential migration before presenting `ContentView`. Migration failure records only a non-secret category and still permits the demo to start with empty/current canonical credentials.

  In `ContentView`, place Keycloak base URL beside username/password, observe `scenePhase`, and reload the complete Keycloak record whenever it becomes `.active`. Build the Cardlink environment from the shared OAuth URL, fixed client ID `cardlink-app`, and the existing default or app-private WebSocket/REST endpoints. Pass the same shared base URL plus `/token` to the native PoPP OAuth client.

  In `RocketChatSettingsSection`, remove `rcServerUrl` from `@AppStorage`, save URL/username/password together only when complete and valid, and reload the complete record on appear and `UIApplication.didBecomeActiveNotification`. Preserve `RocketChatReporter.clearAuth()` after changes. RocketChat channel and trace settings remain app-private.

- [ ] **Step 5: Run tests and native smoke build**

  ```bash
  xcodebuild -project ios/CardlinkDemoDev.xcodeproj -scheme CardlinkDemoDev -destination 'platform=iOS,id=00008110-000111CA11A0401E' test
  xcodebuild -project ios/CardlinkDemoDev.xcodeproj -scheme CardlinkDemoDev -destination 'platform=iOS,id=00008110-000111CA11A0401E' build
  ```

- [ ] **Step 6: Review and checkpoint**

  Verify `KeychainCredentialStorage.swift` (OAuth/session storage) and `CanKeychain` are unchanged. After explicit approval:

  ```bash
  git add ios/CardlinkSample/CardlinkSample/DemoSharedCredentialStore.swift ios/CardlinkSample/CardlinkSample/CardlinkSampleApp.swift ios/CardlinkSample/CardlinkSample/ContentView.swift ios/CardlinkSample/CardlinkSample/UploadView.swift ios/CardlinkSample/CardlinkSample/PoppCheckInView.swift ios/CardlinkSample/CardlinkSample/SettingsView.swift ios/CardlinkSample/CardlinkSample/Models/RocketChatHelper.swift ios/CardlinkDemoTests/DemoSharedCredentialStoreTests.swift scripts/test-native-customer-demo-safety.sh
  git commit -m "feat(ios): migrate native demo credentials"
  ```

---

## Task 3: Implement Public-API Health-Card Cache Migration

**Files:**

- Create: `ios/CardlinkSample/CardlinkSample/HealthCardCacheMigrator.swift`
- Create: `ios/CardlinkDemoTests/HealthCardCacheMigratorTests.swift`
- Modify: `ios/CardlinkDemo.xcodeproj/project.pbxproj`
- Modify: `ios/CardlinkDemoDev.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing migration tests against a cache abstraction**

  Keep the algorithm independent of Kotlin runtime types:

  ```swift
  enum DemoCacheEntry: Equatable {
      case found(Data)
      case notOnCard
      case notCached
  }

  protocol DemoHealthCardCache {
      func allCards() async throws -> [String]
      func can(for iccsn: String) async throws -> String?
      func saveCan(_ can: String, for iccsn: String) async throws
      func cachedFiles(for iccsn: String) async throws -> [String]
      func entry(for iccsn: String, fileName: String) async throws -> DemoCacheEntry
      func put(_ data: Data, for iccsn: String, fileName: String) async throws
  }
  ```

  Cover byte entries, empty/not-on-card markers, CANs, destination-wins behavior, mixed existing/missing entries, read-back verification, failure marker behavior, and idempotent reruns. The fake must retain call history so tests prove no destination value is overwritten.

- [ ] **Step 2: Confirm red tests**

  ```bash
  xcodebuild \
    -project ios/CardlinkDemoDev.xcodeproj \
    -scheme CardlinkDemoDev \
    -destination 'platform=iOS,id=00008110-000111CA11A0401E' \
    -only-testing:CardlinkDemoTests/HealthCardCacheMigratorTests \
    test
  ```

- [ ] **Step 3: Implement the algorithm and ScoopNfc adapter**

  `HealthCardCacheMigrator` must:

  1. return immediately when `demo.shared-storage.cache.v1` is true;
  2. enumerate source cards with `getAll()` through the adapter;
  3. copy a source CAN only if the destination CAN is absent;
  4. copy each source file only when the destination returns `NotCached`;
  5. map source `Found` to bytes and `NotOnCard` to an empty byte array;
  6. read every copied value back and compare it;
  7. set the marker only after every card verifies.

  `ScoopNfcHealthCardCacheAdapter` wraps `SharedFileCacheProvider` and maps `CacheResultFound`, `CacheResultNotOnCard`, and `CacheResultNotCached`. It must never copy encrypted files directly and must not include ICCSN/file names in errors shown to the user or logs.

- [ ] **Step 4: Confirm green focused and complete native tests**

  Run the focused command, then the complete native test command from Task 2 and `ruby scripts/sync-ios-projects.rb --check`.

- [ ] **Step 5: Review and checkpoint**

  Ensure no direct `FileManager` copy and no SDK/bridge changes. After explicit approval:

  ```bash
  git add ios/CardlinkSample/CardlinkSample/HealthCardCacheMigrator.swift ios/CardlinkDemoTests/HealthCardCacheMigratorTests.swift ios/CardlinkDemo.xcodeproj/project.pbxproj ios/CardlinkDemoDev.xcodeproj/project.pbxproj
  git commit -m "feat(ios): migrate health-card cache"
  ```

---

## Task 4: Switch the Native Demo to the Canonical Group

**Files:**

- Modify: `ios/CardlinkSample/CardlinkSample.entitlements`
- Modify: `ios/CardlinkSample/CardlinkSample/Info.plist`
- Modify: `ios/CardlinkSample/CardlinkSample/CardlinkSampleApp.swift`
- Modify: `ios/CardlinkSample/CardlinkSample/SettingsView.swift`
- Modify: `ios/CardlinkDemo.xcodeproj/project.pbxproj`
- Modify: `ios/CardlinkDemoDev.xcodeproj/project.pbxproj`
- Modify: `scripts/test-native-customer-demo-safety.sh`
- Create: `scripts/test-shared-ios-healthcard-storage.sh`

- [ ] **Step 1: Add a failing repository contract guard**

  `scripts/test-shared-ios-healthcard-storage.sh` must fail until it sees:

  - native canonical plus legacy App Groups and Keychain groups;
  - canonical `SCOOP_APP_GROUP_ID` and `SCOOP_KEYCHAIN_ACCESS_GROUP` in both native projects/configurations;
  - separate native legacy Info/build values without a hard-coded Team ID;
  - the exact shared Internet-password labels and fixed OAuth client ID in native code;
  - no canonical secret stored in `UserDefaults`.

  Run:

  ```bash
  bash scripts/test-shared-ios-healthcard-storage.sh
  ```

  Expected: failures describing the still-old native configuration.

- [ ] **Step 2: Configure the transition entitlements and Info values**

  Native entitlements contain both:

  ```text
  group.de.scoopsoftware.nfc.healthcard
  group.de.scoopsoftware.nfc
  ```

  and the corresponding `$(AppIdentifierPrefix)` Keychain groups. Normal build settings point at healthcard; add legacy Info keys/build settings solely for the migrator:

  ```text
  ScoopLegacyAppGroupId
  ScoopLegacyKeychainAccessGroup
  ```

  Move `DemoCacheConfig` out of `SettingsView.swift` into the migration/configuration code and reject empty/unexpanded runtime values.

- [ ] **Step 3: Complete native bootstrap ordering**

  `CardlinkSampleApp` shows a neutral progress view while it runs:

  1. credential migration;
  2. cache migration from the legacy shared provider and then the historical
     app-private fallback to the canonical provider, using independent markers;
  3. root `ContentView` presentation.

  On migration failure, do not set the failing source's marker; present the app
  using the canonical destination and expose only a non-secret diagnostic
  message. Never fall back normal flows to either old cache.

- [ ] **Step 4: Align the release guard with the required NFC artifact**

  Update stale `4.0.3` assertions in `scripts/test-native-customer-demo-safety.sh` to `4.0.4`, because the native project already pins `ti-common.nfc` 4.0.4 and the migration requires the `SharedFileCacheProvider(appGroupId:keychainAccessGroup:)` API. Do not change unrelated SDK pins.

- [ ] **Step 5: Run native guards, tests, and physical build**

  ```bash
  bash scripts/test-shared-ios-healthcard-storage.sh
  bash scripts/test-native-customer-demo-safety.sh
  ruby scripts/sync-ios-projects.rb --check
  xcodebuild -project ios/CardlinkDemoDev.xcodeproj -scheme CardlinkDemoDev -destination 'platform=iOS,id=00008110-000111CA11A0401E' test
  xcodebuild -project ios/CardlinkDemo.xcodeproj -scheme CardlinkDemo -destination 'platform=iOS,id=00008110-000111CA11A0401E' -derivedDataPath /tmp/cardlink-demo-healthcard build
  ```

  If signing reports that `group.de.scoopsoftware.nfc.healthcard` does not exist or is absent from the profile, stop and report the Apple Developer provisioning blocker. Do not substitute another group.

- [ ] **Step 6: Install and validate native migration**

  Preserve the existing installed native demo data, install the new Debug build with `xcrun devicectl`, launch it, and confirm legacy credentials/cards appear. Repeat launch once to prove idempotence. Confirm NFC read, cancel, and wrong-CAN-then-correct-CAN.

- [ ] **Step 7: Review and checkpoint**

  After explicit approval:

  ```bash
  git add ios/CardlinkSample/CardlinkSample.entitlements ios/CardlinkSample/CardlinkSample/Info.plist ios/CardlinkSample/CardlinkSample/CardlinkSampleApp.swift ios/CardlinkSample/CardlinkSample/SettingsView.swift ios/CardlinkDemo.xcodeproj/project.pbxproj ios/CardlinkDemoDev.xcodeproj/project.pbxproj scripts/test-native-customer-demo-safety.sh scripts/test-shared-ios-healthcard-storage.sh
  git commit -m "build(ios): adopt shared health-card group"
  ```

---

## Task 4A: Preserve Unreadable Legacy Cache Records

**Files:**

- Modify: `../scoop-nfc-sdk/packages/sdk/shared/src/commonMain/kotlin/de/scoopsoftware/nfc/cache/FileCacheProvider.kt`
- Modify: `../scoop-nfc-sdk/packages/sdk/shared/src/commonMain/kotlin/de/scoopsoftware/nfc/cache/SharedFileCacheProvider.kt`
- Modify: `../scoop-nfc-sdk/packages/sdk/shared/src/commonTest/kotlin/de/scoopsoftware/nfc/cache/FileCacheProviderTest.kt`
- Modify: `ios/CardlinkSample/CardlinkSample/HealthCardCacheMigrator.swift`
- Modify: `ios/CardlinkDemoTests/HealthCardCacheMigratorTests.swift`
- Modify: `scripts/test-shared-ios-healthcard-storage.sh`

**Interfaces:**

- Produces: public NFC SDK enum `InvalidCacheEntryPolicy` with `REMOVE` and
  `PRESERVE`, plus source-compatible `FileCacheProvider` and
  `SharedFileCacheProvider` constructors accepting that policy.
- Consumes: the two legacy source factories in `DemoNfcCacheProviderFactory`;
  canonical providers continue using the existing default behavior.

- [x] **Step 1: Add failing NFC SDK behavior tests**

  Extend `FileCacheProviderTest` with real `FileCacheProvider` tests proving:

  - `InvalidCacheEntryPolicy.PRESERVE` returns `NotCached` for an invalid data
    record without deleting the encrypted file;
  - `PRESERVE` excludes a card with an invalid CAN from `getAll()` without
    deleting `_CAN`;
  - the default constructor retains the existing deletion behavior.

- [x] **Step 2: Confirm the new tests are red**

  ```bash
  cd ../scoop-nfc-sdk
  ./gradlew :packages:sdk:shared:iosSimulatorArm64Test \
    --tests 'de.scoopsoftware.nfc.cache.FileCacheProviderTest'
  ```

  Expected: compilation fails because `InvalidCacheEntryPolicy` and the new
  constructor argument do not exist.

- [x] **Step 3: Implement the minimal public SDK policy**

  Add:

  ```kotlin
  public enum class InvalidCacheEntryPolicy {
      REMOVE,
      PRESERVE,
  }
  ```

  Existing constructors default to `REMOVE`. Add overloads accepting the
  policy without removing or changing any existing signature. In `get()` and
  `getCan()`, delete after `InvalidCacheEntryException` only for `REMOVE`;
  both policies return the same cache miss result. Forward the policy through
  `SharedFileCacheProvider`.

- [x] **Step 4: Confirm focused and complete NFC SDK tests are green**

  ```bash
  cd ../scoop-nfc-sdk
  ./gradlew :packages:sdk:shared:allTests
  ```

  Then build the iOS XCFramework and confirm the Swift header exposes the new
  enum and policy-bearing constructors while the old constructors remain.

- [x] **Step 5: Select preserve mode only for legacy demo sources**

  Pass `.preserve` from `DemoNfcCacheProviderFactory.makeLegacy()` and
  `makeLegacyAppPrivate()`. Keep `makeCanonical()` and every normal Cardlink,
  PoPP, settings, upload, and known-card provider on the default policy. Add a
  repository guard for the two explicit legacy selections.

- [x] **Step 6: Run complete demo verification and device acceptance**

  Run both repository guards, project sync, all native XCTest cases, and the
  signed DevSDK build on iPhone 13 Pro. Install it and verify card persistence,
  NFC read, cancellation back to setup, and wrong-CAN-then-correct-CAN.

- [ ] **Step 7: Review and checkpoint**

  Do not publish NFC 4.0.4. After explicit approval, commit the NFC SDK and
  demo changes separately with Conventional Commit messages.

---

## Task 5: Add the Demo-Only Flutter Shared-Keychain Plugin

**Files:**

- Modify: `flutter/demo_core/pubspec.yaml`
- Modify: `flutter/demo_core/lib/demo_core.dart`
- Create: `flutter/demo_core/lib/src/demo_shared_storage.dart`
- Create: `flutter/demo_core/ios/demo_core/Package.swift`
- Create: `flutter/demo_core/ios/demo_core/Sources/demo_core/DemoSharedStoragePlugin.swift`
- Create: `flutter/demo_core/test/demo_shared_storage_test.dart`

- [ ] **Step 1: Write failing Dart MethodChannel contract tests**

  Define the public demo-only Dart boundary:

  ```dart
  enum DemoSharedCredentialKind {
    keycloak,
    rocketChat,
  }

  final class DemoInternetCredential {
    const DemoInternetCredential({
      required this.baseUrl,
      required this.username,
      required this.password,
    });

    final String baseUrl;
    final String username;
    final String password;
  }

  abstract interface class DemoSharedStorage {
    Future<DemoInternetCredential?> read(DemoSharedCredentialKind kind);
    Future<void> write(
      DemoSharedCredentialKind kind,
      DemoInternetCredential credential,
    );
  }
  ```

  The channel is `de.scoopsoftware.cardlink.demo/shared-storage`, with methods `readCredential` and `writeCredential`; arguments use the exact kind names `keycloak` and `rocketChat`. Test complete maps, absent records, malformed or partial native replies, invalid URLs, and `PlatformException` propagation. Use `TestDefaultBinaryMessengerBinding` and never put real credentials in fixtures.

- [ ] **Step 2: Confirm red tests**

  ```bash
  cd flutter/demo_core
  flutter test test/demo_shared_storage_test.dart
  ```

- [ ] **Step 3: Implement the Dart adapter and SwiftPM package**

  Register `demo_core` as an iOS Flutter plugin in `pubspec.yaml`. Use the same SwiftPM layout as `scoop_nfc`:

  ```text
  ios/demo_core/Package.swift
  ios/demo_core/Sources/demo_core/DemoSharedStoragePlugin.swift
  ```

  `Package.swift` depends only on Flutter's generated `FlutterFramework` package and links `Security`. `DemoSharedStoragePlugin` reads `ScoopKeychainAccessGroup` from `Bundle.main`, rejects missing/unexpanded values, and uses the exact Internet-password labels, URL mapping, and accessibility from Task 1. `writeCredential` writes URL attributes, account, and password in one item, performs a complete read-back comparison, and returns `FlutterError` on any failure; error details contain no URL, value, or query.

- [ ] **Step 4: Confirm tests and SwiftPM discovery**

  Run the Dart test again and:

  ```bash
  cd flutter/cardlink_demo
  flutter pub get
  grep -F '"name":"demo_core"' .flutter-plugins-dependencies
  ```

  Expected: `demo_core` appears as an iOS `native_build` plugin and SwiftPM remains enabled.

- [ ] **Step 5: Review and checkpoint**

  Confirm no SDK or bridge repository changed. After explicit approval:

  ```bash
  git add flutter/demo_core
  git commit -m "feat(flutter): add shared iOS demo storage"
  ```

---

## Task 6: Move Flutter Credentials Out of Shared Preferences

**Files:**

- Modify: `flutter/demo_core/pubspec.yaml`
- Modify: `flutter/demo_core/lib/src/demo_settings.dart`
- Create: `flutter/demo_core/lib/src/demo_settings_lifecycle.dart`
- Modify: `flutter/demo_core/lib/demo_core.dart`
- Modify: `flutter/cardlink_demo/lib/screens/settings_screen.dart`
- Modify: `flutter/cardlink_demo/lib/main.dart`
- Modify: `flutter/full_demo/lib/main.dart`
- Create: `flutter/demo_core/test/demo_settings_test.dart`
- Create: `flutter/demo_core/test/demo_settings_lifecycle_test.dart`

- [ ] **Step 1: Write failing settings persistence tests**

  With an injected fake `DemoSharedStorage`, cover:

  - iOS loads Keycloak base URL, username, and password from the shared store;
  - iOS never reads or writes `oauthBaseUrl`/`username`/`password` via `SharedPreferences`;
  - WebSocket/REST URLs, switches, history, and timings remain app-private;
  - Android retains app-private username/password persistence and never invokes the iOS adapter;
  - a failed shared write becomes a non-secret observable settings error;
  - `reloadSharedCredentials()` refreshes the complete record and notifies listeners;
  - resumed lifecycle invokes exactly one reload.

  Use platform injection/default-target override; remove the direct `dart:io Platform` dependency from `DemoSettings` so tests are deterministic.

- [ ] **Step 2: Confirm the tests fail**

  ```bash
  cd flutter/demo_core
  flutter test test/demo_settings_test.dart test/demo_settings_lifecycle_test.dart
  ```

- [ ] **Step 3: Split secret and app-private persistence**

  `DemoSettings.load()` always creates ordinary app-private `SharedPreferencesAsync`; it does not use `SharedPreferencesAsyncFoundationOptions` or an App Group suite. On iOS only, it loads Cardlink values from `DemoSharedStorage`.

  Remove the now-unneeded direct `shared_preferences_foundation` dependency from `demo_core`; `shared_preferences` remains the only preferences API dependency.

  Add one async complete-record setter that surfaces failures:

  ```dart
  Future<void> setKeycloakCredential({
    required String baseUrl,
    required String username,
    required String password,
  })
  Future<void> reloadSharedCredentials()
  Object? get credentialPersistenceError
  ```

  Serialize complete-record writes so an older completion cannot overwrite a newer edit. Keep the existing synchronous `update` only for app-private settings. The fixed OAuth client ID is `cardlink-app`. In `SettingsScreen`, save the Keycloak URL/username/password together and render a short error message such as `Credentials could not be shared on this device.` without including native details or entered values. When the shared OAuth URL differs from the SDK default, construct a custom Cardlink environment with that URL, the fixed client ID, and the current default or app-private WebSocket/REST endpoints.

  The adapter already supports the complete RocketChat record for schema parity; do not add a Flutter RocketChat screen.

- [ ] **Step 4: Refresh credentials on app resume**

  `DemoSettingsLifecycle` is a small `WidgetsBindingObserver` wrapper. It calls `reloadSharedCredentials()` on `AppLifecycleState.resumed`. Wrap each demo's root `Scaffold`/home with it rather than duplicating lifecycle code in the two apps.

- [ ] **Step 5: Run Dart tests and analyzers**

  ```bash
  cd flutter/demo_core
  flutter test
  flutter analyze
  cd ../cardlink_demo
  flutter analyze
  cd ../full_demo
  flutter analyze
  ```

- [ ] **Step 6: Review and checkpoint**

  Search for forbidden iOS shared preference credentials:

  ```bash
  grep -R -nE "SharedPreferencesAsyncFoundationOptions|setString\('(oauthBaseUrl|username|password)'" flutter/demo_core/lib
  ```

  Expected: no matches. After explicit approval:

  ```bash
  git add flutter/demo_core flutter/cardlink_demo/lib/screens/settings_screen.dart flutter/cardlink_demo/lib/main.dart flutter/full_demo/lib/main.dart
  git commit -m "feat(flutter): share iOS demo credentials"
  ```

---

## Task 7: Point Both Flutter Runners at the Canonical Health-Card Group

**Files:**

- Modify: `flutter/cardlink_demo/ios/Runner/Runner.entitlements`
- Modify: `flutter/cardlink_demo/ios/Runner/Info.plist`
- Modify: `flutter/full_demo/ios/Runner/Runner.entitlements`
- Modify: `flutter/full_demo/ios/Runner/Info.plist`
- Modify: `scripts/test-shared-ios-healthcard-storage.sh`
- Modify: `scripts/test-ios-swiftpm-only.sh`

- [ ] **Step 1: Extend the guard and confirm it fails**

  Require both Flutter Runners to contain exactly one App Group and one Keychain group, both canonical. Require both `Info.plist` files to expose the canonical values. Require the `demo_core` SwiftPM package and forbid CocoaPods integration.

  Run:

  ```bash
  bash scripts/test-shared-ios-healthcard-storage.sh
  bash scripts/test-ios-swiftpm-only.sh
  ```

  Expected: the healthcard guard fails because both Runners still use `group.de.scoopsoftware.cardlink.demo`.

- [ ] **Step 2: Update only Flutter Runner configuration**

  In both apps, replace the old group with:

  ```text
  ScoopAppGroupId = group.de.scoopsoftware.nfc.healthcard
  ScoopKeychainAccessGroup = $(AppIdentifierPrefix)group.de.scoopsoftware.nfc.healthcard
  ```

  Do not add the legacy group to either Flutter target and do not alter bundle IDs or Apple Team configuration.

- [ ] **Step 3: Run repository gates**

  ```bash
  bash scripts/test-shared-ios-healthcard-storage.sh
  bash scripts/test-ios-swiftpm-only.sh
  bash scripts/test-ios-swiftpm-only-regressions.sh
  bash scripts/test-native-customer-demo-safety.sh
  ```

- [ ] **Step 4: Build both Flutter apps for the physical device**

  ```bash
  ./scripts/run-local-flutter.sh cardlink_demo run --debug -d 00008110-000111CA11A0401E
  ./scripts/run-local-flutter.sh full_demo run --debug -d 00008110-000111CA11A0401E
  ```

  Complete and stop each interactive run before starting the next app. Do not build a simulator substitute. A provisioning failure for the canonical group is an external blocker to report.

- [ ] **Step 5: Review and checkpoint**

  Confirm Flutter has no legacy entitlement. After explicit approval:

  ```bash
  git add flutter/cardlink_demo/ios/Runner/Runner.entitlements flutter/cardlink_demo/ios/Runner/Info.plist flutter/full_demo/ios/Runner/Runner.entitlements flutter/full_demo/ios/Runner/Info.plist scripts/test-shared-ios-healthcard-storage.sh scripts/test-ios-swiftpm-only.sh
  git commit -m "build(ios): share health-card group across demos"
  ```

---

## Task 8: Cross-App Physical Acceptance and Final Review

**Files:**

- Modify only if a verified defect is found.

- [ ] **Step 1: Run the complete automated suite**

  ```bash
  bash scripts/test-shared-ios-healthcard-storage.sh
  bash scripts/test-ios-swiftpm-only.sh
  bash scripts/test-ios-swiftpm-only-regressions.sh
  bash scripts/test-native-customer-demo-safety.sh
  ruby scripts/sync-ios-projects.rb --check
  xcodebuild -project ios/CardlinkDemoDev.xcodeproj -scheme CardlinkDemoDev -destination 'platform=iOS,id=00008110-000111CA11A0401E' test
  cd flutter/demo_core && flutter test && flutter analyze
  cd ../cardlink_demo && flutter analyze
  cd ../full_demo && flutter analyze
  ```

- [ ] **Step 2: Install all three apps without clearing native data**

  Install/launch native `CardlinkDemo`, Flutter `cardlink_demo`, and Flutter `full_demo` on `00008110-000111CA11A0401E`. Do not uninstall the native demo before migration acceptance; uninstalling would invalidate app-private migration coverage.

- [ ] **Step 3: Execute the cross-app credential matrix**

  Verify:

  1. legacy native Cardlink/PoPP and RocketChat credentials plus their resolved base URLs appear after upgrade;
  2. Flutter `full_demo` sees the Keycloak URL and credentials without re-entry;
  3. editing Keycloak URL or credentials in Flutter is visible and used in native after foregrounding;
  4. editing them in native is visible and used in both Flutter apps after foregrounding;
  5. no OAuth/session, WebSocket/REST URL, RocketChat channel, history, or timing state crosses apps;
  6. the complete RocketChat record remains available to native and through the adapter contract, without adding Flutter UI.

- [ ] **Step 4: Execute the cache and NFC matrix**

  Verify known cards and cached card data are visible in both Cardlink flows after native migration. On native and Flutter, test successful read and cancel; on native test wrong CAN followed by correct CAN. Confirm a second native launch neither duplicates nor overwrites canonical cache entries.

- [ ] **Step 5: Inspect release artifacts and source diffs**

  Run:

  ```bash
  git diff --check
  git status --short
  git diff --stat 8e87828..HEAD
  ```

  Manually confirm:

  - no Team ID hard-coded in new source;
  - no credentials/cache data in logs or tests;
  - no Flutter CocoaPods files;
  - no SDK/bridge public API changes;
  - native legacy data and groups remain for rollback;
  - all changed PBX files still parse with `xcodebuild -list`.

- [ ] **Step 6: Request code review before integration**

  Use `superpowers:requesting-code-review` or `code-review-expert` against the complete diff. Fix only substantiated findings, rerun affected gates, and create additional Conventional Commits only after explicit user approval.

- [ ] **Step 7: Hand off without publishing**

  Report commit IDs, automated results, physical acceptance results, and any Apple provisioning dependency. Do not merge, push, tag, publish packages, or create a release until the user explicitly requests that separate action.
