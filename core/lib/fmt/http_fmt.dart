import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/uri_util.dart';

/// HTTP 代理链接解析与生成。
/// http://user:pass@host:port#name
class HttpFmt {
  HttpFmt._();

  static const String type = ProfileType.http;

  static Profile parse(String raw) {
    final uri = Uri.parse(raw);
    final userInfo = uri.userInfo;
    final uiParts = UriUtil.parseUserInfo(userInfo);
    final username = uiParts.isNotEmpty ? uiParts[0] : '';
    final password = uiParts.length > 1 ? uiParts[1] : '';
    final host = uri.host;
    final port = uri.port != 0 ? uri.port : 80;
    if (host.isEmpty) {
      throw FormatException('无法解析 HTTP 代理链接: $raw');
    }
    return Profile(
      type: type,
      name: uri.fragment,
      serverAddress: host,
      serverPort: port,
      bean: {
        'username': username,
        'password': password,
        'tls': uri.scheme == 'https',
        'sni': UriUtil.strParam(uri, 'sni', ''),
        'allowInsecure': UriUtil.strParam(uri, 'allowInsecure', '') == '1',
      },
    );
  }
}

/// 导出
class HttpFmtExport {
  HttpFmtExport._();

  static String export(Profile p) {
    final username = p.bean['username'] ?? '';
    final password = p.bean['password'] ?? '';
    final tls = p.bean['tls'] == true;
    final scheme = tls ? 'https' : 'http';
    final userInfo = username.isNotEmpty ? '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}@' : '';
    final name = p.name.isNotEmpty ? '#${Uri.encodeComponent(p.name)}' : '';
    final params = <String, String>{};
    final sni = p.bean['sni']?.toString() ?? '';
    if (sni.isNotEmpty) params['sni'] = sni;
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$scheme://$userInfo${p.serverAddress}:${p.serverPort}?$query$name';
  }
}
