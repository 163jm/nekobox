# sing-box 二进制目录

把对应平台的 sing-box 二进制放到这里(不入库):

## Android(arm64)

从 [sing-box Releases](https://github.com/SagerNet/sing-box/releases) 下载
`sing-box-<version>-android-arm64.tar.gz`,解压出 `sing-box` 可执行文件,
**重命名为 `libsingbox.so`** 后放到本目录。

> 运行时 APK 内嵌的是重命名后的 `libsingbox.so`(见 `scripts/prepare_android.sh`),
> 这里放一个原始二进制仅用于本地调试。

## Windows(amd64)

下载 `sing-box-<version>-windows-amd64.zip`,解压出:

- `sing-box.exe` — 代理核心
- `wintun.dll` — TUN 模式必需(Windows 10/11 自带 wintun 则无需)

放到本目录即可,Windows 应用启动时会自动探测本目录。

CI 会自动完成上述下载,无需手动放置。
