#!/usr/bin/env bash
# 准备 Windows 平台壳:删除旧壳 → flutter create 生成
# 用法: bash scripts/prepare_windows.sh
set -euo pipefail

cd "$(dirname "$0")/../apps/windows"

rm -rf windows
flutter create --platforms=windows --org io.nekobox --project-name nekobox_windows .

# flutter create 生成的默认 widget_test.dart 引用模板 MyApp,
# 与本项目 main.dart 不兼容,删除以免 flutter test 报错
rm -rf test

echo "Windows 平台壳准备完成"
