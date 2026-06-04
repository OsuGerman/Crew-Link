import com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.crewlink.crew_link"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 17+ verlangt Core-Library-Desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.crewlink.crew_link"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Echter Release-Key wird über Umgebungsvariablen eingespielt
        // (CI-Secret oder lokal). Ohne sie bleibt der Block leer und der
        // release-Build fällt unten auf den Debug-Key zurück.
        create("release") {
            val keystorePath = System.getenv("RELEASE_KEYSTORE_FILE")
            if (keystorePath != null) {
                storeFile = file(keystorePath)
                storePassword = System.getenv("RELEASE_STORE_PASSWORD")
                keyAlias = System.getenv("RELEASE_KEY_ALIAS")
                keyPassword = System.getenv("RELEASE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Play-uploadfähig signieren, sobald RELEASE_KEYSTORE_FILE gesetzt
            // ist; sonst Debug-Key (nicht Play-fähig) mit deutlicher Warnung.
            signingConfig = if (System.getenv("RELEASE_KEYSTORE_FILE") != null) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "Release-Build mit Debug-Key signiert — RELEASE_KEYSTORE_FILE " +
                        "(+ RELEASE_STORE_PASSWORD/RELEASE_KEY_ALIAS/RELEASE_KEY_PASSWORD) " +
                        "für Play-Upload setzen.",
                )
                signingConfigs.getByName("debug")
            }
            // Crashlytics-Mapping-Upload deaktivieren: scheitert mit den
            // Platzhalter-google-services.json-Credentials (HTTP 400). Fuer
            // dev/debug-signierte APKs nicht benoetigt.
            configure<CrashlyticsExtension> {
                mappingFileUploadEnabled = false
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Pflicht-Laufzeit-Lib fuer Core-Library-Desugaring (flutter_local_notifications).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
