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
trap cleanup EXIT

if ! override_temp="$(mktemp "$app_dir/.pubspec_overrides.XXXXXX")"; then
    echo "failed to create a temporary local override" >&2
    exit 1
fi
{
    printf 'dependency_overrides:\n'
    for package in "${packages[@]}"; do
        package_name="${package%-flutter}"
        package_name="${package_name//-/_}"
        printf "  %s:\n    path: '%s/%s'\n" "$package_name" "$escaped_projects_root" "$package"
    done
} > "$override_temp"
if ! ln "$override_temp" "$override"; then
    echo "refusing to overwrite existing $override" >&2
    exit 1
fi

cd "$app_dir"
flutter "$@"
exit "$?"
