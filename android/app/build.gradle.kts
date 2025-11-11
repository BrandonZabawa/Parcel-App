plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")    // keep only if android/app/google-services.json exists
}

android {
    namespace = "com.sd2robot.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.sd2robot.app"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        resources {
            excludes += listOf(
                "META-INF/DEPENDENCIES",
                "META-INF/INDEX.LIST",
                "META-INF/*.kotlin_module",
                "META-INF/AL2.0",
                "META-INF/LGPL2.1"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

flutter {
    source = "../.."
}

// If you’re using FlutterFire through Dart, don’t also add native Firebase
// dependencies here. Let FlutterFire handle it. If you’re *not* using FlutterFire,
// you could add Firebase BOM + ktx deps in a `dependencies { ... }` block.

//// android/app/build.gradle.kts
//import java.util.Properties
//import java.io.FileInputStream
//plugins {
//    id("com.android.application")
//    id("org.jetbrains.kotlin.android")
//    // Flutter plugin must be applied on the app module
//    id("dev.flutter.flutter-gradle-plugin")
//    // Firebase: enable Google Services (requires google-services.json in android/app)
//    id("com.google.gms.google-services")
//}
//
//android {
//    namespace = "com.sd2robot.app"
//
//    // Use explicit API levels
//    compileSdk = 34
//
//    defaultConfig {
//        applicationId = "com.sd2robot.app"
//
//        // WebRTC requires >= 24
//        minSdk = 24
//        targetSdk = 34
//
//        versionCode = 1
//        versionName = "1.0"
//
//        // If you hit method count issues later
//        multiDexEnabled = true
//    }
//
//    buildTypes {
//        release {
//            // Use debug keys so `flutter run --release` works until you add real signing
//            signingConfig = signingConfigs.getByName("debug")
//
//            // Optional shrink/obfuscate later
//            // isMinifyEnabled = false
//            // proguardFiles(
//            //     getDefaultProguardFile("proguard-android-optimize.txt"),
//            //     "proguard-rules.pro"
//            // )
//        }
//    }
//
//    // Avoid duplicate META-INF entries that some transitive libs add
//    packaging {
//        resources {
//            excludes += listOf(
//                "META-INF/DEPENDENCIES",
//                "META-INF/INDEX.LIST",
//                "META-INF/*.kotlin_module",
//                "META-INF/AL2.0",
//                "META-INF/LGPL2.1"
//            )
//        }
//    }
//
//    compileOptions {
//        sourceCompatibility = JavaVersion.VERSION_17
//        targetCompatibility = JavaVersion.VERSION_17
//    }
//    kotlinOptions { jvmTarget = "17" }
//}
//
//// This tells the Flutter Gradle plugin where the Flutter module is.
//flutter {
//    source = "../.."
//}

/**
 * Firebase dependencies:
 *
 * If you are using FlutterFire plugins (recommended), you typically DO NOT need
 * to add native Firebase dependencies here; the Flutter plugins bundle them.
 *
 * If you are intentionally wiring native Firebase KTX libs yourself (advanced),
 * uncomment the block below and include only what you actually use to avoid
 * duplicate class issues.
 */
//dependencies {
//    implementation(platform("com.google.firebase:firebase-bom:33.6.0"))
//    implementation("com.google.firebase:firebase-analytics-ktx")
//    implementation("com.google.firebase:firebase-auth-ktx")
//    implementation("com.google.firebase:firebase-firestore-ktx")
//}

/* --- Your previous variants preserved as comments (for reference) ---

//plugins {
//    id("com.android.application")
//    id("org.jetbrains.kotlin.android")
//    // Flutter plugin must be applied on the app module
//    id("dev.flutter.flutter-gradle-plugin")
//    // If (and only if) you have android/app/google-services.json present, keep this enabled:
//    // id("com.google.gms.google-services")
//}
//
//android {
//    namespace = "com.sd2robot.app"
//    compileSdk = 34
//
//    defaultConfig {
//        applicationId = "com.sd2robot.app"
//        minSdk = 24
//        targetSdk = 34
//        versionCode = 1
//        versionName = "1.0"
//        multiDexEnabled = true
//    }
//
//    buildTypes {
//        release {
//            signingConfig = signingConfigs.getByName("debug")
//        }
//    }
//
//    packaging {
//        resources {
//            excludes += listOf(
//                "META-INF/DEPENDENCIES",
//                "META-INF/INDEX.LIST",
//                "META-INF/*.kotlin_module"
//            )
//        }
//    }
//
//    compileOptions {
//        sourceCompatibility = JavaVersion.VERSION_17
//        targetCompatibility = JavaVersion.VERSION_17
//    }
//    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }
//}
//
//dependencies {
//    implementation(platform("com.google.firebase:firebase-bom:33.6.0"))
//    implementation("com.google.firebase:firebase-analytics-ktx")
//    implementation("com.google.firebase:firebase-auth-ktx")
//    implementation("com.google.firebase:firebase-firestore-ktx")
//}

//plugins {
//    id("com.android.application")
//    // START: FlutterFire Configuration
//    id("com.google.gms.google-services")
//    // END: FlutterFire Configuration
//    id("kotlin-android")
//    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
//    id("dev.flutter.flutter-gradle-plugin")
//}
//
//android {
//    namespace  = "com.sd2robot.app"
//    compileSdk = flutter.compileSdkVersion
//    ndkVersion = flutter.ndkVersion
//
//    compileOptions {
//        sourceCompatibility = JavaVersion.VERSION_11
//        targetCompatibility = JavaVersion.VERSION_11
//    }
//    kotlinOptions { jvmTarget = JavaVersion.VERSION_11.toString() }
//
//    defaultConfig {
//        applicationId = "com.sd2robot.app"
//        minSdk = flutter.minSdkVersion
//        targetSdk = flutter.targetSdkVersion
//        versionCode = flutter.versionCode
//        versionName = flutter.versionName
//    }
//
//    buildTypes {
//        release {
//            signingConfig = signingConfigs.getByName("debug")
//        }
//    }
//}
//
//flutter {
//    source = "../.."
//}
--- */

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

//plugins {
//    id("com.android.application")
//    id("org.jetbrains.kotlin.android")
//    // Flutter plugin must be applied on the app module
//    id("dev.flutter.flutter-gradle-plugin")
//    // If (and only if) you have android/app/google-services.json present, keep this enabled:
//    // id("com.google.gms.google-services")
//}
//
//android {
//    namespace = "com.sd2robot.app"
//
//    // Use explicit API levels; avoid the old flutter.* properties
//    compileSdk = 34
//
//    defaultConfig {
//        applicationId = "com.sd2robot.app"
//
//        // WebRTC requires >= 24
//        minSdk = 24
//        targetSdk = 34
//
//        versionCode = 1
//        versionName = "1.0"
//
//        // If you hit method count issues later
//        multiDexEnabled = true
//    }
//
//    // You can keep default debug/release unless you have signing set up
//    buildTypes {
//        release {
//            // Use debug keys so `flutter run --release` works until you add real signing
//            signingConfig = signingConfigs.getByName("debug")
//            // Optional: shrinker/obfuscation later
//            // isMinifyEnabled = false
//            // proguardFiles(
//            //     getDefaultProguardFile("proguard-android-optimize.txt"),
//            //     "proguard-rules.pro"
//            // )
//        }
//    }
//
//    // Avoid duplicate META-INF entries that some transitive libs add
//    packaging {
//        resources {
//            excludes += listOf(
//                "META-INF/DEPENDENCIES",
//                "META-INF/INDEX.LIST",
//                "META-INF/*.kotlin_module",
//                "META-INF/AL2.0",
//                "META-INF/LGPL2.1"
//            )
//        }
//    }
//
//    compileOptions {
//        sourceCompatibility = JavaVersion.VERSION_17
//        targetCompatibility = JavaVersion.VERSION_17
//    }
//    kotlinOptions { jvmTarget = "17" }
//}
//
//// This tells the Flutter Gradle plugin where the Flutter module is.
//// Keep it, even with the plugin loader.
//flutter {
//    source = "../.."
//}

// If you are **not** using FlutterFire, leave dependencies empty.
// If you **are** using FlutterFire, prefer the FlutterFire Gradle integration;
// do NOT double-declare native Firebase deps here unless you know why.
// Example (ONLY if you aren’t using FlutterFire’s auto-setup):
// dependencies {
//     implementation(platform("com.google.firebase:firebase-bom:33.6.0"))
//     implementation("com.google.firebase:firebase-analytics-ktx")
//     implementation("com.google.firebase:firebase-auth-ktx")
//     implementation("com.google.firebase:firebase-firestore-ktx")
// }

//plugins {
//    id("com.android.application")
//    id("org.jetbrains.kotlin.android")
//    id("dev.flutter.flutter-gradle-plugin")   // Flutter embedding & tasks
//    id("com.google.gms.google-services")      // if Firebase is used
//}
//
//android {
//    namespace = "com.sd2robot.app"
//    compileSdk = 34
//
//    defaultConfig {
//        applicationId = "com.sd2robot.app"
//        minSdk = flutter.minSdkVersion
//        targetSdk = 34
//        versionCode = 1
//        versionName = "1.0"
//    }
//
//    compileOptions {
//        sourceCompatibility = JavaVersion.VERSION_17
//        targetCompatibility = JavaVersion.VERSION_17
//    }
//    kotlinOptions { jvmTarget = "17" }
//}

//plugins {
//    id("com.android.application")
//    id("org.jetbrains.kotlin.android")
//    id("dev.flutter.flutter-gradle-plugin")
//    id("com.google.gms.google-services")
//}
//
//android {
//    namespace = "com.sd2robot.app"
//    compileSdk = 34
//
//    defaultConfig {
//        applicationId = "com.sd2robot.app"
//        minSdk = 24                       // <-- WebRTC requires >= 24
//        targetSdk = 34
//        versionCode = 1
//        versionName = "1.0"
//        multiDexEnabled = true
//    }
//
//    buildTypes {
//        release {
//            signingConfig = signingConfigs.getByName("debug")
//        }
//    }
//
//    packaging {
//        resources {
//            excludes += listOf(
//                "META-INF/DEPENDENCIES",
//                "META-INF/INDEX.LIST",
//                "META-INF/*.kotlin_module"
//            )
//        }
//    }
//
//    compileOptions {
//        sourceCompatibility = JavaVersion.VERSION_17
//        targetCompatibility = JavaVersion.VERSION_17
//    }
//    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }
//}
//
//dependencies {
//    implementation(platform("com.google.firebase:firebase-bom:33.6.0"))
//    implementation("com.google.firebase:firebase-analytics-ktx")
//    implementation("com.google.firebase:firebase-auth-ktx")
//    implementation("com.google.firebase:firebase-firestore-ktx")
//}

//plugins {
//    id("com.android.application")
//    // START: FlutterFire Configuration
//    id("com.google.gms.google-services")
//    // END: FlutterFire Configuration
//    id("kotlin-android")
//    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
//    id("dev.flutter.flutter-gradle-plugin")
//}
//
//android {
////    namespace = "com.sd2robot.sd2_robot_app"
//    namespace  = "com.sd2robot.app"
//    compileSdk = flutter.compileSdkVersion
//    ndkVersion = flutter.ndkVersion
//
//    compileOptions {
//        sourceCompatibility = JavaVersion.VERSION_11
//        targetCompatibility = JavaVersion.VERSION_11
//    }
//
//    kotlinOptions {
//        jvmTarget = JavaVersion.VERSION_11.toString()
//    }
//
//    defaultConfig {
//        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
////        applicationId = "com.sd2robot.sd2_robot_app"
//        applicationId = "com.sd2robot.app"
//        // You can update the following values to match your application needs.
//        // For more information, see: https://flutter.dev/to/review-gradle-config.
//        minSdk = flutter.minSdkVersion
//        targetSdk = flutter.targetSdkVersion
//        versionCode = flutter.versionCode
//        versionName = flutter.versionName
//    }
//
//    buildTypes {
//        release {
//            // TODO: Add your own signing config for the release build.
//            // Signing with the debug keys for now, so `flutter run --release` works.
//            signingConfig = signingConfigs.getByName("debug")
//        }
//    }
//}
//
//flutter {
//    source = "../.."
//}
