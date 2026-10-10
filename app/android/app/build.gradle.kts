import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// A build against the local Supabase stack can install next to the app on the
// phone: DILBAZ_APP_ID_SUFFIX=.local gives it its own id, label and data.
val appIdSuffix = System.getenv("DILBAZ_APP_ID_SUFFIX").orEmpty()

// Release builds are signed with the upload key that android/key.properties
// names (docs/19-setup.md §5.1); neither is in git. Without it the debug key
// signs, so `flutter run --release` still works, but such an APK cannot
// update the app the upload key signed.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
} else if (gradle.startParameter.taskNames.any { it.contains("Release") }) {
    // Error level, as the Flutter plugin's own warnings: flutter runs Gradle
    // with -q.
    logger.error(
        "WARNING: android/key.properties not found: this release build is signed " +
            "with the debug key. Do not hand it out (docs/19-setup.md §5).",
    )
}

android {
    namespace = "com.dilbaz.dilbaz_app"
    // permission_handler_android 14.1 requires compiling against API 37;
    // targetSdk stays at the Flutter default.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (scheduled notifications).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.dilbaz.dilbaz_app$appIdSuffix"
        manifestPlaceholders["appLabel"] = "Dilbaz$appIdSuffix"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig =
                signingConfigs.getByName(if (keystorePropertiesFile.exists()) "release" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
