import 'package:flutter/material.dart';

import 'package:core/core.dart';

/// 分应用代理:已安装应用选择器(Android 专属)。
///
/// 展示已安装的第三方应用列表,勾选后保存到
/// [AppSettings.proxyAppList],配置生成时转为 user_id 规则。
class AppSelectorPage extends StatefulWidget {
  const AppSelectorPage({super.key});

  @override
  State<AppSelectorPage> createState() => _AppSelectorPageState();
}

class _AppSelectorPageState extends State<AppSelectorPage> {
  List<String> _apps = [];
  Set<String> _selected = {};
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected.addAll(Repository.instance.settings.proxyAppList);
    _load();
  }

  Future<void> _load() async {
    final apps = await AndroidUidResolver.listInstalledApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  List<String> get _filtered {
    if (_query.isEmpty) return _apps;
    final q = _query.toLowerCase();
    return _apps.where((a) => a.toLowerCase().contains(q)).toList();
  }

  Future<void> _save() async {
    final s = Repository.instance.settings.copy();
    s.proxyAppList = _selected.toList()..sort();
    await Repository.instance.updateSettings(s);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('分应用代理'),
        actions: [
          TextButton(
            onPressed: _loading
                ? null
                : () => setState(() {
                      _selected.addAll(_apps);
                    }),
            child: const Text('全选'),
          ),
          TextButton(
            onPressed: _loading
                ? null
                : () => setState(() => _selected.clear()),
            child: const Text('清空'),
          ),
          FilledButton(
            onPressed: _loading ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: '搜索应用',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  _loading
                      ? '正在加载应用列表…'
                      : '已选 ${_selected.length} / ${_apps.length} 个应用',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (!_loading && _selected.isNotEmpty)
                  TextButton(
                    onPressed: _save,
                    child: const Text('已选应用 → 保存'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _apps.isEmpty
                    ? Center(
                        child: Text(
                          '未获取到应用列表\n(需 Android 环境)',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final app = _filtered[i];
                          final checked = _selected.contains(app);
                          return CheckboxListTile(
                            dense: true,
                            secondary: const Icon(Icons.android, size: 20),
                            title: Text(
                              app,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            value: checked,
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(app);
                              } else {
                                _selected.remove(app);
                              }
                            }),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
