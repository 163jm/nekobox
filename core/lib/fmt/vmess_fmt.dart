import 'dart:convert';

import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/base64_util.dart';
import '../utils/uri_util.dart';

/// VMess 链接解析。
/// 支持两种格式:
/// - vmess://base64(json)
/// - vmess://uuid@host:port?scy=auto&type=tcp#name(标准 v2rayN 格式)
class VMessFmt {
  VMessFmt._();

  static const String type = ProfileType.vmess;

  /// tcp + headerType=http → http 传输(http 伪装,对齐原版 V2RayFmt)
  static String _resolveNetwork(String net, String headerType) {
    if (headerType == 'http' && (net.isEmpty || net == 'tcp')) {
      return 'http';
    }
    return net;
  }

  static Profile parse(String raw) {
    final withoutScheme = raw.substring('vmess://'.length);
    final qIdx = withoutScheme.indexOf('?');
    final hashIdx = withoutScheme.indexOf('#');

    // 标准 URI 格式:vmess://uuid@host:port?...
    final atIdx = withoutScheme.indexOf('@');
    if (atIdx > 0 && qIdx > atIdx) {
      return _parseStandard(withoutScheme, atIdx, qIdx, hashIdx);
    }

    // base64(json) 格式
    final body = hashIdx >= 0
        ? withoutScheme.substring(0, hashIdx)
        : withoutScheme.substring(0, qIdx >= 0 ? qIdx : withoutScheme.length);
    final name = hashIdx >= 0
        ? Uri.decodeComponent(withoutScheme.substring(hashIdx + 1))
        : '';
    final jsonStr = Base64Util.decodeToString(body);
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return _fromJsonMap(data, name);
    } catch (_) {
      throw FormatException('无法解析 VMess 链接: $raw');
    }
  }

  static Profile _parseStandard(
      String s, int atIdx, int qIdx, int hashIdx) {
    final uuid = s.substring(0, atIdx);
    final authority = s.substring(atIdx + 1, qIdx);
    final queryPart = s.substring(qIdx + 1,
        hashIdx >= 0 ? hashIdx : s.length);
    final name = hashIdx >= 0
        ? Uri.decodeComponent(s.substring(hashIdx + 1))
        : '';
    final uri = Uri.parse('vmess://$authority?$queryPart');
    final (host, port) = UriUtil.parseHostPort(
        uri.authority.isNotEmpty ? uri.authority : authority, 443);

    return Profile(
      type: type,
      name: name,
      serverAddress: host,
      serverPort: port,
      bean: {
        'uuid': uuid,
        'security': UriUtil.strParam(uri, 'scy', 'auto'),
        'network': _resolveNetwork(
            UriUtil.strParam(uri, 'type', 'tcp'),
            UriUtil.strParam(uri, 'headerType', '')),
        'tls': UriUtil.strParam(uri, 'security', '') == 'tls',
        'sni': UriUtil.strParam(uri, 'sni', ''),
        'fp': UriUtil.strParam(uri, 'fp', ''),
        'alterId': UriUtil.intParam(uri, 'aid', 0),
        'wsPath': UriUtil.strParam(uri, 'path', ''),
        'wsHost': UriUtil.strParam(uri, 'host', ''),
        'alpn': UriUtil.strParam(uri, 'alpn', ''),
        'headers': UriUtil.strParam(uri, 'header', ''),
        'wsMaxEarlyData': UriUtil.intParam(uri, 'ed', 0),
        'grpcServiceName': UriUtil.strParam(uri, 'serviceName', ''),
        'allowInsecure': UriUtil.strParam(uri, 'allowInsecure', '') == '1',
      },
    );
  }

  static Profile _fromJsonMap(Map<String, dynamic> data, String name) {
    final host = (data['add'] ?? data['server'] ?? '').toString();
    final port = int.tryParse((data['port'] ?? 0).toString()) ?? 0;
    final network = _resolveNetwork(
        (data['net'] ?? 'tcp').toString(),
        (data['headerType'] ?? '').toString());
    final tls = (data['tls'] ?? '').toString() == 'tls';

    return Profile(
      type: type,
      name: name.isNotEmpty ? name : (data['ps'] ?? '').toString(),
      serverAddress: host,
      serverPort: port,
      bean: {
        'uuid': (data['id'] ?? '').toString(),
        'alterId': int.tryParse((data['aid'] ?? 0).toString()) ?? 0,
        'security': (data['scy'] ?? 'auto').toString(),
        'network': network,
        'tls': tls,
        'sni': (data['sni'] ?? '').toString(),
        'fp': (data['fp'] ?? '').toString(),
        'wsPath': (data['path'] ?? '').toString(),
        'wsHost': (data['host'] ?? '').toString(),
        'allowInsecure': (data['allowInsecure'] ?? false),
      },
    );
  }
}

/// 导出(vmess://base64(json) 格式)
class VMessFmtExport {
  VMessFmtExport._();

  static String export(Profile p) {
    final map = <String, dynamic>{
      'v': '2',
      'ps': p.name,
      'add': p.serverAddress,
      'port': p.serverPort,
      'id': p.bean['uuid'] ?? '',
      'aid': p.bean['alterId'] ?? 0,
      'scy': p.bean['security'] ?? 'auto',
      'net': p.bean['network'] ?? 'tcp',
      'type': 'none',
      'host': p.bean['wsHost'] ?? '',
      'path': p.bean['wsPath'] ?? '',
      'tls': (p.bean['tls'] == true) ? 'tls' : '',
      'sni': p.bean['sni'] ?? '',
    };
    return 'vmess://${Base64Util.encodeUrlSafe(jsonEncode(map))}';
  }
}
