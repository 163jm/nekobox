import 'dart:io';

import 'package:flutter/material.dart';

import 'package:core/core.dart';

/// 规则编辑页(对齐原版 RouteSettingsActivity)。
class RouteRuleEditPage extends StatefulWidget {
  final RouteRule rule;

  const RouteRuleEditPage({super.key, required this.rule});

  @override
  State<RouteRuleEditPage> createState() => _RouteRuleEditPageState();
}

class _RouteRuleEditPageState extends State<RouteRuleEditPage> {
  late RouteRule _draft;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _configCtrl;
  late final TextEditingController _domainsCtrl;
  late final TextEditingController _ipCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _sourcePortCtrl;
  late final TextEditingController _networkCtrl;
  late final TextEditingController _sourceCtrl;
  late final TextEditingController _protocolCtrl;
  late final TextEditingController _srsNameCtrl;
  late final TextEditingController _srsUrlCtrl;
  late final TextEditingController _packagesCtrl;
  late String _srsType;

  @override
  void initState() {
    super.initState();
    _draft = widget.rule.copy();
    _nameCtrl = TextEditingController(text: _draft.name);
    _configCtrl = TextEditingController(text: _draft.config);
    _domainsCtrl = TextEditingController(text: _draft.domains);
    _ipCtrl = TextEditingController(text: _draft.ip);
    _portCtrl = TextEditingController(text: _draft.port);
    _sourcePortCtrl = TextEditingController(text: _draft.sourcePort);
    _networkCtrl = TextEditingController(text: _draft.network);
    _sourceCtrl = TextEditingController(text: _draft.source);
    _protocolCtrl = TextEditingController(text: _draft.protocol);
    _srsNameCtrl = TextEditingController(text: _draft.srsName);
    _srsUrlCtrl = TextEditingController(text: _draft.srsUrl);
    _packagesCtrl = TextEditingController(text: _draft.packages.join('\n'));
    _srsType = _draft.srsType;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _configCtrl.dispose();
    _domainsCtrl.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _sourcePortCtrl.dispose();
    _networkCtrl.dispose();
    _sourceCtrl.dispose();
    _protocolCtrl.dispose();
    _srsNameCtrl.dispose();
    _srsUrlCtrl.dispose();
    _packagesCtrl.dispose();
    super.dispose();
  }

  void _collect() {
    _draft.name = _nameCtrl.text.trim();
    _draft.config = _configCtrl.text.trim();
    _draft.domains = _domainsCtrl.text.trim();
    _draft.ip = _ipCtrl.text.trim();
    _draft.port = _portCtrl.text.trim();
    _draft.sourcePort = _sourcePortCtrl.text.trim();
    _draft.network = _networkCtrl.text.trim();
    _draft.source = _sourceCtrl.text.trim();
    _draft.protocol = _protocolCtrl.text.trim();
    _draft.srsName = _srsNameCtrl.text.trim();
    _draft.srsUrl = _srsUrlCtrl.text.trim();
    _draft.srsType = _srsType;
    _draft.packages = _packagesCtrl.text
        .split(RegExp(r'[,\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _collect();
    if (_draft.checkEmpty() && _draft.name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('规则没有任何匹配条件')),
      );
      return;
    }
    final repo = Repository.instance;
    if (_draft.id == 0) {
      _draft.enabled = true;
      await repo.addRule(_draft);
    } else {
      await repo.updateRule(_draft);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _selectOutbound() async {
    final current = _draft.outboundMode;
    final profiles = Repository.instance.profiles;
    final ok = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('出站选择'),
        children: [
          for (final (value, label) in [
            (0, '代理'),
            (1, '绕过'),
            (2, '拒绝'),
            (3, '选择节点…'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, value),
              child: Row(
                children: [
                  Radio<int>(
                      value: value,
                      groupValue: current,
                      onChanged: null),
                  Text(label),
                ],
              ),
            ),
        ],
      ),
    );
    if (ok == null) return;
    setState(() {
      _draft.outboundMode = ok;
      if (ok == 3 && _draft.outboundProfileId == 0) {
        // 默认选中第一个节点
        final g = Repository.instance.selectedGroup;
        if (g != null) {
          final first = Repository.instance.currentProfiles.isNotEmpty
              ? Repository.instance.currentProfiles.first
              : null;
          if (first != null) _draft.outboundProfileId = first.id;
        } else if (profiles.isNotEmpty) {
          _draft.outboundProfileId = profiles.first.id;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _draft.id == 0;
    final selectedProfile = Repository.instance.profiles
        .where((p) => p.id == _draft.outboundProfileId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? '添加规则' : '编辑规则'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '规则名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // 出站
            Card(
              child: ListTile(
                leading: Icon(
                  _draft.outboundMode == 2
                      ? Icons.block
                      : (_draft.outboundMode == 1
                          ? Icons.flight_land
                          : Icons.vpn_lock),
                  color: _draft.outboundMode == 2
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                title: const Text('出站'),
                subtitle: Text(_outboundLabel(selectedProfile)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _selectOutbound,
              ),
            ),
            const SizedBox(height: 12),
            _section('域名(每行一条)'),
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '支持前缀: full:完整域名 / domain:后缀 / regexp:正则 / '
                'keyword:关键字;裸域名按后缀匹配。',
                style: TextStyle(fontSize: 12),
              ),
            ),
            TextFormField(
              controller: _domainsCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'domain:google.com\nexample.com',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            _section('IP(每行一条)'),
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '支持 CIDR 与 geoip:private;本版本仅使用 srs 规则集,'
                'geoip:xxx 不生效,请用下方 srs 字段。',
                style: TextStyle(fontSize: 12),
              ),
            ),
            TextFormField(
              controller: _ipCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '1.2.3.0/24\ngeoip:private',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _portCtrl,
                    decoration: const InputDecoration(
                      labelText: '目标端口',
                      hintText: '80,443,1000:2000',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _sourcePortCtrl,
                    decoration: const InputDecoration(
                      labelText: '源端口',
                      hintText: '1000:2000',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _networkCtrl,
                    decoration: const InputDecoration(
                      labelText: '网络',
                      hintText: 'tcp / udp',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _protocolCtrl,
                    decoration: const InputDecoration(
                      labelText: '协议(需嗅探)',
                      hintText: 'http / tls',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sourceCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '源 IP',
                hintText: '192.168.0.0/16',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            _section('应用(分应用,仅 Android VPN 模式生效)'),
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '每行一个应用包名,流量按应用分流。'
                '需 VPN/TUN 模式(本地代理模式不生效)。',
                style: TextStyle(fontSize: 12),
              ),
            ),
            if (Platform.isAndroid)
              TextFormField(
                controller: _packagesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'com.example.app\norg.mozilla.firefox',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              )
            else
              TextFormField(
                controller: _packagesCtrl,
                maxLines: 3,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: '仅 Android 支持',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            const SizedBox(height: 16),
            _section('srs 规则集'),
            TextFormField(
              controller: _srsNameCtrl,
              decoration: const InputDecoration(
                labelText: 'srs 文件名',
                hintText: 'geosite-cn.srs',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _srsUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'srs 下载地址(可选,保存后下载)',
                hintText: 'https://example.com/rules.srs',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _srsType,
              decoration: const InputDecoration(
                labelText: 'srs 类型',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: '', child: Text('未设置')),
                DropdownMenuItem(value: 'domain', child: Text('域名规则集')),
                DropdownMenuItem(value: 'ip', child: Text('IP 规则集')),
              ],
              onChanged: (v) => setState(() => _srsType = v ?? ''),
            ),
            const SizedBox(height: 16),
            _section('高级(自定义规则 JSON)'),
            TextFormField(
              controller: _configCtrl,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: '{"domain":["example.com"],"outbound":"direct"}',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '填写后将直接作为 sing-box 规则,忽略上方自动生成的字段。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String _outboundLabel(List<Profile> selectedProfile) {
    switch (_draft.outboundMode) {
      case 1:
        return '绕过(直连)';
      case 2:
        return '拒绝';
      case 3:
        return selectedProfile.isNotEmpty
            ? selectedProfile.first.displayName()
            : '选择节点…';
      default:
        return '代理';
    }
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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