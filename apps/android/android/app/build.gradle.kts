plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// 说明: 本工程使用 Flutter Built-in Kotlin(Flutter 3.44+),
// 不显式应用 kotlin-android 插件, 由 flutter-gradle-plugin 内置 Kotlin 支持。

android {
    namespace = "io.nekobox.nekobox_android"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.nekobox.nekobox_android"
        // 仅 arm64
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        // AndroidManifest 中 ${applicationName} 占位符
        manifestPlaceholders["applicationName"] = "android.app.Application"
        // TileService / NetworkCallback / getSystemService(Class) 等需 API 24+
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // 开发阶段使用 debug 签名
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // NDK C 库:tun fd 传递 + sing-box 子进程启动(非 root TUN)
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }
}

flutter {
    source = "../.."
}
