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
- the Keycloak base URL plus Cardlink/PoPP development username and password;
- the RocketChat base URL, username, and password.

OAuth tokens, Cardlink sessions, CAN values stored outside the SDK cache,
WebSocket and REST environment URLs, RocketChat channels, feature switches,
scan history, and timing data remain private to each app.

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

Credentials use shared `kSecClassInternetPassword` items, not App Group
`UserDefaults` or a shared plaintext file. The schema consists of two stable
labels:

```text
de.scoopsoftware.cardlink.demo.keycloak
de.scoopsoftware.cardlink.demo.rocketchat
```

Each item stores one complete Internet credential: the normalized base URL in
the Internet-password server/protocol/port/path attributes, the username in
`kSecAttrAccount`, and the password in `kSecValueData`. The fixed Keycloak
OAuth client ID `cardlink-app` remains application configuration and is not
stored in the Keychain. Items use the canonical Keychain access group and
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. They are available only while
the device is unlocked, never synchronize through iCloud Keychain, and do not
migrate to another device.

The stable label and explicit access group locate the existing item even when
its URL or username changes. A save updates the URL attributes, account, and
password in one `SecItemUpdate` and then compares a complete read-back. The
first `SecItemAdd` likewise either creates the complete item or creates
nothing. Invalid or incomplete records are rejected without replacing the
last valid item.

The native demo receives a `DemoSharedCredentialStore` and changes its existing
Cardlink/PoPP and RocketChat helpers to read and write this schema. The Flutter
`demo_core` package becomes the owner of a small, demo-only iOS platform adapter
named `DemoSharedStoragePlugin`. Its MethodChannel API reads and writes the same
two Internet credentials. This keeps demo credential handling out of the NFC,
Cardlink, PoPP, and Flutter bridge product APIs.

On Android, the existing app-private demo settings remain unchanged. On iOS,
`DemoSettings` stops persisting the Keycloak base URL, username, and password
through `shared_preferences` and delegates those values to the shared Keychain
adapter. WebSocket and REST URLs remain app-private. The adapter also exposes
the complete RocketChat credential even though adding or redesigning a Flutter
RocketChat UI is outside this change.

The native flow setup presents Keycloak base URL, username, and password
together. Both Cardlink and PoPP token acquisition use the shared URL. A URL
changed in a Flutter demo therefore also takes effect in the native demo after
it becomes active. RocketChat settings present and save its base URL, username,
and password as one record; its channel and trace switch remain app-private.

## Native Credential Migration

Only the native demo migrates legacy credentials. Migration runs before the
root UI loads and follows these rules independently for each Internet
credential:

1. Read the canonical shared Keychain item.
2. If its URL, username, and password are complete and valid, keep it unchanged.
3. Otherwise read the native demo's existing app-private Cardlink/PoPP or
   RocketChat credentials.
4. Combine Cardlink/PoPP credentials with the SDK's fixed Dev Keycloak base
   URL. Combine RocketChat credentials with the existing app-private
   `rcServerUrl`. If any of the three values is absent, do not migrate.
5. Write one complete Internet-password item and compare a complete read-back
   before marking that item migrated.

A failed read, write, entitlement check, or read-back leaves the legacy item
and migration marker untouched. Migration is idempotent and safe to retry on
the next launch. The existing app-private entries remain during the transition
release as rollback data, but all normal reads and writes use the canonical
store after successful migration.

If the canonical and legacy values differ, the canonical values win. This
prevents an older installation from overwriting credentials already changed in
another participating demo.

## Health-Card Cache Migration

Historical native demo builds used two possible encrypted SDK cache locations:
`group.de.scoopsoftware.nfc` when the App Group provider could be created, and
the app-private encrypted `FileCacheProvider` as a fallback. The next launch
migrates both sources, in that order, to
`group.de.scoopsoftware.nfc.healthcard` before starting a Cardlink or PoPP flow.

Migration uses the public `SharedFileCacheProvider` for the shared source and
destination, the public encrypted `FileCacheProvider` for the app-private
source, and only public `CacheProvider` operations. It must not copy encrypted
files directly because cache authentication binds ciphertext to its storage
context.

Legacy source providers use the NFC SDK's public invalid-entry policy in
`preserve` mode. Existing consumers and the canonical destination retain the
default `remove` behavior. An unreadable legacy record is therefore ignored
for migration but remains byte-for-byte untouched for rollback or later
recovery; the demo never implements private filesystem access for this.

For every source ICCSN, migration:

1. enumerates the source card with `getAll()`;
2. copies its CAN with `getCan()` and `saveCan()` only when the destination has
   no CAN;
3. enumerates cached files with `getCachedFiles()`;
4. reads each source entry and writes either its bytes or its not-on-card marker
   to the destination only when the destination entry is not cached;
5. reads all copied values back from the destination;
6. records the source-specific native app-private migration marker only after
   full verification.

The legacy shared and legacy app-private sources have independent markers. A
previously completed shared-group migration therefore never suppresses the
app-private fallback migration discovered in older installations. Failure in
one source likewise does not prevent attempting the other source; bootstrap
still reports a generic failure so the unsuccessful source remains retryable.

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

Storage errors never crash a demo and never erase a valid destination item.
The UI continues with the fixed Dev Keycloak URL and empty credentials when
neither canonical nor legacy data is available. Invalid URLs are rejected
before any Keychain mutation. Migration failures are reported through a
non-secret diagnostic message; URLs, credential values, CANs, cache contents,
and Keychain query payloads must not be logged.

Normal shared-store writes return an explicit success or error to Dart so the
Flutter UI cannot silently claim that credentials were saved. Reads are
refreshed when an app becomes active, allowing changes made in another demo to
appear without reinstalling or restarting the process.

## Verification

Automated verification covers:

- exact canonical and transitional entitlement membership;
- matching `Info.plist` App Group and Keychain group values;
- identical Internet-password labels and URL mapping in native and Flutter
  implementations;
- no iOS Keycloak URL, username, or password in Flutter `shared_preferences`;
- canonical-values-win behavior;
- complete-record migration and rejection of partial or invalid records;
- failed-write/read-back retry behavior;
- cache migration for bytes, not-on-card markers, CANs, and existing
  destination values;
- idempotent repeated migration;
- Dart MethodChannel success and failure contracts;
- existing iOS SwiftPM-only and Android regression gates.

Physical acceptance uses the iPhone 13 Pro:

1. install the current native demo and create legacy credentials/cache data;
2. install the migration build and confirm the native demo still sees them;
3. install Flutter `full_demo` and confirm Keycloak URL, credentials, and known
   cards appear;
4. change the Keycloak URL or Cardlink/PoPP credentials in Flutter and confirm
   the native demo reloads and uses them after becoming active;
5. change the Keycloak URL or credentials in the native demo and confirm both
   Flutter demos reload them;
6. confirm OAuth/session state, WebSocket/REST URLs, RocketChat channel,
   history, and timings remain separate;
7. confirm NFC read, cancel, and wrong-CAN-then-correct-CAN flows still work.

## Out of Scope

- sharing OAuth access, refresh, or ID tokens;
- sharing Cardlink session identifiers;
- sharing WebSocket/REST URLs, RocketChat channel, other settings, trace
  switches, history, or timing records;
- synchronizing data between different devices or Apple teams;
- adding a new Flutter RocketChat user interface;
- deleting the legacy native groups or rollback data in this release;
- changing customer-facing SDK storage policy.
