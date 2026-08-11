import 'dart:io';

import 'package:flutter/services.dart';

/// Android 开机自启管理。
///
/// 通过 MethodChannel 与原生层通信,控制 BOOT_COMPLETED 广播接收器
/// 和直接启动权限(Android 14+)。非 Android 平台方法均返回安全默认值。
class BootHelper {
  BootHelper._();

  static final BootHelper instance = BootHelper._();

  static const MethodChannel _ch = MethodChannel('nekobox/boot');

  /// 当前平台是否支持开机自启。
  bool get isSupported => Platform.isAndroid;

  /// 检查开机自启是否已启用。
  ///
  /// 读取 SharedPreferences 中保存的用户设置,并检查
  /// BOOT_COMPLETED 接收器是否在清单中声明。
  Future<bool> isAutoStartEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _ch.invokeMethod<bool>('isAutoStartEnabled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 启用开机自启。
  ///
  /// 将在 SharedPreferences 中记录用户选择,BOOT_COMPLETED
  /// 接收器触发后会读取此值决定是否自动启动代理服务。
  Future<bool> enableAutoStart() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _ch.invokeMethod<bool>('enableAutoStart');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 禁用开机自启。
  Future<void> disableAutoStart() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('disableAutoStart');
    } catch (_) {}
  }

  /// 请求直接启动权限(Android 14+,部分 ROM 需要)。
  ///
  /// 某些 Android 定制 ROM(如 MIUI、ColorOS)要求用户在系统设置中
  /// 手动允许"自启动"权限。此方法打开对应的系统设置页面。
  Future<void> requestAutoStartPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('requestAutoStartPermission');
    } catch (_) {}
  }

  /// 检查是否需要请求直接启动权限。
  ///
  /// Android 14+ (API 34+) 必须声明 USE_FULL_SCREEN_INTENT 权限
  /// 才能从后台(如 BOOT_COMPLETED)启动 Activity。
  Future<bool> needsFullScreenIntentPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final result =
          await _ch.invokeMethod<bool>('needsFullScreenIntentPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}