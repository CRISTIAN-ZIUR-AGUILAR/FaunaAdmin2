plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.faunadmin2"

    // SDKs
    compileSdk = 35

    defaultConfig {
        applicationId = "com.example.faunadmin2"

        // Requisito de tflite_flutter
        minSdk = 26
        targetSdk = 35

        versionCode = 1
        versionName = "1.0.0"

        // opcional, por si superas 64k métodos
        multiDexEnabled = true
    }

    // Java/Kotlin toolchains
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            // mientras no tengas firma de release, usa la de debug
            signingConfig = signingConfigs.getByName("debug")
            // isMinifyEnabled = false
            // isShrinkResources = false
        }
    }
}

// ruta del proyecto Flutter (Kotlin DSL)
flutter {
    source = "../.."
}
