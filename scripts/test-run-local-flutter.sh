#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="$repo_root/scripts/run-local-flutter.sh"
work="$(mktemp -d)"
projects_root="$work/projects"
fake_bin="$work/bin"
captured_override="$work/override.yaml"
captured_args="$work/args.txt"
captured_pwd="$work/pwd.txt"
cardlink_override_owned=false

cleanup() {
    rm -rf "$work"
    if [[ "$cardlink_override_owned" == true ]]; then
        rm -f "$repo_root/flutter/cardlink_demo/pubspec_overrides.yaml"
    fi
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

mkdir -p "$fake_bin"
[[ ! -e "$repo_root/flutter/cardlink_demo/pubspec_overrides.yaml" && ! -L "$repo_root/flutter/cardlink_demo/pubspec_overrides.yaml" ]] \
    || fail "test must not run over an existing cardlink_demo override"
[[ ! -e "$repo_root/flutter/full_demo/pubspec_overrides.yaml" && ! -L "$repo_root/flutter/full_demo/pubspec_overrides.yaml" ]] \
    || fail "test must not run over an existing full_demo override"
for package in scoop-nfc-flutter scoop-cardlink-flutter scoop-popp-flutter; do
    mkdir -p "$projects_root/$package"
    printf 'name: %s\n' "$package" > "$projects_root/$package/pubspec.yaml"
done

cat > "$fake_bin/flutter" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cp pubspec_overrides.yaml "$FAKE_FLUTTER_OVERRIDE"
printf '%s\n' "$@" > "$FAKE_FLUTTER_ARGS"
pwd > "$FAKE_FLUTTER_PWD"
exit "${FAKE_FLUTTER_STATUS:-0}"
EOF
chmod +x "$fake_bin/flutter"

run_wrapper() {
    SCOOP_PROJECTS_ROOT="$projects_root" \
    PATH="$fake_bin:$PATH" \
    FAKE_FLUTTER_OVERRIDE="$captured_override" \
    FAKE_FLUTTER_ARGS="$captured_args" \
    FAKE_FLUTTER_PWD="$captured_pwd" \
    "$wrapper" "$@"
}

expected_cardlink_override="$(printf "dependency_overrides:\n  scoop_cardlink:\n    path: '%s'\n  scoop_nfc:\n    path: '%s'" "$projects_root/scoop-cardlink-flutter" "$projects_root/scoop-nfc-flutter")"
expected_full_override="$(printf "dependency_overrides:\n  scoop_cardlink:\n    path: '%s'\n  scoop_nfc:\n    path: '%s'\n  scoop_popp:\n    path: '%s'" "$projects_root/scoop-cardlink-flutter" "$projects_root/scoop-nfc-flutter" "$projects_root/scoop-popp-flutter")"

run_wrapper cardlink_demo analyze --no-pub
[[ "$(cat "$captured_override")" == "$expected_cardlink_override" ]] \
    || fail "cardlink_demo must write only exact Cardlink and NFC overrides"
[[ "$(cat "$captured_args")" == $'analyze\n--no-pub' ]] \
    || fail "cardlink_demo must preserve Flutter arguments"
[[ "$(cat "$captured_pwd")" == "$repo_root/flutter/cardlink_demo" ]] \
    || fail "cardlink_demo must run Flutter in its app directory"
[[ ! -e "$repo_root/flutter/cardlink_demo/pubspec_overrides.yaml" ]] \
    || fail "cardlink_demo must remove the override after success"

run_wrapper full_demo test --plain-name 'release graph'
[[ "$(cat "$captured_override")" == "$expected_full_override" ]] \
    || fail "full_demo must write only exact Cardlink, NFC, and PoPP overrides"
[[ "$(cat "$captured_args")" == $'test\n--plain-name\nrelease graph' ]] \
    || fail "full_demo must preserve Flutter arguments"
[[ "$(cat "$captured_pwd")" == "$repo_root/flutter/full_demo" ]] \
    || fail "full_demo must run Flutter in its app directory"
[[ ! -e "$repo_root/flutter/full_demo/pubspec_overrides.yaml" ]] \
    || fail "full_demo must remove the override after success"

set +e
FAKE_FLUTTER_STATUS=37 run_wrapper cardlink_demo analyze
status=$?
set -e
[[ "$status" == 37 ]] || fail "wrapper must preserve Flutter's exit status, got $status"
[[ ! -e "$repo_root/flutter/cardlink_demo/pubspec_overrides.yaml" ]] \
    || fail "cardlink_demo must remove the override after failure"

set +e
run_wrapper unknown analyze
status=$?
set -e
[[ "$status" == 2 ]] || fail "wrapper must reject an invalid target with usage status 2"
[[ ! -e "$repo_root/flutter/cardlink_demo/pubspec_overrides.yaml" && ! -e "$repo_root/flutter/full_demo/pubspec_overrides.yaml" ]] \
    || fail "invalid target must not leave an override"

existing_override="$repo_root/flutter/cardlink_demo/pubspec_overrides.yaml"
printf 'existing: true\n' > "$existing_override"
cardlink_override_owned=true
set +e
run_wrapper cardlink_demo analyze
status=$?
set -e
[[ "$status" != 0 ]] || fail "wrapper must refuse an existing override"
[[ "$(cat "$existing_override")" == 'existing: true' ]] \
    || fail "wrapper must not overwrite an existing override"
rm -f "$existing_override"
cardlink_override_owned=false

echo "PASS: run-local-flutter scopes and cleans local overrides for both demos"
