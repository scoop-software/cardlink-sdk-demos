#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="$repo_root/scripts/run-local-flutter.sh"
work="$(mktemp -d)"
projects_root="$work/projects"
fake_bin="$work/bin"
link_race_bin="$work/link-race-bin"
captured_override="$work/override.yaml"
captured_args="$work/args.txt"
captured_pwd="$work/pwd.txt"
stdin_capture="$work/stdin.txt"
started="$work/started"
child_pid_file="$work/flutter.pid"
flutter_sentinel="$work/flutter-launched"
test_override_temp=""
test_override_path=""
race_overrides=("")

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
    local race_override race_directory
    for race_override in "${race_overrides[@]}"; do
        [[ -n "$race_override" ]] || continue
        race_directory="$work/link-race-$(basename "$(dirname "$race_override")")"
        if [[ -L "$race_override" && "$(readlink "$race_override")" == "$race_directory" ]]; then
            rm -f "$race_override"
        fi
    done
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

mkdir -p "$fake_bin" "$link_race_bin"
assert_no_overrides
for package in scoop-nfc-flutter scoop-cardlink-flutter scoop-popp-flutter; do
    mkdir -p "$projects_root/$package"
    printf 'name: %s\n' "$package" > "$projects_root/$package/pubspec.yaml"
done

cat > "$fake_bin/flutter" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${FAKE_FLUTTER_SENTINEL:-}" ]]; then
    : > "$FAKE_FLUTTER_SENTINEL"
fi
if [[ "${FAKE_FLUTTER_MODE:-exit}" == startup_wait ]]; then
    printf '%s\n' "$$" > "$FAKE_FLUTTER_PID_FILE"
    : > "$FAKE_FLUTTER_STARTED"
    while :; do
        sleep 0.05
    done
fi
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
cat > "$link_race_bin/ln" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ ! -e "$LINK_RACE_OVERRIDE" && ! -L "$LINK_RACE_OVERRIDE" ]]; then
    /bin/ln -s "$LINK_RACE_DIRECTORY" "$LINK_RACE_OVERRIDE"
fi
exec /bin/ln "$@"
EOF
chmod +x "$fake_bin/flutter" "$link_race_bin/ln"

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
override_path = Path(override)
child_pid = None
owned_identity = None
owned_temps: list[Path] = []


def capture_owned_override() -> None:
    global owned_identity, owned_temps
    if not override_path.exists() or override_path.is_symlink():
        return
    for temporary in override_path.parent.glob(".pubspec_overrides.*"):
        try:
            if os.path.samefile(override_path, temporary):
                stat = override_path.stat()
                owned_identity = (stat.st_dev, stat.st_ino)
                owned_temps = [temporary]
                return
        except FileNotFoundError:
            continue


def same_identity(path: Path) -> bool:
    if owned_identity is None:
        return False
    try:
        stat = path.stat()
    except FileNotFoundError:
        return False
    return not path.is_symlink() and (stat.st_dev, stat.st_ino) == owned_identity


try:
    deadline = time.monotonic() + 2
    while not Path(started).exists() and time.monotonic() < deadline:
        capture_owned_override()
        time.sleep(0.02)
    if not Path(started).exists():
        raise RuntimeError(f"{target} {signal_name} wrapper did not start")
    capture_owned_override()
    child_pid = int(Path(child_pid_file).read_text(encoding="utf-8"))
    process.send_signal(getattr(signal, f"SIG{signal_name}"))
    status = process.wait(timeout=2)
    if status != int(expected_status):
        raise RuntimeError(
            f"{target} {signal_name} status must be {expected_status}, got {status}"
        )
    try:
        os.kill(child_pid, 0)
    except ProcessLookupError:
        pass
    else:
        raise RuntimeError(f"{target} {signal_name} child survived")
    if override_path.exists() or override_path.is_symlink():
        raise RuntimeError(f"{target} {signal_name} must remove its override")
    if list(override_path.parent.glob(".pubspec_overrides.*")):
        raise RuntimeError(f"{target} {signal_name} must remove its temporary override")
except (subprocess.TimeoutExpired, RuntimeError) as error:
    raise SystemExit(f"FAIL: {error}")
finally:
    capture_owned_override()
    if process.poll() is None:
        process.kill()
        process.wait()
    if child_pid is None and Path(child_pid_file).exists():
        child_pid = int(Path(child_pid_file).read_text(encoding="utf-8"))
    if child_pid is not None:
        try:
            os.kill(child_pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if same_identity(override_path):
        override_path.unlink()
    for temporary in owned_temps:
        if same_identity(temporary):
            temporary.unlink()
PY
}

startup_signal_and_assert() {
    local target="full_demo"
    local override="$repo_root/flutter/$target/pubspec_overrides.yaml"
    rm -f "$override" "$started" "$child_pid_file"
    python3 - "$wrapper" "$fake_bin" "$projects_root" "$target" "$captured_override" \
        "$captured_args" "$captured_pwd" "$child_pid_file" "$started" "$override" \
        "$work" <<'PY'
import os
from pathlib import Path
import signal
import subprocess
import sys

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
    work,
) = sys.argv[1:]
override_path = Path(override)
trace_marker = Path(work) / "startup-signal-traced"
bash_env = Path(work) / "startup-signal.bash"
bash_env.write_text(
    """set -T
startup_signal_trace() {
    local traced_command=\"$1\"
    if [[ \"$traced_command\" == 'child_pid=$!' && ! -e \"$STARTUP_SIGNAL_MARKER\" ]]; then
        printf '%s\\n' \"$!\" > \"$FAKE_FLUTTER_PID_FILE\"
        : > \"$STARTUP_SIGNAL_MARKER\"
        kill -TERM \"$$\"
    fi
}
trap 'startup_signal_trace \"$BASH_COMMAND\"' DEBUG
""",
    encoding="utf-8",
)
environment = os.environ.copy()
environment.update(
    {
        "BASH_ENV": str(bash_env),
        "PATH": f"{fake_bin}:{environment['PATH']}",
        "SCOOP_PROJECTS_ROOT": projects_root,
        "FAKE_FLUTTER_MODE": "startup_wait",
        "FAKE_FLUTTER_OVERRIDE": captured_override,
        "FAKE_FLUTTER_ARGS": captured_args,
        "FAKE_FLUTTER_PWD": captured_pwd,
        "FAKE_FLUTTER_PID_FILE": child_pid_file,
        "FAKE_FLUTTER_STARTED": started,
        "STARTUP_SIGNAL_MARKER": str(trace_marker),
    }
)
process = subprocess.Popen([wrapper, target, "analyze"], env=environment)
child_pid = None
owned_identity = None
owned_temps: list[Path] = []


def capture_owned_override() -> None:
    global owned_identity, owned_temps
    if not override_path.exists() or override_path.is_symlink():
        return
    for temporary in override_path.parent.glob(".pubspec_overrides.*"):
        try:
            if os.path.samefile(override_path, temporary):
                stat = override_path.stat()
                owned_identity = (stat.st_dev, stat.st_ino)
                owned_temps = [temporary]
                return
        except FileNotFoundError:
            continue


def same_identity(path: Path) -> bool:
    if owned_identity is None:
        return False
    try:
        stat = path.stat()
    except FileNotFoundError:
        return False
    return not path.is_symlink() and (stat.st_dev, stat.st_ino) == owned_identity


try:
    status = process.wait(timeout=3)
    if Path(child_pid_file).exists():
        child_pid = int(Path(child_pid_file).read_text(encoding="utf-8"))
    if not trace_marker.exists():
        raise RuntimeError("startup signal trace did not reach child_pid publication")
    if status != 143:
        raise RuntimeError(f"startup TERM exit status must be 143, got {status}")
    if child_pid is None:
        raise RuntimeError("startup signal trace did not capture fake Flutter PID")
    try:
        os.kill(child_pid, 0)
    except ProcessLookupError:
        pass
    else:
        raise RuntimeError("startup TERM left fake Flutter alive")
    if override_path.exists() or override_path.is_symlink():
        raise RuntimeError("startup TERM must remove its override")
    if list(override_path.parent.glob(".pubspec_overrides.*")):
        raise RuntimeError("startup TERM must remove its temporary ownership file")
except (subprocess.TimeoutExpired, RuntimeError) as error:
    raise SystemExit(f"FAIL: {error}")
finally:
    capture_owned_override()
    if process.poll() is None:
        process.kill()
        process.wait()
    if child_pid is None and Path(child_pid_file).exists():
        child_pid = int(Path(child_pid_file).read_text(encoding="utf-8"))
    if child_pid is not None:
        try:
            os.kill(child_pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if same_identity(override_path):
        override_path.unlink()
    for temporary in owned_temps:
        if same_identity(temporary):
            temporary.unlink()
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

write_failure_env="$work/write-failure.bash"
cat > "$write_failure_env" <<'EOF'
printf() {
    return 73
}
EOF
rm -f "$flutter_sentinel"
set +e
BASH_ENV="$write_failure_env" \
    SCOOP_PROJECTS_ROOT="$projects_root" \
    PATH="$fake_bin:$PATH" \
    FAKE_FLUTTER_OVERRIDE="$captured_override" \
    FAKE_FLUTTER_ARGS="$captured_args" \
    FAKE_FLUTTER_PWD="$captured_pwd" \
    FAKE_FLUTTER_SENTINEL="$flutter_sentinel" \
    "$wrapper" full_demo analyze
status=$?
set -e
[[ "$status" != 0 ]] || fail "temporary YAML write failure must fail the wrapper"
[[ ! -e "$flutter_sentinel" ]] \
    || fail "temporary YAML write failure must abort before Flutter"
assert_no_overrides

for target in cardlink_demo full_demo; do
    race_override="$repo_root/flutter/$target/pubspec_overrides.yaml"
    race_directory="$work/link-race-$target"
    mkdir "$race_directory"
    race_overrides+=("$race_override")
    rm -f "$flutter_sentinel"
    set +e
    LINK_RACE_OVERRIDE="$race_override" \
        LINK_RACE_DIRECTORY="$race_directory" \
        SCOOP_PROJECTS_ROOT="$projects_root" \
        PATH="$link_race_bin:$fake_bin:$PATH" \
        FAKE_FLUTTER_OVERRIDE="$captured_override" \
        FAKE_FLUTTER_ARGS="$captured_args" \
        FAKE_FLUTTER_PWD="$captured_pwd" \
        FAKE_FLUTTER_SENTINEL="$flutter_sentinel" \
        "$wrapper" "$target" analyze
    status=$?
    set -e
    [[ "$status" != 0 ]] || fail "$target publication race must fail"
    [[ ! -e "$flutter_sentinel" ]] \
        || fail "$target publication race must abort before Flutter"
    [[ -L "$race_override" ]] \
        || fail "$target racing destination symlink must remain untouched"
    [[ "$(readlink "$race_override")" == "$race_directory" ]] \
        || fail "$target racing destination symlink target must remain unchanged"
    [[ -z "$(find "$race_directory" -mindepth 1 -maxdepth 1 -print)" ]] \
        || fail "$target publication race must not leave a target-directory hardlink"
    rm "$race_override"
done
race_overrides=("")
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
startup_signal_and_assert
assert_no_overrides

echo "PASS: run-local-flutter scopes, cleans, preserves stdin, and terminates local overrides"
