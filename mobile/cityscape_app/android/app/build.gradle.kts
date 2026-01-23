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
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) keystoreProperties.load(FileInputStream(keystorePropertiesFile))

val storeFileProp = keystoreProperties.getProperty("storeFile")?.trim()
val storePass     = keystoreProperties.getProperty("storePassword")?.trim()
val keyAliasProp  = keystoreProperties.getProperty("keyAlias")?.trim()
val keyPass       = keystoreProperties.getProperty("keyPassword")?.trim()

val hasAllKeystoreProps = hasKeystore &&
    listOf(storeFileProp, storePass, keyAliasProp, keyPass).all { !it.isNullOrBlank() }

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
    namespace = "com.roadpapattes.cityscape"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.roadpapattes.cityscape"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = 24
        versionName = "0.3.10"

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
		if (hasAllKeystoreProps) {
			create("release") {
				storeFile = file(storeFileProp!!)
				storePassword = storePass!!
				keyAlias = keyAliasProp!!
				keyPassword = keyPass!!
			}
		}
	}

    buildTypes {
		getByName("release") {
			if (hasAllKeystoreProps) {
				signingConfig = signingConfigs.getByName("release")
			} else {
				println(">>> WARN: key.properties absent ou incomplet — release non signée.")
			}
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
