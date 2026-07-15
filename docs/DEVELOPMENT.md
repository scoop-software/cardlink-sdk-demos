# SDK Developer Guide

This document is for developers of the Cardlink SDK who want to iterate on the demos against their local SDK source instead of the published artifacts.

## Setup (once per machine)

1. Ensure the SDK repos are siblings of this repo:

   ```
   ~/projects/
   ├── cardlink-sdk/
   ├── cardlink-sdk-demos/   ← you are here
   ├── scoop-nfc-sdk/
   └── scoop-popp-module/
   ```

2. Install the version-bump git hook:

   ```
   ./scripts/setup-hooks.sh
   ```

3. Verify your environment with the doctor script:

   ```
   ./scripts/doctor.sh
   ```

## Dev mode vs published mode

The demos default to consuming published SDK artifacts. To consume your local SDK source instead, use the `Dev`-suffixed task variants:

| Platform | Published (default for customers)               | Dev (local SDK source)                                                           |
|----------|-------------------------------------------------|----------------------------------------------------------------------------------|
| Android  | `./gradlew installDebug`                        | `./gradlew installDevDebug`                                                      |
| iOS      | `open ios/CardlinkDemo.xcodeproj` (Xcode → Run) | `open ios/CardlinkDemoDev.xcodeproj` (Xcode → Run; rebuild SDK XCFramework first)|
| Flutter  | (coming in later phase)                         | (coming in later phase)                                                          |

The Android `Dev` task triggers `settings.gradle.kts` to detect "Dev" in the requested task name. When detected, the script registers sibling SDK repos as composite builds and substitutes the Maven coordinates with local project dependencies. The `build.gradle.kts` is unchanged between modes.

Sibling SDK repos that aren't present on disk are gracefully skipped — you can have only `cardlink-sdk` checked out and dev-mode will still work, falling through to published artifacts for NFC and PoPP.

## Verifying dev-mode actually fired

After running an `installDevDebug`, check the Gradle output for lines like:

```
Dev mode: including build ../../cardlink-sdk, substituting de.scoopsoftware.cardlink:shared-android
```

To inspect the resolved dependency tree under dev mode:

```
./gradlew :app:assembleDevDebug :app:dependencies --configuration debugRuntimeClasspath
```

Look for `-> project :cardlink-sdk:packages:sdk:shared` arrows in the output — those confirm Gradle is using the local source.

If you see only `Dev mode: skipping` lines (or no Dev mode lines at all), check your sibling layout via `./scripts/doctor.sh`.

### iOS Dev-mode workflow

1. Edit Kotlin source in `~/projects/cardlink-sdk/packages/sdk/shared/...` (or `~/projects/scoop-nfc-sdk/packages/sdk/shared/...` for NFC, including `ScoopNfcUI` SwiftUI views).
2. Rebuild the XCFramework(s):

   ```
   # Cardlink SDK changes:
   cd ~/projects/cardlink-sdk
   ./gradlew :packages:sdk:shared:buildXCFrameworkDevice

   # NFC SDK / ScoopNfcUI changes:
   cd ~/projects/scoop-nfc-sdk
   ./gradlew :packages:sdk:shared:buildXCFrameworkDevice
   ```

   (~1 minute on first build, cached on subsequent runs unless source changes.)

3. Open `cardlink-sdk-demos/ios/CardlinkDemoDev.xcodeproj` and build. The local `Package.swift` manifests at `cardlink-sdk/tools/cardlink-dev-spm/Package.swift` and `scoop-nfc-sdk/tools/nfc-dev-spm/Package.swift` reference the freshly-built XCFrameworks directly.

The Dev project installs side-by-side with the customer-facing Debug build (bundle ID `de.scoopsoftware.cardlink.demo.ios.devsdk`, name "Cardlink DevSDK").

If Xcode caches the old XCFramework, delete the project's DerivedData and rebuild:

```
rm -rf ~/Library/Developer/Xcode/DerivedData/CardlinkDemoDev-*
```

Published XCFrameworks use module-stable interfaces with Explicit Modules
enabled. Releases are compiled and cold-cache consumer-tested with Xcode 26.0,
the oldest Xcode supported by the maintained build host. Importing a textual
interface does not by itself guarantee that a static binary avoids newer Swift
runtime symbols.

## Authentication for the published Maven repos

Customer (and CI) builds resolve the NFC + PoPP `de.scoopsoftware.*` artifacts from two GitHub Packages Maven repos, which require authentication (the Cardlink SDK is now on a public Maven repo and needs none). Gradle's auth error message can be misleading. Any of the following work:

- Environment variables: `GITHUB_ACTOR` and `GITHUB_TOKEN` (the token needs `read:packages` scope on the `scoop-software` org).
- Gradle properties in `~/.gradle/gradle.properties`:

  ```
  gpr.user=<your-github-username>
  gpr.key=<your-github-PAT>
  ```

- For local development, you can bridge the `gh` CLI's authentication into Gradle:

  ```
  export GITHUB_ACTOR=$(gh api user --jq .login)
  export GITHUB_TOKEN=$(gh auth token)
  ./gradlew installDebug
  ```

## Versioning

Each platform has its own `version.properties` (e.g. `android/version.properties`). The git post-commit hook auto-bumps based on the conventional commit message:

| Commit prefix                            | Bump  |
|------------------------------------------|-------|
| `feat:`                                  | minor |
| `fix:` / `perf:`                         | patch |
| `BREAKING CHANGE:` or `feat!:` / `fix!:` | major |
| `chore:` / `docs:` / `refactor:` / `test:` | no bump |

Only platforms with changes in the commit get bumped — a `feat(android):` commit that only touches `android/` bumps only `android/version.properties`.

SDK pin updates (when the SDK release pipeline pushes a new pin to this repo) use the `chore:` prefix and don't bump demo versions.
