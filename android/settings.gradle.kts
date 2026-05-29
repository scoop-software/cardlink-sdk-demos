pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // GitHub Packages namespaces by repo (not by group), so each SDK needs its own URL.
        // Credentials are shared — a single GITHUB_TOKEN with read:packages scope works for all three.
        listOf(
            "GitHubPackagesCardlink" to "https://maven.pkg.github.com/scoop-software/cardlink-sdk",
            "GitHubPackagesNfc"      to "https://maven.pkg.github.com/scoop-software/nfc-sdk",
            "GitHubPackagesPopp"     to "https://maven.pkg.github.com/scoop-software/scoop-popp-module",
        ).forEach { (repoName, repoUrl) ->
            maven {
                name = repoName
                url = uri(repoUrl)
                credentials {
                    username = System.getenv("GITHUB_ACTOR")
                        ?: providers.gradleProperty("gpr.user").orNull
                        ?: ""
                    password = System.getenv("GITHUB_TOKEN")
                        ?: providers.gradleProperty("gpr.key").orNull
                        ?: ""
                }
            }
        }
    }
}

rootProject.name = "cardlink-sdk-demos-android"
include(":app")

// ── Dev-mode SDK substitution ─────────────────────────────────────────────
//
// When any requested task name contains "Dev" (case-insensitive), we wire up
// sibling SDK repos as composite builds and substitute their Maven coordinates
// with the local project dependencies. The app's build.gradle.kts is unchanged
// — Gradle does the swap transparently.
//
// Sibling repos that don't exist on disk are silently skipped (graceful
// degradation: dev mode works even if only some SDKs are checked out).

val isDevBuild = startParameter.taskNames.any { it.contains("Dev", ignoreCase = true) }

if (isDevBuild) {
    val siblings = listOf(
        Triple("../../cardlink-sdk",       "de.scoopsoftware.cardlink:shared-android", ":packages:sdk:shared"),
        Triple("../../scoop-nfc-sdk",      "de.scoopsoftware.nfc:shared-android",      ":packages:sdk:shared"),
        Triple("../../scoop-popp-module",  "de.scoopsoftware.popp:shared-android",     ":packages:sdk:shared"),
    )

    siblings.forEach { (relativePath, moduleCoord, projectPath) ->
        val siblingRoot = file(relativePath)
        if (siblingRoot.exists() && siblingRoot.resolve("settings.gradle.kts").exists()) {
            logger.lifecycle("Dev mode: including build $relativePath, substituting $moduleCoord")
            includeBuild(relativePath) {
                dependencySubstitution {
                    substitute(module(moduleCoord)).using(project(projectPath))
                }
            }
        } else {
            logger.lifecycle("Dev mode: skipping $relativePath (not present on disk)")
        }
    }
}
