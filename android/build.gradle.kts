allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
plugins {
    // versions already declared in settings.gradle.kts
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
    // do NOT add dev.flutter.flutter-gradle-plugin here
}
//plugins {
//    id("com.android.application") version "8.6.1" apply false
//    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
//    id("com.google.gms.google-services") version "4.4.2" apply false
//    // Do NOT declare a version for dev.flutter.flutter-gradle-plugin here;
//    // it’s supplied via includeBuild(...) in settings.gradle.kts.
//}

//plugins {
//    id("com.android.application") apply false
//    id("com.android.library")     apply false
//    id("org.jetbrains.kotlin.android") apply false
//    // You can keep a version here if you want, it rarely collides:
//    id("com.google.gms.google-services") apply false
//}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}
tasks.register("clean", Delete::class){
    delete(rootProject.buildDir)
}
//tasks.register<Delete>("clean") {
//    delete(rootProject.layout.buildDirectory)
//}
