plugins {
    // 注意：AGP 9 起 `com.android.application` 已内置 Kotlin 支持，
    // 再显式声明 `org.jetbrains.kotlin.android` 会报
    // "The 'org.jetbrains.kotlin.android' plugin is no longer required for Kotlin support"。
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.liquidmiuix.example"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.liquidmiuix.example"
        minSdk = 33
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

dependencies {
    implementation(project(":library"))

    // library 里用的是 implementation，不会传递到调用方，所以这里要显式声明。
    implementation("androidx.compose.material3:material3:1.5.0-alpha22")
    implementation("androidx.compose.material:material-icons-extended:1.7.8")
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.core:core-ktx:1.17.0")
}
