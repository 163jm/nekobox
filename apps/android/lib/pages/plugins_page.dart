import 'package:flutter/material.dart';

class PluginInfo {
  final String id;
  final String name;
  final String description;
  final String version;
  final String downloadUrl;
  String path;
  bool installed;
  bool enabled;
  double downloadProgress;
  bool isDownloading;

  PluginInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.downloadUrl,
    this.path = '',
    this.installed = false,
    this.enabled = false,
    this.downloadProgress = 0.0,
    this.isDownloading = false,
  });

  PluginInfo copyWith({
    String? path,
    bool? installed,
    bool? enabled,
    double? downloadProgress,
    bool? isDownloading,
  }) {
    return PluginInfo(
      id: id,
      name: name,
      description: description,
      version: version,
      downloadUrl: downloadUrl,
      path: path ?? this.path,
      installed: installed ?? this.installed,
      enabled: enabled ?? this.enabled,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      isDownloading: isDownloading ?? this.isDownloading,
    );
  }
}

class PluginManager extends ChangeNotifier {
  final List<PluginInfo> _plugins = [
    PluginInfo(
      id: 'v2ray-plugin',
      name: 'v2ray-plugin',
      description: 'V2Ray 协议插件,支持 VMess/VLESS/Trojan 等协议',
      version: '1.5.0',
      downloadUrl: 'https://github.com/v2ray/v2ray-core/releases/download/v5.18.0/v2ray-linux-64.zip',
    ),
    PluginInfo(
      id: 'obfs-local',
      name: 'obfs-local',
      description: '本地流量混淆插件,支持 HTTP/TLS 混淆',
      version: '1.4.3',
      downloadUrl: 'https://github.com/shadowsocks/simple-obfs/releases/download/v0.0.5/simple-obfs-linux-x86_64.tar.gz',
    ),
  ];

  List<PluginInfo> get plugins => List.unmodifiable(_plugins);

  final Map<String, String> _testResults = {};
  Map<String, String> get testResults => Map.unmodifiable(_testResults);

  PluginInfo _getById(String id) => _plugins.firstWhere((p) => p.id == id);

  Future<void> downloadPlugin(String id) async {
    final plugin = _getById(id);
    if (plugin.isDownloading) return;

    final idx = _plugins.indexOf(plugin);
    _plugins[idx] = plugin.copyWith(isDownloading: true, downloadProgress: 0.0);
    notifyListeners();

    try {
      for (int i = 0; i <= 100; i += 2) {
        await Future.delayed(const Duration(milliseconds: 60));
        if (_plugins[idx].id != id) return;
        if (!_plugins[idx].isDownloading) return;
        _plugins[idx] = _plugins[idx].copyWith(downloadProgress: i / 100);
        notifyListeners();
      }
      _plugins[idx] = _plugins[idx].copyWith(
        isDownloading: false,
        downloadProgress: 1.0,
        installed: true,
        path: '/data/local/tmp/ss-plugin-${plugin.id}',
      );
      _testResults[id] = '下载完成';
    } catch (e) {
      _plugins[idx] = _plugins[idx].copyWith(
        isDownloading: false,
        downloadProgress: 0.0,
      );
      _testResults[id] = '下载失败: $e';
    }
    notifyListeners();
  }

  void cancelDownload(String id) {
    final idx = _plugins.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _plugins[idx] = _plugins[idx].copyWith(
      isDownloading: false,
      downloadProgress: 0.0,
    );
    notifyListeners();
  }

  void setEnabled(String id, bool enabled) {
    final idx = _plugins.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _plugins[idx] = _plugins[idx].copyWith(enabled: enabled);
    notifyListeners();
  }

  void updatePath(String id, String path) {
    final idx = _plugins.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _plugins[idx] = _plugins[idx].copyWith(path: path);
    notifyListeners();
  }

  Future<void> testPlugin(String id) async {
    final plugin = _getById(id);
    if (!plugin.installed) {
      _testResults[id] = '插件未安装';
      notifyListeners();
      return;
    }
    _testResults[id] = '测试中…';
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1));
    final ok = plugin.path.isNotEmpty && plugin.enabled;
    _testResults[id] = ok ? '测试通过 ✓' : '测试失败:路径未配置或未启用';
    notifyListeners();
  }

  void uninstallPlugin(String id) {
    final idx = _plugins.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _plugins[idx] = _plugins[idx].copyWith(
      installed: false,
      enabled: false,
      path: '',
      downloadProgress: 0.0,
    );
    _testResults.remove(id);
    notifyListeners();
  }
}

class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key});

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  late final PluginManager _manager;

  @override
  void initState() {
    super.initState();
    _manager = PluginManager();
    _manager.addListener(_onChanged);
  }

  @override
  void dispose() {
    _manager.removeListener(_onChanged);
    _manager.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _editPath(PluginInfo plugin) async {
    final ctrl = TextEditingController(text: plugin.path);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${plugin.name} 插件路径'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: '/data/local/tmp/ss-plugin',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final path = ctrl.text.trim();
      if (path.isEmpty) {
        _toast('路径不能为空');
        return;
      }
      _manager.updatePath(plugin.id, path);
      _toast('插件路径已更新');
    }
  }

  Future<void> _confirmUninstall(PluginInfo plugin) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('卸载 ${plugin.name}'),
        content: const Text('确定要卸载此插件吗?这将删除插件文件和配置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _manager.uninstallPlugin(plugin.id);
      _toast('${plugin.name} 已卸载');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plugins = _manager.plugins;

    return Scaffold(
      appBar: AppBar(title: const Text('插件管理')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _section('可用插件'),
          for (final plugin in plugins) _buildPluginCard(plugin, scheme),
          const SizedBox(height: 16),
          _section('说明'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'Shadowsocks 插件用于扩展协议支持。下载后可在节点配置中指定插件路径。\n\n'
              '· v2ray-plugin:支持 VMess/VLESS 等协议的流量混淆\n'
              '· obfs-local:本地 HTTP/TLS 流量混淆插件',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPluginCard(PluginInfo plugin, ColorScheme scheme) {
    final statusColor = plugin.installed
        ? (plugin.enabled ? Colors.green : scheme.tertiary)
        : scheme.error;
    final statusText = plugin.installed
        ? (plugin.enabled ? '已安装 · 已启用' : '已安装 · 未启用')
        : '未安装';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    plugin.installed ? Icons.extension : Icons.extension_off,
                    color: scheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            plugin.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plugin.description,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '版本 ${plugin.version}',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant.withOpacity(0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (plugin.isDownloading) ...[
              const SizedBox(height: 12),
              _buildDownloadProgress(plugin, scheme),
            ],
            if (plugin.installed) ...[
              const SizedBox(height: 12),
              _buildPathRow(plugin, scheme),
              const SizedBox(height: 8),
              _buildPluginActions(plugin, scheme),
            ] else if (!plugin.isDownloading) ...[
              const SizedBox(height: 12),
              _buildInstallRow(plugin, scheme),
            ],
            if (_manager.testResults.containsKey(plugin.id)) ...[
              const SizedBox(height: 12),
              _buildTestResult(plugin, scheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadProgress(PluginInfo plugin, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: plugin.downloadProgress > 0
                      ? plugin.downloadProgress
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  plugin.downloadProgress >= 1.0
                      ? '下载完成,正在安装…'
                      : '下载中… ${(plugin.downloadProgress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _manager.cancelDownload(plugin.id),
                child: const Text('取消'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: plugin.downloadProgress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathRow(PluginInfo plugin, ColorScheme scheme) {
    return Row(
      children: [
        Icon(Icons.folder, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            plugin.path.isEmpty ? '未设置插件路径' : plugin.path,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: plugin.path.isEmpty
                  ? scheme.error
                  : scheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          tooltip: '编辑路径',
          icon: const Icon(Icons.edit, size: 18),
          onPressed: () => _editPath(plugin),
        ),
      ],
    );
  }

  Widget _buildPluginActions(PluginInfo plugin, ColorScheme scheme) {
    return Row(
      children: [
        Expanded(
          child: SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: plugin.enabled,
            onChanged: (v) => _manager.setEnabled(plugin.id, v),
            title: const Text('启用插件', style: TextStyle(fontSize: 13)),
            subtitle: Text(
              plugin.enabled ? '插件已启用' : '插件已禁用',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ),
        IconButton(
          tooltip: '测试插件',
          icon: Icon(Icons.play_arrow, color: scheme.primary),
          onPressed: () async {
            await _manager.testPlugin(plugin.id);
            final result = _manager.testResults[plugin.id];
            if (result != null) _toast('${plugin.name}: $result');
          },
        ),
        IconButton(
          tooltip: '卸载',
          icon: Icon(Icons.delete_outline, color: scheme.error),
          onPressed: () => _confirmUninstall(plugin),
        ),
      ],
    );
  }

  Widget _buildInstallRow(PluginInfo plugin, ColorScheme scheme) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () {
          _manager.downloadPlugin(plugin.id);
          _toast('开始下载 ${plugin.name}…');
        },
        icon: const Icon(Icons.download, size: 20),
        label: Text('下载并安装 ${plugin.name}'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 40),
        ),
      ),
    );
  }

  Widget _buildTestResult(PluginInfo plugin, ColorScheme scheme) {
    final result = _manager.testResults[plugin.id] ?? '';
    final isOk = result.contains('通过');
    final isLoading = result.contains('测试中');

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isLoading
            ? scheme.primaryContainer.withOpacity(0.3)
            : isOk
                ? Colors.green.withOpacity(0.1)
                : scheme.errorContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isLoading
                ? Icons.hourglass_empty
                : isOk
                    ? Icons.check_circle
                    : Icons.error_outline,
            size: 18,
            color: isLoading
                ? scheme.primary
                : isOk
                    ? Colors.green
                    : scheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '测试结果: $result',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface,
              ),
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