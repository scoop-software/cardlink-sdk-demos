#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$root/scripts/test-ios-swiftpm-only.sh"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/ios-swiftpm-only.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

make_valid_fixture() {
    rm -rf "$fixture/repo"
    local app ios
    for app in cardlink_demo full_demo; do
        ios="$fixture/repo/flutter/$app/ios"
        mkdir -p "$ios/Runner.xcodeproj" "$ios/Runner.xcworkspace" "$ios/Flutter"
        printf '// fixture\n' > "$ios/Runner.xcodeproj/project.pbxproj"
        printf '<Workspace/>\n' > "$ios/Runner.xcworkspace/contents.xcworkspacedata"
        printf '#include "Generated.xcconfig"\n' > "$ios/Flutter/Debug.xcconfig"
        printf '#include "Generated.xcconfig"\n' > "$ios/Flutter/Release.xcconfig"
    done
}

expect_failure() {
    local name="$1" expected="$2" output status
    set +e
    output="$(DEMO_REPO_ROOT="$fixture/repo" bash "$gate" 2>&1)"
    status=$?
    set -e
    [[ "$status" -ne 0 ]] || {
        echo "FAIL: $name unexpectedly passed" >&2
        exit 1
    }
    [[ "$output" == *"$expected"* ]] || {
        echo "FAIL: $name expected '$expected', got: $output" >&2
        exit 1
    }
}

make_valid_fixture
DEMO_REPO_ROOT="$fixture/repo" bash "$gate" >/dev/null

make_valid_fixture
ln -s missing-target "$fixture/repo/flutter/cardlink_demo/ios/Pods"
expect_failure dangling-pods 'still contains CocoaPods files'

make_valid_fixture
rm -rf "$fixture/repo/flutter/full_demo/ios/Runner.xcodeproj"
expect_failure missing-project 'Xcode project is missing or symbolic'

make_valid_fixture
rm "$fixture/repo/flutter/full_demo/ios/Runner.xcodeproj/project.pbxproj"
expect_failure missing-project-file 'required iOS project file is missing, unreadable, or symbolic'

make_valid_fixture
rm "$fixture/repo/flutter/full_demo/ios/Runner.xcodeproj/project.pbxproj"
ln -s missing-project.pbxproj \
    "$fixture/repo/flutter/full_demo/ios/Runner.xcodeproj/project.pbxproj"
expect_failure dangling-project-file 'required iOS project file is missing, unreadable, or symbolic'

make_valid_fixture
printf '[CP] Check Pods Manifest.lock\n' \
    > "$fixture/repo/flutter/cardlink_demo/ios/Runner.xcodeproj/project.pbxproj"
expect_failure pods-build-phase 'still contains CocoaPods project integration'

echo 'Flutter iOS SwiftPM-only gate regression tests passed.'
