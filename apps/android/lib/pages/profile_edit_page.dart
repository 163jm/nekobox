import 'package:flutter/material.dart';

import 'package:core/core.dart';

/// 节点编辑页:根据协议类型动态渲染字段表单。
class ProfileEditPage extends StatefulWidget {
  final Profile profile;

  const ProfileEditPage({super.key, required this.profile});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  late Profile _draft;
  final _formKey = GlobalKey<FormState>();

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _switches = {};
  final Map<String, String> _choices = {};

  @override
  void initState() {
    super.initState();
    _draft = widget.profile.copy();
    _initControllers();
  }

  void _initControllers() {
    for (final f in _fieldsFor(_draft.type)) {
      final value = f.isCommon
          ? _commonValue(f)
          : (_draft.bean[f.key] ?? f.defaultValue);
      if (f.type == FieldType.bool) {
        _switches[f.key] = value == true;
      } else if (f.type == FieldType.choice) {
        _choices[f.key] = value.toString();
      } else {
        _controllers[f.key] = TextEditingController(text: value.toString());
      }
    }
  }

  dynamic _commonValue(ProfileField f) {
    switch (f.key) {
      case 'name':
        return _draft.name;
      case 'serverAddress':
        return _draft.serverAddress;
      case 'serverPort':
        return _draft.serverPort;
      case 'notes':
        return _draft.notes;
      default:
        return f.defaultValue;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _collect() {
    _draft.name = _controllers['name']?.text.trim() ?? _draft.name;
    _draft.serverAddress =
        _controllers['serverAddress']?.text.trim() ?? _draft.serverAddress;
    _draft.serverPort =
        int.tryParse(_controllers['serverPort']?.text.trim() ?? '') ?? 0;
    _draft.notes = _controllers['notes']?.text.trim() ?? _draft.notes;

    for (final f in _fieldsFor(_draft.type)) {
      if (f.isCommon) continue;
      switch (f.type) {
        case FieldType.bool:
          _draft.bean[f.key] = _switches[f.key] ?? false;
          break;
        case FieldType.choice:
          _draft.bean[f.key] = _choices[f.key] ?? '';
          break;
        case FieldType.int:
          _draft.bean[f.key] =
              int.tryParse(_controllers[f.key]?.text.trim() ?? '') ?? 0;
          break;
        default:
          _draft.bean[f.key] = _controllers[f.key]?.text.trim() ?? '';
      }
    }

    // WireGuard:将平面字段归一到 peers 结构
    if (_draft.type == ProfileType.wireguard) {
      final peer = <String, dynamic>{
        'server': _draft.serverAddress,
        'server_port': _draft.serverPort,
        'public_key': _draft.bean['peerPublicKey'] ?? '',
        'pre_shared_key': _draft.bean['preSharedKey'] ?? '',
        'allowed_ips': _draft.bean['allowedIps'] ?? '0.0.0.0/0,::/0',
      };
      _draft.bean['peers'] = [peer];
      _draft.bean.remove('peerPublicKey');
      _draft.bean.remove('preSharedKey');
      _draft.bean.remove('allowedIps');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _draft.id == 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? '添加节点' : '编辑节点'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _protocolSelector(),
            const SizedBox(height: 16),
            ..._fieldsFor(_draft.type).map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildField(f),
                )),
          ],
        ),
      ),
    );
  }

  Widget _protocolSelector() {
    return DropdownButtonFormField<String>(
      initialValue: _draft.type,
      decoration: const InputDecoration(
        labelText: '协议类型',
        border: OutlineInputBorder(),
      ),
      items: ProfileType.all
          .map((t) => DropdownMenuItem(
                value: t,
                child: Text(ProfileType.displayName(t)),
              ))
          .toList(),
      onChanged: (v) {
        if (v == null || v == _draft.type) return;
        setState(() {
          // 切换类型时清空 bean
          _draft.type = v;
          _draft.bean = {};
          for (final c in _controllers.values) {
            c.dispose();
          }
          _controllers.clear();
          _switches.clear();
          _choices.clear();
          _initControllers();
        });
      },
    );
  }

  Widget _buildField(ProfileField f) {
    if (f.isCommon) {
      return TextFormField(
        controller: _controllers[f.key],
        decoration: InputDecoration(
          labelText: f.label,
          border: const OutlineInputBorder(),
        ),
        keyboardType: f.type == FieldType.int
            ? TextInputType.number
            : TextInputType.text,
        validator: f.required
            ? (v) => (v == null || v.trim().isEmpty) ? '必填' : null
            : null,
      );
    }
    switch (f.type) {
      case FieldType.bool:
        return SwitchListTile(
          title: Text(f.label),
          value: _switches[f.key] ?? false,
          onChanged: (v) => setState(() => _switches[f.key] = v),
          contentPadding: EdgeInsets.zero,
        );
      case FieldType.choice:
        return DropdownButtonFormField<String>(
          initialValue: _choices[f.key] ?? f.defaultValue.toString(),
          decoration: InputDecoration(
            labelText: f.label,
            border: const OutlineInputBorder(),
          ),
          items: (f.choices ?? [])
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) => setState(() => _choices[f.key] = v ?? ''),
        );
      default:
        return TextFormField(
          controller: _controllers[f.key],
          decoration: InputDecoration(
            labelText: f.label,
            border: const OutlineInputBorder(),
          ),
          keyboardType: f.type == FieldType.int
              ? TextInputType.number
              : TextInputType.text,
          obscureText: f.isPassword,
        );
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _collect();
    final repo = Repository.instance;
    if (_draft.id == 0) {
      _draft.groupId = repo.selectedGroupId;
      await repo.addProfile(_draft);
    } else {
      await repo.updateProfile(_draft);
    }
    if (mounted) Navigator.pop(context);
  }
}

enum FieldType { text, int, bool, choice }

class ProfileField {
  final String key;
  final String label;
  final FieldType type;
  final String? hint;
  final dynamic defaultValue;
  final bool required;
  final bool isPassword;
  final bool isCommon;
  final List<String>? choices;

  const ProfileField.text(this.key, this.label,
      {this.hint, this.defaultValue = '', this.required = true, this.isPassword = false, this.isCommon = false})
      : type = FieldType.text,
        choices = null;

  const ProfileField.int(this.key, this.label,
      {this.hint, this.defaultValue = 0, this.required = true, this.isCommon = false})
      : type = FieldType.int,
        isPassword = false,
        choices = null;

  const ProfileField.bool(this.key, this.label,
      {this.defaultValue = false})
      : type = FieldType.bool,
        hint = null,
        required = false,
        isPassword = false,
        isCommon = false,
        choices = null;

  const ProfileField.choice(this.key, this.label, this.choices,
      {this.defaultValue = ''})
      : type = FieldType.choice,
        hint = null,
        required = false,
        isPassword = false,
        isCommon = false;
}

/// 各协议类型的字段定义。
List<ProfileField> _fieldsFor(String type) {
  final common = const [
    ProfileField.text('name', '名称', hint: '节点名称', required: false, isCommon: true),
    ProfileField.text('serverAddress', '服务器地址', hint: 'IP 或域名', isCommon: true),
    ProfileField.int('serverPort', '端口', isCommon: true),
    ProfileField.text('notes', '备注', required: false, isCommon: true),
  ];

  final advanced = const [
    ProfileField.bool('resolveDestination', '解析目标地址', defaultValue: true),
    ProfileField.bool('allowInsecureOnRequest', '请求允许不安全连接'),
  ];

  List<ProfileField> fields;
  switch (type) {
    case ProfileType.v2ray:
      fields = [
        ...common,
        ProfileField.text('uuid', 'UUID', hint: '自动生成请留空', required: false),
        ProfileField.int('alterId', 'AlterId', defaultValue: 0),
        ProfileField.choice('network', '传输协议', const [
          'tcp', 'kcp', 'ws',
        ], defaultValue: 'tcp'),
        ProfileField.bool('tls', 'TLS'),
        ProfileField.text('sni', 'SNI', required: false),
      ];
      break;
    case ProfileType.mieru:
      fields = [
        ...common,
        ProfileField.text('password', '密码', isPassword: true, required: false),
        ProfileField.choice('encryptionMethod', '加密方式', const [
          'aes-gcm-256', 'chaCha20-poly1305',
        ], defaultValue: 'aes-gcm-256'),
        ProfileField.choice('transport', '传输协议', const [
          'tcp', 'udp',
        ], defaultValue: 'tcp'),
      ];
      break;
    case ProfileType.shadowsocks:
      fields = [
        ...common,
        ProfileField.choice('method', '加密方式', const [
          'aes-128-gcm',
          'aes-256-gcm',
          'chacha20-ietf-poly1305',
          '2022-blake3-aes-128-gcm',
          '2022-blake3-aes-256-gcm',
          '2022-blake3-chacha20-poly1305',
        ], defaultValue: 'aes-128-gcm'),
        ProfileField.text('password', '密码', isPassword: true),
        ProfileField.text('plugin', '插件', hint: '如 v2ray-plugin', required: false),
        ProfileField.text('plugin_opts', '插件参数', hint: '如 mode=websocket', required: false),
      ];
      break;
    case ProfileType.vmess:
      fields = [
        ...common,
        ProfileField.text('uuid', 'UUID', hint: '自动生成请留空', required: false),
        ProfileField.choice('security', '加密方式', const [
          'auto', 'aes-128-gcm', 'chacha20-poly1305', 'zero', 'none',
        ], defaultValue: 'auto'),
        ProfileField.int('alterId', 'AlterId', defaultValue: 0),
        ProfileField.choice('network', '传输协议', const [
          'tcp', 'ws', 'grpc', 'http', 'httpupgrade', 'quic',
        ], defaultValue: 'tcp'),
        ProfileField.bool('tls', 'TLS'),
        ProfileField.text('sni', 'SNI', required: false),
        ProfileField.text('fp', '指纹', hint: '如 chrome', required: false),
        ProfileField.text('alpn', 'ALPN', hint: '逗号分隔,如 h2,http/1.1', required: false),
        ProfileField.text('headers', '自定义 Headers', hint: 'JSON,如 {"X-Token":"abc"}', required: false),
        ProfileField.text('wsPath', 'WS 路径', required: false),
        ProfileField.text('wsHost', 'WS Host', required: false),
        ProfileField.int('wsMaxEarlyData', 'WS Early Data', hint: '0=关闭', defaultValue: 0),
        ProfileField.text('earlyDataHeaderName', 'Early Data Header', required: false),
        ProfileField.bool('allowInsecure', '允许不安全连接'),
        ProfileField.bool('enableMux', 'Mux 多路复用(节点级)'),
        ProfileField.choice('muxType', 'Mux 协议', const [
          'h2mux', 'smux', 'yamux',
        ], defaultValue: 'h2mux'),
        ProfileField.int('muxConcurrency', 'Mux 并发数', defaultValue: 8),
        ProfileField.bool('muxPadding', 'Mux Padding'),
      ];
      break;
    case ProfileType.vless:
      fields = [
        ...common,
        ProfileField.text('uuid', 'UUID', hint: '自动生成请留空', required: false),
        ProfileField.choice('flow', 'Flow', const [
          '', 'xtls-rprx-vision', 'xtls-rprx-vision-udp443',
        ], defaultValue: ''),
        ProfileField.bool('tls', 'TLS'),
        ProfileField.bool('reality', 'Reality'),
        ProfileField.text('sni', 'SNI', required: false),
        ProfileField.text('publicKey', 'Reality 公钥', required: false),
        ProfileField.text('shortId', 'Short ID', required: false),
        ProfileField.choice('network', '传输协议', const [
          'tcp', 'ws', 'grpc', 'http', 'httpupgrade',
        ], defaultValue: 'tcp'),
        ProfileField.text('alpn', 'ALPN', hint: '逗号分隔,如 h2,http/1.1', required: false),
        ProfileField.text('headers', '自定义 Headers', hint: 'JSON,如 {"X-Token":"abc"}', required: false),
        ProfileField.text('wsPath', 'WS 路径', required: false),
        ProfileField.text('wsHost', 'WS Host', required: false),
        ProfileField.int('wsMaxEarlyData', 'WS Early Data', hint: '0=关闭', defaultValue: 0),
        ProfileField.text('earlyDataHeaderName', 'Early Data Header', required: false),
        ProfileField.text('grpcServiceName', 'gRPC ServiceName', required: false),
        ProfileField.bool('allowInsecure', '允许不安全连接'),
        ProfileField.bool('enableMux', 'Mux 多路复用(节点级)'),
        ProfileField.choice('muxType', 'Mux 协议', const [
          'h2mux', 'smux', 'yamux',
        ], defaultValue: 'h2mux'),
        ProfileField.int('muxConcurrency', 'Mux 并发数', defaultValue: 8),
        ProfileField.bool('muxPadding', 'Mux Padding'),
      ];
      break;
    case ProfileType.trojan:
    case ProfileType.trojanGo:
      fields = [
        ...common,
        ProfileField.text('password', '密码', isPassword: true),
        ProfileField.bool('tls', 'TLS', defaultValue: true),
        ProfileField.text('sni', 'SNI', required: false),
        ProfileField.choice('network', '传输协议', const [
          'tcp', 'ws', 'grpc', 'http', 'httpupgrade',
        ], defaultValue: 'tcp'),
        ProfileField.text('alpn', 'ALPN', hint: '逗号分隔,如 h2,http/1.1', required: false),
        ProfileField.text('headers', '自定义 Headers', hint: 'JSON,如 {"X-Token":"abc"}', required: false),
        ProfileField.text('wsPath', 'WS 路径', required: false),
        ProfileField.text('wsHost', 'WS Host', required: false),
        ProfileField.int('wsMaxEarlyData', 'WS Early Data', hint: '0=关闭', defaultValue: 0),
        ProfileField.text('earlyDataHeaderName', 'Early Data Header', required: false),
        ProfileField.bool('allowInsecure', '允许不安全连接'),
        ProfileField.bool('enableMux', 'Mux 多路复用(节点级)'),
        ProfileField.choice('muxType', 'Mux 协议', const [
          'h2mux', 'smux', 'yamux',
        ], defaultValue: 'h2mux'),
        ProfileField.int('muxConcurrency', 'Mux 并发数', defaultValue: 8),
        ProfileField.bool('muxPadding', 'Mux Padding'),
      ];
      break;
    case ProfileType.tuic:
      fields = [
        ...common,
        ProfileField.text('uuid', 'UUID', hint: '自动生成请留空', required: false),
        ProfileField.text('password', '密码', isPassword: true),
        ProfileField.choice('congestionControl', '拥塞控制', const [
          'cubic', 'new_reno', 'bbr',
        ], defaultValue: 'cubic'),
        ProfileField.text('sni', 'SNI', required: false),
        ProfileField.bool('allowInsecure', '允许不安全连接'),
      ];
      break;
    case ProfileType.hysteria2:
      fields = [
        ...common,
        ProfileField.text('password', '密码', isPassword: true),
        ProfileField.text('sni', 'SNI', required: false),
        ProfileField.int('upMbps', '上行 Mbps(0=不限)', defaultValue: 0, required: false),
        ProfileField.int('downMbps', '下行 Mbps(0=不限)', defaultValue: 0, required: false),
        ProfileField.bool('allowInsecure', '允许不安全连接'),
      ];
      break;
    case ProfileType.hysteria:
      fields = [
        ...common,
        ProfileField.text('authPayload', '认证(Auth)', hint: '服务器认证口令', required: false),
        ProfileField.text('sni', 'SNI', hint: 'peer 参数', required: false),
        ProfileField.int('upMbps', '上行 Mbps(0=不限)', defaultValue: 0, required: false),
        ProfileField.int('downMbps', '下行 Mbps(0=不限)', defaultValue: 0, required: false),
        ProfileField.text('alpn', 'ALPN', hint: '如 hysteria', required: false),
        ProfileField.text('obfuscation', '混淆参数(obfs)', hint: 'xplus 参数', required: false),
        ProfileField.bool('allowInsecure', '允许不安全连接'),
      ];
      break;
    case ProfileType.naive:
      fields = [
        ...common,
        ProfileField.text('username', '用户名', required: false),
        ProfileField.text('password', '密码', isPassword: true, required: false),
        ProfileField.text('sni', 'SNI', required: false),
        ProfileField.text('fp', '指纹', hint: '如 chrome', required: false),
        ProfileField.bool('allowInsecure', '允许不安全连接'),
      ];
      break;
    case ProfileType.wireguard:
      fields = [
        ...common,
        ProfileField.text('privateKey', '私钥', required: false),
        ProfileField.text('peerPublicKey', 'Peer 公钥', required: false),
        ProfileField.text('preSharedKey', '预共享密钥', required: false),
        ProfileField.text('allowedIps', 'Allowed IPs', defaultValue: '0.0.0.0/0,::/0', required: false),
      ];
      break;
    case ProfileType.http:
      fields = [
        ...common,
        ProfileField.text('username', '用户名', required: false),
        ProfileField.text('password', '密码', isPassword: true, required: false),
        ProfileField.bool('tls', 'TLS'),
        ProfileField.text('sni', 'SNI', required: false),
        ProfileField.bool('allowInsecure', '允许不安全连接'),
      ];
      break;
    case ProfileType.socks:
      fields = [
        ...common,
        ProfileField.text('username', '用户名', required: false),
        ProfileField.text('password', '密码', isPassword: true, required: false),
        ProfileField.bool('udpOverTcp', 'UDP over TCP'),
      ];
      break;
    case ProfileType.ssh:
      fields = [
        ...common,
        ProfileField.text('username', '用户名', required: false),
        ProfileField.text('password', '密码', isPassword: true, required: false),
        ProfileField.text('privateKey', '私钥', hint: '可选,私钥内容', required: false),
        ProfileField.text('privateKeyPassphrase', '私钥口令', isPassword: true, required: false),
        ProfileField.text('hostKeyAlgorithms', 'Host Key 算法', hint: '逗号分隔', required: false),
        ProfileField.text('clientVersion', '客户端版本', required: false),
        ProfileField.text('hostKey', 'Host Key(服务器指纹)', required: false),
      ];
      break;
    case ProfileType.anytls:
      fields = [
        ...common,
        ProfileField.text('password', '密码', isPassword: true),
        ProfileField.text('sni', 'SNI', required: false),
        ProfileField.text('fp', '指纹', hint: '如 chrome', required: false),
        ProfileField.bool('allowInsecure', '允许不安全连接'),
        ProfileField.bool('enableMux', 'Mux 多路复用(节点级)'),
        ProfileField.choice('muxType', 'Mux 协议', const [
          'h2mux', 'smux', 'yamux',
        ], defaultValue: 'h2mux'),
        ProfileField.int('muxConcurrency', 'Mux 并发数', defaultValue: 8),
        ProfileField.bool('muxPadding', 'Mux Padding'),
      ];
      break;
    case ProfileType.shadowtls:
      fields = [
        ...common,
        ProfileField.text('password', '密码', isPassword: true),
        ProfileField.int('version', '版本', defaultValue: 3),
        ProfileField.text('sni', 'SNI', required: false),
      ];
      break;
    default:
      fields = common;
  }

  return [...fields, ...advanced];
}
