import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

android {
    namespace = "com.pettexo.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.pettexo.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        val mapsApiKey =
            (localProperties.getProperty("MAPS_API_KEY")?.takeIf { it.isNotBlank() })
                ?: System.getenv("PETTXO_MAPS_API_KEY")?.takeIf { it.isNotBlank() }
                ?: ""
        manifestPlaceholders["MAPS_API_KEY"] =
            mapsApiKey
    }

    signingConfigs {
        create("release") {
            val storeFilePath =
                keystoreProperties.getProperty("storeFile")
                    ?: System.getenv("PETTXO_UPLOAD_STORE_FILE")
            val storePasswordValue =
                keystoreProperties.getProperty("storePassword")
                    ?: System.getenv("PETTXO_UPLOAD_STORE_PASSWORD")
            val keyAliasValue =
                keystoreProperties.getProperty("keyAlias")
                    ?: System.getenv("PETTXO_UPLOAD_KEY_ALIAS")
            val keyPasswordValue =
                keystoreProperties.getProperty("keyPassword")
                    ?: System.getenv("PETTXO_UPLOAD_KEY_PASSWORD")

            if (!storeFilePath.isNullOrBlank()) {
                storeFile = file(storeFilePath)
            }
            storePassword = storePasswordValue
            keyAlias = keyAliasValue
            keyPassword = keyPasswordValue
        }
    }

    buildTypes {
        debug {
            isShrinkResources = false
        }
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig =
                if (signingConfigs.getByName("release").storeFile != null) {
                    signingConfigs.getByName("release")
                } else {
                    null
                }
        }
    }
}

val requestedTasks = gradle.startParameter.taskNames.joinToString(" ")
if (
    requestedTasks.contains("Release", ignoreCase = true) &&
    (
        localProperties.getProperty("MAPS_API_KEY")?.isBlank() != false &&
        System.getenv("PETTXO_MAPS_API_KEY")?.isBlank() != false
    )
) {
    throw GradleException(
        "Google Maps API key is missing. Add MAPS_API_KEY to android/local.properties or export PETTXO_MAPS_API_KEY for release builds.",
    )
}

flutter {
    source = "../.."
}
