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
        maven {
            name = "GitHubPackages"
            url = uri("https://maven.pkg.github.com/scoop-software/cardlink-sdk")
            credentials {
                username = System.getenv("GITHUB_ACTOR")
                    ?: providers.gradleProperty("gpr.user").orNull
                    ?: ""
                password = System.getenv("GITHUB_TOKEN")
                    ?: providers.gradleProperty("gpr.key").orNull
                    ?: ""
            }
        }
        // TODO: add maven for NFC and PoPP packages if they're served from different URLs.
        // For now we assume GitHub Packages can resolve all three via the same URL
        // (it usually can — GH Packages namespaces by repo, not group). Task 8 will catch if not.
    }
}

rootProject.name = "cardlink-sdk-demos-android"
include(":app")
