import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../fmt/universal_fmt.dart';
import '../models/settings.dart';
import '../repo/repository.dart';
import '../repo/subscription_updater.dart';

/// 订阅自动更新调度器。
///
/// 基于 [Timer] 的周期性订阅更新调度,支持:
/// - 可配置更新间隔(分钟,从 [AppSettings.autoUpdateInterval] 读取)
/// - 暂停 / 恢复控制
/// - 遍历所有活动订阅组执行更新
/// - 尊重计量网络设置([AppSettings.updateOnMeteredNetwork])
/// - 通过 [StreamController] 发送更新事件,供 UI 层展示通知
/// - 错误隔离:单个组更新失败不影响其他组
///
/// 使用单例模式: [SubscriptionScheduler.instance]
class SubscriptionScheduler {
  SubscriptionScheduler._();

  static final SubscriptionScheduler instance = SubscriptionScheduler._();

  Timer? _timer;
  bool _isRunning = false;
  bool _isUpdating = false;
  int _intervalMinutes = 60;

  final StreamController<UpdateEvent> _eventController =
      StreamController<UpdateEvent>.broadcast();

  Stream<UpdateEvent> get events => _eventController.stream;

  /// 计量网络检测回调(由平台层注入)。
  /// 返回 true 表示当前网络为计量网络(如移动数据)。
  bool Function()? isMeteredNetworkCallback;

  void start({bool immediate = true}) {
    if (_isRunning) return;
    final settings = Repository.instance.settings;
    if (!settings.autoUpdateSubscription) return;

    _intervalMinutes =
        settings.autoUpdateInterval > 0 ? settings.autoUpdateInterval : 60;
    _isRunning = true;

    if (immediate) {
      _doUpdateAll().catchError((_) {});
    }
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(minutes: _intervalMinutes),
      (_) {
        _doUpdateAll().catchError((_) {});
      },
    );
  }

  void pause() {
    if (!_isRunning) return;
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    if (_isRunning) return;
    final settings = Repository.instance.settings;
    if (!settings.autoUpdateSubscription) return;
    _intervalMinutes =
        settings.autoUpdateInterval > 0 ? settings.autoUpdateInterval : 60;
    _isRunning = true;
    _scheduleNext();
  }

  void applySettings(AppSettings settings) {
    if (!settings.autoUpdateSubscription) {
      pause();
      return;
    }
    _intervalMinutes =
        settings.autoUpdateInterval > 0 ? settings.autoUpdateInterval : 60;
    if (!_isRunning) {
      start(immediate: false);
    } else {
      _scheduleNext();
    }
  }

  Future<UpdateResult> updateAll() async {
    return _doUpdateAll();
  }

  Future<UpdateResult> _doUpdateAll() async {
    if (_isUpdating) {
      return UpdateResult.skipped('已有更新任务在执行中');
    }
    _isUpdating = true;

    try {
      final repo = Repository.instance;
      final settings = repo.settings;

      if (settings.meteredNetwork && !settings.updateOnMeteredNetwork) {
        _isUpdating = false;
        final result = UpdateResult.skipped('计量网络下跳过订阅更新');
        _eventController.add(UpdateEvent.completed(result));
        return result;
      }

      if (isMeteredNetworkCallback != null && isMeteredNetworkCallback!()) {
        _isUpdating = false;
        final result = UpdateResult.skipped('当前为计量网络,跳过更新');
        _eventController.add(UpdateEvent.completed(result));
        return result;
      }

      final groups = repo.groups.where((g) => g.subscription).toList();
      if (groups.isEmpty) {
        _isUpdating = false;
        final result = UpdateResult.skipped('没有需要更新的订阅组');
        _eventController.add(UpdateEvent.completed(result));
        return result;
      }

      final successCount = <String>[];
      final failedCount = <String>[];

      _eventController.add(UpdateEvent.started(groups.length));

      for (final group in groups) {
        try {
          final text = await SubscriptionUpdater.fetchText(group.url);
          final profiles = UniversalFmt.parseSubscriptionText(text);
          if (profiles.isEmpty) {
            throw FormatException('订阅内容为空或无法解析');
          }
          await repo.replaceProfiles(group.id, profiles);
          successCount.add(group.name);
          debugPrint('订阅更新成功: ${group.name}, 新增 ${profiles.length} 个节点');
        } catch (e) {
          failedCount.add('${group.name}: $e');
          debugPrint('订阅更新失败: ${group.name} - $e');
        }
      }

      final result = UpdateResult(
        total: groups.length,
        success: successCount.length,
        failed: failedCount.length,
        successGroups: successCount,
        failedGroups: failedCount,
      );

      _eventController.add(UpdateEvent.completed(result));
      return result;
    } finally {
      _isUpdating = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _eventController.close();
  }
}

class UpdateResult {
  final int total;
  final int success;
  final int failed;
  final List<String> successGroups;
  final List<String> failedGroups;
  final String skipReason;

  bool get isSkipped => skipReason.isNotEmpty;

  const UpdateResult({
    required this.total,
    required this.success,
    required this.failed,
    required this.successGroups,
    required this.failedGroups,
    this.skipReason = '',
  });

  factory UpdateResult.skipped(String reason) {
    return UpdateResult(
      total: 0,
      success: 0,
      failed: 0,
      successGroups: const [],
      failedGroups: const [],
      skipReason: reason,
    );
  }
}

class UpdateEvent {
  final UpdateEventType type;
  final int? totalGroups;
  final UpdateResult? result;

  const UpdateEvent._(this.type, this.totalGroups, this.result);

  factory UpdateEvent.started(int totalGroups) {
    return UpdateEvent._(UpdateEventType.started, totalGroups, null);
  }

  factory UpdateEvent.completed(UpdateResult result) {
    return UpdateEvent._(
        UpdateEventType.completed, result.total > 0 ? result.total : null, result);
  }
}

enum UpdateEventType { started, completed }