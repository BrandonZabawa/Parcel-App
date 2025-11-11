// android/settings.gradle.kts

import java.util.Properties
import java.io.File
import java.io.FileInputStream

// ---------- Helpers ----------
fun loadProps(file: File): Properties? =
    if (file.exists()) Properties().apply { FileInputStream(file).use { load(it) } } else null

fun findFlutterHome(settingsDir: File): String {
    // Prefer Flutter-provided envs when `flutter run` invokes Gradle
    val env = sequenceOf("FLUTTER_ROOT", "FLUTTER_HOME", "FLUTTER_SDK")
        .mapNotNull { System.getenv(it) }
        .firstOrNull()

    // Also allow android/local.properties (kept for compatibility)
    val local = loadProps(File(settingsDir, "local.properties"))?.getProperty("flutter.sdk")

    val candidates = listOfNotNull(env, local)

    fun isValid(p: String) = File(p).resolve("packages/flutter_tools/gradle").exists()

    val hit = candidates.firstOrNull { it.isNotBlank() && isValid(it) }
    return hit ?: throw GradleException(
        """
        Cannot locate Flutter SDK for Gradle.

        Set ONE of the following before running:
          • export FLUTTER_ROOT=/absolute/path/to/flutter  (preferred when using `flutter run`)
          • android/local.properties:  flutter.sdk=/absolute/path/to/flutter

        And ensure: <flutter>/packages/flutter_tools/gradle  exists.
        """.trimIndent()
    )
}

// ---------- Locate Flutter SDK ----------
val flutterHome: String = findFlutterHome(settingsDir)
println("Using Flutter SDK at: $flutterHome")

// ---------- (Optional) includeBuild; harmless with legacy loader, useful for some setups ----------
includeBuild(File(flutterHome, "packages/flutter_tools/gradle"))

// ---------- Use the legacy loader script instead of the plugin id ----------
// This avoids: "Plugin 'dev.flutter.flutter-plugin-loader' not found"
//apply(from = File(flutterHome, "packages/flutter_tools/gradle/app_plugin_loader.gradle"))

// ---------- Normal plugin management for your *other* plugins ----------
pluginManagement {
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
        // Optional mirror for some Flutter artifacts:
        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
    }
    plugins {
        id("com.android.application") version "8.6.1"
        id("org.jetbrains.kotlin.android") version "2.1.0"
        id("com.google.gms.google-services") version "4.4.2"
    }
}

// ---------- Do NOT reference the Flutter plugin here ----------
plugins {
    // Only expose non-Flutter plugins to subprojects
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
    id("com.google.gms.google-services") apply false
}

// ---------- Repositories for module dependencies ----------
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
    }
}

rootProject.name = "sd2_robot_app"
include(":app")




//// android/settings.gradle.kts
//
//import java.util.Properties
//import java.io.FileInputStream
//
//// 1) Load flutter.sdk from android/local.properties
//val localPropsFile = File(settingsDir, "local.properties")
//require(localPropsFile.exists()) {
//    "Missing android/local.properties. Create it with:\n" +
//            "  flutter.sdk=/absolute/path/to/flutter\n" +
//            "  sdk.dir=/absolute/path/to/Android/Sdk"
//}
//val localProps = Properties().apply {
//    FileInputStream(localPropsFile).use { load(it) }
//}
//val flutterSdk: String = localProps.getProperty("flutter.sdk")
//    ?: throw GradleException("android/local.properties is missing flutter.sdk")
//
//// 2) Expose Flutter’s Gradle build to this build (makes dev.flutter.* plugins resolvable)
//includeBuild("$flutterSdk/packages/flutter_tools/gradle")
//
//// 3) Normal plugin management and repos
//pluginManagement {
//    repositories {
//        gradlePluginPortal()
//        google()
//        mavenCentral()
//        // Optional, but helps resolve Flutter artifacts when needed:
//        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
//        maven(url = uri("$flutterSdk/bin/cache/artifacts/engine"))
//    }
//    // You can pin other plugin versions here (do NOT set a version for dev.flutter.*)
//    plugins {
//        id("com.android.application") version "8.6.1"
//        id("org.jetbrains.kotlin.android") version "2.1.0"
//        id("com.google.gms.google-services") version "4.4.2" // if you use Firebase
//    }
//}
//
//// 4) Use Flutter’s plugin loader (now available because of includeBuild above)
//plugins {
//    id("dev.flutter.flutter-plugin-loader")
//    id("com.android.application") apply false
//    id("org.jetbrains.kotlin.android") apply false
//    id("com.google.gms.google-services") apply false
//}
//
//// 5) Central dependency repos for all modules
//dependencyResolutionManagement {
//    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
//    repositories {
//        google()
//        mavenCentral()
//        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
//        maven(url = uri("$flutterSdk/bin/cache/artifacts/engine"))
//    }
//}
//
//rootProject.name = "sd2_robot_app"
//include(":app")

//// android/settings.gradle.kts
//
//import java.util.Properties
//import java.io.FileInputStream
//
//// ---- Load flutter.sdk (and fail early with a clear message) ----
//val localPropsFile = File(settingsDir, "local.properties")
//require(localPropsFile.exists()) {
//    "Missing android/local.properties. Create it with:\n" +
//            "  flutter.sdk=/absolute/path/to/flutter\n" +
//            "  sdk.dir=/absolute/path/to/Android/Sdk"
//}
//
//val localProps = Properties().apply {
//    FileInputStream(localPropsFile).use { load(it) }
//}
//
//val flutterSdk: String = localProps.getProperty("flutter.sdk")
//    ?: throw GradleException("android/local.properties is missing flutter.sdk")
//
//// ---- Make Flutter’s Gradle plugin available to this build ----
//pluginManagement {
//    repositories {
//        gradlePluginPortal()
//        google()
//        mavenCentral()
//        // Flutter mirrors for artifacts (ok if not used; harmless)
//        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
//        // Local engine cache (exists after flutter downloads artifacts)
//        maven(url = uri("https://jitpack.io"))
////        maven(url = uri("$flutterSdk/bin/cache/artifacts/engine"))
//    }
//
//    // NOTE: Do NOT set a version for dev.flutter.* here.
//    // The Flutter plugin is provided by the included build below.
////    includeBuild("$flutterSdk/packages/flutter_tools/gradle")
//    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
//
//    // Pin other plugin versions (Android, Kotlin, Firebase)
//    plugins {
//        id("com.android.application") version "8.6.1"
//        id("org.jetbrains.kotlin.android") version "2.1.0"
//        id("com.google.gms.google-services") version "4.4.2"
//    }
//}
//
//// Apply Flutter's plugin loader (provided by includeBuild above)
//plugins {
//    id("dev.flutter.flutter-plugin-loader")
//    // Make these available to subprojects without applying to the settings build
//    id("com.android.application") apply false
//    id("org.jetbrains.kotlin.android") apply false
//    id("com.google.gms.google-services") apply false
//}
//
//// Centralize dependency repositories for modules
//dependencyResolutionManagement {
//    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
//    repositories {
//        google()
//        mavenCentral()
//        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
//        maven(url = uri("https://jitpack.io"))
////        maven(url = uri("$flutterSdk/bin/cache/artifacts/engine"))
//    }
//}
//
//rootProject.name = "sd2_robot_app"
//include(":app")

//// android/settings.gradle.kts
//
//// ---------- Imports ----------
//import java.util.Properties
//import java.io.FileInputStream
//import java.io.File
//
//// ---------- Resolve flutter.sdk from android/local.properties ----------
//val localPropsFile = File(settingsDir, "local.properties")
//require(localPropsFile.exists()) {
//    """
//    Missing android/local.properties. Create it with at least:
//      flutter.sdk=/absolute/path/to/flutter
//      sdk.dir=/absolute/path/to/Android/Sdk
//    """.trimIndent()
//}
//
//val props = Properties().apply {
//    FileInputStream(localPropsFile).use { load(it) }
//}
//
//val flutterSdk: String = props.getProperty("flutter.sdk")
//    ?: throw GradleException("android/local.properties is missing 'flutter.sdk'")
//
//// Optional sanity check (comment out if you dislike strictness)
//require(File("$flutterSdk/packages/flutter_tools/gradle").exists()) {
//    "Not found: $flutterSdk/packages/flutter_tools/gradle . Is flutter.sdk correct?"
//}
//
//// ---------- Make Flutter’s Gradle build available & pin tool plugin versions ----------
//// android/settings.gradle.kts
//
//pluginManagement {
//    repositories {
//        gradlePluginPortal()
//        google()
//        mavenCentral()
//        // Optional but harmless; some Flutter artifacts are mirrored here:
//        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
//    }
//    plugins {
//        id("com.android.application") version "8.6.1"
//        id("org.jetbrains.kotlin.android") version "2.1.0"
//        id("com.google.gms.google-services") version "4.4.2"
//        // <- This is the only Flutter piece you need in settings:
//        id("dev.flutter.flutter-plugin-loader") version "1.0.0"
//    }
//}
//
//// Apply the loader; it wires Flutter tooling without needing flutterSdk paths.
//plugins {
//    id("dev.flutter.flutter-plugin-loader")
//    id("com.android.application") apply false
//    id("org.jetbrains.kotlin.android") apply false
//    id("com.google.gms.google-services") apply false
//}
//
//dependencyResolutionManagement {
//    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
//    repositories {
//        google()
//        mavenCentral()
//        // Optional mirror:
//        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
//    }
//}
//
//rootProject.name = "sd2_robot_app"
//include(":app")
//
///*
//---------------------------------------------------------
//Notes / Troubleshooting
//---------------------------------------------------------
//1) Ensure android/local.properties exists with:
//     flutter.sdk=/abs/path/to/flutter
//     sdk.dir=/abs/path/to/Android/Sdk
//   (Paths must be absolute.)
//
//2) The app module (android/app/build.gradle.kts) should:
//   - Apply: id("com.android.application"), id("org.jetbrains.kotlin.android"),
//            id("dev.flutter.flutter-gradle-plugin")
//   - If you use FlutterFire (google-services.json present in android/app/):
//            id("com.google.gms.google-services")
//   - Set compileSdk/targetSdk/minSdk explicitly (e.g., 34 / 34 / 24).
//   - No need to add native Firebase deps in `dependencies {}` unless you call
//     Firebase from Kotlin/Java directly. Flutter plugins pull them in.
//
//3) If you previously tried the “plugin loader with version '1.0.0'” without
//   includeBuild, that’s what caused the “plugin not found” errors. This script
//   uses the **supported** pattern: include Flutter’s gradle via includeBuild.
//
//4) If Gradle still caches old settings, run:
//     ./gradlew --stop
//     ./gradlew clean
//   or from Flutter:
//     flutter clean
//     flutter pub get
//     flutter run
//*/

//// android/settings.gradle.kts
//import java.util.Properties
//import java.io.FileInputStream
//
//pluginManagement {
//    // Read flutter.sdk from android/local.properties (default Flutter location)
//    val localProps = Properties().apply {
//        val file = File(settingsDir, "local.properties")
//        if (!file.exists()) {
//            throw GradleException("Missing android/local.properties. Create it with flutter.sdk and sdk.dir.")
//        }
//        FileInputStream(file).use { load(it) }
//    }
//    val flutterSdk = localProps.getProperty("flutter.sdk")
//        ?: throw GradleException("local.properties is missing flutter.sdk")
//
//    // Make Flutter's Gradle plugin available
//    includeBuild("$flutterSdk/packages/flutter_tools/gradle")
//
//    repositories {
//        google()
//        mavenCentral()
//        gradlePluginPortal()
//    }
//
//    // Pin common plugin versions here (Flutter plugin comes from includeBuild above)
//    plugins {
//        id("com.android.application") version "8.6.1"
//        id("org.jetbrains.kotlin.android") version "2.1.0"
//        id("com.google.gms.google-services") version "4.4.2"
//    }
//}
//
//// Apply Flutter's loader (provided by includeBuild)
//plugins {
//    id("dev.flutter.flutter-plugin-loader")
//    id("com.android.application") apply false
//    id("org.jetbrains.kotlin.android") apply false
//    id("com.google.gms.google-services") apply false
//}
//
//dependencyResolutionManagement {
//    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
//    repositories {
//        google()
//        mavenCentral()
//    }
//}
//
//rootProject.name = "sd2_robot_app"
//include(":app")

//// settings.gradle.kts  (Android module)
//// --- Read flutter.sdk BEFORE any blocks that use it ---
//import java.util.Properties
//import java.io.FileInputStream
//
//val props = Properties().apply {
//    val lp = File(rootDir, "local.properties")
//    require(lp.exists()) {
//        "Missing local.properties at project root. Add: flutter.sdk=/absolute/path/to/flutter"
//    }
//    FileInputStream(lp).use { load(it) }
//}
//
//val flutterSdk: String = props.getProperty("flutter.sdk")
//    ?: throw GradleException("Set flutter.sdk in local.properties, e.g. flutter.sdk=/home/you/flutter")
//
//// --- Make Flutter's Gradle plugin available and set tool repos/versions ---
//pluginManagement {
//    repositories {
//        google()
//        mavenCentral()
//        gradlePluginPortal()
//        // Flutter engine artifacts
//        maven { url = uri("$flutterSdk/bin/cache/artifacts/engine") }
//        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
//    }
//
//    // Expose Flutter gradle plugins to this build (this is what provides dev.flutter.*)
//    includeBuild("$flutterSdk/packages/flutter_tools/gradle")
//
//    // Pin common plugin versions (Flutter plugin comes from includeBuild above; no version there)
//    plugins {
//        id("com.android.application") version "8.6.1"
//        id("org.jetbrains.kotlin.android") version "2.1.0"
//        id("com.google.gms.google-services") version "4.4.2" // keep only if you actually use Firebase
//    }
//}
//
//// Apply Flutter’s plugin loader (no version; supplied by includeBuild)
//plugins {
//    id("dev.flutter.flutter-plugin-loader")
//    // Make tools available to subprojects without applying them here
//    id("com.android.application") apply false
//    id("org.jetbrains.kotlin.android") apply false
//    id("com.google.gms.google-services") apply false
//}
//
//// Centralize dependency repos; repeat Flutter repos so dependencies resolve
//dependencyResolutionManagement {
//    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
//    repositories {
//        google()
//        mavenCentral()
//        maven { url = uri("$flutterSdk/bin/cache/artifacts/engine") }
//        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
//    }
//}
//
//rootProject.name = "sd2_robot_app"
//include(":app")

//// settings.gradle.kts  (Android module)
//// --- Read flutter.sdk BEFORE any blocks that use it ---
//import java.util.Properties
//import java.io.FileInputStream
//
//val props = Properties().apply {
//    val lp = File(rootDir, "local.properties")
//    require(lp.exists()) {
//        "Missing local.properties at project root. Add: flutter.sdk=/absolute/path/to/flutter"
//    }
//    FileInputStream(lp).use { load(it) }
//}
//
//val flutterSdk: String = props.getProperty("flutter.sdk")
//    ?: throw GradleException("Set flutter.sdk in local.properties, e.g. flutter.sdk=/home/you/flutter")
//
//// --- Make Flutter's Gradle plugin available and set tool repos/versions ---
//pluginManagement {
//    repositories {
//        google()
//        mavenCentral()
//        gradlePluginPortal()
//        // Flutter engine artifacts
//        maven { url = uri("$flutterSdk/bin/cache/artifacts/engine") }
//        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
//    }
//
//    // Expose Flutter gradle plugins to this build (this is what provides dev.flutter.*)
//    includeBuild("$flutterSdk/packages/flutter_tools/gradle")
//
//    // Pin common plugin versions (Flutter plugin comes from includeBuild above; no version there)
//    plugins {
//        id("com.android.application") version "8.6.1"
//        id("org.jetbrains.kotlin.android") version "2.1.0"
//        id("com.google.gms.google-services") version "4.4.2" // keep only if you actually use Firebase
//    }
//}
//
//// Apply Flutter’s plugin loader (no version; supplied by includeBuild)
//plugins {
//    id("dev.flutter.flutter-plugin-loader")
//    // Make tools available to subprojects without applying them here
//    id("com.android.application") apply false
//    id("org.jetbrains.kotlin.android") apply false
//    id("com.google.gms.google-services") apply false
//}
//
//// Centralize dependency repos; repeat Flutter repos so dependencies resolve
//dependencyResolutionManagement {
//    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
//    repositories {
//        google()
//        mavenCentral()
//        maven { url = uri("$flutterSdk/bin/cache/artifacts/engine") }
//        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
//    }
//}
//
//rootProject.name = "sd2_robot_app"
//include(":app")


//pluginManagement {
//    repositories {
//        google()
//        mavenCentral()
//        gradlePluginPortal()
//    }
//    // Pin tool versions here so subprojects don't need to.
//    plugins {
//        id("com.android.application") version "8.6.1"
//        id("org.jetbrains.kotlin.android") version "2.1.0"
//        // This loader replaces the old includeBuild("$flutterSdk/...") pattern.
//        id("dev.flutter.flutter-plugin-loader") version "1.0.0"
//    }
//}
//
//plugins {
//    id("dev.flutter.flutter-plugin-loader")
//}
//
//dependencyResolutionManagement {
//    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
//    repositories {
//        google()
//        mavenCentral()
//    }
//}
//
//rootProject.name = "sd2_robot_app"
//include(":app")


//import java.util.Properties
//import java.io.FileInputStream
//
//val props = Properties().apply {
//    FileInputStream(File(rootDir, "local.properties")).use { load(it) }
//}
//val flutterSdk: String = props.getProperty("flutter.sdk") ?: ""
//require(flutterSdk.isNotBlank()) { "Set flutter.sdk in local.properties" }
//
//pluginManagement {
//    repositories {
//        google()
//        mavenCentral()
//        gradlePluginPortal()
//        // Flutter engine & artifacts
//        maven { url = uri("$flutterSdk/bin/cache/artifacts/engine") }
//        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
//    }
//    // Make Gradle see Flutter’s build plugin
//    includeBuild("$flutterSdk/packages/flutter_tools/gradle")
//}
//
//dependencyResolutionManagement {
//    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
//    repositories {
//        google()
//        mavenCentral()
//        maven { url = uri("$flutterSdk/bin/cache/artifacts/engine") }
//        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
//    }
//}
//
//rootProject.name = "sd2_robot_app"
//include(":app")

//import java.util.Properties
//import java.io.FileInputStream
//
//val props = Properties().apply {
//    FileInputStream(File(rootDir, "local.properties")).use { load(it) }
//}
//val flutterSdk = props.getProperty("flutter.sdk")
//require(!flutterSdk.isNullOrBlank()) { "Set flutter.sdk in local.properties" }
//
//// Let Gradle see Flutter's build plugin
//includeBuild("$flutterSdk/packages/flutter_tools/gradle")
//
//pluginManagement {
//    repositories {
//        google()
//        mavenCentral()
//        gradlePluginPortal()
//        maven(url = uri("https://jitpack.io"))
//        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
//    }
//    plugins {
//        id("com.android.application") version "8.6.1"
//        id("com.android.library") version "8.6.1"
//        id("org.jetbrains.kotlin.android") version "2.0.21"
//        id("com.google.gms.google-services") version "4.4.2"
//        // Flutter's gradle plugin is provided by includeBuild(...) above
//    }
//}
//
//dependencyResolutionManagement {
//    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
//    repositories {
//        google()
//        mavenCentral()
//        maven(url = uri("https://jitpack.io"))
//        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
//    }
//}
//
//rootProject.name = "android"
//include(":app")


//pluginManagement {
//    val flutterSdkPath =
//        run {
//            val properties = java.util.Properties()
//            file("local.properties").inputStream().use { properties.load(it) }
//            val flutterSdkPath = properties.getProperty("flutter.sdk")
//            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
//            flutterSdkPath
//        }
//
//    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
//
//    repositories {
//        google()
//        mavenCentral()
//        gradlePluginPortal()
//        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
//    }
//}
//
//// Just added dependencyResolutionManagement
//dependencyResolutionManagement {
//    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
//    repositories { google(); mavenCentral()
//        maven(url = uri("https://storage.googleapis.com/download.flutter.io")) }
//}
//
//plugins {
//    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
//    id("com.android.application") version "8.9.1" apply false
//    // START: FlutterFire Configuration
//    id("com.google.gms.google-services") version("4.3.15") apply false
//    // END: FlutterFire Configuration
//    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
//}
//
//include(":app")
