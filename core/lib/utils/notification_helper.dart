import 'dart:io';

import 'package:flutter/services.dart';

/// 通知抽象接口。
///
/// 核心层通过此接口与平台通知系统解耦:Android 端通过 MethodChannel
/// 实现(前台服务通知 + 速度通知),其他平台提供空实现。
abstract class NotificationHelper {
  /// 显示速度通知(ongoing,不可清除)。
  ///
  /// 用于代理运行时在通知栏显示实时上下行速度。
  Future<void> showSpeedNotification({
    String? title,
    String? text,
  });

  /// 更新速度通知的当前速度值。
  ///
  /// [upSpeed] 上行速度字符串(如 "1.2 MB/s")。
  /// [downSpeed] 下行速度字符串。
  /// [label] 可选的附加说明(如当前节点名)。
  Future<void> updateSpeedNotification({
    String? upSpeed,
    String? downSpeed,
    String? label,
  });

  /// 取消速度通知。
  Future<void> cancelSpeedNotification();

  /// 显示订阅更新完成通知。
  ///
  /// [success] 更新是否成功。
  /// [message] 通知正文(如 "已更新 3 个订阅")。
  Future<void> showSubscriptionUpdateNotification({
    required bool success,
    String? message,
  });

  /// 取消所有通知。
  Future<void> cancelAllNotifications();
}

/// 空实现(非 Android 平台或未注入时使用)。
class NoOpNotificationHelper implements NotificationHelper {
  @override
  Future<void> showSpeedNotification({String? title, String? text}) async {}

  @override
  Future<void> updateSpeedNotification(
      {String? upSpeed, String? downSpeed, String? label}) async {}

  @override
  Future<void> cancelSpeedNotification() async {}

  @override
  Future<void> showSubscriptionUpdateNotification(
      {required bool success, String? message}) async {}

  @override
  Future<void> cancelAllNotifications() async {}
}

/// 默认实例;由平台层(Android app)在初始化时注入实现。
NotificationHelper _instance = NoOpNotificationHelper();

NotificationHelper get notificationHelper => _instance;

void setNotificationHelper(NotificationHelper helper) {
  _instance = helper;
}

/// Android 通知实现(通过 MethodChannel 与原生层通信)。
class AndroidNotificationHelper implements NotificationHelper {
  AndroidNotificationHelper._();

  static final AndroidNotificationHelper instance =
      AndroidNotificationHelper._();

  static const MethodChannel _ch = MethodChannel('nekobox/notification');

  @override
  Future<void> showSpeedNotification({String? title, String? text}) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('showSpeedNotification', {
        'title': title ?? 'NekoBox 代理运行中',
        'text': text ?? '等待数据…',
      });
    } catch (_) {}
  }

  @override
  Future<void> updateSpeedNotification({
    String? upSpeed,
    String? downSpeed,
    String? label,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('updateSpeedNotification', {
        'upSpeed': upSpeed ?? '',
        'downSpeed': downSpeed ?? '',
        'label': label ?? '',
      });
    } catch (_) {}
  }

  @override
  Future<void> cancelSpeedNotification() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('cancelSpeedNotification');
    } catch (_) {}
  }

  @override
  Future<void> showSubscriptionUpdateNotification({
    required bool success,
    String? message,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('showSubscriptionUpdateNotification', {
        'success': success,
        'message': message ?? (success ? '订阅更新完成' : '订阅更新失败'),
      });
    } catch (_) {}
  }

  @override
  Future<void> cancelAllNotifications() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('cancelAllNotifications');
    } catch (_) {}
  }
}