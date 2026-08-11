import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import 'package:core/core.dart';

import 'app.dart';
import 'windows_sysproxy.dart';

/// Windows 上探测 sing-box.exe 路径:
/// 1. 可执行文件同目录(sing-box.exe)
/// 2. 环境变量 NEKOBOX_SINGBOX
/// 3. 当前工作目录
String _findSingBox() {
  const name = 'sing-box.exe';
  final candidates = <String>[];
  try {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    candidates.add('$exeDir${Platform.pathSeparator}$name');
    candidates.add(
        '$exeDir${Platform.pathSeparator}..${Platform.pathSeparator}..'
        '${Platform.pathSeparator}..${Platform.pathSeparator}sing-box'
        '${Platform.pathSeparator}$name');
  } catch (_) {}
  final env = Platform.environment['NEKOBOX_SINGBOX'];
  if (env != null && env.isNotEmpty) {
    candidates.add(env);
  }
  candidates.add(name);
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return '';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CoreEnv.singBoxPathProvider = _findSingBox;
  // 系统代理联动:连接建立后设置 Windows 系统代理,断开/退出时恢复。
  // 由 SingBoxController 在 start/stop/异常退出时统一调用。
  CoreEnv.systemProxyEnable = WindowsSystemProxy.enable;
  CoreEnv.systemProxyDisable = WindowsSystemProxy.disable;
  try {
    await Repository.init();
  } catch (e) {
    debugPrint('Repository.init failed: $e');
    // 自愈:删除可能损坏的数据库后重试一次
    try {
      final dbPath = await CoreEnv.getDatabasePath();
      final f = File(dbPath);
      if (await f.exists()) await f.delete();
      AndroidUidResolver.invalidate();
      await Repository.init();
    } catch (e2) {
      debugPrint('Repository retry failed: $e2');
    }
  }
  runApp(const NekoBoxApp());
}
