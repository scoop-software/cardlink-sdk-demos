#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# update-sdk-pin.sh — single source of truth for bumping demo SDK pins.
#
# Called after a successful Gitea release (or manually). Edits the pin files
# in-place; the caller decides
# whether to commit. Idempotent — running with the current value is a no-op.
#
# Usage:
#   ./scripts/update-sdk-pin.sh <sdk> <version>
#
#   sdk:     cardlink | nfc | popp
#   version: semver (e.g. 2.3.0)
#
# What it touches:
#
#   ANDROID (always)
#     android/gradle/libs.versions.toml
#       cardlink → key 'cardlink-sdk'
#       nfc      → key 'nfc-sdk'
#       popp     → key 'popp-module'
#
#   iOS (when sdk == cardlink, nfc, or popp-sdk)
#     ios/CardlinkDemo.xcodeproj/project.pbxproj
#       Cardlink and NFC use independent Gitea registry package versions.
#       Edited via the `xcodeproj` Ruby gem (proper tooling — the previous
#       awk-based edit left a stray `};` in the file that took xcodebuild
#       down for two days).
# ---------------------------------------------------------------------------

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <cardlink|nfc|popp> <version>"
    exit 1
fi

SDK=$1
VER=$2
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Strict semver — value flows into a gradle string literal and a pbxproj field.
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.-]+)?$ ]] \
    || { echo "ERROR: invalid version '$VER' (expected semver)"; exit 1; }

case "$SDK" in
    cardlink) TOML_KEY=cardlink-sdk ;;
    nfc)      TOML_KEY=nfc-sdk ;;
    popp)     TOML_KEY=popp-module ;;
    popp-sdk) TOML_KEY=popp-sdk ;;
    *)        echo "ERROR: unknown sdk '$SDK' (expected cardlink|nfc|popp|popp-sdk)"; exit 1 ;;
esac

# ── Android: libs.versions.toml ──
# A simple TOML with one-line `key = "value"` pairs at the top level. Anchored
# sed on '^key' is unambiguous here; if the file ever grows nested tables a
# proper TOML library would be warranted.
TOML="$REPO_ROOT/android/gradle/libs.versions.toml"
[[ -f "$TOML" ]] || { echo "ERROR: $TOML not found"; exit 1; }

current=$(awk -v key="$TOML_KEY" '$1==key && $2=="=" { gsub(/"/,"",$3); print $3; exit }' "$TOML")
if [[ -z "$current" ]]; then
    echo "ERROR: key '$TOML_KEY' not found in $TOML"; exit 1
fi

if [[ "$current" == "$VER" ]]; then
    echo "  ↪ android $SDK already at $VER"
else
    sed -i.bak -E "s|^(${TOML_KEY}) = \"[^\"]+\"|\\1 = \"$VER\"|" "$TOML"
    rm "$TOML.bak"
    echo "  ✓ android $SDK $current → $VER"
fi

# ── iOS: pbxproj via the xcodeproj Ruby gem ──
if [[ "$SDK" == "cardlink" || "$SDK" == "nfc" || "$SDK" == "popp-sdk" ]]; then
    PBX_DIR="$REPO_ROOT/ios/CardlinkDemo.xcodeproj"
    if [[ ! -d "$PBX_DIR" ]]; then
        echo "  ⚠️ $PBX_DIR not found — skipping iOS bump"
        exit 0
    fi

    # Pick a ruby that can actually USE the xcodeproj gem. macOS system ruby
    # (/usr/bin/ruby, 2.6) is on PATH and `require 'xcodeproj'` succeeds, but
    # nanaimo's native extensions (strscan) are ABI-mismatched and blow up at
    # runtime. The strict probe is "open a real pbxproj"; if that round-trips
    # without raising, the ruby is usable.
    RUBY=""
    for candidate in \
        /opt/homebrew/bin/ruby \
        /opt/homebrew/Cellar/ruby/*/bin/ruby \
        /usr/local/bin/ruby \
        "$(command -v ruby 2>/dev/null || echo /usr/bin/ruby)"
    do
        [[ -x "$candidate" ]] || continue
        if "$candidate" -e "require 'xcodeproj'; Xcodeproj::Project.open(ARGV[0])" "$PBX_DIR" 2>/dev/null; then
            RUBY="$candidate"; break
        fi
    done
    if [[ -z "$RUBY" ]]; then
        echo "ERROR: no ruby with a working 'xcodeproj' gem found."
        echo "       Install with:  gem install xcodeproj"
        echo "       (macOS system ruby 2.6 doesn't work — use Homebrew ruby.)"
        exit 1
    fi

    "$RUBY" - "$PBX_DIR" "$SDK" "$VER" <<'RUBY'
require 'xcodeproj'

project_path, sdk, ver = ARGV
project = Xcodeproj::Project.open(project_path)
identity = { 'cardlink' => 'ti-cardlink.cardlink', 'nfc' => 'ti-common.nfc', 'popp-sdk' => 'ti-popp.popp-sdk' }.fetch(sdk)

found = false
updated = false
project.root_object.package_references.each do |ref|
  next unless ref.respond_to?(:repositoryURL) && ref.repositoryURL.to_s == identity
  found = true
  current = ref.requirement.is_a?(Hash) ? ref.requirement['version'] : nil
  if current == ver
    puts "  ios #{identity} already at #{ver}"
  else
    ref.requirement = { 'kind' => 'exactVersion', 'version' => ver }
    puts "  ios #{identity} #{current || '?'} -> #{ver}"
    updated = true
  end
end

abort "registry package not found in CardlinkDemo.xcodeproj: #{identity}" unless found
project.save if updated
RUBY
fi
