import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// sing-box 二进制定位与部署(跨平台,重点解决 Android)。
///
/// Android 的 jniLibs 伪装了 `libsingbox.so`,位于 nativeLibraryDir
/// (`/data/app/...`),该目录是 **noexec 挂载,不能直接执行**。
/// 流程:探测源路径 → 复制到应用数据目录 → chmod 755 → 返回可执行路径。
///
/// Windows 由 [CoreEnv.singBoxPathProvider] 直接注入 exe 路径,
/// 本工具主要供 Android 使用。
class SingBoxLocator {
  SingBoxLocator._();

  /// 已部署路径缓存(进程生命周期内复用,避免重复复制 58MB)。
  static String? _deployedPath;

  /// 当前已部署路径(只读缓存,不触发定位)。
  static String? get deployedPath => _deployedPath;

  /// 定位并部署 sing-box,返回可执行文件路径;失败返回 null。
  static Future<String?> locate() async {
    if (_deployedPath != null && File(_deployedPath!).existsSync()) {
      return _deployedPath;
    }
    String? src;
    if (Platform.isAndroid) {
      src = _findSourceByMaps();
    }
    if (src == null || src.isEmpty || !File(src).existsSync()) {
      return null;
    }
    try {
      final srcFile = File(src);
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final dest = File('${dir.path}${Platform.pathSeparator}sing-box');
      if (!dest.existsSync() || dest.lengthSync() != srcFile.lengthSync()) {
        await srcFile.copy(dest.path);
        if (Platform.isAndroid) {
          await Process.run('chmod', ['755', dest.path]);
        }
        debugPrint('NekoBox: sing-box 已部署到 ${dest.path}');
      }
      if (dest.existsSync()) {
        _deployedPath = dest.path;
        return dest.path;
      }
    } catch (e) {
      debugPrint('NekoBox: 部署 sing-box 失败: $e');
    }
    return src;
  }

  /// 清空缓存,强制重新定位部署(设置页"重新检测")。
  static void reset() => _deployedPath = null;

  /// 通过 `/proc/self/maps` 定位 libflutter.so 目录(与 libsingbox.so 同目录)。
  /// 不依赖 MethodChannel,无注册时序问题。
  static String? _findSourceByMaps() {
    try {
      final maps = File('/proc/self/maps').readAsStringSync();
      // 形如: /data/app/~~xxx==/com.example.app-xxx==/lib/arm64/libflutter.so
      final m = RegExp(r'(/[\w.\-/]+)/libflutter\.so').firstMatch(maps);
      if (m == null) return null;
      final libDir = m.group(1);
      if (libDir == null) return null;
      final f = File('$libDir/libsingbox.so');
      if (f.existsSync()) return f.absolute.path;
    } catch (e) {
      debugPrint('NekoBox: /proc/self/maps 探测失败: $e');
    }
    return null;
  }
}
