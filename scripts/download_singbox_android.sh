#!/usr/bin/env bash
# 下载 sing-box Android arm64 二进制,重命名为 libsingbox.so
# 用法: bash scripts/download_singbox_android.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p sing-box

# 仓库已内置二进制则跳过下载
if [ -f "sing-box/libsingbox.so" ]; then
  echo "已存在 sing-box/libsingbox.so,跳过下载"
  exit 0
fi

VERSION="${1:-latest}"
BASE_URL="https://github.com/SagerNet/sing-box/releases/download"

if [ "$VERSION" = "latest" ]; then
  echo "查询 sing-box 最新版本..."
  VERSION="$(curl -fsSL "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | python3 -c 'import sys,json;print(json.load(sys.stdin)["tag_name"])')"
fi
echo "使用 sing-box 版本: $VERSION"

ARCHIVE="sing-box/singbox-android-arm64.tar.gz"
URL="${BASE_URL}/${VERSION}/sing-box-${VERSION}-android-arm64.tar.gz"
echo "下载: $URL"
curl -fL --retry 3 -o "$ARCHIVE" "$URL"

tar -xzf "$ARCHIVE" -C sing-box
mv -f sing-box/sing-box sing-box/libsingbox.so
rm -f "$ARCHIVE"

echo "OK: sing-box/libsingbox.so"
file sing-box/libsingbox.so || true
