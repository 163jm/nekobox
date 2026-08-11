import 'dart:async';

import 'package:flutter/material.dart';

import 'package:core/core.dart';

import '../widgets/speed_test_dialog.dart';
import 'backup_page.dart';
import 'chain_settings_page.dart';
import 'log_share_page.dart';
import 'network_tools_page.dart';
import 'plugins_page.dart';
import 'stun_page.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  @override
  void initState() {
    super.initState();
    Repository.instance.addListener(_onRepoChange);
    SingBoxController.instance.addListener(_onRepoChange);
  }

  @override
  void dispose() {
    Repository.instance.removeListener(_onRepoChange);
    SingBoxController.instance.removeListener(_onRepoChange);
    super.dispose();
  }

  void _onRepoChange() {
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _runUrlTest() async {
    final repo = Repository.instance;
    final profiles = repo.currentProfiles;
    if (profiles.isEmpty) {
      _toast('当前分组没有节点');
      return;
    }
    final ctrl = StreamController<SpeedTestProgress>();
    SpeedTestDialog.show(
      context,
      profiles: profiles,
      progressStream: ctrl.stream,
      onCancel: () => ctrl.close(),
    ).then((_) => ctrl.close());

    await UrlTester.testAll(
      profiles,
      onProgress: (i, total, name, delay) {
        ctrl.add(SpeedTestProgress(
          completed: i,
          total: total,
          currentName: name,
          delay: delay,
        ));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = SingBoxController.instance;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('工具')),
      body: ListView(
        children: [
          _section('连接'),
          ListTile(
            leading: Icon(Icons.speed, color: scheme.primary),
            title: const Text('URL 测试全部节点'),
            subtitle: const Text('测试当前分组全部节点延迟,带进度对话框'),
            trailing: const Icon(Icons.play_arrow),
            onTap: _runUrlTest,
          ),
          ListTile(
            leading: Icon(
              ctrl.isRunning ? Icons.stop_circle : Icons.play_circle_outline,
              color: ctrl.isRunning ? scheme.primary : scheme.outline,
            ),
            title: const Text('代理开关'),
            subtitle: Text(ctrl.isRunning ? '运行中 (${ctrl.proxyMode})' : '已停止'),
            onTap: () => ctrl.toggle(
              profiles: Repository.instance.currentProfiles,
              selected: Repository.instance.currentProfile,
            ),
          ),
          const Divider(),
          _section('网络'),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('STUN 网络测试'),
            subtitle: const Text('NAT 类型 / 延迟 / 网速'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StunPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.timeline),
            title: const Text('网络工具'),
            subtitle: const Text('Ping / TCP 路由 / 端口扫描'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NetworkToolsPage()),
            ),
          ),
          const Divider(),
          _section('代理配置'),
          ListTile(
            leading: const Icon(Icons.settings_input_component),
            title: const Text('链式代理设置'),
            subtitle: const Text('配置前置/落地代理链路'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final result = await Navigator.of(context).push<List<dynamic>>(
                MaterialPageRoute(
                  builder: (_) => ChainSettingsPage(
                    profiles: Repository.instance.profiles,
                  ),
                ),
              );
              if (result != null) {
                _toast('链式代理已更新');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.extension),
            title: const Text('插件管理'),
            subtitle: const Text('Shadowsocks 插件 (v2ray-plugin/obfs-local)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PluginsPage()),
            ),
          ),
          const Divider(),
          _section('数据'),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('备份与恢复'),
            subtitle: const Text('选择性导入/导出数据'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BackupPage()),
            ),
          ),
          const Divider(),
          _section('日志'),
          ListTile(
            leading: Icon(Icons.terminal, color: scheme.primary),
            title: const Text('运行日志'),
            subtitle: Text('共 ${ctrl.logs.length} 条'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openLogs(),
          ),
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('日志分享与反馈'),
            subtitle: const Text('复制/分享/发送日志到开发者'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogSharePage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('清空日志'),
            onTap: ctrl.clearLogs,
          ),
          const Divider(),
          _section('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于 NekoBox Flutter'),
            subtitle: const Text('sing-box 通用代理工具链'),
            onTap: () => _showAbout(),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  void _openLogs() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LogViewPage()),
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'NekoBox Flutter',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.bolt, size: 40),
      children: const [
        Text('基于 sing-box 的通用代理客户端。\n'
            'Flutter 重写 · 支持多平台'),
      ],
    );
  }
}

/// 日志查看页
class LogViewPage extends StatefulWidget {
  const LogViewPage({super.key});

  @override
  State<LogViewPage> createState() => _LogViewPageState();
}

class _LogViewPageState extends State<LogViewPage> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    SingBoxController.instance.addListener(_onLog);
  }

  @override
  void dispose() {
    SingBoxController.instance.removeListener(_onLog);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onLog() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final logs = SingBoxController.instance.logs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: SingBoxController.instance.clearLogs,
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(child: Text('暂无日志'))
          : ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(12),
              itemCount: logs.length,
              itemBuilder: (context, i) {
                final line = logs[i];
                final isError =
                    line.contains('ERROR') || line.contains('FATAL');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: isError
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
