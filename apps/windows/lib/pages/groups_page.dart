import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:core/core.dart';

/// 订阅组管理页(桌面)。
class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  @override
  void initState() {
    super.initState();
    Repository.instance.addListener(_onRepoChange);
  }

  @override
  void dispose() {
    Repository.instance.removeListener(_onRepoChange);
    super.dispose();
  }

  void _onRepoChange() {
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final groups = repo.groups;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('分组管理'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonalIcon(
              onPressed: _addSubscription,
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: const Text('添加订阅'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: _addManualGroup,
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('新建分组'),
            ),
          ),
        ],
      ),
      body: groups.isEmpty
          ? Center(
              child: Text('还没有分组,点击右上角添加',
                  style: TextStyle(color: scheme.outline)),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: groups.length,
              itemBuilder: (context, i) {
                final g = groups[i];
                final count =
                    repo.profiles.where((p) => p.groupId == g.id).length;
                final isCurrent = g.id == repo.selectedGroupId;
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isCurrent ? scheme.primary : Colors.transparent,
                      width: isCurrent ? 1.5 : 0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      g.subscription
                          ? Icons.cloud_outlined
                          : Icons.folder_outlined,
                      color: scheme.primary,
                    ),
                    title: Text(g.name.isEmpty ? '(未命名组)' : g.name),
                    subtitle: Text(_groupStatus(g, count)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '组设置(前置/落地代理)',
                          icon: const Icon(Icons.settings_outlined, size: 20),
                          onPressed: () => _editGroupSettings(g),
                        ),
                        if (g.subscription)
                          IconButton(
                            tooltip: '更新',
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: () => _updateGroup(g),
                          ),
                        PopupMenuButton<String>(
                          tooltip: '更多',
                          onSelected: (v) => _onGroupMenu(v, g),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'export',
                              child: ListTile(
                                leading: Icon(Icons.copy_all_outlined),
                                title: Text('导出全部节点链接'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'clear',
                              child: ListTile(
                                leading: Icon(Icons.delete_sweep),
                                title: Text('清空节点'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                leading: Icon(Icons.delete_outline),
                                title: Text('删除分组'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    onTap: () async {
                      await repo.selectGroup(g.id);
                      if (mounted) Navigator.pop(context);
                    },
                  ),
                );
              },
            ),
    );
  }

  Future<void> _addSubscription() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加订阅'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: '订阅名称(可选)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: '订阅链接',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('添加并更新'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final url = urlCtrl.text.trim();
    if (url.isEmpty) {
      _toast('请输入订阅链接');
      return;
    }
    try {
      final group = ProxyGroup(
        name: nameCtrl.text.trim(),
        url: url,
        subscription: true,
      );
      await Repository.instance.addGroup(group);
      await Repository.instance.selectGroup(group.id);
      _toast('正在更新订阅…');
      final text = await SubscriptionUpdater.fetchText(url);
      final profiles = UniversalFmt.parseSubscriptionText(text);
      await Repository.instance.replaceProfiles(group.id, profiles);
      if (mounted && group.name.isEmpty) {
        group.name = _groupNameFromUrl(url);
        await Repository.instance.updateGroup(group);
      }
      _toast('添加成功,共 ${profiles.length} 个节点');
    } catch (e) {
      _toast('添加失败: $e');
    }
  }

  Future<void> _addManualGroup() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: '分组名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await Repository.instance.addGroup(ProxyGroup(name: ctrl.text.trim()));
      if (mounted) Navigator.pop(context);
    }
  }

  String _groupNameFromUrl(String url) {
    try {
      return Uri.parse(url).host.isNotEmpty ? Uri.parse(url).host : url;
    } catch (_) {
      return url;
    }
  }

  /// 组设置:重命名 + 前置代理(frontProxy)/ 落地代理(landingProxy),
  /// 对齐原版 GroupSettingsActivity 的链式代理设置。
  String _groupStatus(ProxyGroup g, int count) {
    if (!g.subscription) {
      return count == 0 ? '手动组 · 空' : '手动组 · $count 节点';
    }
    if (g.updateTime <= 0) {
      return '订阅 · $count 节点';
    }
    final d = DateTime.fromMillisecondsSinceEpoch(g.updateTime);
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '订阅 · $count 节点 · $month-$day 更新';
  }

  Future<void> _onGroupMenu(String value, ProxyGroup g) async {
    switch (value) {
      case 'export':
        final profiles = Repository.instance.profiles
            .where((p) => p.groupId == g.id)
            .toList();
        final links = profiles
            .map((p) {
              try {
                return UniversalFmt.export(p);
              } catch (_) {
                return '';
              }
            })
            .where((l) => l.isNotEmpty)
            .join('\n');
        if (links.isEmpty) {
          _toast('该组没有可导出的节点');
          return;
        }
        await Clipboard.setData(ClipboardData(text: links));
        _toast('已复制 ${profiles.length} 个节点链接');
        break;
      case 'clear':
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('清空节点'),
            content: Text('确定清空「${g.name}」的全部节点?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('清空'),
              ),
            ],
          ),
        );
        if (ok == true) {
          final all = Repository.instance.profiles
              .where((p) => p.groupId == g.id)
              .toList();
          await Repository.instance.removeProfiles(all);
          _toast('已清空');
        }
        break;
      case 'delete':
        await _removeGroup(g);
        break;
    }
  }

  Future<void> _editGroupSettings(ProxyGroup g) async {
    final repo = Repository.instance;
    final members = repo.profiles
        .where((p) => p.groupId == g.id)
        .toList();
    final nameCtrl = TextEditingController(text: g.name);
    var frontId = g.frontProxyId;
    var landingId = g.landingProxyId;

    Widget proxyDropdown(String label, int current, void Function(int?) onChanged) {
      final items = <DropdownMenuItem<int>>[
        const DropdownMenuItem(value: -1, child: Text('无')),
        ...members.map((p) => DropdownMenuItem(
              value: p.id,
              child: Text(
                p.displayName(),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            )),
      ];
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: DropdownButtonFormField<int>(
          initialValue: members.any((m) => m.id == current) ? current : -1,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          isExpanded: true,
          items: items,
          onChanged: onChanged,
        ),
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('组设置'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '分组名称',
                    border: OutlineInputBorder(),
                  ),
                ),
                proxyDropdown('前置代理(先连它)', frontId, (v) => frontId = v ?? -1),
                proxyDropdown('落地代理(最终出口)', landingId, (v) => landingId = v ?? -1),
                const SizedBox(height: 12),
                const Text(
                  '链式代理:客户端 → 前置 → 节点 → 落地 → 目标',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
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
      final copy = g.clone()
        ..name = nameCtrl.text.trim()
        ..frontProxyId = frontId
        ..landingProxyId = landingId;
      await repo.updateGroup(copy);
    }
  }

  Future<void> _updateGroup(ProxyGroup g) async {
    try {
      final text = await SubscriptionUpdater.fetchText(g.url);
      final profiles = UniversalFmt.parseSubscriptionText(text);
      await Repository.instance.replaceProfiles(g.id, profiles);
      _toast('更新成功: ${profiles.length} 个节点');
    } catch (e) {
      _toast('更新失败: $e');
    }
  }

  Future<void> _removeGroup(ProxyGroup g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分组'),
        content: Text('确定删除「${g.name}」及其全部节点?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Repository.instance.removeGroup(g);
    }
  }
}
