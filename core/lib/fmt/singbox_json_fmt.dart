import 'dart:convert';

import '../models/profile.dart';
import '../models/profile_type.dart';

/// sing-box outbound JSON 订阅解析。
/// 支持格式:
/// - 根为数组:[{type:..., tag:..., ...}]
/// - 根为对象:{"outbounds": [...]}
class SingBoxJsonFmt {
  SingBoxJsonFmt._();

  static List<Profile> parse(String text) {
    final dynamic doc;
    try {
      doc = jsonDecode(text);
    } catch (_) {
      throw FormatException('无法解析 sing-box JSON');
    }

    final List<dynamic> outbounds;
    if (doc is List) {
      outbounds = doc;
    } else if (doc is Map<String, dynamic>) {
      final ob = doc['outbounds'];
      if (ob is List) {
        outbounds = ob;
      } else {
        throw FormatException('sing-box JSON 中没有 outbounds');
      }
    } else {
      throw FormatException('无法解析 sing-box JSON');
    }

    final result = <Profile>[];
    for (final raw in outbounds) {
      if (raw is! Map) continue;
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      final p = _convert(map);
      if (p != null) result.add(p);
    }
    return result;
  }

  static Profile? _convert(Map<String, dynamic> outbound) {
    final type = outbound['type']?.toString();
    if (type == null) return null;
    if (type == 'direct' || type == 'block' || type == 'selector' ||
        type == 'urltest' || type == 'dns') {
      return null;
    }
    final tag = (outbound['tag'] ?? outbound['name'] ?? '').toString();
    final server = (outbound['server'] ?? '').toString();
    final port = _toInt(outbound['server_port']) ?? _toInt(outbound['port']) ?? 0;
    if (server.isEmpty) return null;

    final bean = Map<String, dynamic>.from(outbound)
      ..remove('type')
      ..remove('tag');

    // 归一化:tls 子对象 → 顶层字段
    final tls = outbound['tls'];
    if (tls is Map) {
      bean['tls'] = true;
      bean['sni'] = tls['server_name'] ?? bean['sni'] ?? '';
      bean['allowInsecure'] = tls['insecure'] ?? false;
      bean['fp'] = tls['utls']?.toString().replaceAll('utls:', '') ?? '';
      final reality = tls['reality'];
      if (reality is Map) {
        bean['reality'] = true;
        bean['publicKey'] = reality['public_key'] ?? '';
        bean['shortId'] = reality['short_id'] ?? '';
      }
    }
    // transport 子对象
    final transport = outbound['transport'];
    if (transport is Map) {
      final tType = transport['type']?.toString() ?? 'tcp';
      bean['network'] = tType;
      if (tType == 'ws') {
        bean['wsPath'] = transport['path'] ?? '';
        final headers = transport['headers'];
        if (headers is Map) {
          bean['wsHost'] = headers['Host'] ?? '';
        }
      } else if (tType == 'grpc') {
        bean['grpcServiceName'] = transport['service_name'] ?? '';
      }
    }
    // password 归一化(ss/trojan/hysteria2/anytls/shadowtls 共用)
    if (bean['password'] == null && outbound['password'] != null) {
      bean['password'] = outbound['password'];
    }

    return Profile(
      type: type,
      name: tag,
      serverAddress: server,
      serverPort: port,
      bean: bean,
    );
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}
