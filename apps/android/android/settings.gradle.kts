pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    // 显式 Kotlin 2.2.20:mobile_scanner 等新依赖要求 Kotlin 2.2+
    // (Flutter Built-in Kotlin 为 2.0.0,元数据不兼容)
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
