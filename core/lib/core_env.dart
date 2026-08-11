import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'controller/android_proxy_bridge.dart';

/// 环境抽象:数据目录 / sing-box 二进制 / srs 规则集文件。
class CoreEnv {
  CoreEnv._();

  /// sing-box 可执行文件路径;由各平台 app 注入。
  static String Function()? singBoxPathProvider;

  /// 系统代理启用钩子:连接建立成功后调用(参数为代理地址,如 127.0.0.1:2080)。
  /// Windows app 注入 `WindowsSystemProxy.enable`,Android 不注入。
  static Future<void> Function(String proxyServer)? systemProxyEnable;

  /// 系统代理关闭钩子:连接断开/意外退出时调用。
  /// Windows app 注入 `WindowsSystemProxy.disable`。
  static Future<void> Function()? systemProxyDisable;

  /// Android 前台服务桥接(托管 sing-box 子进程 + 通知 + 开机自启等)。
  /// 由 Android app 注入;为 null 时回退 Process.start 子进程方案。
  static AndroidProxyBridge? androidProxyBridge;

  static String get singBoxPath {
    final pv = singBoxPathProvider;
    if (pv != null) {
      final path = pv();
      if (path.isNotEmpty && File(path).existsSync()) {
        return path;
      }
    }
    // 兜底:工作目录 / 仓库根
    final candidates = [
      'sing-box${Platform.isWindows ? '.exe' : ''}',
      '${Directory.current.path}${Platform.pathSeparator}'
          'sing-box${Platform.isWindows ? '.exe' : ''}',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return '';
  }

  static bool get hasSingBox => singBoxPath.isNotEmpty;

  /// 应用数据目录(由 path_provider 提供)
  static Future<Directory> getDataDirectory() async {
    final dir = await getApplicationSupportDirectory();
    return Directory('${dir.path}${Platform.pathSeparator}nekobox');
  }

  /// SQLite 数据库文件路径
  static Future<String> getDatabasePath() async {
    final data = await getDataDirectory();
    return p.join(data.path, 'nekobox.db');
  }

  /// 备份目录(数据目录下 backups/)
  static Future<Directory> getBackupDirectory() async {
    final data = await getDataDirectory();
    return Directory(p.join(data.path, 'backups'));
  }

  /// 临时目录
  static Future<Directory> getTempDirectory() async {
    final dir = await getTemporaryDirectory();
    return Directory('${dir.path}${Platform.pathSeparator}nekobox');
  }

  /// srs 规则集目录(数据目录下 rules/)
  static Future<Directory> getSrsDirectory() async {
    final data = await getDataDirectory();
    return Directory('${data.path}${Platform.pathSeparator}rules');
  }

  /// Clash 面板(dashboard)目录(数据目录下 dashboard/,对齐原版 files/yacd)
  static Future<Directory> getDashboardDirectory() async {
    final data = await getDataDirectory();
    return Directory('${data.path}${Platform.pathSeparator}dashboard');
  }

  /// 面板访问地址(对齐原版 yacdURL: http://127.0.0.1:9090/ui)
  static String dashboardUrl(int clashApiPort) =>
      'http://127.0.0.1:$clashApiPort/ui';

  /// 内置 srs 文件名列表(与预设分流对应)
  static const List<String> builtinSrsFiles = [
    'geosite-cn.srs',
    'geoip-cn.srs',
    'category-ads.srs',
  ];

  /// 同步 srs 规则集到本地目录:
  /// - Android: 从 assets 解压
  /// - 桌面: 从 exe 旁 / 仓库 sing-box 目录复制
  /// 返回实际可用的 srs 文件名列表(不含路径)。
  static Future<List<String>> syncSrsFiles() async {
    final dir = await getSrsDirectory();
    await dir.create(recursive: true);
    final available = <String>[];

    for (final name in builtinSrsFiles) {
      final dest = File(p.join(dir.path, name));
      var ok = false;
      try {
        if (!await dest.exists()) {
          if (Platform.isAndroid) {
            // 从 Flutter assets 解压
            final data = await rootBundle.load('assets/rules/$name');
            await dest.writeAsBytes(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
                flush: true);
            ok = true;
          } else {
            // 从候选目录复制(exe 旁、仓库 sing-box/)
            final candidates = [
              if (!Platform.isAndroid)
                p.join(File(Platform.resolvedExecutable).parent.path, name),
              p.join(Directory.current.path, 'sing-box', name),
            ];
            for (final src in candidates) {
              final f = File(src);
              if (await f.exists()) {
                await f.copy(dest.path);
                ok = true;
                break;
              }
            }
          }
        } else {
          ok = true;
        }
      } catch (_) {
        ok = false;
      }
      if (ok) available.add(name);
    }
    return available;
  }

  /// 同步 Clash 面板到本地目录(数据目录 dashboard/):
  /// 两平台都从 Flutter assets 解压(assets 已随 APK/exe 打包)。
  /// 返回是否成功;面板文件已存在则跳过。
  static Future<bool> syncDashboard() async {
    final dir = await getDashboardDirectory();
    await dir.create(recursive: true);
    try {
      // 从 asset manifest 列出 dashboard 下全部文件
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final files = manifest
          .listAssets()
          .where((e) => e.startsWith('assets/dashboard/'))
          .toList();
      if (files.isEmpty) return false;

      for (final asset in files) {
        final rel = asset.substring('assets/dashboard/'.length);
        final dest = File(p.join(dir.path, rel));
        if (await dest.exists()) continue;
        await dest.parent.create(recursive: true);
        final data = await rootBundle.load(asset);
        await dest.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
