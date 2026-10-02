plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.egebaykal.starmap"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Set, and permanent. Google Play ties a listing to this string for the life of the app:
        // once something is published under it, it can never be changed.
        applicationId = "com.egebaykal.starmap"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // NOT PUBLISHABLE AS IT STANDS, and this is the first thing to fix before a store
            // listing. A release build signed with the debug keystore installs fine on your own
            // phone and is rejected by Google Play, because the debug key is shared by every
            // Flutter project on earth.
            //
            // What has to happen, once, by the account holder:
            //   1. keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA \
            //        -keysize 2048 -validity 10000 -alias upload
            //   2. put its path and passwords in android/key.properties  (NEVER commit that file,
            //      and never commit the .jks either - losing the key means losing the ability to
            //      update the app, and leaking it means someone else can ship as you)
            //   3. read key.properties here and use it as the signingConfig
            //
            // Left on the debug key deliberately rather than half-wired: a signing config that
            // looks real but points at a keystore nobody has is worse than one that says so.
            signingConfig = signingConfigs.getByName("debug")
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
