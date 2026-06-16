# Cardlink SDK Demos

Reference demo applications for the [Cardlink SDK](https://github.com/scoop-software/cardlink-sdk).

These demos are intended for 3rd-party developers as ready-to-build examples of how to consume the SDK. Each platform is a standalone project — clone this repository, change into the platform directory, and build with the platform's native toolchain.

> 📖 **[API Reference → docs/API.md](docs/API.md)** — the consumer API for every flow
> (CardLink, PoPP, eRezept, card reading, metrics) with Kotlin/Swift usage snippets.

## Platforms

| Platform | Status |
|---|---|
| Android (Kotlin) | ✓ available — see [android/](android/) |
| iOS (Swift) | ✓ available — see [ios/](ios/) |
| Flutter | planned |

## Android — Quick start

Requirements: JDK 17, Android Studio Hedgehog or newer, or just the Android SDK with `ANDROID_HOME` set.

```bash
cd android
./gradlew installDebug   # build and install on a connected device or running emulator
```

The Cardlink SDK is pulled from a public Maven repo (`https://scoop-software.github.io/cardlink-packages/maven`) — no credentials needed. The **NFC** and **PoPP** SDKs are still on GitHub Packages, which needs a GitHub personal access token with `read:packages` scope. Place it in `~/.gradle/gradle.properties`:

```
gpr.user=<your-github-username>
gpr.key=<your-github-PAT>
```

## iOS — Quick start

Requirements: Xcode 15+, an Apple developer account for signing.

```bash
open ios/CardlinkDemo.xcodeproj
```

The project pulls `ScoopCardlink`, `ScoopNfc`, and `ScoopNfcUI` from the single
[cardlink-packages](https://github.com/scoop-software/cardlink-packages) Swift package
automatically on first build. Xcode handles the SPM resolution.

## SDK Developer Mode

If you are working on the Cardlink SDK itself and want demos to consume your local source instead of published artifacts, see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
