allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    val configureLibrary: () -> Unit = {
        if (plugins.hasPlugin("com.android.library")) {
            val android = extensions.getByName("android") as com.android.build.gradle.LibraryExtension
            if (android.namespace == null) {
                android.namespace = project.group.toString()
            }
            android.compileSdk = 36
            android.ndkVersion = "26.1.10909125"
        }
    }
    if (state.executed) {
        configureLibrary()
    } else {
        afterEvaluate { configureLibrary() }
    }
    pluginManager.withPlugin("com.android.application") {
        val android = extensions.getByName("android") as com.android.build.gradle.internal.dsl.BaseAppModuleExtension
        android.ndkVersion = "26.1.10909125"
    }
    // Pin every module's Kotlin compilation to JVM 17. Several plugins (e.g.
    // tflite_flutter, flutter_tts) don't declare a Kotlin jvmTarget, so it
    // defaults to the build JDK (17) while their Java stays at 11. We normalise
    // Kotlin to 17 here; the residual Java=11/Kotlin=17 gap on those plugin
    // modules is downgraded from a hard error to a warning via
    // `kotlin.jvm.target.validation.mode=warning` in gradle.properties.
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}
