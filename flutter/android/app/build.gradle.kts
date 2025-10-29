// --- imports DOIVENT être au début ---
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// --- Keystore (release) ---
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Lire android/local.properties en priorité
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) load(FileInputStream(f))
}
val mapsApiKey = (localProps.getProperty("MAPS_API_KEY")
    ?: System.getenv("MAPS_API_KEY")
    ?: "").trim()

println(">>> Gradle: MAPS_API_KEY length = ${mapsApiKey.length}") // trace utile

android {
    namespace = "com.roadpapattes.escape_city_client_clean"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.roadpapattes.escape_city_client_clean"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = 1
        versionName = "0.1.0"

        // Injecte le placeholder utilisé par AndroidManifest.xml
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
        // (équivalent) manifestPlaceholders += mapOf("MAPS_API_KEY" to mapsApiKey)
    }

    // Java 17
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // rien à ajouter ici pour Flutter
}

// Kotlin JVM 17
tasks.withType<KotlinCompile>().configureEach {
    kotlinOptions { jvmTarget = "17" }
}
// (alternative moderne)
// kotlin { jvmToolchain(17) }
