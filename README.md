# NekoBox Flutter

用 Flutter 重写的 NekoBox(基于 sing-box)通用代理客户端。**UI 尽量仿原版 NekoBoxForAndroid**,核心引擎直接驱动 sing-box 官方二进制(子进程方式),不依赖 gomobile。

## 项目结构

```
NekoBox-Flutter/
├── core/               # 共享 Dart 库(全部业务逻辑,跨平台复用)
│   └── lib/
│       ├── models/     #   数据模型(节点/订阅组/设置)
│       ├── fmt/        #   订阅解析(15+ 协议 + ClashMeta + sing-box JSON)
│       ├── config/     #   sing-box 配置生成器
│       ├── repo/       #   数据持久化(JSON)与订阅更新
│       └── controller/ #   sing-box 子进程控制 + 测速
├── apps/
│   ├── android/        # Android UI(仿原版:底部导航 + 节点卡片)
│   │   ├── lib/        #   Dart UI 代码
│   │   ├── assets/     #   srs 规则集 + Clash 面板(dashboard)
│   │   └── android/    #   完整 Android 平台壳(含 jniLibs/libsingbox.so)
│   └── windows/        # Windows UI(桌面布局:侧边导航 + 列表)
│       ├── lib/        # Dart UI 代码
│       └── assets/     #   Clash 面板(dashboard)
├── sing-box/           # sing-box 二进制(Android so / Windows exe+dll)
├── scripts/            # CI 辅助脚本
└── .github/workflows/  # Android(arm64) / Windows(amd64) 构建流水线
```

## 构建

本仓库通过 GitHub Actions 自动编译,不需要本地 Flutter 环境:

- **Android APK(仅 arm64)**: `.github/workflows/android.yml`
- **Windows exe(仅 amd64)**: `.github/workflows/windows.yml`

### 本地构建(可选)

```bash
# Android(需已安装 Android SDK)
cd apps/android
bash ../../scripts/prepare_android.sh   # 重建平台壳并补齐 gradle wrapper
flutter build apk --release --target-platform android-arm64

# Windows(需已安装 VS2022 + Windows SDK)
cd apps/windows
bash ../../scripts/prepare_windows.sh
flutter build windows --release
```

> `apps/android/android/` 为仓库内置的完整平台壳(Manifest / MainActivity /
> res / build.gradle.kts / jniLibs),仅 `gradle-wrapper.jar`(二进制)不入库,
> `prepare_android.sh` 会自动补齐(从 flutter create 临时项目复制)。

构建前确保 `sing-box/` 目录下有对应平台的 sing-box 二进制(或从 CI 产物中提取)。

## sing-box 二进制

仓库 `sing-box/` 已内置 sing-box 1.13.18:

- Android: `libsingbox.so`(同时复制到 `apps/android/android/.../jniLibs/arm64-v8a/`,APK 打包用)
- Windows: `sing-box.exe` + `libcronet.dll`

如需升级版本,替换 `sing-box/` 与 jniLibs 下的文件即可,CI 检测到已有二进制会跳过下载。

## 代理模式

| 平台 | 模式 | 说明 |
|---|---|---|
| Windows | 系统代理(默认)| 自动写入注册表,浏览器全局可用 |
| Windows | TUN 全局 | 需要 `wintun.dll` 与管理员权限 |
| Android | 本地代理 | 监听 127.0.0.1:2080,可复制地址手动配置 |
| Android | Root TUN(开发中)| 检测到 root 后以 tun 模式运行 |

## 协议支持

SOCKS、HTTP(S)、Shadowsocks、VMess、Trojan、VLESS、TUIC、Hysteria 2、WireGuard、SSH、AnyTLS、ShadowTLS;订阅格式支持 ss/vmess/trojan/vless 等 URI、ClashMeta YAML、sing-box outbound JSON。

## 免责声明

仅供学习交流,请遵守当地法律法规。

## Clash 面板(内置)

- `metacubexd` 面板已内置(`apps/*/assets/dashboard/`,约 4MB)
- 设置 → **Clash API** → 启用后,`clash_api.external_ui` 指向内置面板目录(对齐原版 `files/yacd`),运行时从 assets 解压到数据目录
- 点击设置页「Clash 面板」打开 `http://127.0.0.1:<端口>/ui`

## 二期功能(对齐原版)

| 功能 | 说明 | 位置 |
|---|---|---|
| 链式代理 | 组设置里选前置代理(frontProxy)/落地代理(landingProxy),生成 detour 链:客户端 → 前置 → 节点 → 落地 → 目标 | 分组管理 → 组设置 |
| 节点级 Mux | VMess/Trojan 节点可开 Mux(h2mux/smux/yamux + 并发 + padding) | 节点编辑页 |
| FakeIP | DNS FakeIP(198.18.0.0/15),TUN/VPN 模式生效 | 设置 → DNS |
| 分应用规则 | 路由规则按应用包名分流(Android 专属,需 VPN/TUN 模式,`pm list packages -U` 解析 uid) | 路由 → 规则编辑 |

## 数据存储(SQLite)

- 全部数据存于应用数据目录的 `nekobox.db`(SQLite):
  - `groups` / `profiles` / `rules` / `settings` / `state` 五张表
  - Android 原生 SQLite(应用私有目录,`/data/user/0/io.nekobox.nekobox_android/files/nekobox/`)
  - Windows 通过 ffi 打开(随 `sqlite3_flutter_libs` 自动打包 sqlite3.dll,`%APPDATA%\...\nekobox\`)
- 首次启动自动把旧 JSON 文件(`groups.json` 等)迁移进库,迁移后删除 JSON
- **备份/恢复**:设置页「数据」区段 — 备份复制数据库到 `backups/nekobox-<时间戳>.db`(保留最近 10 份),恢复从列表选择并覆盖
