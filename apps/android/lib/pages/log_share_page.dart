import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:core/core.dart';

/// 日志查看与分享页。
///
/// 支持:
/// - 按日志级别过滤(trace/debug/info/warn/error)
/// - 复制日志到剪贴板
/// - 通过平台分享面板分享日志
/// - 生成报告字符串发送给开发者
class LogSharePage extends StatefulWidget {
  const LogSharePage({super.key});

  @override
  State<LogSharePage> createState() => _LogSharePageState();
}

class _LogSharePageState extends State<LogSharePage> {
  static const MethodChannel _ch = MethodChannel('nekobox/core');

  final _scrollCtrl = ScrollController();
  String _filterLevel = 'all';
  List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    SingBoxController.instance.addListener(_onLog);
    _loadLogs();
  }

  @override
  void dispose() {
    SingBoxController.instance.removeListener(_onLog);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onLog() {
    if (!mounted) return;
    _loadLogs();
  }

  void _loadLogs() {
    final allLogs = SingBoxController.instance.logs;
    if (_filterLevel == 'all') {
      _logs = allLogs;
    } else {
      _logs = allLogs.where((l) => _matchesLevel(l, _filterLevel)).toList();
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  bool _matchesLevel(String line, String level) {
    final upper = level.toUpperCase();
    return line.contains(upper) || line.contains(level.toLowerCase());
  }

  Future<void> _copyToClipboard() async {
    if (_logs.isEmpty) return;
    final text = _logs.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('日志已复制到剪贴板')));
  }

  Future<void> _shareLog() async {
    if (_logs.isEmpty) return;
    final text = _logs.join('\n');
    try {
      if (Platform.isAndroid) {
        await _ch.invokeMethod('shareText', {
          'text': text,
          'subject': 'NekoBox 运行日志',
        });
      } else {
        await Clipboard.setData(ClipboardData(text: text));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制到剪贴板,请粘贴到分享应用')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('分享失败: $e')));
    }
  }

  Future<void> _sendToDeveloper() async {
    final report = _buildReport();
    try {
      if (Platform.isAndroid) {
        await _ch.invokeMethod('shareText', {
          'text': report,
          'subject': 'NekoBox 诊断报告',
        });
      } else {
        await Clipboard.setData(ClipboardData(text: report));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('诊断报告已复制到剪贴板')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发送失败: $e')));
    }
  }

  String _buildReport() {
    final settings = Repository.instance.settings;
    final buffer = StringBuffer();
    buffer.writeln('=== NekoBox Flutter 诊断报告 ===');
    buffer.writeln('时间: ${DateTime.now().toIso8601String()}');
    buffer.writeln('平台: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buffer.writeln('Dart: ${Platform.version}');
    buffer.writeln('');
    buffer.writeln('--- 应用设置 ---');
    buffer.writeln('代理模式: ${settings.proxyMode}');
    buffer.writeln('日志级别: ${settings.logLevel}');
    buffer.writeln('本地端口: ${settings.localPort}');
    buffer.writeln('TUN 栈: ${settings.tunStack}');
    buffer.writeln('Clash API: ${settings.clashApiEnabled ? '开启 (端口 ${settings.clashApiPort})' : '关闭'}');
    buffer.writeln('IPv6: ${settings.ipv6Mode}');
    buffer.writeln('');
    buffer.writeln('--- sing-box 日志 (最近 ${_logs.length} 行) ---');
    if (_logs.isEmpty) {
      buffer.writeln('(无日志)');
    } else {
      for (final l in _logs) {
        buffer.writeln(l);
      }
    }
    buffer.writeln('');
    buffer.writeln('=== 报告结束 ===');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (v) {
              switch (v) {
                case 'copy':
                  _copyToClipboard();
                  break;
                case 'share':
                  _shareLog();
                  break;
                case 'report':
                  _sendToDeveloper();
                  break;
                case 'clear':
                  SingBoxController.instance.clearLogs();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('复制到剪贴板')),
              PopupMenuItem(value: 'share', child: Text('分享日志')),
              PopupMenuItem(value: 'report', child: Text('发送给开发者')),
              PopupMenuItem(value: 'clear', child: Text('清空日志')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(scheme),
          Expanded(child: _buildLogList(scheme)),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ColorScheme scheme) {
    const levels = [
      ('all', '全部'),
      ('trace', 'TRACE'),
      ('debug', 'DEBUG'),
      ('info', 'INFO'),
      ('warn', 'WARN'),
      ('error', 'ERROR'),
    ];
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: levels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final key = levels[i].$1;
          final label = levels[i].$2;
          final selected = _filterLevel == key;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: FilterChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  _filterLevel = key;
                  _loadLogs();
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildLogList(ColorScheme scheme) {
    if (_logs.isEmpty) {
      return const Center(child: Text('暂无日志'));
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(12),
      itemCount: _logs.length,
      itemBuilder: (context, i) {
        final line = _logs[i];
        final level = _detectLevel(line);
        final color = _levelColor(level, scheme);
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: SelectableText(
            line,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: color,
            ),
          ),
        );
      },
    );
  }

  String _detectLevel(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('error') || lower.contains('fatal')) return 'error';
    if (lower.contains('warn')) return 'warn';
    if (lower.contains('info')) return 'info';
    if (lower.contains('debug')) return 'debug';
    if (lower.contains('trace')) return 'trace';
    return 'unknown';
  }

  Color _levelColor(String level, ColorScheme scheme) {
    switch (level) {
      case 'error':
        return scheme.error;
      case 'warn':
        return Colors.orange;
      case 'info':
        return scheme.primary;
      case 'debug':
        return scheme.onSurfaceVariant;
      case 'trace':
        return scheme.onSurfaceVariant.withValues(alpha: 0.6);
      default:
        return scheme.onSurface;
    }
  }
}