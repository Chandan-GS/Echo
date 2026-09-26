group = "com.chandangs.echo_native"
version = "1.0"

// Plugin versions come from the host app's settings.gradle.kts.
plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    namespace = "com.chandangs.echo_native"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 26
    }
}
