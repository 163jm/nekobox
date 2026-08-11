import 'dart:io';

import 'package:flutter/services.dart';

/// Android Quick Tile / 快捷方式管理。
///
/// 通过 MethodChannel 与原生层通信,管理 Android 7.0+ 的
/// 快捷设置磁贴(Quick Settings Tile)和桌面快捷方式(Launcher Shortcut)。
/// 非 Android 平台所有方法均返回安全默认值。
class TileHelper {
  TileHelper._();

  static final TileHelper instance = TileHelper._();

  static const MethodChannel _ch = MethodChannel('nekobox/tile');

  /// 当前平台是否支持磁贴功能。
  bool get isAvailable => Platform.isAndroid;

  /// 检查磁贴是否已添加到快捷设置面板。
  Future<bool> isTileAdded() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _ch.invokeMethod<bool>('isTileAdded');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 将磁贴添加到快捷设置面板。
  ///
  /// Android 13+ 需用户在系统设置中手动添加(返回 `false` 表示需引导用户);
  /// 旧版本可直接请求添加。
  Future<bool> addTile() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _ch.invokeMethod<bool>('addTile');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 从快捷设置面板移除磁贴。
  Future<void> removeTile() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('removeTile');
    } catch (_) {}
  }

  /// 刷新磁贴状态(如连接状态变化时更新磁贴显示)。
  ///
  /// [running] 当前代理是否运行中。
  /// [label] 磁贴副标题文案(如节点名)。
  Future<void> refreshTileState({
    required bool running,
    String? label,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('refreshTileState', {
        'running': running,
        'label': label ?? '',
      });
    } catch (_) {}
  }

  /// 添加桌面快捷方式(Launcher Shortcut)。
  ///
  /// Android 8.0+ 支持静态快捷方式,Android 13+ 支持动态快捷方式。
  Future<bool> addShortcut() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _ch.invokeMethod<bool>('addShortcut');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 移除桌面快捷方式。
  Future<void> removeShortcut() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('removeShortcut');
    } catch (_) {}
  }
}