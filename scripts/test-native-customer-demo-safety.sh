#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

failures=0

require_text() {
  local file="$1" needle="$2" description="$3"
  if [[ ! -f "$file" ]]; then
    printf 'FAIL: %s (missing %s)\n' "$description" "$file" >&2
    failures=$((failures + 1))
    return
  fi
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'FAIL: %s\n' "$description" >&2
    failures=$((failures + 1))
  fi
}

forbid_text() {
  local file="$1" needle="$2" description="$3"
  if [[ ! -f "$file" ]]; then
    printf 'FAIL: %s (missing %s)\n' "$description" "$file" >&2
    failures=$((failures + 1))
    return
  fi
  if grep -Fq -- "$needle" "$file"; then
    printf 'FAIL: %s\n' "$description" >&2
    failures=$((failures + 1))
  fi
}

require_resolved_pin() {
  local file="$1" identity="$2" version="$3" description="$4"
  if [[ ! -f "$file" ]] || ! awk -v identity="$identity" -v version="$version" '
    index($0, "\"identity\" : \"" identity "\"") { selected = 1; next }
    selected && index($0, "\"identity\"") { selected = 0 }
    selected && index($0, "\"version\" : \"" version "\"") { found = 1; exit }
    END { exit found ? 0 : 1 }
  ' "$file"; then
    printf 'FAIL: %s\n' "$description" >&2
    failures=$((failures + 1))
  fi
}

require_pbx_pin() {
  local file="$1" repository="$2" version="$3" description="$4"
  if [[ ! -f "$file" ]] || ! awk -v repository="$repository" -v version="$version" '
    index($0, "repositoryURL = \"" repository "\";") { selected = 1; next }
    selected && index($0, "repositoryURL = ") { selected = 0 }
    selected && index($0, "kind = exactVersion;") { exact = 1; next }
    selected && exact && index($0, "version = " version ";") { found = 1; exit }
    END { exit found ? 0 : 1 }
  ' "$file"; then
    printf 'FAIL: %s\n' "$description" >&2
    failures=$((failures + 1))
  fi
}

android_manifest=android/app/src/main/AndroidManifest.xml
android_rules=android/app/src/main/res/xml/data_extraction_rules.xml
android_backup_rules=android/app/src/main/res/xml/backup_rules.xml
android_gradle=android/app/build.gradle.kts
android_credentials=android/app/src/main/java/de/scoopsoftware/cardlink/demo/auth/LocalCredentialStorage.kt
android_settings=android/app/src/main/java/de/scoopsoftware/cardlink/demo/ui/screens/SettingsScreen.kt
android_scan=android/app/src/main/java/de/scoopsoftware/cardlink/demo/ui/screens/ScanScreen.kt
android_popp=android/app/src/main/java/de/scoopsoftware/cardlink/demo/ui/screens/PoppScreen.kt
android_compose_scan=android/app/src/main/java/de/scoopsoftware/cardlink/demo/ui/screens/ScanScreen.kt
android_trace=android/app/src/main/java/de/scoopsoftware/cardlink/demo/ui/components/TraceLogSheet.kt
android_charts=android/app/src/main/java/de/scoopsoftware/cardlink/demo/ui/screens/ChartsScreen.kt
android_history=android/app/src/main/java/de/scoopsoftware/cardlink/demo/ui/model/ScanHistory.kt
ios_reporter=ios/CardlinkSample/CardlinkSample/Models/RocketChatHelper.swift
ios_settings=ios/CardlinkSample/CardlinkSample/SettingsView.swift
ios_history=ios/CardlinkSample/CardlinkSample/Models/ScanHistory.swift
ios_entitlements=ios/CardlinkSample/CardlinkSample/CardlinkSample.entitlements
ios_content=ios/CardlinkSample/CardlinkSample/ContentView.swift
ios_charts=ios/CardlinkSample/CardlinkSample/Charts/ChartsView.swift
pins=android/gradle/libs.versions.toml
ios_pins=ios/CardlinkDemo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
ios_project=ios/CardlinkDemo.xcodeproj/project.pbxproj

# Backups and token persistence must never expose application secrets.
require_text "$android_manifest" 'android:allowBackup="false"' 'Android backups must be disabled.'
require_text "$android_manifest" 'android:dataExtractionRules="@xml/data_extraction_rules"' 'Android data-extraction rules must be declared.'
require_text "$android_manifest" 'android:fullBackupContent="@xml/backup_rules"' 'Android backup rules must be declared.'
require_text "$android_rules" 'domain="sharedpref" path="."' 'Android cloud/device-transfer rules must exclude shared preferences.'
require_text "$android_backup_rules" 'domain="sharedpref" path="."' 'Android backup rules must exclude shared preferences.'
forbid_text "$android_credentials" 'context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)' 'Credential storage must not fall back to plaintext SharedPreferences.'
require_text "$android_credentials" 'Credential storage is unavailable because encrypted storage could not be initialized.' 'Credential-storage initialization failures must be explicit.'

# A customer release must never silently use the debug key.
require_text "$android_gradle" 'val releaseSigningConfig = signingConfigs.findByName("release")' 'Release signing must be resolved explicitly.'
require_text "$android_gradle" 'gradle.taskGraph.whenReady' 'Release signing must be checked against resolved Gradle tasks.'
require_text "$android_gradle" 'error("Release signing configuration is required for release builds.")' 'Release builds must clearly reject missing signing configuration.'
forbid_text "$android_gradle" 'signingConfig = releaseSigningConfig ?: signingConfigs.getByName("debug")' 'Release builds must not fall back to debug signing.'

# RocketChat is an opt-in, fully customer-configured telemetry example.
require_text "$android_settings" 'rcPrefs.getBoolean("enabled", false)' 'Android RocketChat must default to disabled.'
require_text "$android_settings" 'rcPrefs.getString("serverUrl", "")' 'Android RocketChat server must default to an empty customer field.'
require_text "$android_settings" 'rcPrefs.getString("channel", "")' 'Android RocketChat channel must default to an empty customer field.'
require_text "$android_settings" 'rcSecurePrefs.getString("username", "")' 'Android RocketChat username must default to an empty customer field.'
require_text "$android_settings" 'rcSecurePrefs.getString("password", "")' 'Android RocketChat password must default to an empty customer field.'
require_text "$ios_settings" '@AppStorage("rcEnabled") private var enabled = false' 'iOS RocketChat must default to disabled.'
require_text "$ios_settings" '@State private var serverUrl = ""' 'iOS RocketChat server must default to an empty customer field.'
require_text "$ios_settings" '@AppStorage("rcChannel") private var channel = ""' 'iOS RocketChat channel must default to an empty customer field.'
require_text "$ios_settings" '@State private var username = ""' 'iOS RocketChat username must default to an empty customer field.'
require_text "$ios_settings" '@State private var password = ""' 'iOS RocketChat password must default to an empty customer field.'
require_text "$ios_reporter" 'guard defaults.bool(forKey: "rcEnabled") else { return }' 'iOS reporter must remain disabled until the user enables it.'
forbid_text "$android_settings" 'RocketChatReporter.DEFAULT_SERVER_URL' 'Android RocketChat server must not have a baked-in default.'
forbid_text "$android_settings" '"PoPP-Demo"' 'Android RocketChat channel must not have a baked-in default.'
forbid_text "$ios_reporter" 'rocketchat.scoop-gmbh.de' 'iOS RocketChat server must not be hard-coded.'
forbid_text "$ios_reporter" '"PoPP-Demo"' 'iOS RocketChat channel must not be hard-coded.'
forbid_text "$ios_entitlements" 'rocketchat.scoop-gmbh.de' 'iOS entitlements must not preconfigure a RocketChat server.'
require_text "$android_settings" 'Send scan metrics to the configured RocketChat server.' 'Android UI must disclose metric upload before it can occur.'
require_text "$android_settings" 'Include the complete trace log with the upload.' 'Android UI must disclose full-trace upload selection.'
require_text "$ios_settings" 'Send scan metrics to the configured RocketChat server.' 'iOS UI must disclose metric upload before it can occur.'
require_text "$ios_settings" 'Include the complete trace log with the upload.' 'iOS UI must disclose full-trace upload selection.'
require_text "$android_scan" 'getBoolean("includeTrace", false)' 'Android scan reporting must require an explicit full-trace selection.'
require_text "$android_popp" 'getBoolean("includeTrace", false)' 'Android PoPP reporting must require an explicit full-trace selection.'
require_text "$ios_reporter" 'defaults.bool(forKey: "rcIncludeTrace")' 'iOS reporting must require an explicit full-trace selection.'

# Diagnostic tools remain available; sensitive/third-party operations need an explicit explanation.
require_text "$android_compose_scan" 'ToggleRow("Record APDU exchanges"' 'The active Compose scan path must expose an APDU trace switch.'
require_text "$android_compose_scan" 'enableApduTracing = enableApduTracing' 'The active Compose APDU trace switch must configure CardlinkFlowConfig.'
require_text "$android_trace" 'Trace Log' 'Android trace viewer must remain available.'
require_text "$android_trace" 'Text("Copy")' 'Android trace copying must remain available.'
require_text "$android_charts" 'APDU Timeline' 'Android APDU metrics must remain available.'
require_text "$android_history" 'fun exportCSV' 'Android CSV export must remain available.'
require_text "$ios_content" 'struct TraceLogSheet' 'iOS trace viewer must remain available.'
require_text "$ios_content" 'Button("Copy")' 'iOS trace copying must remain available.'
require_text "$ios_charts" 'APDU Timeline' 'iOS APDU metrics must remain available.'
require_text "$ios_history" 'func exportCSV' 'iOS CSV export must remain available.'
require_text "$android_settings" 'Gravatar is a third-party service' 'Android Gravatar use must be labelled as a third-party action.'
require_text "$android_settings" 'Copies raw tokens/JWTs' 'Android raw token copying must be labelled as sensitive.'
require_text "$ios_settings" 'Gravatar is a third-party service' 'iOS Gravatar use must be labelled as a third-party action.'
require_text "$ios_settings" 'Copies raw tokens/JWTs' 'iOS raw token copying must be labelled as sensitive.'

# Candidate matrix must be pinned in distributable Android and iOS projects.
require_text "$pins" 'cardlink-sdk = "5.2.0"' 'Android Cardlink candidate pin must be 5.2.0.'
require_text "$pins" 'nfc-sdk = "4.0.3"' 'Android NFC candidate pin must be 4.0.3.'
require_text "$pins" 'popp-module = "0.23.1"' 'Android PoPP module candidate pin must be 0.23.1.'
require_text "$pins" 'popp-sdk = "3.2.2"' 'Android PoPP SDK candidate pin must be 3.2.2.'
require_pbx_pin "$ios_project" 'ti-cardlink.cardlink' '5.2.0' 'iOS project must directly pin ti-cardlink.cardlink to 5.2.0.'
require_pbx_pin "$ios_project" 'ti-common.nfc' '4.0.3' 'iOS project must directly pin ti-common.nfc to 4.0.3.'
require_pbx_pin "$ios_project" 'ti-popp.popp-sdk' '3.2.2' 'iOS project must directly pin ti-popp.popp-sdk to 3.2.2.'
require_resolved_pin "$ios_pins" 'ti-cardlink.cardlink' '5.2.0' 'iOS resolved ti-cardlink.cardlink pin must be 5.2.0.'
require_resolved_pin "$ios_pins" 'ti-common.nfc' '4.0.3' 'iOS resolved ti-common.nfc pin must be 4.0.3.'
require_resolved_pin "$ios_pins" 'ti-popp.popp-module' '0.23.1' 'iOS resolved ti-popp.popp-module pin must be 0.23.1.'
require_resolved_pin "$ios_pins" 'ti-popp.popp-sdk' '3.2.2' 'iOS resolved ti-popp.popp-sdk pin must be 3.2.2.'

if (( failures > 0 )); then
  printf '\nNative customer-demo safety checks failed: %d\n' "$failures" >&2
  exit 1
fi

printf 'Native customer-demo safety checks passed.\n'
