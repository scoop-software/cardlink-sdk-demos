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

        val giteaUrl = providers.gradleProperty("giteaPackageUrl")
            .orElse(providers.environmentVariable("GITEA_URL"))
            .getOrElse("https://ti-gitea.scoop-gmbh.de")
            .trimEnd('/')
        val giteaUser = providers.gradleProperty("giteaPackageUser")
            .orElse(providers.environmentVariable("GITEA_USERNAME"))
        val giteaToken = providers.gradleProperty("giteaPackageToken")
            .orElse(providers.environmentVariable("GITEA_TOKEN"))

        fun scoopRegistry(owner: String, group: String) = maven {
            name = "scoop-$owner"
            url = uri("$giteaUrl/api/packages/$owner/maven")
            credentials {
                username = giteaUser.orNull.orEmpty()
                password = giteaToken.orNull.orEmpty()
            }
            content {
                includeGroup(group)
            }
        }

        scoopRegistry("ti-cardlink", "de.scoopsoftware.cardlink")
        scoopRegistry("ti-common", "de.scoopsoftware.nfc")
        scoopRegistry("ti-popp", "de.scoopsoftware.popp")
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
