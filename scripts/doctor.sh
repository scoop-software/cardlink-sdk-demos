#!/bin/bash
# doctor.sh — Print diagnostic information about the dev environment.
#
# Use this when an installDevDebug isn't picking up your local SDK source,
# or when onboarding a new developer.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SIBLINGS_ROOT="$(cd "$REPO_ROOT/.." && pwd)"

print_section() {
    echo
    echo "── $1 ──"
}

print_status() {
    local label="$1"
    local path="$2"
    if [ -d "$path" ]; then
        local git_status="(not a git repo)"
        if [ -d "$path/.git" ]; then
            git_status="$(cd "$path" && git status -sb 2>/dev/null | head -1 || echo 'unknown')"
        fi
        printf "  %-25s ✓ %s  %s\n" "$label" "$path" "$git_status"
    else
        printf "  %-25s ✗ %s  (missing)\n" "$label" "$path"
    fi
}

echo "cardlink-sdk-demos — environment diagnostics"
echo "Repo: $REPO_ROOT"

print_section "Sibling SDK repos (for Dev mode)"
print_status "Cardlink"      "$SIBLINGS_ROOT/cardlink-sdk"
print_status "NFC"           "$SIBLINGS_ROOT/scoop-nfc-sdk"
print_status "PoPP module"   "$SIBLINGS_ROOT/scoop-popp-module"

print_section "Toolchains"

check_cmd() {
    local label="$1"
    local cmd="$2"
    local version_flag="${3:---version}"
    if command -v "$cmd" >/dev/null 2>&1; then
        local v
        v=$("$cmd" $version_flag 2>&1 | head -1)
        printf "  %-25s ✓ %s\n" "$label" "$v"
    else
        printf "  %-25s ✗ not installed\n" "$label"
    fi
}

check_cmd "java"          java       "-version"
check_cmd "gradle"        "$REPO_ROOT/android/gradlew"   "--version"
check_cmd "xcodebuild"    xcodebuild "-version"
check_cmd "ruby"          ruby       "--version"
if command -v ruby >/dev/null 2>&1 && ruby -rxcodeproj -e '1' 2>/dev/null; then
    printf "  %-25s ✓ xcodeproj gem installed\n" "ruby-xcodeproj"
else
    printf "  %-25s ✗ xcodeproj gem missing — run 'gem install xcodeproj'\n" "ruby-xcodeproj"
fi
# Flutter checks added in later phases.

print_section "Android dev-mode readiness"

if [ -d "$SIBLINGS_ROOT/cardlink-sdk" ]; then
    echo "  installDevDebug will substitute Cardlink with local source."
else
    echo "  installDevDebug will fall through to published Cardlink artifact."
fi
if [ -d "$SIBLINGS_ROOT/scoop-nfc-sdk" ]; then
    echo "  installDevDebug will substitute NFC with local source."
else
    echo "  installDevDebug will fall through to published NFC artifact."
fi
if [ -d "$SIBLINGS_ROOT/scoop-popp-module" ]; then
    echo "  installDevDebug will substitute PoPP with local source."
else
    echo "  installDevDebug will fall through to published PoPP artifact."
fi

print_section "iOS dev-mode readiness"

CARDLINK_DEV_SPM="$SIBLINGS_ROOT/cardlink-sdk/tools/cardlink-dev-spm/Package.swift"
NFC_DEV_SPM="$SIBLINGS_ROOT/scoop-nfc-sdk/tools/nfc-dev-spm/Package.swift"
CARDLINK_XCF="$SIBLINGS_ROOT/cardlink-sdk/packages/sdk/shared/build/XCFrameworks/ScoopCardlink.xcframework"
NFC_XCF="$SIBLINGS_ROOT/scoop-nfc-sdk/packages/sdk/shared/build/XCFrameworks/ScoopNfc.xcframework"
NFC_UI_XCF="$SIBLINGS_ROOT/scoop-nfc-sdk/packages/sdk/shared/build/XCFrameworks/ScoopNfcUI.xcframework"

if [ -f "$CARDLINK_DEV_SPM" ]; then
    echo "  ✓ cardlink-dev-spm Package.swift present"
else
    echo "  ✗ cardlink-dev-spm Package.swift missing — Dev iOS project won't resolve ScoopCardlink"
fi
if [ -f "$NFC_DEV_SPM" ]; then
    echo "  ✓ nfc-dev-spm Package.swift present"
else
    echo "  ✗ nfc-dev-spm Package.swift missing — Dev iOS project won't resolve ScoopNfc/ScoopNfcUI"
fi
if [ -d "$CARDLINK_XCF" ]; then
    echo "  ✓ ScoopCardlink.xcframework built"
else
    echo "  ✗ ScoopCardlink.xcframework missing — run:"
    echo "      cd ~/projects/cardlink-sdk && ./gradlew :packages:sdk:shared:buildXCFrameworkDevice"
fi
if [ -d "$NFC_XCF" ] && [ -d "$NFC_UI_XCF" ]; then
    echo "  ✓ ScoopNfc + ScoopNfcUI XCFrameworks built"
else
    echo "  ✗ ScoopNfc and/or ScoopNfcUI XCFramework missing — run:"
    echo "      cd ~/projects/scoop-nfc-sdk && ./gradlew :packages:sdk:shared:buildXCFrameworkDevice"
fi

print_section "Maven credentials"
if [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_ACTOR:-}" ]; then
    echo "  ✓ GITHUB_ACTOR + GITHUB_TOKEN set in env"
elif grep -q '^gpr.key=' ~/.gradle/gradle.properties 2>/dev/null; then
    echo "  ✓ gpr.user + gpr.key set in ~/.gradle/gradle.properties"
elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "  ✓ gh CLI authenticated (use 'gh auth token' to bridge to Gradle)"
else
    echo "  ✗ no Maven credentials found — published-mode builds will fail."
    echo "    Options: set GITHUB_ACTOR + GITHUB_TOKEN env vars,"
    echo "             add gpr.user/gpr.key to ~/.gradle/gradle.properties,"
    echo "             or install gh CLI and run 'gh auth login'."
fi

echo
echo "Done."
