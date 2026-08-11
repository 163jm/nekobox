#!/usr/bin/env bash
# 准备 Android 平台壳:仓库已含完整 android/ 平台壳(Manifest/MainActivity/res/
# build.gradle.kts/jniLibs),本脚本只负责补齐缺失的 gradle wrapper jar(二进制不入库)。
# 用法: bash scripts/prepare_android.sh
set -euo pipefail

cd "$(dirname "$0")/../apps/android"

ANDROID_DIR="android"

if [ ! -d "$ANDROID_DIR" ]; then
  echo "未找到 $ANDROID_DIR,使用 flutter create 重建平台壳..."
  flutter create --platforms=android --org io.nekobox --project-name nekobox_android .
fi

# 补齐 gradle-wrapper.jar(flutter create 的临时项目复制而来)
if [ ! -f "$ANDROID_DIR/gradle/wrapper/gradle-wrapper.jar" ]; then
  echo "补齐 gradle-wrapper.jar..."
  TMP_DIR="$(mktemp -d)"
  flutter create --platforms=android --project-name tmp_wrapper "$TMP_DIR" >/dev/null 2>&1
  cp "$TMP_DIR/android/gradle/wrapper/gradle-wrapper.jar" \
     "$ANDROID_DIR/gradle/wrapper/gradle-wrapper.jar"
  rm -rf "$TMP_DIR"
  echo "gradle-wrapper.jar 已补齐"
fi

# 确保 gradlew 可执行
chmod +x "$ANDROID_DIR/gradlew" 2>/dev/null || true

echo "Android 平台壳就绪(使用仓库内置 $ANDROID_DIR/)"
