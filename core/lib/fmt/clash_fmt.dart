import 'package:yaml/yaml.dart';

import '../models/profile.dart';
import '../models/profile_type.dart';

/// ClashMeta / Clash YAML 订阅解析:提取 `proxies` 列表转为 Profile。
class ClashFmt {
  ClashFmt._();

  static List<Profile> parse(String yamlText) {
    final dynamic doc;
    try {
      doc = loadYaml(yamlText);
    } catch (_) {
      throw FormatException('无法解析 Clash YAML');
    }
    if (doc is! YamlMap) {
      throw FormatException('无法解析 Clash YAML: 根节点不是映射');
    }
    final rawProxies = doc['proxies'];
    if (rawProxies is! YamlList) {
      throw FormatException('Clash YAML 中没有 proxies 字段');
    }

    final result = <Profile>[];
    for (final raw in rawProxies) {
      if (raw is! YamlMap) continue;
      final p = _convertProxy(raw);
      if (p != null) result.add(p);
    }
    return result;
  }

  static Profile? _convertProxy(YamlMap proxy) {
    final type = proxy['type']?.toString();
    final name = proxy['name']?.toString() ?? '';
    final server = proxy['server']?.toString() ?? '';
    final port = _toInt(proxy['port']) ?? 0;
    if (server.isEmpty || port == 0) return null;

    switch (type) {
      case 'ss':
        return _ss(proxy, name, server, port);
      case 'vmess':
        return _vmess(proxy, name, server, port);
      case 'vless':
        return _vless(proxy, name, server, port);
      case 'trojan':
        return _trojan(proxy, name, server, port);
      case 'hysteria2':
      case 'hy2':
        return _hysteria2(proxy, name, server, port);
      case 'tuic':
        return _tuic(proxy, name, server, port);
      case 'wireguard':
      case 'wg':
        return _wireguard(proxy, name, server, port);
      case 'http':
        return _http(proxy, name, server, port);
      case 'socks5':
        return _socks(proxy, name, server, port);
      case 'shadowtls':
        return _shadowtls(proxy, name, server, port);
      default:
        return null;
    }
  }

  static Profile _ss(YamlMap p, String name, String server, int port) {
    return Profile(
      type: ProfileType.shadowsocks,
      name: name,
      serverAddress: server,
      serverPort: port,
      bean: {
        'method': p['cipher']?.toString() ?? 'aes-128-gcm',
        'password': p['password']?.toString() ?? '',
      },
    );
  }

  static Profile _vmess(YamlMap p, String name, String server, int port) {
    final tls = p['tls'] == true;
    final network = p['network']?.toString() ?? 'tcp';
    final wsOpts = p['ws-opts'];
    Map<String, dynamic> ws = {};
    if (wsOpts is YamlMap) {
      ws = {
        'path': wsOpts['path']?.toString() ?? '',
        'headers': wsOpts['headers'],
      };
    }
    return Profile(
      type: ProfileType.vmess,
      name: name,
      serverAddress: server,
      serverPort: port,
      bean: {
        'uuid': p['uuid']?.toString() ?? '',
        'alterId': _toInt(p['alterId']) ?? 0,
        'security': p['cipher']?.toString() ?? 'auto',
        'network': network,
        'tls': tls,
        'sni': p['servername']?.toString() ?? '',
        'wsPath': ws['path'] ?? '',
        'wsHost': _headerHost(ws['headers']),
        'allowInsecure': p['skip-cert-verify'] == true,
      },
    );
  }

  static Profile _vless(YamlMap p, String name, String server, int port) {
    final security = p['tls'] == true ? 'tls' : '';
    final reality = p['reality-opts'];
    return Profile(
      type: ProfileType.vless,
      name: name,
      serverAddress: server,
      serverPort: port,
      bean: {
        'uuid': p['uuid']?.toString() ?? '',
        'flow': p['flow']?.toString() ?? '',
        'tls': security == 'tls',
        'reality': reality != null,
        'sni': p['servername']?.toString() ?? '',
        'publicKey': reality is YamlMap
            ? (reality['public-key']?.toString() ?? '')
            : '',
        'shortId': reality is YamlMap ? (reality['short-id']?.toString() ?? '') : '',
        'network': p['network']?.toString() ?? 'tcp',
        'wsPath': _nested(p, 'ws-opts', 'path', ''),
        'wsHost': _headerHost(_nestedRaw(p, 'ws-opts', 'headers')),
        'allowInsecure': p['skip-cert-verify'] == true,
      },
    );
  }

  static Profile _trojan(YamlMap p, String name, String server, int port) {
    return Profile(
      type: ProfileType.trojan,
      name: name,
      serverAddress: server,
      serverPort: port,
      bean: {
        'password': p['password']?.toString() ?? '',
        'tls': true,
        'sni': p['servername']?.toString() ?? '',
        'network': p['network']?.toString() ?? 'tcp',
        'wsPath': _nested(p, 'ws-opts', 'path', ''),
        'wsHost': _headerHost(_nestedRaw(p, 'ws-opts', 'headers')),
        'allowInsecure': p['skip-cert-verify'] == true,
      },
    );
  }

  static Profile _hysteria2(YamlMap p, String name, String server, int port) {
    return Profile(
      type: ProfileType.hysteria2,
      name: name,
      serverAddress: server,
      serverPort: port,
      bean: {
        'password': p['password']?.toString() ?? '',
        'sni': p['sni']?.toString() ?? p['servername']?.toString() ?? '',
        'allowInsecure': p['skip-cert-verify'] == true,
        'upMbps': _toInt(p['up']) ?? 0,
        'downMbps': _toInt(p['down']) ?? 0,
      },
    );
  }

  static Profile _tuic(YamlMap p, String name, String server, int port) {
    return Profile(
      type: ProfileType.tuic,
      name: name,
      serverAddress: server,
      serverPort: port,
      bean: {
        'uuid': p['uuid']?.toString() ?? '',
        'password': p['password']?.toString() ?? '',
        'congestionControl': p['congestion-controller']?.toString() ?? 'cubic',
        'udpRelayMode': p['udp-relay-mode']?.toString() ?? 'native',
        'zeroRttHandshake': p['zero-rtt-handshake'] == true,
        'sni': p['sni']?.toString() ?? p['servername']?.toString() ?? '',
        'allowInsecure': p['skip-cert-verify'] == true,
      },
    );
  }

  static Profile _wireguard(YamlMap p, String name, String server, int port) {
    final rawPeers = p['peers'];
    final peers = <Map<String, dynamic>>[];
    if (rawPeers is YamlList) {
      for (final peer in rawPeers) {
        if (peer is! YamlMap) continue;
        peers.add({
          'server': peer['server']?.toString() ?? server,
          'server_port': _toInt(peer['port']) ?? port,
          'public_key': peer['public-key']?.toString() ?? '',
          'pre_shared_key': peer['pre-shared-key']?.toString() ?? '',
          'allowed_ips': (peer['allowed-ips'] is YamlList)
              ? (peer['allowed-ips'] as YamlList).join(',')
              : '0.0.0.0/0,::/0',
        });
      }
    }
    if (peers.isEmpty) {
      peers.add({
        'server': server,
        'server_port': port,
        'public_key': p['public-key']?.toString() ?? '',
        'pre_shared_key': p['pre-shared-key']?.toString() ?? '',
        'allowed_ips': '0.0.0.0/0,::/0',
      });
    }
    return Profile(
      type: ProfileType.wireguard,
      name: name,
      serverAddress: server,
      serverPort: port,
      bean: {
        'privateKey': p['private-key']?.toString() ?? '',
        'peers': peers,
        'mtu': _toInt(p['mtu']) ?? 1420,
      },
    );
  }

  static Profile _http(YamlMap p, String name, String server, int port) {
    return Profile(
      type: ProfileType.http,
      name: name,
      serverAddress: server,
      serverPort: port,
      bean: {
        'username': p['username']?.toString() ?? '',
        'password': p['password']?.toString() ?? '',
        'tls': p['tls'] == true,
        'sni': p['sni']?.toString() ?? p['servername']?.toString() ?? '',
        'allowInsecure': p['skip-cert-verify'] == true,
      },
    );
  }

  static Profile _socks(YamlMap p, String name, String server, int port) {
    return Profile(
      type: ProfileType.socks,
      name: name,
      serverAddress: server,
      serverPort: port,
      bean: {
        'username': p['username']?.toString() ?? '',
        'password': p['password']?.toString() ?? '',
      },
    );
  }

  static Profile _shadowtls(YamlMap p, String name, String server, int port) {
    return Profile(
      type: ProfileType.shadowtls,
      name: name,
      serverAddress: server,
      serverPort: port,
      bean: {
        'password': p['password']?.toString() ?? '',
        'version': _toInt(p['version']) ?? 3,
        'sni': p['sni']?.toString() ?? p['servername']?.toString() ?? '',
      },
    );
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static String _nested(YamlMap p, String section, String key, String def) {
    final raw = p[section];
    if (raw is YamlMap) {
      return raw[key]?.toString() ?? def;
    }
    return def;
  }

  static dynamic _nestedRaw(YamlMap p, String section, String key) {
    final raw = p[section];
    if (raw is YamlMap) return raw[key];
    return null;
  }

  static String _headerHost(dynamic headers) {
    if (headers is YamlMap) {
      return headers['Host']?.toString() ?? '';
    }
    return '';
  }
}
