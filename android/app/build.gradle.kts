import java.text.SimpleDateFormat
import java.util.Date
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.compose.compiler)
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

// Load keystore properties. Order of precedence:
//   1. android/app/keystore.properties (local dev, gitignored)
//   2. Gradle properties (-PstoreFile=..., e.g. from ~/.gradle/gradle.properties)
//   3. Environment variables (ANDROID_KEYSTORE_FILE, ..._PASSWORD, ..._KEY_ALIAS, ..._KEY_PASSWORD)
val keystorePropertiesFile = rootProject.file("app/keystore.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
} else {
    fun resolve(propKey: String, envKey: String): String? =
        (findProperty(propKey) as? String) ?: System.getenv(envKey)
    resolve("storeFile", "ANDROID_KEYSTORE_FILE")?.let { keystoreProperties["storeFile"] = it }
    resolve("storePassword", "ANDROID_KEYSTORE_PASSWORD")?.let { keystoreProperties["storePassword"] = it }
    resolve("keyAlias", "ANDROID_KEY_ALIAS")?.let { keystoreProperties["keyAlias"] = it }
    resolve("keyPassword", "ANDROID_KEY_PASSWORD")?.let { keystoreProperties["keyPassword"] = it }
}

// Read version from version.properties in the android/ directory (one level up from app/).
val versionProperties = Properties().apply {
    val versionFile = rootProject.file("version.properties")
    if (versionFile.exists()) {
        versionFile.inputStream().use { load(it) }
    }
}

// Calculate versionCode from versionName: "major.minor.patch" -> major*10000 + minor*100 + patch
fun calculateVersionCode(versionName: String): Int {
    val parts = versionName.split(".").map { it.toIntOrNull() ?: 0 }
    val major = parts.getOrElse(0) { 0 }
    val minor = parts.getOrElse(1) { 0 }
    val patch = parts.getOrElse(2) { 0 }
    return major * 10000 + minor * 100 + patch
}

val appVersionName = versionProperties.getProperty("version") ?: "1.0.0"
val appVersionCode = calculateVersionCode(appVersionName)

android {
    namespace = "de.scoopsoftware.cardlink.demo"
    compileSdk = 35

    defaultConfig {
        applicationId = "de.scoopsoftware.cardlink.demo.android"
        minSdk = 26
        targetSdk = 35
        versionCode = appVersionCode
        versionName = appVersionName

        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    signingConfigs {
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        val releaseStoreFile = keystoreProperties.getProperty("storeFile")
        if (releaseStoreFile != null && file(releaseStoreFile).exists()) {
            create("release") {
                storeFile = file(releaseStoreFile)
                storePassword = keystoreProperties.getProperty("storePassword") ?: ""
                keyAlias = keystoreProperties.getProperty("keyAlias") ?: ""
                keyPassword = keystoreProperties.getProperty("keyPassword") ?: ""
            }
        }
    }

    val releaseSigningConfig = signingConfigs.findByName("release")

    buildTypes {
        debug {
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            isMinifyEnabled = false
            signingConfig = releaseSigningConfig ?: signingConfigs.getByName("debug")
        }
        create("releaseOptimized") {
            isMinifyEnabled = true
            isShrinkResources = true
            matchingFallbacks += "release"
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = releaseSigningConfig ?: signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "META-INF/versions/9/OSGI-INF/MANIFEST.MF"
        }
    }
}

dependencies {
    // Scoop SDKs (Maven coordinates resolved via GitHub Packages in settings.gradle.kts)
    implementation(libs.cardlink.shared.android)
    implementation(libs.nfc.shared.android)
    implementation(libs.popp.shared.android)

    // AndroidX core
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.activity.ktx)
    implementation(libs.material)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.androidx.lifecycle.runtime.ktx)

    // CameraX
    implementation(libs.camerax.core)
    implementation(libs.camerax.camera2)
    implementation(libs.camerax.lifecycle)
    implementation(libs.camerax.view)

    // ML Kit
    implementation(libs.mlkit.text.recognition)
    implementation(libs.mlkit.barcode.scanning)

    // Compose BOM
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.navigation.compose)
    debugImplementation(libs.compose.ui.tooling)

    // Vico charts
    implementation(libs.vico.compose.m3)

    // Misc
    implementation(libs.gson)
    implementation(libs.lottie.compose)
    implementation(libs.coil.compose)
    implementation(libs.coil.svg)
    implementation(libs.security.crypto)
    implementation(libs.credentials)
    implementation(libs.credentials.play.services.auth)
    implementation(libs.kotlinx.coroutines.core)
}

// Custom dev-mode tasks. These don't change anything about the build —
// they delegate to the standard tasks. The actual SDK source substitution
// happens in settings.gradle.kts based on "Dev" in the task name.
tasks.register("assembleDevDebug") {
    dependsOn("assembleDebug")
    group = "build"
    description = "Assemble Debug variant against local SDK source (Dev mode)"
}
tasks.register("installDevDebug") {
    dependsOn("installDebug")
    group = "install"
    description = "Install Debug variant against local SDK source (Dev mode)"
}

// Output filenames for release builds: {id}_{version}.{timestamp}.{ext}
androidComponents {
    onVariants { variant ->
        if (variant.buildType in setOf("release", "releaseOptimized")) {
            val timestamp = SimpleDateFormat("yyyyMMddHHmm").format(Date())
            val baseName = "${variant.applicationId.get()}_${appVersionName}.${timestamp}"
            variant.outputs.forEach { output ->
                if (output is com.android.build.api.variant.impl.VariantOutputImpl) {
                    output.outputFileName.set("$baseName.apk")
                }
            }
        }
    }
}
