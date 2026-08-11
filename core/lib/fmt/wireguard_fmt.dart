import 'dart:convert';

import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/base64_util.dart';

/// WireGuard 链接解析。
/// 支持 wg://base64(json) 与 wireguard://base64(json) 两种 scheme。
class WireGuardFmt {
  WireGuardFmt._();

  static const String type = ProfileType.wireguard;

  static Profile parse(String raw) {
    final idx = raw.indexOf('://');
    if (idx < 0) {
      throw FormatException('无法解析 WireGuard 链接: $raw');
    }
    final body = raw.substring(idx + 3);
    final hashIdx = body.indexOf('#');
    final name = hashIdx >= 0
        ? Uri.decodeComponent(body.substring(hashIdx + 1))
        : '';
    final payload = hashIdx >= 0 ? body.substring(0, hashIdx) : body;

    // 标准 wireguard:// URI query 格式(业界通用):
    // wireguard://publickey@host:port?psk=...&allowed_ips=...&reserved=...&address=...#name
    if (!payload.contains('%') && payload.startsWith(RegExp(r'[A-Za-z0-9+/=_-]+@'))) {
      final at = payload.indexOf('@');
      final publicKey = payload.substring(0, at);
      var rest = payload.substring(at + 1);
      var peerHost = rest;
      var query = '';
      final qIdx = rest.indexOf('?');
      if (qIdx >= 0) {
        peerHost = rest.substring(0, qIdx);
        query = rest.substring(qIdx + 1);
      }
      final pIdx = peerHost.lastIndexOf(':');
      var serverAddress = peerHost;
      var serverPort = 443;
      if (pIdx >= 0) {
        serverAddress = peerHost.substring(0, pIdx);
        serverPort = int.tryParse(peerHost.substring(pIdx + 1)) ?? 443;
      }
      final qParams = Uri.splitQueryString(query);
      final address = qParams['address'] ?? qParams['local_address'] ?? '10.0.0.1/32';
      return Profile(
        type: type,
        name: name,
        serverAddress: serverAddress,
        serverPort: serverPort,
        bean: {
          'privateKey': '',
          'localAddress': address,
          'peers': [
            {
              'publicKey': publicKey,
              'preSharedKey': qParams['psk'] ?? '',
              'allowedIps': qParams['allowed_ips'] ?? '0.0.0.0/0,::/0',
              if (qParams.containsKey('reserved'))
                'reserved': qParams['reserved']!,
            },
          ],
        },
      );
    }

    final decoded = Base64Util.decodeToString(payload);
    // 兼容双重编码:payload 内仍是 wg:// 前缀
    var jsonStr = decoded;
    if (decoded.trimLeft().startsWith('wg://')) {
      jsonStr = Base64Util.decodeToString(decoded.substring(5));
    }

    final dynamic parsed;
    try {
      parsed = jsonDecode(jsonStr);
    } catch (_) {
      throw FormatException('无法解析 WireGuard 链接: $raw');
    }
    if (parsed is! Map<String, dynamic>) {
      throw FormatException('无法解析 WireGuard 链接: $raw');
    }
    final data = parsed;

    final peers = <Map<String, dynamic>>[];
    final rawPeers = data['peers'];
    if (rawPeers is List) {
      for (final p in rawPeers) {
        if (p is Map) {
          peers.add(p.map((k, v) => MapEntry(k.toString(), v)));
        }
      }
    } else if (data['peer_public_key'] != null) {
      peers.add({
        'server': data['server'] ?? '',
        'public_key': data['peer_public_key'],
        'pre_shared_key': data['preshared_key'] ?? '',
        'allowed_ips': data['allowed_ips'] ?? '0.0.0.0/0,::/0',
      });
    }

    final host = (data['server'] ?? data['address'] ?? '').toString();
    final port = _toInt(data['server_port']) ?? _toInt(data['port']) ?? 51820;

    return Profile(
      type: type,
      name: name,
      serverAddress: host,
      serverPort: port,
      bean: {
        'privateKey': (data['private_key'] ?? '').toString(),
        'peers': peers,
        'mtu': _toInt(data['mtu']) ?? 1420,
      },
    );
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}
