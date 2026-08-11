import 'dart:io';

/// 分应用规则用的包名 → uid 映射。
///
/// 对齐原版 PackageCache:Android 上通过 `pm list packages -U`
/// 一次性读取全量包名与 uid(无需 root)。非 Android 平台返回空,
/// 分应用规则仅在 VPN/TUN 模式(流量经 sing-box)下生效。
class AndroidUidResolver {
  AndroidUidResolver._();

  static Map<String, int>? _cache;

  /// 获取包名 → uid 映射(带缓存,进程生命周期内一次)。
  static Future<Map<String, int>> load() async {
    if (_cache != null) return _cache!;
    final result = <String, int>{};
    if (Platform.isAndroid) {
      try {
        final proc = await Process.run('pm', ['list', 'packages', '-U']);
        if (proc.exitCode == 0) {
          final lines = (proc.stdout as String).split('\n');
          final re = RegExp(r'^package:(.+)\s+uid:(\d+)$');
          for (final line in lines) {
            final m = re.firstMatch(line.trim());
            if (m != null) {
              result[m.group(1)!] = int.tryParse(m.group(2)!) ?? -1;
            }
          }
        }
      } catch (_) {}
    }
    _cache = result;
    return result;
  }

  /// 清空缓存(包安装/卸载后可调用)。
  static void invalidate() => _cache = null;

  /// 已安装应用包名列表(第三方应用)。
  ///
  /// Android 上通过 `pm list packages -3` 列出**第三方**应用
  /// (系统应用过多且基本不需要代理)。非 Android 平台返回空列表。
  static Future<List<String>> listInstalledApps() async {
    final result = <String>[];
    if (!Platform.isAndroid) return result;
    try {
      final proc = await Process.run('pm', ['list', 'packages', '-3']);
      if (proc.exitCode == 0) {
        final lines = (proc.stdout as String).split('\n');
        final re = RegExp(r'^package:(.+)$');
        for (final line in lines) {
          final m = re.firstMatch(line.trim());
          if (m != null) {
            final pkg = m.group(1)!.trim();
            if (pkg.isNotEmpty) result.add(pkg);
          }
        }
      }
    } catch (_) {}
    result.sort();
    return result;
  }
}
