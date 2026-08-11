import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:core/core.dart';
import 'package:core/utils/sn_uri.dart';

import '../widgets/profile_card.dart';
import '../widgets/speed_test_dialog.dart';
import 'groups_page.dart';
import 'profile_edit_page.dart';
import 'qr_scanner_page.dart';
import 'network_tools_page.dart';
import 'stun_page.dart';

/// 配置页(仿原版 ConfigurationFragment):
/// 顶部 TabLayout 分组页签 + 每组独立节点列表 + 搜索/添加/更多菜单。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  bool _searching = false;
  String _searchText = '';
  bool _refreshing = false;
  TabController? _tabController;
  int _lastGroupCount = -1;

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
    _tabController?.dispose();
    super.dispose();
  }

  void _onRepoChange() {
    if (!mounted) return;
    _ensureTabController();
    // 外部选中组变化(如分组页)时同步 Tab 位置
    final tc = _tabController;
    if (tc != null) {
      final idx = Repository.instance.groups
          .indexWhere((g) => g.id == Repository.instance.selectedGroupId);
      if (idx >= 0 && idx != tc.index && !tc.indexIsChanging) {
        tc.index = idx;
      }
    }
    setState(() {});
  }

  /// 按当前分组数创建/复用 TabController,初始定位到选中组。
  void _ensureTabController() {
    final groups = Repository.instance.groups;
    if (groups.isEmpty) {
      _tabController?.dispose();
      _tabController = null;
      _lastGroupCount = -1;
      return;
    }
    if (_tabController != null && _lastGroupCount == groups.length) return;
    var idx = Repository.instance.groups
        .indexWhere((g) => g.id == Repository.instance.selectedGroupId);
    if (idx < 0) idx = 0;
    _tabController?.dispose();
    final tc = TabController(
      length: groups.length,
      initialIndex: idx,
      vsync: this,
    );
    tc.addListener(_onTabChange);
    _tabController = tc;
    _lastGroupCount = groups.length;
  }

  /// Tab 变化时同步选中组(替代已移除的 TabBarView.onPageChanged)。
  void _onTabChange() {
    final tc = _tabController;
    if (tc == null || tc.indexIsChanging) return;
    final groups = Repository.instance.groups;
    if (tc.index >= groups.length) return;
    final g = groups[tc.index];
    if (g.id != Repository.instance.selectedGroupId) {
      Repository.instance.selectGroup(g.id);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final ctrl = SingBoxController.instance;
    final groups = repo.groups;
    final running = ctrl.isRunning;
    _ensureTabController();

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _searchText = v.trim()),
                decoration: const InputDecoration(
                  hintText: '搜索名称 / 类型 / 地址',
                  border: InputBorder.none,
                ),
              )
            : const Text('配置'),
        actions: [
          IconButton(
            tooltip: _searching ? '取消搜索' : '搜索',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _searchText = '';
            }),
          ),
          // 连接开关(仿原版状态栏开关)
          IconButton(
            tooltip: running ? '停止' : '连接',
            icon: Icon(
              running ? Icons.stop_circle : Icons.play_circle_fill,
              color: running
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
            ),
            iconSize: 28,
            onPressed: _toggleProxy,
          ),
          // ➕ 添加
          PopupMenuButton<String>(
            tooltip: '添加',
            onSelected: _onAddMenu,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'clipboard',
                child: ListTile(
                  leading: Icon(Icons.content_paste),
                  title: Text('从剪贴板导入'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'scan_qr',
                child: ListTile(
                  leading: Icon(Icons.qr_code_scanner),
                  title: Text('扫描二维码'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'import_file',
                child: ListTile(
                  leading: Icon(Icons.file_upload),
                  title: Text('从文件导入'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'manual',
                child: ListTile(
                  leading: Icon(Icons.edit_note),
                  title: Text('手动添加节点'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'subscription',
                child: ListTile(
                  leading: Icon(Icons.cloud_download_outlined),
                  title: Text('添加订阅'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          // ⋮ 更多
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: _onMoreMenu,
            itemBuilder: (context) {
              final settings = Repository.instance.settings;
              final autoUpdate = settings.autoUpdateSubscription;
              final interval = settings.autoUpdateInterval;
              return [
                PopupMenuItem(
                  value: 'update_sub',
                  child: ListTile(
                    leading: const Icon(Icons.refresh),
                    title: const Text('更新当前订阅'),
                    subtitle: autoUpdate
                        ? Text('自动更新: 每 ${interval > 0 ? interval : 60} 分钟',
                            style: const TextStyle(fontSize: 11))
                        : null,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
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
                  value: 'stun_test',
                  child: ListTile(
                    leading: Icon(Icons.waves_outlined),
                    title: Text('STUN 测试'),
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
                const PopupMenuItem(
                  value: 'network_tools',
                  child: ListTile(
                    leading: Icon(Icons.router),
                    title: Text('网络工具'),
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
              ];
            },
          ),
        ],
        bottom: groups.isEmpty
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: groups
                    .map((g) => Tab(
                          text: g.name.isEmpty ? '(未命名)' : g.name,
                        ))
                    .toList(),
              ),
      ),
      body: groups.isEmpty
          ? _EmptyView(onAdd: _openGroupsPage)
          : TabBarView(
              controller: _tabController,
              children: groups.map((g) {
                final profiles = _profilesOf(g);
                return _ProfileList(
                  key: ValueKey('g${g.id}'),
                  profiles: profiles,
                  selectedProfile: repo.currentProfile,
                  running: running,
                  searchText: _searchText,
                  onSelect: (p) => _selectProfile(p, g),
                  onEdit: (p) => _openEditor(p),
                  onShare: (p) => _shareProfile(p),
                  onDelete: (p) => _removeProfile(p),
                  onLongPress: (p) => _showProfileMenu(p),
                  onReorder: (list) => _reorder(g, list),
                  alwaysShowAddress:
                      Repository.instance.settings.alwaysShowAddress,
                );
              }).toList(),
            ),
    );
  }

  List<Profile> _profilesOf(ProxyGroup g) {
    var list = Repository.instance.profiles
        .where((p) => p.groupId == g.id)
        .toList();
    switch (g.order) {
      case 1:
        list.sort((a, b) => a.displayName().compareTo(b.displayName()));
        break;
      case 2:
        list.sort((a, b) {
          final ad = a.delay < 0 ? 0x7fffffff : a.delay;
          final bd = b.delay < 0 ? 0x7fffffff : b.delay;
          return ad.compareTo(bd);
        });
        break;
      default:
        list.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    }
    if (_searchText.isNotEmpty) {
      final q = _searchText.toLowerCase();
      list = list.where((p) {
        return p.displayName().toLowerCase().contains(q) ||
            ProfileType.displayName(p.type).toLowerCase().contains(q) ||
            p.serverAddress.toLowerCase().contains(q);
      }).toList();
    }
    return list;
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

  Future<void> _toggleProxy() async {
    final repo = Repository.instance;
    final ctrl = SingBoxController.instance;
    final profiles = repo.currentProfiles;
    if (profiles.isEmpty) {
      _toast('请先添加节点');
      return;
    }
    try {
      await ctrl.toggle(
        profiles: profiles,
        selected: repo.currentProfile,
      );
    } catch (e) {
      _toast('$e');
    }
  }

  void _selectProfile(Profile p, ProxyGroup g) async {
    final repo = Repository.instance;
    await repo.selectProfile(p);
    // 连接中则重启切换
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

  void _onAddMenu(String value) {
    switch (value) {
      case 'clipboard':
        _importFromClipboard();
        break;
      case 'scan_qr':
        _scanQrCode();
        break;
      case 'import_file':
        _importFromFile();
        break;
      case 'manual':
        _openEditor(Profile(groupId: Repository.instance.selectedGroupId));
        break;
      case 'subscription':
        _openGroupsPage();
        break;
    }
  }

  void _onMoreMenu(String value) async {
    final repo = Repository.instance;
    final profiles = repo.currentProfiles;
    switch (value) {
      case 'update_sub':
        await _updateSubscription();
        break;
      case 'remove_duplicate':
        await _removeDuplicates(profiles);
        break;
      case 'tcp_ping':
        await _runTest(profiles, url: false);
        break;
      case 'url_test':
        await _runTest(profiles, url: true);
        break;
      case 'stun_test':
        _openStunTest();
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
      case 'network_tools':
        _openNetworkTools();
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
    final controller = StreamController<SpeedTestProgress>();

    final testFuture = url
        ? UrlTester.testAllUrl(
            profiles,
            onProgress: (i, total, name, delay) {
              controller.add(SpeedTestProgress(
                completed: i,
                total: total,
                currentName: name,
                delay: delay,
              ));
            },
          )
        : UrlTester.testAll(
            profiles,
            onProgress: (i, total, name, delay) {
              controller.add(SpeedTestProgress(
                completed: i,
                total: total,
                currentName: name,
                delay: delay,
              ));
            },
          );

    final result = await SpeedTestDialog.show(
      context,
      profiles: profiles,
      progressStream: controller.stream,
      title: url ? 'URL 测速' : 'TCP Ping 测速',
      onCancel: () => controller.close(),
    );

    await testFuture;
    if (result != null) {
      _toast('测速完成: ${result.successCount}/${result.total} 可用');
    } else {
      _toast('测速已取消');
    }
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
    final ok = await _confirm(
        '删除重复节点', '将删除 ${dupes.length} 个重复节点,确定?');
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
    final ok = await _confirm(
        '删除不可用节点', '将删除 ${bad.length} 个测速失败的节点,确定?');
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

  Future<bool?> _confirm(String title, String msg) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(msg),
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

  void _openEditor(Profile profile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileEditPage(profile: profile),
      ),
    );
  }

  void _openGroupsPage() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GroupsPage()),
    );
  }

  Future<void> _updateSubscription() async {
    final repo = Repository.instance;
    final group = repo.selectedGroup;
    if (group == null) return;
    if (!group.subscription || group.url.isEmpty) {
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

  Future<void> _shareProfile(Profile p) async {
    try {
      final link = UniversalFmt.export(p);
      await Clipboard.setData(ClipboardData(text: link));
      _toast('已复制分享链接');
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _removeProfile(Profile p) async {
    final ok = await _confirm('删除节点', '确定删除「${p.displayName()}」?');
    if (ok == true) {
      await Repository.instance.removeProfile(p);
    }
  }

  void _showProfileMenu(Profile p) {
    final repo = Repository.instance;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(p.displayName(),
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text('${ProfileType.displayName(p.type)} · '
                    '${p.serverAddress}:${p.serverPort}'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.speed),
                title: const Text('测试连接'),
                onTap: () {
                  Navigator.pop(context);
                  UrlTester.testAndSave(p).then((_) {
                    _toast('${p.displayName()} 延迟: ${p.delay} ms');
                  }).catchError((_) {
                    _toast('${p.displayName()} 测速失败');
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑'),
                onTap: () {
                  Navigator.pop(context);
                  _openEditor(repo.profiles.firstWhere((x) => x.id == p.id,
                      orElse: () => p));
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制分享链接'),
                onTap: () {
                  Navigator.pop(context);
                  _shareProfile(p);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('分享为 sn:// 链接'),
                onTap: () {
                  Navigator.pop(context);
                  _shareAsSnUri(p);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除'),
                onTap: () {
                  Navigator.pop(context);
                  _removeProfile(p);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _reorder(ProxyGroup g, List<Profile> ordered) {
    // 仅原始顺序可拖拽排序;名称/延迟排序忽略
    if (g.order != 0) return;
    Repository.instance.reorderProfiles(ordered);
  }

  void _scanQrCode() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );
  }

  Future<void> _importFromFile() async {
    try {
      final profiles = await FileImport.pickAndImport(
        onProgress: (current, total, fileName) {
          _toast('正在导入 $fileName ($current/$total)');
        },
      );
      if (profiles.isEmpty) {
        _toast('未识别到有效配置');
        return;
      }
      final repo = Repository.instance;
      for (final p in profiles) {
        p.groupId = repo.selectedGroupId;
        await repo.addProfile(p);
      }
      _toast('已导入 ${profiles.length} 个节点');
    } catch (e) {
      _toast('导入失败: $e');
    }
  }

  void _openNetworkTools() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NetworkToolsPage()),
    );
  }

  void _openStunTest() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StunPage()),
    );
  }

  Future<void> _shareAsSnUri(Profile p) async {
    try {
      final link = SnUri.encode(p);
      await Clipboard.setData(ClipboardData(text: link));
      _toast('已复制 sn:// 链接');
    } catch (e) {
      _toast('$e');
    }
  }
}

/// 单组节点列表:拖拽排序 + 左滑删除。
class _ProfileList extends StatelessWidget {
  final List<Profile> profiles;
  final Profile? selectedProfile;
  final bool running;
  final String searchText;
  final ValueChanged<Profile> onSelect;
  final ValueChanged<Profile> onEdit;
  final ValueChanged<Profile> onShare;
  final ValueChanged<Profile> onDelete;
  final ValueChanged<Profile> onLongPress;
  final ValueChanged<List<Profile>> onReorder;
  final bool alwaysShowAddress;

  const _ProfileList({
    super.key,
    required this.profiles,
    required this.selectedProfile,
    required this.running,
    required this.searchText,
    required this.onSelect,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
    required this.onLongPress,
    required this.onReorder,
    required this.alwaysShowAddress,
  });

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty) {
      return Center(
        child: Text(
          searchText.isNotEmpty ? '没有匹配的节点' : '该分组还没有节点\n点右上角 + 添加',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      buildDefaultDragHandles: false,
      itemCount: profiles.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex--;
        final list = List<Profile>.from(profiles);
        final moved = list.removeAt(oldIndex);
        list.insert(newIndex, moved);
        onReorder(list);
      },
      itemBuilder: (context, i) {
        final p = profiles[i];
        return Dismissible(
          key: ValueKey('p${p.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.onErrorContainer),
          ),
          onDismissed: (_) => onDelete(p),
          child: Row(
            children: [
              // 拖拽手柄
              ReorderableDragStartListener(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 20,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              Expanded(
                child: ProfileCard(
                  profile: p,
                  selected: p.id == selectedProfile?.id,
                  isCurrent:
                      running && p.id == selectedProfile?.id,
                  onTap: () => onSelect(p),
                  onEdit: () => onEdit(p),
                  onShare: () => onShare(p),
                  onDelete: () => onDelete(p),
                  onLongPress: () => onLongPress(p),
                  alwaysShowAddress: alwaysShowAddress,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyView({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_outlined, size: 64, color: scheme.outline),
          const SizedBox(height: 16),
          Text(
            '还没有分组',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            '点右上角 + 添加订阅或新建分组',
            style: TextStyle(color: scheme.outline, fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: onAdd,
            child: const Text('去添加'),
          ),
        ],
      ),
    );
  }
}
