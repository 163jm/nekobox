#!/usr/bin/env bash
# 下载 sing-box Windows amd64 二进制(sing-box.exe + wintun.dll)
# 用法: bash scripts/download_singbox_windows.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p sing-box

# 仓库已内置二进制则跳过下载
if [ -f "sing-box/sing-box.exe" ]; then
  echo "已存在 sing-box/sing-box.exe,跳过下载"
  exit 0
fi

VERSION="${1:-latest}"
BASE_URL="https://github.com/SagerNet/sing-box/releases/download"

if [ "$VERSION" = "latest" ]; then
  echo "查询 sing-box 最新版本..."
  VERSION="$(curl -fsSL "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | python3 -c 'import sys,json;print(json.load(sys.stdin)["tag_name"])')"
fi
echo "使用 sing-box 版本: $VERSION"

ARCHIVE="sing-box/singbox-windows-amd64.zip"
URL="${BASE_URL}/${VERSION}/sing-box-${VERSION}-windows-amd64.zip"
echo "下载: $URL"
curl -fL --retry 3 -o "$ARCHIVE" "$URL"

# zip 解压(使用 unzip;Windows runner 自带,否则用 python)
if command -v unzip >/dev/null 2>&1; then
  unzip -o -j "$ARCHIVE" "sing-box-${VERSION}-windows-amd64/sing-box.exe" -d sing-box
  unzip -o -j "$ARCHIVE" "sing-box-${VERSION}-windows-amd64/wintun.dll" -d sing-box || true
else
  PY="python3"
  command -v python3 >/dev/null 2>&1 || PY="python"
  "$PY" - "$ARCHIVE" <<'EOF'
import sys, zipfile
zf = zipfile.ZipFile(sys.argv[1])
for name in zf.namelist():
    base = name.split('/')[-1]
    if base in ('sing-box.exe', 'wintun.dll'):
        with open('sing-box/' + base, 'wb') as f:
            f.write(zf.read(name))
EOF
fi
rm -f "$ARCHIVE"

echo "OK: sing-box/sing-box.exe"
ls -la sing-box/
