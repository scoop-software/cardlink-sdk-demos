#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
projects_root="${SCOOP_PROJECTS_ROOT:-$(dirname "$repo_root")}"

usage() {
    echo "usage: $0 {cardlink_demo|full_demo} <flutter arguments...>" >&2
}

if [[ "$#" -lt 2 ]]; then
    usage
    exit 2
fi

target="$1"
shift
case "$target" in
    cardlink_demo)
        packages=(scoop-cardlink-flutter scoop-nfc-flutter)
        ;;
    full_demo)
        packages=(scoop-cardlink-flutter scoop-nfc-flutter scoop-popp-flutter)
        ;;
    *)
        usage
        exit 2
        ;;
esac

if [[ "$projects_root" == *[[:cntrl:]]* ]]; then
    echo "SCOOP_PROJECTS_ROOT must not contain control characters" >&2
    exit 1
fi
if [[ "$projects_root" != /* ]]; then
    projects_root="$repo_root/$projects_root"
fi
if ! projects_root="$(cd "$projects_root" && pwd)"; then
    echo "SCOOP_PROJECTS_ROOT must name an existing directory" >&2
    exit 1
fi

app_dir="$repo_root/flutter/$target"
override="$app_dir/pubspec_overrides.yaml"
if [[ -e "$override" || -L "$override" ]]; then
    echo "refusing to overwrite existing $override" >&2
    exit 1
fi

for package in "${packages[@]}"; do
    if [[ ! -f "$projects_root/$package/pubspec.yaml" ]]; then
        echo "missing sibling checkout pubspec: $projects_root/$package/pubspec.yaml" >&2
        exit 1
    fi
done

override_temp=""
escaped_projects_root="${projects_root//\'/\'\'}"

cleanup() {
    if [[ -n "$override_temp" ]]; then
        if [[ -e "$override" && "$override" -ef "$override_temp" ]]; then
            rm -f "$override"
        fi
        rm -f "$override_temp"
    fi
}
child_pid=""
child_starting=false
pending_signal=""
pending_status=""

terminate() {
    local signal="$1"
    local status="$2"
    if [[ "$child_starting" == true && -z "$child_pid" ]]; then
        pending_signal="$signal"
        pending_status="$status"
        return
    fi
    trap - HUP INT TERM
    if [[ -n "$child_pid" ]]; then
        kill -"$signal" "$child_pid" 2>/dev/null || true
        if [[ "$signal" != TERM ]]; then
            kill -TERM "$child_pid" 2>/dev/null || true
        fi
        wait "$child_pid" 2>/dev/null || true
        child_pid=""
    fi
    cleanup
    exit "$status"
}

trap cleanup EXIT
trap 'terminate HUP 129' HUP
trap 'terminate INT 130' INT
trap 'terminate TERM 143' TERM

if ! override_temp="$(mktemp "$app_dir/.pubspec_overrides.XXXXXX")"; then
    echo "failed to create a temporary local override" >&2
    exit 1
fi
if ! {
    printf 'dependency_overrides:\n'
    for package in "${packages[@]}"; do
        package_name="${package%-flutter}"
        package_name="${package_name//-/_}"
        printf "  %s:\n    path: '%s/%s'\n" "$package_name" "$escaped_projects_root" "$package"
    done
} > "$override_temp"; then
    cleanup
    echo "failed to write the temporary local override" >&2
    exit 1
fi
case "$(uname -s)" in
    Darwin)
        link_status=0
        ln -h "$override_temp" "$override" || link_status=$?
        ;;
    Linux)
        link_status=0
        ln -T "$override_temp" "$override" || link_status=$?
        ;;
    *)
        cleanup
        echo "unsupported platform for exact override publication" >&2
        exit 1
        ;;
esac
if [[ "$link_status" != 0 ]]; then
    cleanup
    echo "refusing to overwrite existing $override" >&2
    exit 1
fi
if [[ -L "$override" || ! -f "$override" || ! "$override" -ef "$override_temp" ]]; then
    cleanup
    echo "published override failed ownership verification" >&2
    exit 1
fi

cd "$app_dir"
child_starting=true
flutter "$@" <&0 &
child_pid=$!
child_starting=false
if [[ -n "$pending_signal" ]]; then
    terminate "$pending_signal" "$pending_status"
fi
wait "$child_pid"
command_status=$?
child_pid=""
exit "$command_status"
