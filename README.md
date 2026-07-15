# Cardlink SDK Demos

Reference demo applications for the privately distributed Cardlink SDK.

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

The SDKs are pulled from private Gitea Maven registries. Place the customer
credentials in `~/.gradle/gradle.properties`:

```
giteaPackageUser=<customer-user>
giteaPackageToken=<read-package-token>
# Optional override; the project defaults to this production URL:
giteaPackageUrl=https://ti-gitea.scoop-gmbh.de
```

## iOS — Quick start

Requirements: Xcode 26.0+, an Apple developer account for signing.

```bash
open ios/CardlinkDemo.xcodeproj
```

The project pulls `ti-cardlink.cardlink` 2.6.2 and `ti-common.nfc` 2.3.2 from
the configured Gitea Swift registries. Add the customer credentials for
`ti-gitea.scoop-gmbh.de` to the macOS Keychain via
`swift package-registry login` and to `.netrc` for protected XCFramework
downloads before opening Xcode.

## SDK Developer Mode

If you are working on the Cardlink SDK itself and want demos to consume your local source instead of published artifacts, see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
