import 'package:flutter/material.dart';

import 'package:core/core.dart';

import 'route_rule_edit_page.dart';

/// 路由页(对齐原版 RouteFragment):
/// 规则列表(启停/编辑/排序/删除)+ 底部"默认出站" + 文档入口。
class RoutePage extends StatefulWidget {
  const RoutePage({super.key});

  @override
  State<RoutePage> createState() => _RoutePageState();
}

class _RoutePageState extends State<RoutePage> {
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

  String _profileNameOf(int profileId) {
    for (final p in Repository.instance.profiles) {
      if (p.id == profileId) return p.displayName();
    }
    return '';
  }

  Future<void> _addRule() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => RouteRuleEditPage(rule: RouteRule())),
    );
  }

  Future<void> _editRule(RouteRule rule) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => RouteRuleEditPage(rule: rule)),
    );
  }

  Future<void> _removeRule(RouteRule rule) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除规则'),
        content: Text('确定删除「${rule.displayName()}」?'),
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
      await Repository.instance.removeRule(rule);
    }
  }

  Future<void> _resetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置路由'),
        content: const Text('删除全部路由规则?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (ok == true) {
      for (final r in Repository.instance.rules.toList()) {
        await Repository.instance.removeRule(r);
      }
    }
  }

  /// 默认出站对话框(对齐原版 FinalHolder)
  Future<void> _showFinalDialog() async {
    final s = Repository.instance.settings;
    final current = switch (s.routeFinal) {
      '-1' => 1,
      '0' => 0,
      _ => 2,
    };
    final entries = ['代理', '绕过', '选择节点…'];
    final ok = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('默认出站'),
        children: [
          for (var i = 0; i < entries.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, i),
              child: Row(
                children: [
                  Radio<int>(
                      value: i, groupValue: current, onChanged: null),
                  Text(entries[i]),
                ],
              ),
            ),
        ],
      ),
    );
    if (ok == null) return;
    final s2 = Repository.instance.settings.copy();
    if (ok == 2) {
      // 选择节点:默认取当前组第一个节点
      final repo = Repository.instance;
      final first = repo.currentProfiles.isNotEmpty
          ? repo.currentProfiles.first
          : null;
      if (first != null) {
        s2.routeFinal = first.id.toString();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先添加节点')),
        );
        return;
      }
    } else {
      s2.routeFinal = ok == 0 ? '0' : '-1';
    }
    await Repository.instance.updateSettings(s2);
  }

  String _finalLabel() {
    final f = Repository.instance.settings.routeFinal;
    if (f == '-1') return '绕过(直连)';
    if (f == '0') return '代理';
    final name = _profileNameOf(int.tryParse(f) ?? 0);
    return name.isNotEmpty ? '节点: $name' : '选择节点…';
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final rules = repo.rules.toList()
      ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('路由'),
        actions: [
          IconButton(
            tooltip: '重置全部规则',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: rules.isEmpty ? null : _resetAll,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '添加规则',
        onPressed: _addRule,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          // 文档入口(对齐原版 DocumentHolder)
          InkWell(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('路由规则文档: '
                        'https://matsuridayo.github.io/nb4a-route/')),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.menu_book_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('路由规则使用说明(点击查看文档)')),
                ],
              ),
            ),
          ),
          if (rules.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.rule_outlined,
                        size: 48, color: scheme.outline),
                    const SizedBox(height: 8),
                    Text('暂无路由规则,点右下角 + 添加',
                        style: TextStyle(color: scheme.outline)),
                  ],
                ),
              ),
            )
          else
            ...rules.map((r) => _ruleTile(r)).toList(),
          // 默认出站(对齐原版 FinalHolder)
          const Divider(),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('默认出站'),
            subtitle: Text('未命中规则的流量 → ${_finalLabel()}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showFinalDialog,
          ),
        ],
      ),
    );
  }

  Widget _ruleTile(RouteRule rule) {
    final scheme = Theme.of(context).colorScheme;
    final outboundColor = switch (rule.outboundMode) {
      2 => scheme.error,
      1 => const Color(0xFF2E7D32),
      _ => scheme.primary,
    };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      color: rule.enabled
          ? scheme.surfaceContainerLow
          : scheme.surfaceContainerLow.withValues(alpha: 0.5),
      child: ListTile(
        leading: Icon(
          rule.outboundMode == 2
              ? Icons.block
              : (rule.outboundMode == 1
                  ? Icons.flight_land
                  : Icons.vpn_lock),
          color: outboundColor,
        ),
        title: Text(
          rule.displayName(),
          style: TextStyle(
            fontWeight: FontWeight.w500,
            decoration: rule.enabled ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Text(rule.summary().isEmpty ? ' ' : rule.summary(),
            maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              rule.outboundLabel(_profileNameOf),
              style: TextStyle(
                color: outboundColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: rule.enabled ? '停用' : '启用',
              icon: Icon(
                rule.enabled ? Icons.visibility : Icons.visibility_off,
                size: 18,
              ),
              onPressed: () => Repository.instance.toggleRule(rule),
            ),
            IconButton(
              tooltip: '编辑',
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => _editRule(rule),
            ),
          ],
        ),
        onTap: () => Repository.instance.toggleRule(rule),
        onLongPress: () => _removeRule(rule),
      ),
    );
  }
}