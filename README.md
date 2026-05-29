# Cardlink SDK Demos

Reference demo applications for the [Cardlink SDK](https://github.com/scoop-software/cardlink-sdk).

These demos are intended for 3rd-party developers as ready-to-build examples of how to consume the SDK. Each platform is a standalone project — clone this repository, change into the platform directory, and build with the platform's native toolchain.

## Platforms

| Platform | Status |
|---|---|
| Android (Kotlin) | ✓ available — see [android/](android/) |
| iOS (Swift) | planned |
| Flutter | planned |

## Android — Quick start

Requirements: JDK 17, Android Studio Hedgehog or newer, or just the Android SDK with `ANDROID_HOME` set.

```bash
cd android
./gradlew installDebug   # build and install on a connected device or running emulator
```

The build pulls the Cardlink SDK from [GitHub Packages Maven](https://github.com/scoop-software/cardlink-sdk/packages). You need a GitHub personal access token with `read:packages` scope. Place it in `~/.gradle/gradle.properties`:

```
gpr.user=<your-github-username>
gpr.key=<your-github-PAT>
```

## SDK Developer Mode

If you are working on the Cardlink SDK itself and want demos to consume your local source instead of published artifacts, see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
