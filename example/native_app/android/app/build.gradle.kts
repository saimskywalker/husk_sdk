plugins {
    id("com.android.application")
}

android {
    namespace = "com.example.native_app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.native_app"
        minSdk = 24
        targetSdk = 36
    }
}

// BEGIN husk_sdk: generated from husk.yaml, do not edit. Regenerate with `dart run husk_sdk generate`.
// Links the vendor AAR when present, a stub otherwise; see husk.gradle.
apply(from = "husk.gradle")
// END husk_sdk
