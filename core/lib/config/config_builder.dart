import 'dart:convert';

import '../models/profile.dart';
import '../models/profile_type.dart';
import '../models/proxy_group.dart';
import '../models/route_rule.dart';

/// 根据节点列表生成 sing-box 运行配置 JSON。
class ConfigBuilder {
  ConfigBuilder._();

  static Map<String, dynamic> build({
    required List<Profile> profiles,
    required Profile? selected,
    required int localPort,
    String logLevel = 'info',
    String proxyMode = 'local',
    String tunAddress = '172.19.0.1/30',
    int tunMtu = 9000,
    bool bypassLan = true,
    bool enableIpv6 = false,
    int ipv6Mode = 0,
    bool sniff = true,
    bool strictRoute = false,
    bool tcpFastOpen = false,
    String remoteDns = 'https://1.1.1.1/dns-query',
    String directDns = 'localhost',
    bool clashApiEnabled = false,
    int clashApiPort = 9090,
    String clashApiSecret = '',
    String clashApiUi = '',
    String? vpnInterface,
    /// 非 root TUN:VpnService 建立的 tun fd(Android,传给 sing-box)
    int? tunFd,
    // —— 路由(对齐原版) ——
    String routeFinal = '0',
    List<RouteRule> rules = const [],
    List<String> availableSrsFiles = const [],
    String srsDirectory = '',
    // —— 其他(对齐原版) ——
    String tunStack = 'system',
    String globalCustomConfig = '',
    // —— 链式代理 / fakeip / 分应用 ——
    List<ProxyGroup> groups = const [],
    bool enableFakeDns = false,
    Map<String, int> packageUids = const {},
    /// 分应用代理:选中应用的 uid 列表(proxyApps 开启时生效)
    List<int> proxyAppUids = const [],
    // —— 原版设置映射 ——
    bool allowAccess = false,
    bool resolveDestination = true,
    bool enableDnsRouting = true,
    bool bypassLanInCore = true,
    bool globalAllowInsecure = false,
    // —— 新功能扩展 ——
    int mixedPort = 0,
    bool pluginEnabled = false,
    String pluginPath = '',
    bool subscriptionDeduplication = true,
    bool subscriptionForceResolve = false,
  }) {
    final outbounds = <Map<String, dynamic>>[];
    final tags = <String>[];
    // 组 → front/landing 映射(链式代理,对齐原版)
    final groupById = {for (final g in groups) g.id: g};
    final profileById = {for (final p in profiles) p.id: p};

    String selectTagFor(Profile? p) {
      if (p == null) return 'auto';
      final g = groupById[p.groupId];
      final front = (g != null && g.frontProxyId > 0)
          ? profileById[g.frontProxyId]
          : null;
      final landing = (g != null && g.landingProxyId > 0)
          ? profileById[g.landingProxyId]
          : null;
      if (landing != null) return 'l-${p.id}';
      if (front != null) return 'c-${p.id}';
      return p.tag;
    }

    final selectedTag = selectTagFor(selected);

    // IPv6 模式 → 域策略:0=禁用 1=启用(优先IPv4) 2=优先IPv6 3=仅IPv6
    final ipv6Strategy = _resolveIpv6Strategy(ipv6Mode, enableIpv6);

    for (final p in profiles) {
      // 节点自身 outbound(普通,无链;供测速/高级引用)
      final ob = buildOutbound(p, globalAllowInsecure: globalAllowInsecure);
      if (ob == null) continue;
      // 节点级 mux(VMess/Trojan,对齐原版 singMux)
      final muxMap = _muxMap(p);
      if (muxMap != null) ob['multiplex'] = muxMap;

      final group = groupById[p.groupId];
      final front = (group != null && group.frontProxyId > 0)
          ? profileById[group.frontProxyId]
          : null;
      final landing = (group != null && group.landingProxyId > 0)
          ? profileById[group.landingProxyId]
          : null;

      if (front == null && landing == null) {
        outbounds.add(ob);
        tags.add(p.tag);
        continue;
      }

      // 链式代理:route 命中 l-<p.id>(有落地)否则 c-<p.id>
      // detour 链:l-<p> → c-<p> → f-<frontId>(组共享,无 detour)
      if (front != null) {
        final exists = outbounds.any(
            (o) => o['tag'] == 'f-${front.id}');
        if (!exists) {
          final fob = buildOutbound(front, globalAllowInsecure: globalAllowInsecure);
          if (fob != null) {
            fob['tag'] = 'f-${front.id}';
            outbounds.add(fob);
          }
        }
      }
      if (landing != null) {
        final lob = buildOutbound(landing, globalAllowInsecure: globalAllowInsecure);
        if (lob != null) {
          lob['tag'] = 'l-${p.id}';
          lob['detour'] = 'c-${p.id}';
          outbounds.add(lob);
        }
      }
      final cob = buildOutbound(p, globalAllowInsecure: globalAllowInsecure);
      if (cob != null) {
        final muxC = _muxMap(p);
        if (muxC != null) cob['multiplex'] = muxC;
        cob['tag'] = 'c-${p.id}';
        if (front != null) cob['detour'] = 'f-${front.id}';
        outbounds.add(cob);
      }
      // 普通版保留
      outbounds.add(ob);
      tags.add(selectTagFor(p));
    }

    // 兜底出站
    outbounds.add({'type': 'direct', 'tag': 'direct'});
    outbounds.add({'type': 'block', 'tag': 'block'});
    tags.add('direct');
    tags.add('block');

    // 主出站:selector 指向选中节点,便于运行时切换
    final mainOutbound = {
      'type': 'selector',
      'tag': 'main',
      'outbounds': tags,
      'default': selectedTag,
    };
    outbounds.insert(0, mainOutbound);

    // 本地代理入站
    final inbounds = <Map<String, dynamic>>[
      {
        'type': 'mixed',
        'tag': 'mixed-in',
        // allowAccess: 允许局域网访问(0.0.0.0),对齐原版
        'listen': allowAccess ? '0.0.0.0' : '127.0.0.1',
        'listen_port': localPort,
        'sniff': sniff,
        'sniff_override_destination': true,
      },
    ];

    // 混合端口(额外监听,同时支持 SOCKS5 + HTTP)
    if (mixedPort > 0) {
      inbounds.add({
        'type': 'mixed',
        'tag': 'mixed-port-in',
        'listen': allowAccess ? '0.0.0.0' : '127.0.0.1',
        'listen_port': mixedPort,
        'sniff': sniff,
        'sniff_override_destination': true,
      });
    }

    // TUN 入站(可选,对齐原版参数)
    if (proxyMode == 'tun') {
      if (tunFd != null) {
        // 非 root TUN:使用 VpnService 建立的接口,仅传 fd
        // (接口地址/路由由 VpnService 配置,其余字段 fd 模式下无效)
        inbounds.add({
          'type': 'tun',
          'tag': 'tun-in',
          'fd': [tunFd],
          'mtu': tunMtu,
          'sniff': sniff,
          'sniff_override_destination': true,
        });
      } else {
        // root TUN:sing-box 自己创建 tun 设备
        inbounds.add({
          'type': 'tun',
          'tag': 'tun-in',
          'address': [tunAddress],
          'mtu': tunMtu,
          'auto_route': true,
          'strict_route': strictRoute,
          'stack': tunStack,
          'endpoint_independent_nat': true,
          // resolveDestination: false → 域名 as-is
          if (resolveDestination)
            'domain_strategy': ipv6Strategy,
          'sniff': sniff,
          'sniff_override_destination': true,
          if (vpnInterface != null && vpnInterface.isNotEmpty)
            'interface_name': vpnInterface,
        });
      }
    }

    // 路由段(规则 + rule_set + final)
    final routeProfileTags = {
      for (final p in profiles) p.id: selectTagFor(p),
    };
    final routeSection = _buildRoute(
      routeFinal: routeFinal,
      rules: rules,
      profiles: profiles,
      availableSrsFiles: availableSrsFiles,
      srsDirectory: srsDirectory,
      // 内核"私有 IP 直连"规则只由 bypassLanInCore 控制;
      // app 层 bypassLan(VpnService 路由排除)与内核规则是两套独立开关
      bypassLan: bypassLanInCore,
      profileTags: routeProfileTags,
      packageUids: packageUids,
      proxyAppUids: proxyAppUids,
      proxyMode: proxyMode,
    );

    final result = <String, dynamic>{
      'log': {'level': logLevel, 'timestamp': true},
      'inbounds': inbounds,
      'outbounds': outbounds,
      'route': routeSection,
    };

    // —— DNS(对齐原版:block/local/direct/remote + 回环保护 + 节点域名直连解析) ——
    final dnsStrategy = ipv6Strategy;
    // 节点服务器域名 + 远端 DNS 域名 → 强制直连解析(避免死循环)
    final directForceDomains = <String>{};
    for (final p in profiles) {
      final addr = p.serverAddress;
      if (addr.isNotEmpty && !_isIpAddress(addr)) {
        directForceDomains.add('full:$addr');
      }
    }
    try {
      final remoteUri = Uri.parse(remoteDns);
      if (remoteUri.host.isNotEmpty && !_isIpAddress(remoteUri.host)) {
        directForceDomains.add('full:${remoteUri.host}');
      }
    } catch (_) {}

    final dnsServers = <Map<String, dynamic>>[
      {'tag': 'dns-block', 'address': 'rcode://success'},
      {'tag': 'dns-local', 'address': 'local', 'detour': 'direct'},
      if (directDns.trim().isNotEmpty)
        {
          'tag': 'dns-direct',
          'address': directDns.trim(),
          'detour': 'direct',
          'address_resolver': 'dns-local',
          'strategy': dnsStrategy,
        },
      if (remoteDns.trim().isNotEmpty)
        {
          'tag': 'dns-remote',
          'address': remoteDns.trim(),
          'address_resolver': 'dns-direct',
          'strategy': dnsStrategy,
        },
    ];
    final dnsRules = <Map<String, dynamic>>[
      // 避免回环:其余出站一律直连解析
      {'outbound': ['any'], 'server': 'dns-direct'},
    ];
    if (directForceDomains.isNotEmpty) {
      final force = <String, dynamic>{};
      _makeDomainFields(force, directForceDomains.toList());
      force['server'] = 'dns-direct';
      dnsRules.insert(0, force);
    }

    result['dns'] = {
      'servers': dnsServers,
      'rules': dnsRules,
      // dns.final 只由 routeFinal 决定(对齐原版);
      // enableDnsRouting 仅控制用户自定义 DNS 规则是否进 dns.rules
      'final': routeFinal == '-1' ? 'dns-direct' : 'dns-remote',
      'independent_cache': true,
    };

    // FakeIP(TUN 模式,对齐原版 enableFakeDns)
    if (proxyMode == 'tun' && enableFakeDns) {
      dnsServers.add({'tag': 'dns-fake', 'address': 'fakeip', 'strategy': 'ipv4_only'});
      dnsRules.insert(0, {
        'inbound': ['tun-in'],
        'server': 'dns-fake',
        'disable_cache': true,
      });
      (result['dns'] as Map<String, dynamic>)['fakeip'] = {
        'enabled': true,
        'inet4_range': '198.18.0.0/15',
        'inet6_range': 'fc00::/18',
      };
    }

    // TCP Fast Open
    if (tcpFastOpen) {
      result['experimental'] = {'tcp_fast_open': true};
    }

    // Clash API(对齐原版:external_ui 指向面板目录)
    if (clashApiEnabled) {
      final experimental = (result['experimental'] as Map<String, dynamic>?) ?? {};
      experimental['clash_api'] = {
        'default_mode': 'rule',
        if (clashApiSecret.isNotEmpty) 'secret': clashApiSecret,
        'external_controller': '127.0.0.1:$clashApiPort',
        if (clashApiUi.isNotEmpty) 'external_ui': clashApiUi,
      };
      result['experimental'] = experimental;
    }

    // 插件支持(如 v2ray-plugin / obfs-local 等 SS 插件)
    if (pluginEnabled && pluginPath.isNotEmpty) {
      result['plugin'] = {
        'enabled': true,
        'path': pluginPath,
      };
    }

    // 订阅去重与强制解析设置(写入配置元数据,供运行时参考)
    result['subscription_settings'] = {
      'deduplication': subscriptionDeduplication,
      'force_resolve': subscriptionForceResolve,
    };

    // 全局自定义配置 merge(高级,对齐原版 globalCustomConfig)
    if (globalCustomConfig.trim().isNotEmpty) {
      try {
        final extra = jsonDecode(globalCustomConfig);
        if (extra is Map<String, dynamic>) {
          _mergeDeep(result, extra);
        }
      } catch (_) {}
    }

    return result;
  }

  /// 深度合并 extra 到 base(嵌套 map 递归覆盖)
  static void _mergeDeep(
      Map<String, dynamic> base, Map<String, dynamic> extra) {
    for (final entry in extra.entries) {
      final v = entry.value;
      if (v is Map<String, dynamic> &&
          base[entry.key] is Map<String, dynamic>) {
        _mergeDeep(base[entry.key] as Map<String, dynamic>, v);
      } else {
        base[entry.key] = v;
      }
    }
  }

  static bool _isIpAddress(String s) {
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(s)) return true;
    return s.contains(':');
  }

  /// IPv6 模式 → sing-box domain_strategy / dns strategy 字符串。
  /// [ipv6Mode]: 0=禁用 1=启用(优先IPv4) 2=优先IPv6 3=仅IPv6
  /// [enableIpv6]: 旧版兼容参数(ipv6Mode==0 时回退使用)
  static String _resolveIpv6Strategy(int ipv6Mode, bool enableIpv6) {
    if (ipv6Mode == 0) {
      return enableIpv6 ? 'prefer_ipv4' : 'ipv4_only';
    }
    switch (ipv6Mode) {
      case 1:
        return 'prefer_ipv4';
      case 2:
        return 'prefer_ipv6';
      case 3:
        return 'ipv6_only';
      default:
        return 'ipv4_only';
    }
  }

  /// 构建 route 段:用户规则 + rule_set + final(对齐原版 ConfigBuilder)。
  static Map<String, dynamic> _buildRoute({
    required String routeFinal,
    required List<RouteRule> rules,
    required List<Profile> profiles,
    required List<String> availableSrsFiles,
    required String srsDirectory,
    required bool bypassLan,
    required Map<int, String> profileTags,
    required Map<String, int> packageUids,
    required List<int> proxyAppUids,
    required String proxyMode,
  }) {
    final ruleSets = <Map<String, dynamic>>[];
    final ruleList = <Map<String, dynamic>>[];

    for (final rule in rules) {
      if (!rule.enabled) continue;
      if (rule.checkEmpty()) continue;
      final ruleObj =
          _ruleFor(rule, profileTags, availableSrsFiles, srsDirectory, packageUids);
      if (ruleObj == null) continue;
      for (final rs in _collectRuleSets(rule, availableSrsFiles, srsDirectory)) {
        if (!ruleSets.any((e) => e['tag'] == rs['tag'])) {
          ruleSets.add(rs);
        }
      }
      ruleList.add(ruleObj);
    }

    // 基础内置规则(对齐原版):DNS hijack 置顶 + 绕过局域网 + 组播拦截
    ruleList.insert(0, {'protocol': ['dns'], 'action': 'hijack-dns'});
    ruleList.insert(0, {'port': [53], 'action': 'hijack-dns'});
    if (bypassLan) {
      ruleList.add({'outbound': 'direct', 'ip_is_private': true});
    }
    ruleList.add({
      'ip_cidr': ['224.0.0.0/3', 'ff00::/8'],
      'source_ip_cidr': ['224.0.0.0/3', 'ff00::/8'],
      'action': 'reject',
    });

    // 分应用代理(proxyApps):选中应用 → 代理,其余流量 → 直连。
    // 用户分流规则在前(选中应用仍走国内直连/广告拦截),末尾追加
    // user_id → main;final 强制 direct(未选中应用全部直连,模拟原版
    // VpnService 只转发选中应用流量的行为)。
    // 分应用代理仅在 TUN 模式生效(user_id 匹配依赖连接层 uid 凭证,
    // 本地代理入站无 uid 上下文;local 模式下强制 direct 会全量直连)
    final proxyMode2 =
        proxyMode == 'tun' && proxyAppUids.isNotEmpty;
    final finalOutbound = switch (routeFinal) {
      '-1' => 'direct',
      '0' => proxyMode2 ? 'direct' : 'main',
      _ =>
        proxyMode2
            ? 'direct'
            : (profileTags[int.tryParse(routeFinal) ?? 0] ?? 'main'),
    };
    if (proxyMode2) {
      ruleList.add({
        'user_id': proxyAppUids,
        'outbound': 'main',
      });
    }

    return {
      'final': finalOutbound,
      'auto_detect_interface': true,
      if (ruleSets.isNotEmpty) 'rule_set': ruleSets,
      if (ruleList.isNotEmpty) 'rules': ruleList,
    };
  }

  /// 单条规则 → sing-box rule(对齐原版 RuleEntity 转换)。
  static Map<String, dynamic>? _ruleFor(
    RouteRule rule,
    Map<int, String> profileTags,
    List<String> availableSrsFiles,
    String srsDirectory,
    Map<String, int> packageUids,
  ) {
    // 高级:完整自定义规则 JSON 直接使用
    if (rule.config.trim().isNotEmpty) {
      try {
        final parsed = jsonDecode(rule.config);
        if (parsed is Map) {
          final obj = Map<String, dynamic>.from(parsed);
          obj.putIfAbsent('outbound', () => _outboundTag(rule, profileTags));
          return obj;
        }
      } catch (_) {}
    }

    final ruleObj = <String, dynamic>{};

    // 域名(支持 full:/domain:/regexp:/keyword: 前缀)
    final domains = _listByLineOrComma(rule.domains);
    if (domains.isNotEmpty) {
      _makeDomainFields(ruleObj, domains);
    }

    // IP(CIDR / geoip:private)
    final ips = _listByLineOrComma(rule.ip);
    if (ips.isNotEmpty) {
      _makeIpFields(ruleObj, ips);
    }

    // 用户 srs 规则集(本地文件)
    if (rule.srsName.trim().isNotEmpty) {
      ruleObj.putIfAbsent('rule_set', () => <String>[]);
      (ruleObj['rule_set'] as List).add(_srsTag(rule.srsName.trim()));
    }

    // 目标端口(支持 a:b 范围)
    if (rule.port.trim().isNotEmpty) {
      final ports = <int>[];
      final ranges = <String>[];
      for (final item in _listByLineOrComma(rule.port)) {
        if (item.contains(':')) {
          ranges.add(item);
        } else {
          final p = int.tryParse(item);
          if (p != null) ports.add(p);
        }
      }
      if (ports.isNotEmpty) ruleObj['port'] = ports;
      if (ranges.isNotEmpty) ruleObj['port_range'] = ranges;
    }

    // 源端口
    if (rule.sourcePort.trim().isNotEmpty) {
      final ports = <int>[];
      final ranges = <String>[];
      for (final item in _listByLineOrComma(rule.sourcePort)) {
        if (item.contains(':')) {
          ranges.add(item);
        } else {
          final p = int.tryParse(item);
          if (p != null) ports.add(p);
        }
      }
      if (ports.isNotEmpty) ruleObj['source_port'] = ports;
      if (ranges.isNotEmpty) ruleObj['source_port_range'] = ranges;
    }

    // 网络
    if (rule.network.trim().isNotEmpty) {
      ruleObj['network'] = [rule.network.trim()];
    }

    // 源 IP
    final sources = _listByLineOrComma(rule.source);
    if (sources.isNotEmpty) {
      ruleObj['source_ip_cidr'] = sources;
    }

    // 协议(需嗅探)
    final protocols = _listByLineOrComma(rule.protocol);
    if (protocols.isNotEmpty) {
      ruleObj['protocol'] = protocols;
    }

    // 分应用(仅 Android VPN 模式生效;uid 解析失败则该规则不匹配)
    if (rule.packages.isNotEmpty) {
      final uids = <int>[];
      for (final pkg in rule.packages) {
        final uid = packageUids[pkg];
        if (uid != null && uid >= 1000) uids.add(uid);
      }
      if (uids.isNotEmpty) ruleObj['user_id'] = uids;
    }

    // 出站:block 使用 action reject
    final outbound = _outboundTag(rule, profileTags);
    if (outbound == 'block') {
      ruleObj['action'] = 'reject';
    } else {
      ruleObj['outbound'] = outbound;
    }

    if (ruleObj.isEmpty) return null;
    return ruleObj;
  }

  /// 规则引用到的 rule_set 声明列表。
  static List<Map<String, dynamic>> _collectRuleSets(
    RouteRule rule,
    List<String> availableSrsFiles,
    String srsDirectory,
  ) {
    final result = <Map<String, dynamic>>[];
    final srsName = rule.srsName.trim();
    if (srsName.isEmpty) return result;
    final fileName = srsName.endsWith('.srs') ? srsName : '$srsName.srs';
    if (!availableSrsFiles.contains(fileName)) return result;
    result.add({
      'type': 'local',
      'tag': _srsTag(srsName),
      'format': 'binary',
      'path': srsDirectory.isEmpty
          ? fileName
          : '$srsDirectory${'/'}$fileName',
    });
    return result;
  }

  static String _srsTag(String srsName) {
    final fileName = srsName.endsWith('.srs') ? srsName : '$srsName.srs';
    return fileName.endsWith('.srs')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;
  }

  static String _outboundTag(RouteRule rule, Map<int, String> profileTags) {
    switch (rule.outboundMode) {
      case 1:
        return 'direct';
      case 2:
        return 'block';
      case 3:
        return profileTags[rule.outboundProfileId] ?? 'main';
      default:
        return 'main';
    }
  }

  static List<String> _listByLineOrComma(String input) {
    return input
        .split(RegExp(r'[,\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 域名输入 → sing-box 字段(对齐原版 makeSingBoxRule)。
  static void _makeDomainFields(Map<String, dynamic> ruleObj, List<String> list) {
    final domain = <String>[];
    final suffix = <String>[];
    final regex = <String>[];
    final keyword = <String>[];
    for (final raw in list) {
      final it = raw.trim();
      if (it.startsWith('geosite:')) {
        // 依赖内置 geosite 数据库,本项目仅用 srs,忽略
        continue;
      } else if (it.startsWith('full:')) {
        domain.add(it.substring(5).toLowerCase());
      } else if (it.startsWith('domain:')) {
        suffix.add(it.substring(7).toLowerCase());
      } else if (it.startsWith('regexp:')) {
        regex.add(it.substring(7).toLowerCase());
      } else if (it.startsWith('keyword:')) {
        keyword.add(it.substring(8).toLowerCase());
      } else {
        suffix.add(it.toLowerCase());
      }
    }
    if (domain.isNotEmpty) ruleObj['domain'] = domain;
    if (suffix.isNotEmpty) ruleObj['domain_suffix'] = suffix;
    if (regex.isNotEmpty) ruleObj['domain_regex'] = regex;
    if (keyword.isNotEmpty) ruleObj['domain_keyword'] = keyword;
  }

  /// IP 输入 → sing-box 字段(对齐原版 makeSingBoxRule)。
  static void _makeIpFields(Map<String, dynamic> ruleObj, List<String> list) {
    final cidrs = <String>[];
    for (final raw in list) {
      final it = raw.trim();
      if (it.startsWith('geoip:')) {
        if (it == 'geoip:private') {
          ruleObj['ip_is_private'] = true;
        }
        // 其他 geoip: 依赖内置数据库,忽略
        continue;
      }
      cidrs.add(it);
    }
    if (cidrs.isNotEmpty) ruleObj['ip_cidr'] = cidrs;
  }

  /// 生成 sing-box 配置文件并序列化
  static String buildJsonString({
    required List<Profile> profiles,
    required Profile? selected,
    required int localPort,
    String logLevel = 'info',
    String proxyMode = 'local',
    String tunAddress = '172.19.0.1/30',
    int tunMtu = 9000,
    bool bypassLan = true,
    bool enableIpv6 = false,
    int ipv6Mode = 0,
    bool sniff = true,
    bool strictRoute = false,
    bool tcpFastOpen = false,
    String remoteDns = 'https://1.1.1.1/dns-query',
    String directDns = 'localhost',
    bool clashApiEnabled = false,
    int clashApiPort = 9090,
    String clashApiSecret = '',
    String clashApiUi = '',
    String? vpnInterface,
    int? tunFd,
    // —— 路由(对齐原版) ——
    String routeFinal = '0',
    List<RouteRule> rules = const [],
    List<String> availableSrsFiles = const [],
    String srsDirectory = '',
    // —— 其他(对齐原版) ——
    String tunStack = 'system',
    String globalCustomConfig = '',
    List<ProxyGroup> groups = const [],
    bool enableFakeDns = false,
    Map<String, int> packageUids = const {},
    List<int> proxyAppUids = const [],
    // —— 原版设置映射 ——
    bool allowAccess = false,
    bool resolveDestination = true,
    bool enableDnsRouting = true,
    bool bypassLanInCore = true,
    bool globalAllowInsecure = false,
    // —— 新功能扩展 ——
    int mixedPort = 0,
    bool pluginEnabled = false,
    String pluginPath = '',
    bool subscriptionDeduplication = true,
    bool subscriptionForceResolve = false,
  }) {
    return const JsonEncoder.withIndent('  ').convert(build(
      profiles: profiles,
      selected: selected,
      localPort: localPort,
      logLevel: logLevel,
      proxyMode: proxyMode,
      tunAddress: tunAddress,
      tunMtu: tunMtu,
      bypassLan: bypassLan,
      enableIpv6: enableIpv6,
      ipv6Mode: ipv6Mode,
      sniff: sniff,
      strictRoute: strictRoute,
      tcpFastOpen: tcpFastOpen,
      remoteDns: remoteDns,
      directDns: directDns,
      clashApiEnabled: clashApiEnabled,
      clashApiPort: clashApiPort,
      clashApiSecret: clashApiSecret,
      clashApiUi: clashApiUi,
      vpnInterface: vpnInterface,
      tunFd: tunFd,
      routeFinal: routeFinal,
      rules: rules,
      availableSrsFiles: availableSrsFiles,
      srsDirectory: srsDirectory,
      tunStack: tunStack,
      globalCustomConfig: globalCustomConfig,
      groups: groups,
      enableFakeDns: enableFakeDns,
      packageUids: packageUids,
      proxyAppUids: proxyAppUids,
      allowAccess: allowAccess,
      resolveDestination: resolveDestination,
      enableDnsRouting: enableDnsRouting,
      bypassLanInCore: bypassLanInCore,
      globalAllowInsecure: globalAllowInsecure,
      mixedPort: mixedPort,
      pluginEnabled: pluginEnabled,
      pluginPath: pluginPath,
      subscriptionDeduplication: subscriptionDeduplication,
      subscriptionForceResolve: subscriptionForceResolve,
    ));
  }

  /// 单个节点 → sing-box outbound
  static Map<String, dynamic>? buildOutbound(Profile p,
      {bool globalAllowInsecure = false}) {
    final server = p.serverAddress;
    final port = p.serverPort;
    final tag = p.tag;
    if (server.isEmpty || port <= 0) return null;

    switch (p.type) {
      case ProfileType.shadowsocks:
        return {
          'type': 'shadowsocks',
          'tag': tag,
          'server': server,
          'server_port': port,
          'method': p.bean['method'] ?? 'aes-128-gcm',
          'password': p.bean['password'] ?? '',
          'plugin': p.bean['plugin'] ?? '',
          'plugin_opts': p.bean['plugin_opts'] ?? '',
        }..removeWhere((k, v) => v == '');

      case ProfileType.vmess:
        return {
          'type': 'vmess',
          'tag': tag,
          'server': server,
          'server_port': port,
          'uuid': p.bean['uuid'] ?? '',
          'security': p.bean['security'] ?? 'auto',
          'alter_id': p.bean['alterId'] ?? 0,
          'tls': _tlsMap(p, globalAllowInsecure: globalAllowInsecure),
          'transport': _transportMap(p),
        }..removeWhere((k, v) => v == null || (v is Map && v.isEmpty));

      case ProfileType.vless:
        return {
          'type': 'vless',
          'tag': tag,
          'server': server,
          'server_port': port,
          'uuid': p.bean['uuid'] ?? '',
          'flow': p.bean['flow'] ?? '',
          'tls': _tlsMap(p, globalAllowInsecure: globalAllowInsecure),
          'transport': _transportMap(p),
        }..removeWhere((k, v) => v == null || v == '' || (v is Map && v.isEmpty));

      case ProfileType.trojan:
      case ProfileType.trojanGo:
        // Trojan-Go 与标准 Trojan 同构(transport/tls 通用),sing-box trojan 兼容
        return {
          'type': 'trojan',
          'tag': tag,
          'server': server,
          'server_port': port,
          'password': p.bean['password'] ?? '',
          'tls': _tlsMap(p, globalAllowInsecure: globalAllowInsecure),
          'transport': _transportMap(p),
        }..removeWhere((k, v) => v == null || (v is Map && v.isEmpty));

      case ProfileType.tuic:
        return {
          'type': 'tuic',
          'tag': tag,
          'server': server,
          'server_port': port,
          'uuid': p.bean['uuid'] ?? '',
          'password': p.bean['password'] ?? '',
          'congestion_control': p.bean['congestionControl'] ?? 'cubic',
          'udp_relay_mode': p.bean['udpRelayMode'] ?? 'native',
          'zero_rtt_handshake': p.bean['zeroRttHandshake'] ?? false,
          'heartbeat_interval': p.bean['heartbeatInterval'] ?? 10000,
          'tls': _tlsMap(p, globalAllowInsecure: globalAllowInsecure),
        }..removeWhere((k, v) => v == null || (v is Map && v.isEmpty));

      case ProfileType.hysteria2:
        return {
          'type': 'hysteria2',
          'tag': tag,
          'server': server,
          'server_port': port,
          'password': p.bean['password'] ?? '',
          'up_mbps': _positiveOrNull(p.bean['upMbps']),
          'down_mbps': _positiveOrNull(p.bean['downMbps']),
          // 混淆(salamander,几乎必配)
          if ((p.bean['obfs']?.toString() ?? '').isNotEmpty)
            'obfs': {
              'type': 'salamander',
              'password': p.bean['obfs'],
            },
          // 端口跳跃(serverPorts: 1000-2000,2001,3000)
          if ((p.bean['serverPorts']?.toString() ?? '').isNotEmpty)
            'server_ports': p.bean['serverPorts'],
          'tls': _tlsMap(p, globalAllowInsecure: globalAllowInsecure),
        }..removeWhere((k, v) => v == null || (v is Map && v.isEmpty));

      case ProfileType.hysteria:
        // Hysteria v1(对齐原版 HysteriaFmt)
        return {
          'type': 'hysteria',
          'tag': tag,
          'server': server,
          'server_port': port,
          'up_mbps': _positiveOrNull(p.bean['upMbps']),
          'down_mbps': _positiveOrNull(p.bean['downMbps']),
          if ((p.bean['authPayload']?.toString() ?? '').isNotEmpty)
            'auth_str': p.bean['authPayload'],
          if ((p.bean['obfuscation']?.toString() ?? '').isNotEmpty)
            'obfs': 'xplus:${p.bean['obfuscation']}',
          if ((p.bean['streamReceiveWindow'] as num?)?.toInt() != null)
            'recv_window_conn':
                (p.bean['streamReceiveWindow'] as num?)?.toInt(),
          if ((p.bean['connectionReceiveWindow'] as num?)?.toInt() != null)
            'recv_window':
                (p.bean['connectionReceiveWindow'] as num?)?.toInt(),
          if (p.bean['disableMtuDiscovery'] == true)
            'disable_mtu_discovery': true,
          'tls': _tlsMap(p, globalAllowInsecure: globalAllowInsecure),
        }..removeWhere((k, v) =>
            v == null || v == 0 || (v is Map && v.isEmpty));

      case ProfileType.wireguard:
        return _wireguardOutbound(p, server, port, tag);

      case ProfileType.http:
        return {
          'type': 'http',
          'tag': tag,
          'server': server,
          'server_port': port,
          'username': p.bean['username'] ?? '',
          'password': p.bean['password'] ?? '',
          'tls': _tlsMap(p, globalAllowInsecure: globalAllowInsecure),
        }..removeWhere((k, v) => v == null || v == '' || (v is Map && v.isEmpty));

      case ProfileType.naive:
        return {
          'type': 'naive',
          'tag': tag,
          'server': server,
          'server_port': port,
          'username': p.bean['username'] ?? '',
          'password': p.bean['password'] ?? '',
          'tls': _tlsMap(p, globalAllowInsecure: globalAllowInsecure),
        }..removeWhere((k, v) => v == null || v == '' || (v is Map && v.isEmpty));

      case ProfileType.socks:
        return {
          'type': 'socks',
          'tag': tag,
          'server': server,
          'server_port': port,
          'username': p.bean['username'] ?? '',
          'password': p.bean['password'] ?? '',
          'udp_over_tcp': p.bean['udpOverTcp'] ?? false,
        }..removeWhere((k, v) => v == null || v == '');

      case ProfileType.ssh:
        return {
          'type': 'ssh',
          'tag': tag,
          'server': server,
          'server_port': port,
          'user': p.bean['username'] ?? '',
          'password': p.bean['password'] ?? '',
          'private_key': p.bean['privateKey'] ?? '',
          if ((p.bean['privateKeyPassphrase']?.toString() ?? '').isNotEmpty)
            'private_key_passphrase': p.bean['privateKeyPassphrase'],
          if ((p.bean['hostKeyAlgorithms']?.toString() ?? '').isNotEmpty)
            'host_key_algorithms': p.bean['hostKeyAlgorithms']
                .toString()
                .split(RegExp(r'[,\n]'))
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
          if ((p.bean['clientVersion']?.toString() ?? '').isNotEmpty)
            'client_version': p.bean['clientVersion'],
          if ((p.bean['hostKey']?.toString() ?? '').isNotEmpty)
            'host_key': p.bean['hostKey'],
        }..removeWhere((k, v) => v == null || v == '' || v == []);

      case ProfileType.anytls:
        return {
          'type': 'anytls',
          'tag': tag,
          'server': server,
          'server_port': port,
          'password': p.bean['password'] ?? '',
          'tls': _tlsMap(p, globalAllowInsecure: globalAllowInsecure),
        }..removeWhere((k, v) => v == null || (v is Map && v.isEmpty));

      case ProfileType.shadowtls:
        return {
          'type': 'shadowtls',
          'tag': tag,
          'server': server,
          'server_port': port,
          'version': p.bean['version'] ?? 3,
          'password': p.bean['password'] ?? '',
          'tls': _tlsMap(p, globalAllowInsecure: globalAllowInsecure),
        }..removeWhere((k, v) => v == null || (v is Map && v.isEmpty));

      default:
        return null;
    }
  }

  static Map<String, dynamic>? _tlsMap(Profile p,
      {bool globalAllowInsecure = false}) {
    final tls = p.bean['tls'] == true;
    if (!tls) return null;
    final sni = p.bean['sni']?.toString() ?? '';
    final allowInsecure =
        p.bean['allowInsecure'] == true || globalAllowInsecure;
    final fp = p.bean['fp']?.toString() ?? '';

    final map = <String, dynamic>{
      'enabled': true,
      if (sni.isNotEmpty) 'server_name': sni,
      if (allowInsecure) 'insecure': true,
    };
    final alpn = p.bean['alpn']?.toString() ?? '';
    if (alpn.isNotEmpty) {
      map['alpn'] = alpn
          .split(RegExp(r'[,\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (fp.isNotEmpty) {
      map['utls'] = {'enabled': true, 'fingerprint': fp};
    }
    if (p.bean['reality'] == true) {
      map['reality'] = {
        'enabled': true,
        'public_key': p.bean['publicKey'] ?? '',
        'short_id': p.bean['shortId'] ?? '',
        if ((p.bean['spiderX']?.toString() ?? '').isNotEmpty)
          'spider_x': p.bean['spiderX'],
      };
    }
    // ECH(Encrypted ClientHello)
    if (p.bean['ech'] == true) {
      map['ech'] = {
        'enabled': true,
        if ((p.bean['echConfig']?.toString() ?? '').isNotEmpty)
          'config': p.bean['echConfig']
              .toString()
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
      };
    }
    // 证书指纹校验(Hysteria2 pinSHA256 等)
    final pin = p.bean['pinSHA256']?.toString() ?? '';
    if (pin.isNotEmpty) {
      map['pin_sha256'] = pin;
    }
    return map;
  }

  static Map<String, dynamic>? _transportMap(Profile p) {
    final b = p.bean;
    final network = b['network']?.toString() ?? 'tcp';
    switch (network) {
      case 'ws':
        {
          var path = b['wsPath']?.toString() ?? '';
          final host = b['wsHost']?.toString() ?? '';
          // ?ed= 早期数据(对齐原版)
          var maxEarlyData = 0;
          if (path.contains('?ed=')) {
            maxEarlyData =
                int.tryParse(path.split('?ed=')[1]) ?? 2048;
            path = path.split('?ed=')[0];
          }
          final ed =
              (b['wsMaxEarlyData'] as num?)?.toInt() ?? maxEarlyData;
          var headers = _customHeaders(b['headers']);
          if (host.isNotEmpty) {
            (headers ??= {})['Host'] = host;
          }
          return {
            'type': 'ws',
            'path': path.isNotEmpty ? path : '/',
            if (headers != null && headers.isNotEmpty) 'headers': headers,
            if (ed > 0) 'max_early_data': ed,
            if (ed > 0)
              'early_data_header_name':
                  b['earlyDataHeaderName']?.toString().isNotEmpty == true
                      ? b['earlyDataHeaderName']
                      : 'Sec-WebSocket-Protocol',
          };
        }
      case 'http':
        {
          final path = b['wsPath']?.toString() ?? '';
          final host = b['wsHost']?.toString() ?? '';
          final hosts = host
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          return {
            'type': 'http',
            'path': path.isNotEmpty ? path : '/',
            // 非 TLS 时 GET(v2ray tcp header 伪装,对齐原版)
            if (!_tlsEnabled(b)) 'method': 'GET',
            if (hosts.isNotEmpty) 'host': hosts,
          };
        }
      case 'quic':
        return {'type': 'quic'};
      case 'grpc':
        return {
          'type': 'grpc',
          'service_name': b['grpcServiceName']?.toString() ?? '',
        };
      case 'httpupgrade':
        return {
          'type': 'httpupgrade',
          'host': b['wsHost']?.toString() ?? '',
          'path': b['wsPath']?.toString().isNotEmpty == true
              ? b['wsPath']
              : '/',
        };
      default:
        // VMess headerType=http 的 tcp(http 伪装,对齐原版 V2RayFmt)
        if (b['headerType']?.toString() == 'http') {
          final path = b['wsPath']?.toString() ?? '';
          final host = b['wsHost']?.toString() ?? '';
          final hosts = host
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          return {
            'type': 'http',
            'path': path.isNotEmpty ? path : '/',
            if (!_tlsEnabled(b)) 'method': 'GET',
            if (hosts.isNotEmpty) 'host': hosts,
          };
        }
        return null; // tcp
    }
  }

  /// 是否启用 TLS(含 reality)
  static bool _tlsEnabled(Map<String, dynamic> b) {
    final sec = b['security']?.toString() ?? '';
    return b['tls'] == true || sec == 'tls' || sec == 'reality';
  }

  /// 自定义 headers(bean['headers'] 为 JSON 对象字符串)
  static Map<String, String>? _customHeaders(Object? raw) {
    if (raw == null) return null;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    try {
      final parsed = jsonDecode(text);
      if (parsed is Map) {
        return parsed.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return null;
  }

  static Map<String, dynamic>? _wireguardOutbound(
      Profile p, String server, int port, String tag) {
    final rawPeers = p.bean['peers'];
    final peers = <Map<String, dynamic>>[];
    if (rawPeers is List) {
      for (final raw in rawPeers) {
        if (raw is! Map) continue;
        final peer = raw.map((k, v) => MapEntry(k.toString(), v));
        peers.add({
          'server': (peer['server']?.toString() ?? server),
          'server_port':
              (peer['server_port'] as num?)?.toInt() ?? peer['serverPort'] ?? port,
          'public_key': peer['public_key']?.toString() ??
              peer['publicKey']?.toString() ??
              '',
          'pre_shared_key': peer['pre_shared_key']?.toString() ??
              peer['preSharedKey']?.toString() ??
              '',
          'allowed_ips': peer['allowed_ips']?.toString() ??
              peer['allowedIps']?.toString() ??
              '0.0.0.0/0,::/0',
        });
      }
    }
    if (peers.isEmpty) return null;
    final localAddr = p.bean['localAddress']?.toString() ?? '10.0.0.1/32';
    final localAddresses = localAddr
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    // reserved(AmneziaWG,逗号分隔 3 字节)
    List<int>? reserved;
    final rawReserved = p.bean['reserved']?.toString() ?? '';
    if (rawReserved.isNotEmpty) {
      reserved = rawReserved
          .split(',')
          .map((e) => int.tryParse(e.trim()))
          .whereType<int>()
          .toList();
    }
    return {
      'type': 'wireguard',
      'tag': tag,
      'server': server,
      'server_port': port,
      'local_address': localAddresses,
      'private_key': p.bean['privateKey'] ?? '',
      'mtu': p.bean['mtu'] ?? 1420,
      if (reserved != null && reserved.isNotEmpty) 'reserved': reserved,
      'peers': peers,
    };
  }

  /// 节点级 mux(VMess/Trojan,对齐原版 singMux)。
  static Map<String, dynamic>? _muxMap(Profile p) {
    // sing-box multiplex 支持的 TCP 出站(vmess/vless/trojan/anytls)
    switch (p.type) {
      case ProfileType.vmess:
      case ProfileType.vless:
      case ProfileType.trojan:
      case ProfileType.trojanGo:
      case ProfileType.anytls:
        break;
      default:
        return null;
    }
    final b = p.bean;
    if (b['enableMux'] != true) return null;
    var protocol = (b['muxType'] as String?) ?? 'h2mux';
    // 兼容数字存储(1=smux 2=yamux 其他=h2mux)
    final numType = b['muxType'];
    if (numType is num) {
      protocol = switch (numType.toInt()) {
        1 => 'smux',
        2 => 'yamux',
        _ => 'h2mux',
      };
    }
    return {
      'enabled': true,
      'protocol': protocol,
      'max_streams': (b['muxConcurrency'] as num?)?.toInt() ?? 8,
      'padding': b['muxPadding'] == true,
    };
  }

  static dynamic _positiveOrNull(dynamic v) {
    if (v == null) return null;
    final n = v is num ? v.toInt() : int.tryParse(v.toString());
    if (n == null || n <= 0) return null;
    return n;
  }
}

/// Profile 的 sing-box tag(节点在配置中的唯一标识)。
extension ProfileTag on Profile {
  String get tag => 'profile_$id';
}
