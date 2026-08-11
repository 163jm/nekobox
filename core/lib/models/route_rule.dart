import 'dart:convert';

/// 分流规则,字段对齐原版 RuleEntity。
/// 规则为"多字段组合":可同时填域名/IP/端口/网络/协议/源/应用/srs。
class RouteRule {
  int id;
  String name;

  /// 自定义配置:填写完整 sing-box rule JSON 时覆盖自动生成
  String config;

  /// 排序(原版 userOrder)
  int sortIndex;
  bool enabled;

  /// 域名(每行一条,支持前缀):
  /// full:example.com / domain:example.com / regexp:... /
  /// keyword:... / geosite:xxx / 裸域名(按后缀匹配)
  String domains;

  /// IP(每行一条):CIDR 或 geoip:xxx / geoip:private
  String ip;

  /// 目标端口(每行/逗号分隔,支持 a:b 范围)
  String port;

  /// 源端口
  String sourcePort;

  /// 网络:tcp / udp
  String network;

  /// 源 IP CIDR(每行一条)
  String source;

  /// 协议(每行一条):http / tls 等(需嗅探)
  String protocol;

  /// 出站选择:0=代理 1=绕过(直连) 2=拒绝 3=选择节点
  int outboundMode;

  /// 选择节点时的节点 id
  int outboundProfileId;

  /// 应用包名(仅 Android VpnService 模式生效)
  List<String> packages;

  /// srs 规则集文件名(如 geosite-cn.srs)
  String srsName;

  /// srs 下载 URL(非空时保存后自动下载)
  String srsUrl;

  /// srs 类型:'' / 'domain' / 'ip'(用于 DNS 规则集)
  String srsType;

  RouteRule({
    this.id = 0,
    this.name = '',
    this.config = '',
    this.sortIndex = 0,
    this.enabled = true,
    this.domains = '',
    this.ip = '',
    this.port = '',
    this.sourcePort = '',
    this.network = '',
    this.source = '',
    this.protocol = '',
    this.outboundMode = 0,
    this.outboundProfileId = 0,
    List<String>? packages,
    this.srsName = '',
    this.srsUrl = '',
    this.srsType = '',
  }) : packages = packages ?? [];

  factory RouteRule.fromJson(Map<String, dynamic> json) {
    return RouteRule(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      config: (json['config'] as String?) ?? '',
      sortIndex: (json['sortIndex'] as num?)?.toInt() ?? 0,
      enabled: (json['enabled'] as bool?) ?? true,
      domains: (json['domains'] as String?) ?? '',
      ip: (json['ip'] as String?) ?? '',
      port: (json['port'] as String?) ?? '',
      sourcePort: (json['sourcePort'] as String?) ?? '',
      network: (json['network'] as String?) ?? '',
      source: (json['source'] as String?) ?? '',
      protocol: (json['protocol'] as String?) ?? '',
      outboundMode: (json['outboundMode'] as num?)?.toInt() ?? 0,
      outboundProfileId: (json['outboundProfileId'] as num?)?.toInt() ?? 0,
      packages: (json['packages'] as List?)?.whereType<String>().toList() ?? [],
      srsName: (json['srsName'] as String?) ?? '',
      srsUrl: (json['srsUrl'] as String?) ?? '',
      srsType: (json['srsType'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'config': config,
      'sortIndex': sortIndex,
      'enabled': enabled,
      'domains': domains,
      'ip': ip,
      'port': port,
      'sourcePort': sourcePort,
      'network': network,
      'source': source,
      'protocol': protocol,
      'outboundMode': outboundMode,
      'outboundProfileId': outboundProfileId,
      'packages': packages,
      'srsName': srsName,
      'srsUrl': srsUrl,
      'srsType': srsType,
    };
  }

  RouteRule copy() => RouteRule.fromJson(jsonDecode(jsonEncode(toJson())));

  String displayName() => name.isNotEmpty ? name : 'Rule $id';

  /// 摘要(对齐原版 mkSummary,最多 3 行)
  String summary() {
    final lines = <String>[];
    if (config.isNotEmpty) lines.add('[config]');
    if (domains.trim().isNotEmpty) lines.add(domains.trim());
    if (ip.trim().isNotEmpty) lines.add(ip.trim());
    if (source.trim().isNotEmpty) lines.add('src ip: ${source.trim()}');
    if (sourcePort.trim().isNotEmpty) lines.add('src port: ${sourcePort.trim()}');
    if (port.trim().isNotEmpty) lines.add('dst port: ${port.trim()}');
    if (network.trim().isNotEmpty) lines.add('network: ${network.trim()}');
    if (protocol.trim().isNotEmpty) lines.add('protocol: ${protocol.trim()}');
    if (packages.isNotEmpty) lines.add('apps: ${packages.length}');
    if (srsName.isNotEmpty) {
      lines.add('srs: $srsName${srsType.isNotEmpty ? '[$srsType]' : ''}');
    }
    if (lines.length > 3) {
      return '${lines.take(3).join('\n')}\n...';
    }
    return lines.join('\n');
  }

  /// 出站显示名
  String outboundLabel(String Function(int profileId) profileNameOf) {
    switch (outboundMode) {
      case 1:
        return '绕过';
      case 2:
        return '拒绝';
      case 3:
        return profileNameOf(outboundProfileId) ?? '选择配置';
      default:
        return '代理';
    }
  }

  /// 是否为空规则(无任何匹配条件)
  bool checkEmpty() {
    return domains.trim().isEmpty &&
        ip.trim().isEmpty &&
        port.trim().isEmpty &&
        sourcePort.trim().isEmpty &&
        network.trim().isEmpty &&
        source.trim().isEmpty &&
        protocol.trim().isEmpty &&
        packages.isEmpty &&
        srsName.trim().isEmpty &&
        config.trim().isEmpty;
  }
}
