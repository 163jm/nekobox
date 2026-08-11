import 'dart:async';

import 'package:flutter/material.dart';

import 'package:core/core.dart';

/// 测速进度事件(由外部通过 Stream 传入)。
class SpeedTestProgress {
  final int completed;
  final int total;
  final String currentName;
  final int? delay;

  const SpeedTestProgress({
    required this.completed,
    required this.total,
    required this.currentName,
    this.delay,
  });

  double get ratio => total == 0 ? 0.0 : completed / total;
  bool get isComplete => completed >= total;
  String get delayText => delay != null ? '$delay ms' : '失败';
}

/// 测速单项结果(用于最终汇总展示)。
class SpeedTestItemResult {
  final String name;
  final int? delay;

  const SpeedTestItemResult({
    required this.name,
    this.delay,
  });
}

/// 测速汇总结果(完成时返回给调用方)。
class SpeedTestResult {
  final int total;
  final int successCount;
  final int failCount;
  final List<SpeedTestItemResult> items;

  const SpeedTestResult({
    required this.total,
    required this.successCount,
    required this.failCount,
    required this.items,
  });
}

/// 节点测速进度对话框。
///
/// 通过 [Stream<SpeedTestProgress>] 接收实时进度,展示当前测速节点、
/// 进度条和完成计数;完成后显示汇总结果;支持中途取消剩余测试。
///
/// ## 使用方式
/// ```dart
/// final controller = StreamController<SpeedTestProgress>();
/// final result = await SpeedTestDialog.show(
///   context,
///   profiles: profiles,
///   progressStream: controller.stream,
///   onCancel: () => controller.close(),
/// );
/// // 开始测速,在回调中添加事件:
/// UrlTester.testAll(profiles, onProgress: (i, total, name, delay) {
///   controller.add(SpeedTestProgress(
///     completed: i, total: total,
///     currentName: name, delay: delay,
///   ));
/// });
/// ```
class SpeedTestDialog extends StatefulWidget {
  final List<Profile> profiles;
  final Stream<SpeedTestProgress> progressStream;
  final String title;
  final VoidCallback? onCancel;
  final ValueChanged<SpeedTestResult>? onComplete;

  const SpeedTestDialog({
    super.key,
    required this.profiles,
    required this.progressStream,
    this.title = '节点测速',
    this.onCancel,
    this.onComplete,
  });

  /// 便捷方法:弹出对话框并返回最终汇总结果。
  static Future<SpeedTestResult?> show(
    BuildContext context, {
    required List<Profile> profiles,
    required Stream<SpeedTestProgress> progressStream,
    String title = '节点测速',
    VoidCallback? onCancel,
    ValueChanged<SpeedTestResult>? onComplete,
  }) {
    return showDialog<SpeedTestResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SpeedTestDialog(
        profiles: profiles,
        progressStream: progressStream,
        title: title,
        onCancel: onCancel,
        onComplete: onComplete,
      ),
    );
  }

  @override
  State<SpeedTestDialog> createState() => _SpeedTestDialogState();
}

class _SpeedTestDialogState extends State<SpeedTestDialog> {
  final List<SpeedTestItemResult> _results = [];
  int _completed = 0;
  late final int _total;
  String _currentName = '';
  int? _currentDelay;
  bool _isComplete = false;
  bool _isCancelled = false;
  StreamSubscription<SpeedTestProgress>? _subscription;

  @override
  void initState() {
    super.initState();
    _total = widget.profiles.length;
    _subscription = widget.progressStream.listen((event) {
      if (!mounted || _isCancelled) return;
      setState(() {
        _completed = event.completed;
        _currentName = event.currentName;
        _currentDelay = event.delay;
        _results.add(SpeedTestItemResult(
          name: event.currentName,
          delay: event.delay,
        ));
        if (event.isComplete) {
          _isComplete = true;
          _subscription?.cancel();
          _subscription = null;
          _notifyComplete();
        }
      });
    }, onError: (_) {
      if (!mounted || _isCancelled) return;
      setState(() => _isComplete = true);
    });
  }

  void _notifyComplete() {
    widget.onComplete?.call(_buildResult());
  }

  SpeedTestResult _buildResult() {
    return SpeedTestResult(
      total: _total,
      successCount: _results.where((e) => e.delay != null).length,
      failCount: _results.where((e) => e.delay == null).length,
      items: List.unmodifiable(_results),
    );
  }

  void _handleCancel() {
    _isCancelled = true;
    _subscription?.cancel();
    _subscription = null;
    widget.onCancel?.call();
    Navigator.of(context).pop();
  }

  void _handleDismiss() {
    if (_isComplete) {
      Navigator.of(context).pop(_buildResult());
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.speed, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.title)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: _isComplete
              ? _buildSummary(scheme)
              : _buildProgress(scheme),
        ),
        actions: [
          if (_isComplete)
            FilledButton(
              onPressed: _handleDismiss,
              child: const Text('关闭'),
            )
          else
            TextButton(
              onPressed: _handleCancel,
              child: const Text('取消'),
            ),
        ],
      ),
    );
  }

  Widget _buildProgress(ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 进度数字
        Row(
          children: [
            Text(
              '$_completed / $_total',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
            const Spacer(),
            if (_currentDelay != null || _currentName.isNotEmpty)
              Text(
                _currentDelay != null
                    ? '${_currentDelay} ms'
                    : '测试中…',
                style: TextStyle(
                  color: _delayColor(_currentDelay, scheme),
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // 进度条
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _total == 0 ? 0.0 : _completed / _total,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 12),
        // 当前节点
        if (_currentName.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: _currentDelay != null ? 1.0 : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _currentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                if (_currentDelay != null)
                  Icon(
                    Icons.check_circle,
                    size: 18,
                    color: scheme.primary,
                  ),
              ],
            ),
          ),
        // 已完成列表(紧凑)
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 120),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final item = _results[i];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(
                        item.delay != null
                            ? Icons.check_circle
                            : Icons.error_outline,
                        size: 14,
                        color: item.delay != null
                            ? Colors.green.shade600
                            : scheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        item.delay != null ? '${item.delay} ms' : '失败',
                        style: TextStyle(
                          fontSize: 12,
                          color: item.delay != null
                              ? _delayColor(item.delay, scheme)
                              : scheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSummary(ColorScheme scheme) {
    final success = _results.where((e) => e.delay != null).toList()
      ..sort((a, b) => a.delay!.compareTo(b.delay!));
    final failed = _results.where((e) => e.delay == null).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 汇总统计
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statBlock('总计', '$_total', scheme.primary),
              _statBlock(
                '成功',
                '${success.length}',
                Colors.green.shade600,
              ),
              _statBlock(
                '失败',
                '${failed.length}',
                scheme.error,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 结果列表
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _results.length,
            itemBuilder: (context, i) {
              final item = _results[i];
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(
                  item.delay != null
                      ? Icons.check_circle
                      : Icons.error_outline,
                  size: 18,
                  color: item.delay != null
                      ? Colors.green.shade600
                      : scheme.error,
                ),
                title: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  item.delay != null ? '${item.delay} ms' : '失败',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: item.delay != null
                        ? _delayColor(item.delay, scheme)
                        : scheme.error,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _statBlock(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
          ),
        ),
      ],
    );
  }

  static Color _delayColor(int? delay, ColorScheme scheme) {
    if (delay == null || delay < 0) return scheme.error;
    if (delay < 200) return Colors.green.shade600;
    if (delay < 500) return Colors.amber.shade700;
    return Colors.red.shade600;
  }
}