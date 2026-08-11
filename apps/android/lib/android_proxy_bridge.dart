import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:core/core.dart';

/// Android 前台服务桥接实现。
///
/// 通过 MethodChannel 控制 [SingBoxService],状态与日志从
/// 文件(filesDir 下)读取——App 退后台/重启后依然可靠。
class AndroidProxyBridgeImpl implements AndroidProxyBridge {
  AndroidProxyBridgeImpl._();

  static final AndroidProxyBridgeImpl instance = AndroidProxyBridgeImpl._();

  static const MethodChannel _ch = MethodChannel('nekobox/core');

  /// 应用私有数据目录(filesDir)。
  static Future<Directory> get _supportDir async =>
      await getApplicationSupportDirectory();

  @override
  Future<void> startService(String configPath, int port) async {
    await _ch.invokeMethod('startService', {
      'configPath': configPath,
      'port': port,
    });
  }

  @override
  Future<void> stopService() async {
    await _ch.invokeMethod('stopService');
  }

  @override
  Future<void> restartService() async {
    await _ch.invokeMethod('restartService');
  }

  @override
  Future<void> startVpn(String configPath, int port) async {
    await _ch.invokeMethod('startVpn', {
      'configPath': configPath,
      'port': port,
    });
  }

  @override
  Future<void> stopVpn() async {
    await _ch.invokeMethod('stopVpn');
  }

  @override
  Future<bool> isRunning() async {
    final dir = await _supportDir;
    final f = File('${dir.path}${Platform.pathSeparator}singbox-state.json');
    if (!await f.exists()) return false;
    try {
      final state = jsonDecode(await f.readAsString());
      return (state['running'] as bool?) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> readLogTail({int maxLines = 300}) async {
    final dir = await _supportDir;
    final f = File('${dir.path}${Platform.pathSeparator}singbox.log');
    if (!await f.exists()) return [];
    try {
      final lines = (await f.readAsString())
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.length <= maxLines) return lines;
      return lines.sublist(lines.length - maxLines);
    } catch (_) {
      return [];
    }
  }

  @override
  Future<String?> getPendingImport() async {
    return await _ch.invokeMethod<String>('getPendingImport');
  }

  @override
  Future<void> clearPendingImport() async {
    await _ch.invokeMethod('clearPendingImport');
  }

  @override
  Future<bool> prepareVpn() async {
    final ok = await _ch.invokeMethod<bool>('prepareVpn');
    return ok ?? false;
  }
}
