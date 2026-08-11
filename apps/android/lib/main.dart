import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:core/core.dart';

import 'android_proxy_bridge.dart';
import 'app.dart';

/// 平台通道兜底:从 Android 原生获取 sing-box 二进制路径。
/// (主方案为纯 Dart 的 [SingBoxLocator],通道仅作 fallback)
const MethodChannel _coreChannel = MethodChannel('nekobox/core');

String? _singBoxPath;

/// 兜底通道:原生侧会把 libsingbox.so 复制到 filesDir 并 chmod 后返回。
Future<String?> _viaChannel() async {
  try {
    final viaChannel =
        await _coreChannel.invokeMethod<String>('getSingBoxPath');
    if (viaChannel != null && viaChannel.isNotEmpty) {
      if (File(viaChannel).existsSync()) return viaChannel;
    }
  } catch (e) {
    debugPrint('NekoBox: MethodChannel 查询失败: $e');
  }
  return null;
}

/// 请求通知权限(Android 13+ 前台服务通知需要)。
Future<void> _requestNotificationPermission() async {
  try {
    final ver = int.tryParse(Platform.version.split('.').first) ?? 0;
    if (Platform.isAndroid && ver >= 13) {
      // 通过通道让原生请求 POST_NOTIFICATIONS
      await _coreChannel.invokeMethod('requestNotificationPermission');
    }
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 定位并部署 sing-box 二进制(Android: maps 探测 → 复制 → chmod)
  _singBoxPath = await SingBoxLocator.locate() ?? await _viaChannel();
  if (_singBoxPath == null || _singBoxPath!.isEmpty) {
    debugPrint('NekoBox: 未找到 sing-box 二进制');
  } else {
    debugPrint('NekoBox: sing-box 路径 = $_singBoxPath');
  }

  // 注入 sing-box 路径(优先读取 SingBoxLocator 缓存,支持设置页"重新检测"后刷新)
  CoreEnv.singBoxPathProvider =
      () => SingBoxLocator.deployedPath ?? _singBoxPath ?? '';

  // Android:前台服务桥接(通知常驻 / 开机自启 / 磁贴 / 深链接依赖它)
  if (Platform.isAndroid) {
    CoreEnv.androidProxyBridge = AndroidProxyBridgeImpl.instance;
  }

  await _requestNotificationPermission();

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
