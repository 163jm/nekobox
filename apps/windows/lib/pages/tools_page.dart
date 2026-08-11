import 'package:flutter/material.dart';

import 'package:core/core.dart';

/// 工具页(桌面):URL 测试 / 日志 / 关于。
class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  bool _testing = false;
  String? _testStatus;

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

  Future<void> _runUrlTest() async {
    final repo = Repository.instance;
    final profiles = repo.currentProfiles;
    if (profiles.isEmpty) {
      _toast('当前分组没有节点');
      return;
    }
    setState(() {
      _testing = true;
      _testStatus = '开始测速…';
    });
    await UrlTester.testAll(
      profiles,
      onProgress: (i, total, name, delay) {
        if (!mounted) return;
        setState(() {
          _testStatus = delay != null
              ? '$i/$total  $name  ${delay} ms'
              : '$i/$total  $name  失败';
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testStatus = '测速完成';
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
            subtitle: Text(_testing ? (_testStatus ?? '…') : '测试当前分组全部节点延迟'),
            trailing: _testing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            onTap: _testing ? null : _runUrlTest,
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
          _section('日志'),
          ListTile(
            leading: Icon(Icons.terminal, color: scheme.primary),
            title: const Text('运行日志'),
            subtitle: Text('共 ${ctrl.logs.length} 条'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogViewPage()),
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
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'NekoBox Flutter',
              applicationVersion: '1.0.0',
              applicationIcon: const Icon(Icons.bolt, size: 40),
              children: const [
                Text('基于 sing-box 的通用代理客户端。\n'
                    'Flutter 重写 · Windows 版'),
              ],
            ),
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
}

/// 日志查看页(桌面)
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
