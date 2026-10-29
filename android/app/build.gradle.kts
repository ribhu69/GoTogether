plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.gotogether.app"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.gotogether.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 2
        versionName = "0.2"
    }
    buildFeatures { compose = true }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.10.01"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.4")
    implementation("org.osmdroid:osmdroid-android:6.1.20")
    implementation("androidx.preference:preference:1.2.1")
    testImplementation("junit:junit:4.13.2")
}
