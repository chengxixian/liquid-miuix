// 顶层构建脚本。版本号与参考实现（KSuRoot）保持一致：
// miuix 0.9.4 要求 AGP >= 9.1.0 / Gradle >= 9.4.1 / compileSdk 37。
plugins {
    id("com.android.library") version "9.2.1" apply false
    id("com.android.application") version "9.2.1" apply false
    id("org.jetbrains.kotlin.android") version "2.4.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.20" apply false
}
