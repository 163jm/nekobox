import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/uri_util.dart';

/// Trojan 链接解析与生成。
/// trojan://password@host:port?sni=...#name
class TrojanFmt {
  TrojanFmt._();

  static const String type = ProfileType.trojan;

  static Profile parse(String raw) {
    final uri = Uri.parse(raw);
    final password = Uri.decodeComponent(uri.userInfo);
    final host = uri.host;
    final port = uri.port != 0 ? uri.port : 443;
    if (password.isEmpty || host.isEmpty) {
      throw FormatException('无法解析 Trojan 链接: $raw');
    }
    final security = UriUtil.strParam(uri, 'security', '');
    return Profile(
      type: type,
      name: uri.fragment,
      serverAddress: host,
      serverPort: port,
      bean: {
        'password': password,
        'tls': true,
        'reality': security == 'reality',
        'sni': UriUtil.strParam(uri, 'sni', ''),
        'fp': UriUtil.strParam(uri, 'fp', ''),
        'publicKey': UriUtil.strParam(uri, 'pbk', ''),
        'shortId': UriUtil.strParam(uri, 'sid', ''),
        'network': UriUtil.strParam(uri, 'type', 'tcp'),
        'wsPath': UriUtil.strParam(uri, 'path', ''),
        'wsHost': UriUtil.strParam(uri, 'host', ''),
        'grpcServiceName': UriUtil.strParam(uri, 'serviceName', ''),
        'allowInsecure': UriUtil.strParam(uri, 'allowInsecure', '') == '1',
      },
    );
  }
}

/// 导出
class TrojanFmtExport {
  TrojanFmtExport._();

  static String export(Profile p) {
    final password = p.bean['password'] ?? '';
    final params = <String, String>{};
    final sni = p.bean['sni']?.toString() ?? '';
    if (sni.isNotEmpty) params['sni'] = sni;
    final network = p.bean['network']?.toString() ?? 'tcp';
    if (network != 'tcp') params['type'] = network;
    final wsPath = p.bean['wsPath']?.toString() ?? '';
    if (wsPath.isNotEmpty) params['path'] = wsPath;
    final wsHost = p.bean['wsHost']?.toString() ?? '';
    if (wsHost.isNotEmpty) params['host'] = wsHost;
    final pbk = p.bean['publicKey']?.toString() ?? '';
    if (pbk.isNotEmpty) params['pbk'] = pbk;

    final query = params.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final name = p.name.isNotEmpty ? '#${Uri.encodeComponent(p.name)}' : '';
    return 'trojan://${Uri.encodeComponent(password)}@'
        '${p.serverAddress}:${p.serverPort}?$query$name';
  }
}
