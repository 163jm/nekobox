import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/uri_util.dart';

/// Trojan-Go 链接解析(对齐原版 TrojanGoBean)。
/// trojan-go://password@host:port?type=ws&host=xxx&path=xxx&sni=xxx&encryption=xxx#name
/// 与标准 Trojan 同构,sing-box trojan outbound 直接兼容。
class TrojanGoFmt {
  TrojanGoFmt._();

  static const String type = ProfileType.trojanGo;

  static Profile parse(String raw) {
    final uri = Uri.parse(raw);
    final password = Uri.decodeComponent(uri.userInfo);
    final host = uri.host;
    final port = uri.port != 0 ? uri.port : 443;
    if (password.isEmpty || host.isEmpty) {
      throw FormatException('无法解析 Trojan-Go 链接: $raw');
    }
    return Profile(
      type: type,
      name: uri.fragment,
      serverAddress: host,
      serverPort: port,
      bean: {
        'password': password,
        'tls': true,
        'sni': UriUtil.strParam(uri, 'sni', ''),
        'fp': UriUtil.strParam(uri, 'fp', ''),
        'allowInsecure': UriUtil.strParam(uri, 'allowInsecure', '') == '1',
        'network': UriUtil.strParam(uri, 'type', 'tcp'),
        'wsPath': UriUtil.strParam(uri, 'path', ''),
        'wsHost': UriUtil.strParam(uri, 'host', ''),
        'grpcServiceName': UriUtil.strParam(uri, 'serviceName', ''),
      },
    );
  }
}

/// 导出 trojan-go:// 链接
class TrojanGoFmtExport {
  TrojanGoFmtExport._();

  static String export(Profile p) {
    final params = <String, String>{};
    final network = p.bean['network']?.toString() ?? 'tcp';
    if (network != 'tcp') params['type'] = network;
    final wsPath = p.bean['wsPath']?.toString() ?? '';
    if (wsPath.isNotEmpty) params['path'] = wsPath;
    final wsHost = p.bean['wsHost']?.toString() ?? '';
    if (wsHost.isNotEmpty) params['host'] = wsHost;
    final sni = p.bean['sni']?.toString() ?? '';
    if (sni.isNotEmpty) params['sni'] = sni;
    final query = params.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final name = p.name.isNotEmpty ? '#${Uri.encodeComponent(p.name)}' : '';
    return 'trojan-go://${Uri.encodeComponent(p.bean['password']?.toString() ?? '')}@'
        '${p.serverAddress}:${p.serverPort}?$query$name';
  }
}
