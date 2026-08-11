import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:core/core.dart';

import 'groups_page.dart';
import 'profile_edit_page.dart';
import '../widgets/profile_tile.dart';

/// 配置页(桌面布局):顶部工具栏 + 分组下拉 + 节点列表(右键菜单)。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _refreshing = false;
  bool _searching = false;
  String _searchText = '';

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

  Future<void> _toggleProxy() async {
    final repo = Repository.instance;
    final profiles = repo.currentProfiles;
    if (profiles.isEmpty) {
      _toast('请先添加节点');
      return;
    }
    try {
      await SingBoxController.instance.toggle(
        profiles: profiles,
        selected: repo.currentProfile,
      );
      // 系统代理联动已由 SingBoxController 统一处理(start/stop/异常退出)
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _selectProfile(Profile p) async {
    final repo = Repository.instance;
    await repo.selectProfile(p);
    if (SingBoxController.instance.isRunning) {
      try {
        await SingBoxController.instance.restart(
          profiles: repo.currentProfiles,
          selected: repo.currentProfile,
        );
      } catch (e) {
        _toast('切换失败: $e');
      }
    }
  }

  Future<void> _updateSubscription() async {
    final repo = Repository.instance;
    final group = repo.selectedGroup;
    if (group == null || !group.subscription || group.url.isEmpty) {
      _toast('当前不是订阅组,无法更新');
      return;
    }
    setState(() => _refreshing = true);
    try {
      final text = await SubscriptionUpdater.fetchText(group.url);
      final newProfiles = UniversalFmt.parseSubscriptionText(text);
      if (newProfiles.isEmpty) {
        throw FormatException('订阅内容为空');
      }
      await repo.replaceProfiles(group.id, newProfiles);
      _toast('更新成功,共 ${newProfiles.length} 个节点');
    } catch (e) {
      _toast('更新失败: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _showProfileMenu(Profile p, Offset position) {
    final repo = Repository.instance;
    final screenSize = MediaQuery.of(context).size;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & screenSize,
      ),
      items: [
        PopupMenuItem(
          value: 'test',
          child: Row(children: const [
            Icon(Icons.speed, size: 18),
            SizedBox(width: 8),
            Text('测试连接'),
          ]),
        ),
        PopupMenuItem(
          value: 'select',
          child: Row(children: const [
            Icon(Icons.check_circle_outline, size: 18),
            SizedBox(width: 8),
            Text('选中'),
          ]),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(children: const [
            Icon(Icons.edit_outlined, size: 18),
            SizedBox(width: 8),
            Text('编辑'),
          ]),
        ),
        PopupMenuItem(
          value: 'copy',
          child: Row(children: const [
            Icon(Icons.copy, size: 18),
            SizedBox(width: 8),
            Text('复制分享链接'),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: const [
            Icon(Icons.delete_outline, size: 18),
            SizedBox(width: 8),
            Text('删除'),
          ]),
        ),
      ],
    ).then((value) async {
      switch (value) {
        case 'test':
          await _testProfile(p);
          break;
        case 'select':
          await _selectProfile(p);
          break;
        case 'edit':
          await _openEditor(
              repo.profiles.firstWhere((x) => x.id == p.id, orElse: () => p));
          break;
        case 'copy':
          try {
            final link = UniversalFmt.export(p);
            await Clipboard.setData(ClipboardData(text: link));
            _toast('已复制');
          } catch (e) {
            _toast('$e');
          }
          break;
        case 'delete':
          await _deleteProfile(p);
          break;
      }
    });
  }

  Future<void> _testProfile(Profile p) async {
    try {
      await UrlTester.testAndSave(p);
      _toast('${p.displayName()} 延迟: ${p.delay} ms');
    } catch (_) {
      _toast('${p.displayName()} 测速失败');
    }
  }

  Future<void> _deleteProfile(Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除节点'),
        content: Text('确定删除「${p.displayName()}」?'),
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
      await Repository.instance.removeProfile(p);
    }
  }

  Future<void> _openEditor(Profile profile) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfileEditPage(profile: profile)),
    );
  }

  void _openGroupsPage() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GroupsPage()),
    );
  }

  String _orderLabel(int order) {
    switch (order) {
      case 1:
        return '按名称';
      case 2:
        return '按延迟';
      default:
        return '原始顺序';
    }
  }

  void _onMoreMenu(String value) async {
    final repo = Repository.instance;
    final profiles = repo.currentProfiles;
    switch (value) {
      case 'remove_duplicate':
        await _removeDuplicates(profiles);
        break;
      case 'tcp_ping':
        await _runTest(profiles, url: false);
        break;
      case 'url_test':
        await _runTest(profiles, url: true);
        break;
      case 'clear_results':
        for (final p in profiles) {
          await repo.updateProfileDelay(p, -1);
        }
        _toast('已清除测速结果');
        break;
      case 'delete_unavailable':
        await _deleteUnavailable(profiles);
        break;
      case 'order':
        await _changeOrder();
        break;
    }
  }

  Future<void> _runTest(List<Profile> profiles, {required bool url}) async {
    if (profiles.isEmpty) {
      _toast('当前组没有节点');
      return;
    }
    _toast(url ? '开始 URL 测速…' : '开始 TCP Ping…');
    var okCount = 0;
    for (final p in profiles) {
      try {
        if (url) {
          await UrlTester.testAndSaveUrl(p);
        } else {
          await UrlTester.testAndSave(p);
        }
        if (p.delay >= 0) okCount++;
      } catch (_) {}
    }
    _toast('测速完成: $okCount/${profiles.length} 可用');
  }

  Future<void> _removeDuplicates(List<Profile> profiles) async {
    final seen = <String>{};
    final dupes = <Profile>[];
    for (final p in profiles) {
      final key = '${p.type}|${p.serverAddress}|${p.serverPort}';
      if (!seen.add(key)) {
        dupes.add(p);
      }
    }
    if (dupes.isEmpty) {
      _toast('没有重复节点');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除重复节点'),
        content: Text('将删除 ${dupes.length} 个重复节点,确定?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Repository.instance.removeProfiles(dupes);
      _toast('已删除 ${dupes.length} 个重复节点');
    }
  }

  Future<void> _deleteUnavailable(List<Profile> profiles) async {
    final bad = profiles.where((p) => p.delay < 0).toList();
    if (bad.isEmpty) {
      _toast('没有不可用节点(无测速结果)');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除不可用节点'),
        content: Text('将删除 ${bad.length} 个测速失败的节点,确定?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Repository.instance.removeProfiles(bad);
      _toast('已删除 ${bad.length} 个节点');
    }
  }

  Future<void> _changeOrder() async {
    final g = Repository.instance.selectedGroup;
    if (g == null) return;
    final current = g.order;
    final ok = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('排序方式'),
        children: [
          for (final (value, label) in [
            (0, '原始顺序'),
            (1, '按名称'),
            (2, '按延迟'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, value),
              child: Row(
                children: [
                  Radio<int>(
                      value: value, groupValue: current, onChanged: null),
                  Text(label),
                ],
              ),
            ),
        ],
      ),
    );
    if (ok != null && ok != current) {
      final copy = g.clone()..order = ok;
      await Repository.instance.updateGroup(copy);
    }
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.isEmpty) {
      _toast('剪贴板为空');
      return;
    }
    final profiles = UniversalFmt.parseClipboard(text);
    if (profiles.isEmpty) {
      _toast('未识别到有效链接');
      return;
    }
    final repo = Repository.instance;
    for (final p in profiles) {
      p.groupId = repo.selectedGroupId;
      await repo.addProfile(p);
    }
    _toast('已导入 ${profiles.length} 个节点');
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final ctrl = SingBoxController.instance;
    final group = repo.selectedGroup;
    var profiles = repo.currentProfiles;
    if (_searchText.isNotEmpty) {
      final q = _searchText.toLowerCase();
      profiles = profiles.where((p) {
        return p.displayName().toLowerCase().contains(q) ||
            ProfileType.displayName(p.type).toLowerCase().contains(q) ||
            p.serverAddress.toLowerCase().contains(q);
      }).toList();
    }
    final selected = repo.currentProfile;
    final running = ctrl.isRunning;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: _searching
            ? TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _searchText = v.trim()),
                decoration: const InputDecoration(
                  hintText: '搜索名称 / 类型 / 地址',
                  border: InputBorder.none,
                ),
              )
            : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(group?.name.isEmpty == true ? '(未命名组)' : (group?.name ?? 'NekoBox')),
            const SizedBox(width: 12),
            // 分组切换
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: repo.selectedGroupId == 0 ? null : repo.selectedGroupId,
                hint: const Text('选择分组'),
                items: repo.groups
                    .map((g) => DropdownMenuItem(
                          value: g.id,
                          child: Text(g.name.isEmpty ? '(未命名组)' : g.name),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) repo.selectGroup(v);
                },
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _searching ? '取消搜索' : '搜索',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _searchText = '';
            }),
          ),
          TextButton.icon(
            onPressed: _refreshing ? null : _updateSubscription,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('更新'),
          ),
          IconButton(
            tooltip: '从剪贴板导入',
            icon: const Icon(Icons.content_paste),
            onPressed: _importFromClipboard,
          ),
          IconButton(
            tooltip: '手动添加节点',
            icon: const Icon(Icons.add),
            onPressed: () =>
                _openEditor(Profile(groupId: repo.selectedGroupId)),
          ),
          IconButton(
            tooltip: '分组管理',
            icon: const Icon(Icons.folder_open),
            onPressed: _openGroupsPage,
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: _onMoreMenu,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'remove_duplicate',
                child: ListTile(
                  leading: Icon(Icons.copy_all),
                  title: Text('删除重复节点'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'tcp_ping',
                child: ListTile(
                  leading: Icon(Icons.speed),
                  title: Text('TCP Ping 测速'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'url_test',
                child: ListTile(
                  leading: Icon(Icons.network_check),
                  title: Text('URL 测速'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'clear_results',
                child: ListTile(
                  leading: Icon(Icons.clear_all),
                  title: Text('清除测速结果'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'delete_unavailable',
                child: ListTile(
                  leading: Icon(Icons.delete_sweep_outlined),
                  title: Text('删除不可用节点'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'order',
                child: ListTile(
                  leading: const Icon(Icons.sort),
                  title: const Text('排序方式'),
                  contentPadding: EdgeInsets.zero,
                  trailing: Text(
                    _orderLabel(repo.selectedGroup?.order ?? 0),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          // 连接开关
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonalIcon(
              onPressed: _toggleProxy,
              icon: Icon(
                running ? Icons.stop_circle : Icons.play_circle_fill,
                size: 20,
              ),
              label: Text(running ? '停止' : '连接'),
            ),
          ),
        ],
      ),
      body: profiles.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  const Text('当前分组还没有节点'),
                  const SizedBox(height: 4),
                  Text('点击右上角 + 添加,或导入订阅',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                          fontSize: 13)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: profiles.length,
              itemBuilder: (context, i) {
                final p = profiles[i];
                return GestureDetector(
                  onSecondaryTapDown: (d) =>
                      _showProfileMenu(p, d.globalPosition),
                  child: ProfileTile(
                    profile: p,
                    selected: p.id == selected?.id,
                    isCurrent: running && p.id == selected?.id,
                    onTap: () => _selectProfile(p),
                  ),
                );
              },
            ),
    );
  }
}
