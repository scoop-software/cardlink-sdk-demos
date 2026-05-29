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
