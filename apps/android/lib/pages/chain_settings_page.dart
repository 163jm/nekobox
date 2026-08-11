import 'package:flutter/material.dart';

import 'package:core/core.dart';

class ChainEntry {
  int? profileId;
  String name;
  bool enabled;

  ChainEntry({
    this.profileId,
    this.name = '',
    this.enabled = true,
  });

  ChainEntry copy() => ChainEntry(
        profileId: profileId,
        name: name,
        enabled: enabled,
      );
}

class ChainController extends ChangeNotifier {
  final List<Profile> availableProfiles;
  final List<ChainEntry> entries;

  ChainController({
    required this.availableProfiles,
    List<ChainEntry>? initialEntries,
  }) : entries = List<ChainEntry>.from(initialEntries ?? []);

  void addEntry() {
    entries.add(ChainEntry(
      name: '代理节点 ${entries.length + 1}',
    ));
    notifyListeners();
  }

  void removeEntry(int index) {
    if (index < 0 || index >= entries.length) return;
    entries.removeAt(index);
    notifyListeners();
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (newIndex > oldIndex) newIndex--;
    final item = entries.removeAt(oldIndex);
    entries.insert(newIndex, item);
    notifyListeners();
  }

  void moveUp(int index) {
    if (index <= 0) return;
    final tmp = entries[index];
    entries[index] = entries[index - 1];
    entries[index - 1] = tmp;
    notifyListeners();
  }

  void moveDown(int index) {
    if (index < 0 || index >= entries.length - 1) return;
    final tmp = entries[index];
    entries[index] = entries[index + 1];
    entries[index + 1] = tmp;
    notifyListeners();
  }

  void updateProfile(int index, int? profileId) {
    if (index < 0 || index >= entries.length) return;
    entries[index].profileId = profileId;
    if (profileId != null) {
      final p = availableProfiles.where((p) => p.id == profileId).firstOrNull;
      if (p != null && entries[index].name.isEmpty) {
        entries[index].name = p.displayName();
      }
    }
    notifyListeners();
  }

  void updateName(int index, String name) {
    if (index < 0 || index >= entries.length) return;
    entries[index].name = name;
    notifyListeners();
  }

  void toggleEnabled(int index) {
    if (index < 0 || index >= entries.length) return;
    entries[index].enabled = !entries[index].enabled;
    notifyListeners();
  }

  List<ChainEntry> get enabledEntries =>
      entries.where((e) => e.enabled).toList();
}

class ChainSettingsPage extends StatefulWidget {
  final List<Profile> profiles;
  final List<ChainEntry>? initialEntries;
  final String title;

  const ChainSettingsPage({
    super.key,
    required this.profiles,
    this.initialEntries,
    this.title = '链式代理配置',
  });

  @override
  State<ChainSettingsPage> createState() => _ChainSettingsPageState();
}

class _ChainSettingsPageState extends State<ChainSettingsPage> {
  late final ChainController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ChainController(
      availableProfiles: widget.profiles,
      initialEntries: widget.initialEntries,
    );
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    if (_controller.enabledEntries.isEmpty) {
      _toast('请至少添加一个启用的代理节点');
      return;
    }
    final invalid = _controller.enabledEntries
        .where((e) => e.profileId == null)
        .toList();
    if (invalid.isNotEmpty) {
      _toast('第 ${_controller.enabledEntries.indexOf(invalid.first) + 1} 项未选择代理');
      return;
    }
    Navigator.of(context).pop(
      _controller.enabledEntries.map((e) => e.copy()).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = _controller.entries;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '保存',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(scheme),
          Expanded(
            child: entries.isEmpty
                ? _buildEmpty(scheme)
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    buildDefaultDragHandles: false,
                    itemCount: entries.length,
                    onReorder: _controller.reorder,
                    itemBuilder: (context, index) {
                      return _buildEntryTile(scheme, index);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_chain_entry',
        tooltip: '添加代理节点',
        onPressed: _controller.addEntry,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_outlined,
                  size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                '链式代理',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
              const Spacer(),
              Text(
                '${_controller.enabledEntries.length}/${_controller.entries.length} 已启用',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '客户端 → 代理1 → 代理2 → ... → 目标',
            style: TextStyle(
              fontSize: 12,
              color: scheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_tree,
            size: 64,
            color: scheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无链式代理节点',
            style: TextStyle(color: scheme.outline),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角 + 添加第一个节点',
            style: TextStyle(color: scheme.outline, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryTile(ColorScheme scheme, int index) {
    final entry = _controller.entries[index];
    final profile = entry.profileId != null
        ? widget.profiles
            .where((p) => p.id == entry.profileId)
            .firstOrNull
        : null;

    return ReorderableDragStartListener(
      index: index,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: entry.enabled
                  ? scheme.primary.withValues(alpha: 0.3)
                  : scheme.outlineVariant.withValues(alpha: 0.3),
              width: 1.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.drag_indicator,
                            size: 20, color: scheme.outlineVariant),
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              entry.name.isEmpty
                                  ? '代理节点 ${index + 1}'
                                  : entry.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: entry.enabled
                                    ? scheme.onSurface
                                    : scheme.onSurface
                                        .withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: entry.enabled,
                      onChanged: (_) => _controller.toggleEnabled(index),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildProfileDropdown(scheme, index, profile),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: entry.name,
                        decoration: const InputDecoration(
                          labelText: '节点名称(可选)',
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                        onChanged: (v) => _controller.updateName(index, v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '上移',
                          icon: const Icon(Icons.arrow_upward, size: 20),
                          onPressed: index == 0
                              ? null
                              : () => _controller.moveUp(index),
                        ),
                        IconButton(
                          tooltip: '下移',
                          icon: const Icon(Icons.arrow_downward, size: 20),
                          onPressed: index == _controller.entries.length - 1
                              ? null
                              : () => _controller.moveDown(index),
                        ),
                      ],
                    ),
                    IconButton(
                      tooltip: '删除',
                      icon: Icon(Icons.delete_outline,
                          size: 20, color: scheme.error),
                      onPressed: () => _controller.removeEntry(index),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileDropdown(
      ColorScheme scheme, int index, Profile? currentProfile) {
    final items = <DropdownMenuItem<int?>>[
      const DropdownMenuItem<int?>(
        value: null,
        child: Text('-- 选择代理 --'),
      ),
      ...widget.profiles.map((p) => DropdownMenuItem<int?>(
            value: p.id,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Color(ProfileType.color(p.type)),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.displayName(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          )),
    ];

    return DropdownButtonFormField<int?>(
      initialValue: currentProfile?.id,
      decoration: const InputDecoration(
        labelText: '选择代理节点',
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding:
            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      isExpanded: true,
      items: items,
      onChanged: (v) => _controller.updateProfile(index, v),
    );
  }
}