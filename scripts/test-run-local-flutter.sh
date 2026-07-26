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
stdin_capture="$work/stdin.txt"
started="$work/started"
child_pid_file="$work/flutter.pid"
test_override_temp=""
test_override_path=""

remove_test_override() {
    if [[ -n "$test_override_temp" ]]; then
        if [[ -e "$test_override_path" && "$test_override_path" -ef "$test_override_temp" ]]; then
            rm -f "$test_override_path"
        fi
        rm -f "$test_override_temp"
        test_override_temp=""
        test_override_path=""
    fi
}

cleanup() {
    remove_test_override
    rm -rf "$work"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_no_overrides() {
    local target
    for target in cardlink_demo full_demo; do
        [[ ! -e "$repo_root/flutter/$target/pubspec_overrides.yaml" && ! -L "$repo_root/flutter/$target/pubspec_overrides.yaml" ]] \
            || fail "$target must not retain pubspec_overrides.yaml"
        shopt -s nullglob
        local temporary=("$repo_root/flutter/$target"/.pubspec_overrides.*)
        shopt -u nullglob
        [[ "${#temporary[@]}" == 0 ]] \
            || fail "$target must not retain a hidden temporary override"
    done
}

mkdir -p "$fake_bin"
assert_no_overrides
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
if [[ "${FAKE_FLUTTER_MODE:-exit}" == wait ]]; then
    printf '%s\n' "$$" > "$FAKE_FLUTTER_PID_FILE"
    : > "$FAKE_FLUTTER_STARTED"
    while :; do
        sleep 0.05
    done
fi
if [[ "${FAKE_FLUTTER_MODE:-exit}" == read_stdin ]]; then
    if IFS= read -r line; then
        printf '%s\n' "$line" > "$FAKE_FLUTTER_STDIN_CAPTURE"
    else
        printf '<EOF>\n' > "$FAKE_FLUTTER_STDIN_CAPTURE"
    fi
fi
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

terminate_and_assert() {
    local target="$1"
    local signal="$2"
    local expected_status="$3"
    local override="$repo_root/flutter/$target/pubspec_overrides.yaml"
    rm -f "$override" "$started" "$child_pid_file"
    python3 - "$wrapper" "$fake_bin" "$projects_root" "$target" "$captured_override" \
        "$captured_args" "$captured_pwd" "$child_pid_file" "$started" "$override" \
        "$signal" "$expected_status" <<'PY'
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

(
    wrapper,
    fake_bin,
    projects_root,
    target,
    captured_override,
    captured_args,
    captured_pwd,
    child_pid_file,
    started,
    override,
    signal_name,
    expected_status,
) = sys.argv[1:]
environment = os.environ.copy()
environment.update(
    {
        "PATH": f"{fake_bin}:{environment['PATH']}",
        "SCOOP_PROJECTS_ROOT": projects_root,
        "FAKE_FLUTTER_MODE": "wait",
        "FAKE_FLUTTER_OVERRIDE": captured_override,
        "FAKE_FLUTTER_ARGS": captured_args,
        "FAKE_FLUTTER_PWD": captured_pwd,
        "FAKE_FLUTTER_PID_FILE": child_pid_file,
        "FAKE_FLUTTER_STARTED": started,
    }
)
process = subprocess.Popen([wrapper, target, "analyze"], env=environment)
deadline = time.monotonic() + 2
while not Path(started).exists() and time.monotonic() < deadline:
    time.sleep(0.02)
if not Path(started).exists():
    process.kill()
    process.wait()
    raise SystemExit(f"FAIL: {target} {signal_name} wrapper did not start")
process.send_signal(getattr(signal, f"SIG{signal_name}"))
try:
    status = process.wait(timeout=2)
except subprocess.TimeoutExpired:
    process.kill()
    process.wait()
    raise SystemExit(f"FAIL: {target} {signal_name} wrapper did not terminate")
if status != int(expected_status):
    raise SystemExit(
        f"FAIL: {target} {signal_name} status must be {expected_status}, got {status}"
    )
if Path(child_pid_file).exists():
    child_pid = int(Path(child_pid_file).read_text(encoding="utf-8"))
    try:
        os.kill(child_pid, 0)
    except ProcessLookupError:
        pass
    else:
        os.kill(child_pid, signal.SIGKILL)
        raise SystemExit(f"FAIL: {target} {signal_name} child survived")
if Path(override).exists() or Path(override).is_symlink():
    raise SystemExit(f"FAIL: {target} {signal_name} must remove its override")
if list(Path(override).parent.glob(".pubspec_overrides.*")):
    raise SystemExit(f"FAIL: {target} {signal_name} must remove its temporary override")
PY
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
assert_no_overrides

run_wrapper full_demo test --plain-name 'release graph'
[[ "$(cat "$captured_override")" == "$expected_full_override" ]] \
    || fail "full_demo must write only exact Cardlink, NFC, and PoPP overrides"
[[ "$(cat "$captured_args")" == $'test\n--plain-name\nrelease graph' ]] \
    || fail "full_demo must preserve Flutter arguments"
[[ "$(cat "$captured_pwd")" == "$repo_root/flutter/full_demo" ]] \
    || fail "full_demo must run Flutter in its app directory"
assert_no_overrides

set +e
FAKE_FLUTTER_STATUS=37 run_wrapper cardlink_demo analyze
status=$?
set -e
[[ "$status" == 37 ]] || fail "wrapper must preserve Flutter's exit status, got $status"
assert_no_overrides

printf 'local stdin line\n' | \
    SCOOP_PROJECTS_ROOT="$projects_root" \
    PATH="$fake_bin:$PATH" \
    FAKE_FLUTTER_MODE=read_stdin \
    FAKE_FLUTTER_OVERRIDE="$captured_override" \
    FAKE_FLUTTER_ARGS="$captured_args" \
    FAKE_FLUTTER_PWD="$captured_pwd" \
    FAKE_FLUTTER_STDIN_CAPTURE="$stdin_capture" \
    "$wrapper" full_demo analyze
[[ "$(cat "$stdin_capture")" == 'local stdin line' ]] \
    || fail "wrapper must preserve stdin for Flutter"
assert_no_overrides

set +e
run_wrapper unknown analyze
status=$?
set -e
[[ "$status" == 2 ]] || fail "wrapper must reject an invalid target with usage status 2"
assert_no_overrides

existing_override="$repo_root/flutter/cardlink_demo/pubspec_overrides.yaml"
test_override_path="$existing_override"
test_override_temp="$(mktemp "$repo_root/flutter/cardlink_demo/.test_pubspec_overrides.XXXXXX")"
printf 'existing: true\n' > "$test_override_temp"
ln "$test_override_temp" "$existing_override"
set +e
run_wrapper cardlink_demo analyze
status=$?
set -e
[[ "$status" != 0 ]] || fail "wrapper must refuse an existing override"
[[ "$(cat "$existing_override")" == 'existing: true' ]] \
    || fail "wrapper must not overwrite an existing override"
rm -f "$existing_override"
printf 'replacement: true\n' > "$existing_override"
remove_test_override
[[ "$(cat "$existing_override")" == 'replacement: true' ]] \
    || fail "test cleanup must preserve a concurrently replaced override"
rm -f "$existing_override"
assert_no_overrides

for target in cardlink_demo full_demo; do
    terminate_and_assert "$target" TERM 143
    terminate_and_assert "$target" INT 130
    terminate_and_assert "$target" HUP 129
done
assert_no_overrides

echo "PASS: run-local-flutter scopes, cleans, preserves stdin, and terminates local overrides"
