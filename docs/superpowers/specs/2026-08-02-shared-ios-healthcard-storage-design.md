# Shared iOS Health-Card Storage Design

**Date:** 2026-08-02
**Status:** Approved for implementation planning

## Goal

The native Cardlink iOS demo, the Flutter Cardlink demo, and the Flutter full
demo shall share the health-card cache and the two explicitly selected sets of
demo credentials. A tester enters credentials once and can reuse them in every
demo installed on the same iPhone.

The shared data is limited to:

- the complete encrypted NFC health-card cache, including ICCSN, CAN, and
  cached card files;
- the Cardlink/PoPP development username and password;
- the RocketChat username and password.

OAuth tokens, Cardlink sessions, CAN values stored outside the SDK cache,
environment URLs, feature switches, scan history, and timing data remain
private to each app.

## Canonical Apple Groups

All three apps use this App Group for the SDK cache:

```text
group.de.scoopsoftware.nfc.healthcard
```

They use the corresponding fully qualified Keychain access group for shared
cache keys and demo credentials:

```text
$(AppIdentifierPrefix)group.de.scoopsoftware.nfc.healthcard
```

The runtime value is injected through each app's `Info.plist`; source code must
not hard-code an Apple Team ID. Every participating App ID and provisioning
profile must belong to the same Apple Developer team. The native target
authorizes both groups during migration; the Flutter targets authorize only the
canonical group.

The native demo temporarily retains its legacy App Group and Keychain group so
it can migrate an already deployed installation:

```text
group.de.scoopsoftware.nfc
$(AppIdentifierPrefix)group.de.scoopsoftware.nfc
```

Neither Flutter app needs the legacy groups because no Flutter demo using the
old group has been distributed.

## Credential Storage

Credentials use a shared Keychain store, not App Group `UserDefaults` or a
shared plaintext file. The canonical generic-password service is:

```text
de.scoopsoftware.cardlink.demo.shared
```

The schema consists of four stable accounts:

```text
cardlink.username
cardlink.password
rocketchat.username
rocketchat.password
```

Items use the canonical Keychain access group and
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. They are available only while
the device is unlocked, never synchronize through iCloud Keychain, and do not
migrate to another device.

The native demo receives a `DemoSharedCredentialStore` and changes its existing
Cardlink/PoPP and RocketChat helpers to read and write this schema. The Flutter
`demo_core` package becomes the owner of a small, demo-only iOS platform adapter
named `DemoSharedStoragePlugin`. Its MethodChannel API reads and writes the same
four accounts. This keeps demo credential handling out of the NFC, Cardlink,
PoPP, and Flutter bridge product APIs.

On Android, the existing app-private demo settings remain unchanged. On iOS,
`DemoSettings` stops persisting username and password through
`shared_preferences` and delegates those values to the shared Keychain adapter.
All non-secret Flutter settings remain app-private. The adapter also exposes
the RocketChat pair even though adding or redesigning a Flutter RocketChat UI is
outside this change.

## Native Credential Migration

Only the native demo migrates legacy credentials. Migration runs before the
root UI loads and follows these rules independently for each credential pair:

1. Read the canonical shared Keychain pair.
2. If both canonical values are present, keep them unchanged.
3. Otherwise read the native demo's existing app-private Cardlink/PoPP or
   RocketChat Keychain pair.
4. Write a complete pair to the shared Keychain; never migrate a half pair.
5. Read the new pair back and compare it before marking that pair migrated.

A failed read, write, entitlement check, or read-back leaves the legacy item
and migration marker untouched. Migration is idempotent and safe to retry on
the next launch. The existing app-private entries remain during the transition
release as rollback data, but all normal reads and writes use the canonical
store after successful migration.

If the canonical and legacy values differ, the canonical values win. This
prevents an older installation from overwriting credentials already changed in
another participating demo.

## Health-Card Cache Migration

The native demo currently stores its encrypted SDK cache in
`group.de.scoopsoftware.nfc`. Its next launch migrates that cache to
`group.de.scoopsoftware.nfc.healthcard` before starting a Cardlink or PoPP flow.

Migration uses two public `SharedFileCacheProvider` instances and the public
`CacheProvider` operations. It must not copy encrypted files directly because
cache authentication binds ciphertext to its storage context.

For every source ICCSN, migration:

1. enumerates the source card with `getAll()`;
2. copies its CAN with `getCan()` and `saveCan()` only when the destination has
   no CAN;
3. enumerates cached files with `getCachedFiles()`;
4. reads each source entry and writes either its bytes or its not-on-card marker
   to the destination only when the destination entry is not cached;
5. reads all copied values back from the destination;
6. records a native app-private migration marker only after full verification.

Existing destination entries always win. The old cache remains intact for the
transition release and is no longer used by normal flows. The public SDK and
Flutter bridge APIs do not gain demo-specific migration methods.

Both Flutter apps point their existing `ScoopAppGroupId` and
`ScoopKeychainAccessGroup` configuration directly at the canonical group.
Their first card flow therefore sees the cache produced or migrated by the
native demo without a Flutter-side migration.

## Entitlements and Configuration

The following targets are in scope:

- native `CardlinkDemo` and its development project/configuration;
- Flutter `cardlink_demo` Runner;
- Flutter `full_demo` Runner.

The native target declares the legacy and canonical App/Keychain groups during
the migration window. Each Flutter Runner declares only the canonical groups.
All normal SDK cache configuration points at the canonical values.

Repository guards verify that entitlements, `Info.plist` values, and Keychain
schema constants agree. A future cleanup release may remove the native legacy
groups only after the migration version has been distributed and accepted.

## Error Handling

Storage errors never crash a demo and never erase a valid destination value.
The UI continues with empty credentials when neither canonical nor legacy data
is available. Migration failures are reported through a non-secret diagnostic
message; credential values, CANs, cache contents, and Keychain query payloads
must not be logged.

Normal shared-store writes return an explicit success or error to Dart so the
Flutter UI cannot silently claim that credentials were saved. Reads are
refreshed when an app becomes active, allowing changes made in another demo to
appear without reinstalling or restarting the process.

## Verification

Automated verification covers:

- exact canonical and transitional entitlement membership;
- matching `Info.plist` App Group and Keychain group values;
- identical service/account schema in native and Flutter implementations;
- no iOS username or password in Flutter `shared_preferences`;
- canonical-values-win behavior;
- complete-pair migration and rejection of partial pairs;
- failed-write/read-back retry behavior;
- cache migration for bytes, not-on-card markers, CANs, and existing
  destination values;
- idempotent repeated migration;
- Dart MethodChannel success and failure contracts;
- existing iOS SwiftPM-only and Android regression gates.

Physical acceptance uses the iPhone 13 Pro:

1. install the current native demo and create legacy credentials/cache data;
2. install the migration build and confirm the native demo still sees them;
3. install Flutter `full_demo` and confirm credentials and known cards appear;
4. change the Cardlink/PoPP credentials in Flutter and confirm the native demo
   reloads the new values after becoming active;
5. change credentials in the native demo and confirm both Flutter demos reload
   them;
6. confirm OAuth/session state, settings, history, and timings remain separate;
7. confirm NFC read, cancel, and wrong-CAN-then-correct-CAN flows still work.

## Out of Scope

- sharing OAuth access, refresh, or ID tokens;
- sharing Cardlink session identifiers;
- sharing settings, URLs, trace switches, history, or timing records;
- synchronizing data between different devices or Apple teams;
- adding a new Flutter RocketChat user interface;
- deleting the legacy native groups or rollback data in this release;
- changing customer-facing SDK storage policy.
