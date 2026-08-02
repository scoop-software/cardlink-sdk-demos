#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

failures=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_text() {
  local file="$1" needle="$2" description="$3"
  [[ -f "$file" ]] || { fail "$description (missing $file)"; return; }
  grep -Fq -- "$needle" "$file" || fail "$description"
}

forbid_text() {
  local file="$1" needle="$2" description="$3"
  [[ -f "$file" ]] || { fail "$description (missing $file)"; return; }
  if grep -Fq -- "$needle" "$file"; then
    fail "$description"
  fi
}

require_count() {
  local file="$1" needle="$2" minimum="$3" description="$4"
  [[ -f "$file" ]] || { fail "$description (missing $file)"; return; }
  local actual
  actual="$(grep -Fc -- "$needle" "$file" || true)"
  if (( actual < minimum )); then
    fail "$description"
  fi
}

require_exact_count() {
  local file="$1" needle="$2" expected="$3" description="$4"
  [[ -f "$file" ]] || { fail "$description (missing $file)"; return; }
  local actual
  actual="$(grep -Fc -- "$needle" "$file" || true)"
  if (( actual != expected )); then
    fail "$description (expected $expected, found $actual)"
  fi
}

require_plist_array_value() {
  local file="$1" key="$2" value="$3" description="$4"
  [[ -f "$file" ]] || { fail "$description (missing $file)"; return; }
  if ! /usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null | grep -Fq -- "$value"; then
    fail "$description"
  fi
}

require_plist_value() {
  local file="$1" key="$2" value="$3" description="$4"
  [[ -f "$file" ]] || { fail "$description (missing $file)"; return; }
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null || true)"
  [[ "$actual" == "$value" ]] || fail "$description"
}

entitlements=ios/CardlinkSample/CardlinkSample.entitlements
info_plist=ios/CardlinkSample/CardlinkSample/Info.plist
customer_project=ios/CardlinkDemo.xcodeproj/project.pbxproj
dev_project=ios/CardlinkDemoDev.xcodeproj/project.pbxproj
credentials=ios/CardlinkSample/CardlinkSample/DemoSharedCredentialStore.swift
cache_migration=ios/CardlinkSample/CardlinkSample/HealthCardCacheMigrator.swift
app=ios/CardlinkSample/CardlinkSample/CardlinkSampleApp.swift

canonical_app_group='group.de.scoopsoftware.nfc.healthcard'
legacy_app_group='group.de.scoopsoftware.nfc'
canonical_keychain_group='$(AppIdentifierPrefix)group.de.scoopsoftware.nfc.healthcard'
legacy_keychain_group='$(AppIdentifierPrefix)group.de.scoopsoftware.nfc'

# Native builds retain the old groups only for one-way migration and rollback.
require_plist_array_value "$entitlements" 'com.apple.security.application-groups' "$canonical_app_group" 'Native entitlements must authorize the canonical App Group.'
require_plist_array_value "$entitlements" 'com.apple.security.application-groups' "$legacy_app_group" 'Native entitlements must retain the legacy App Group for migration.'
require_plist_array_value "$entitlements" 'keychain-access-groups' "$canonical_keychain_group" 'Native entitlements must authorize the canonical Keychain group.'
require_plist_array_value "$entitlements" 'keychain-access-groups' "$legacy_keychain_group" 'Native entitlements must retain the legacy Keychain group for migration.'

# Info.plist is the single runtime boundary between signing configuration and Swift.
require_plist_value "$info_plist" 'ScoopAppGroupId' '$(SCOOP_APP_GROUP_ID)' 'Info.plist must expose the canonical App Group build setting.'
require_plist_value "$info_plist" 'ScoopKeychainAccessGroup' '$(SCOOP_KEYCHAIN_ACCESS_GROUP)' 'Info.plist must expose the canonical Keychain group build setting.'
require_plist_value "$info_plist" 'ScoopLegacyAppGroupId' '$(SCOOP_LEGACY_APP_GROUP_ID)' 'Info.plist must expose the legacy App Group build setting.'
require_plist_value "$info_plist" 'ScoopLegacyKeychainAccessGroup' '$(SCOOP_LEGACY_KEYCHAIN_ACCESS_GROUP)' 'Info.plist must expose the legacy Keychain group build setting.'

for project in "$customer_project" "$dev_project"; do
  require_count "$project" 'SCOOP_APP_GROUP_ID = "group.de.scoopsoftware.nfc.healthcard";' 2 "$project must select the canonical App Group in Debug and Release."
  require_count "$project" 'SCOOP_KEYCHAIN_ACCESS_GROUP = "$(AppIdentifierPrefix)group.de.scoopsoftware.nfc.healthcard";' 2 "$project must select the canonical Keychain group in Debug and Release."
  require_count "$project" 'SCOOP_LEGACY_APP_GROUP_ID = "group.de.scoopsoftware.nfc";' 2 "$project must separately expose the legacy App Group in Debug and Release."
  require_count "$project" 'SCOOP_LEGACY_KEYCHAIN_ACCESS_GROUP = "$(AppIdentifierPrefix)group.de.scoopsoftware.nfc";' 2 "$project must separately expose the legacy Keychain group in Debug and Release."
  forbid_text "$project" 'SCOOP_KEYCHAIN_ACCESS_GROUP = "845RN736HR.' "$project must not hard-code a development-team prefix into the canonical Keychain group."
  forbid_text "$project" 'SCOOP_LEGACY_KEYCHAIN_ACCESS_GROUP = "845RN736HR.' "$project must not hard-code a development-team prefix into the legacy Keychain group."
done

# The internet-password records are stable across native and Flutter demos.
require_text "$credentials" 'static let keycloakLabel = "de.scoopsoftware.cardlink.demo.keycloak"' 'The Keycloak credential label must stay stable.'
require_text "$credentials" 'static let rocketChatLabel = "de.scoopsoftware.cardlink.demo.rocketchat"' 'The RocketChat credential label must stay stable.'
require_text "$credentials" 'static let oauthClientId = "cardlink-app"' 'The fixed OAuth client ID must stay stable.'

# Bootstrap order and runtime validation are product behavior, not optional sample code.
require_text "$cache_migration" 'struct DemoCacheConfig' 'Shared cache configuration must live with the migration code.'
require_text "$cache_migration" 'case invalidConfiguration' 'Empty or unresolved cache configuration must be rejected.'
require_text "$cache_migration" 'static func makeLegacyAppPrivate()' 'Migration must include the historical app-private cache fallback.'
require_exact_count "$cache_migration" 'invalidCacheEntryPolicy: .preserve' 2 'Both legacy cache readers must preserve unreadable source records.'
require_text "$cache_migration" 'case legacyAppPrivate = "demo.shared-storage.cache.app-private.v1"' 'The app-private cache source must have an independent migration marker.'
require_text "$cache_migration" 'static func migrateCaches(' 'Bootstrap must migrate both legacy cache sources before normal operation.'
require_text "$app" 'DemoSharedStorageBootstrap.run()' 'The app must run the combined shared-storage bootstrap before ContentView.'
require_text "$app" 'sharedStorageBootstrapComplete' 'ContentView must wait for shared-storage bootstrap completion.'

# Normal operation must never silently write a second per-app cache.
for file in ios/CardlinkSample/CardlinkSample/*.swift; do
  forbid_text "$file" '?? FileCacheProvider(securityLevel: .encrypted)' "$file must not silently fall back to a per-app persistent cache."
  forbid_text "$file" '?? ScoopPoppSDK.FileCacheProvider(securityLevel: .encrypted)' "$file must not silently fall back to a PoPP per-app persistent cache."
done
forbid_text ios/CardlinkSample/CardlinkSample/SettingsView.swift 'enum DemoCacheConfig' 'Cache configuration must not remain coupled to SettingsView.'

# Canonical secrets are Keychain-only. UserDefaults may contain migration markers
# and the pre-existing legacy values only while the one-way migration is supported.
forbid_text "$credentials" 'defaults.set(credential.username' 'Canonical usernames must not be written to UserDefaults.'
forbid_text "$credentials" 'defaults.set(credential.password' 'Canonical passwords must not be written to UserDefaults.'
forbid_text "$credentials" 'defaults.set(credential.baseURL' 'Canonical credential URLs must not be written to UserDefaults.'

if (( failures > 0 )); then
  printf '\nShared iOS health-card storage checks failed: %d\n' "$failures" >&2
  exit 1
fi

printf 'Shared iOS health-card storage checks passed.\n'
