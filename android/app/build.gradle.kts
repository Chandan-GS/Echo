import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.chandangs.echo"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        create("release") {
            val keystoreProperties = Properties()
            val keystorePropertiesFile = rootProject.file("key.properties")
            
            if (keystorePropertiesFile.exists()) {
                keystoreProperties.load(FileInputStream(keystorePropertiesFile))
                
                storeFile = file(keystoreProperties.getProperty("storeFile").replace("\"", ""))
                storePassword = keystoreProperties.getProperty("storePassword").replace("\"", "")
                keyAlias = keystoreProperties.getProperty("keyAlias").replace("\"", "")
                keyPassword = keystoreProperties.getProperty("keyPassword").replace("\"", "")
            }
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    // ECHO_DEMO=1 (with --dart-define=ECHO_DEMO=true) builds "Echo Demo" for
    // filming: its own app id, so it installs beside the real app without
    // touching its data.
    val demo = System.getenv("ECHO_DEMO") == "1"

    defaultConfig {
        applicationId = if (demo) "com.chandangs.echo.demo" else "com.chandangs.echo"
        manifestPlaceholders["appLabel"] = if (demo) "Echo Demo" else "Echo"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
        }
        getByName("release") {
            // A release signed with the debug key can't be uploaded to Play
            // as an update, so a missing upload key fails the build rather
            // than falling back quietly. CI's sideload APKs opt in with
            // ECHO_ALLOW_DEBUG_SIGNING=1.
            val releaseConfig = signingConfigs.getByName("release")
            val hasUploadKey = releaseConfig.storeFile?.exists() == true
            signingConfig = if (hasUploadKey) releaseConfig else signingConfigs.getByName("debug")
            if (!hasUploadKey && System.getenv("ECHO_ALLOW_DEBUG_SIGNING") != "1") {
                gradle.taskGraph.whenReady {
                    if (allTasks.any { it.project == project && it.name.endsWith("Release") }) {
                        throw GradleException(
                            "No upload key (android/key.properties): set ECHO_ALLOW_DEBUG_SIGNING=1 for a debug-signed release.",
                        )
                    }
                }
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}