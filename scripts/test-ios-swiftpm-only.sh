#!/usr/bin/env bash
set -euo pipefail

root="${DEMO_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

for app in cardlink_demo full_demo; do
    ios="$root/flutter/$app/ios"
    [[ -d "$ios" ]] || {
        echo "ERROR: missing iOS demo directory: $ios" >&2
        exit 1
    }
    for forbidden in "$ios/Podfile" "$ios/Podfile.lock" "$ios/Pods"; do
        [[ ! -e "$forbidden" && ! -L "$forbidden" ]] || {
            echo "ERROR: $app still contains CocoaPods files: $forbidden" >&2
            exit 1
        }
    done

    project="$ios/Runner.xcodeproj"
    project_file="$project/project.pbxproj"
    workspace="$ios/Runner.xcworkspace/contents.xcworkspacedata"
    debug_config="$ios/Flutter/Debug.xcconfig"
    release_config="$ios/Flutter/Release.xcconfig"
    [[ -d "$project" && ! -L "$project" ]] || {
        echo "ERROR: $app Xcode project is missing or symbolic" >&2
        exit 1
    }
    for required in "$project_file" "$workspace" "$debug_config" "$release_config"; do
        [[ -f "$required" && -r "$required" && ! -L "$required" ]] || {
            echo "ERROR: $app required iOS project file is missing, unreadable, or symbolic: $required" >&2
            exit 1
        }
    done

    set +e
    matches="$(grep -RInE \
        'Pods\.xcodeproj|\[CP\]|PODS_ROOT|PODS_PODFILE|Target Support Files/Pods|pod install' \
        "$project_file" "$workspace" "$debug_config" "$release_config" \
        --exclude='.gitignore' 2>&1)"
    grep_status=$?
    set -e
    if [[ "$grep_status" -eq 0 ]]; then
        printf '%s\n' "$matches" >&2
        echo "ERROR: $app still contains CocoaPods project integration" >&2
        exit 1
    elif [[ "$grep_status" -gt 1 ]]; then
        printf '%s\n' "$matches" >&2
        echo "ERROR: $app CocoaPods integration scan failed" >&2
        exit 1
    fi
done

echo 'Flutter iOS demos are SwiftPM-only.'
