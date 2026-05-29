#!/bin/bash
# setup-hooks.sh — One-time installer for the cardlink-sdk-demos git hooks.
#
# Run this once after cloning the repo, if you intend to make commits
# (i.e., you're an SDK developer). 3rd-party customers don't need to.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

git config core.hooksPath .githooks
echo "Git hooks path set to .githooks"
echo "Installed hooks:"
ls .githooks/ | sed 's/^/  - /'
