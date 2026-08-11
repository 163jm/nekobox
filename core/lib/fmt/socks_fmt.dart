import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/uri_util.dart';

/// SOCKS 代理链接解析与生成。
/// socks://user:pass@host:port#name(兼容 socks4/socks5)
class SocksFmt {
  SocksFmt._();

  static const String type = ProfileType.socks;

  static Profile parse(String raw) {
    final uri = Uri.parse(raw);
    final userInfo = uri.userInfo;
    final uiParts = UriUtil.parseUserInfo(userInfo);
    final username = uiParts.isNotEmpty ? uiParts[0] : '';
    final password = uiParts.length > 1 ? uiParts[1] : '';
    final host = uri.host;
    final port = uri.port != 0 ? uri.port : 1080;
    if (host.isEmpty) {
      throw FormatException('无法解析 SOCKS 代理链接: $raw');
    }
    return Profile(
      type: type,
      name: uri.fragment,
      serverAddress: host,
      serverPort: port,
      bean: {
        'username': username,
        'password': password,
        'udpOverTcp': UriUtil.strParam(uri, 'udp-over-tcp', '') == 'true',
      },
    );
  }
}

/// 导出
class SocksFmtExport {
  SocksFmtExport._();

  static String export(Profile p) {
    final username = p.bean['username'] ?? '';
    final password = p.bean['password'] ?? '';
    final userInfo = username.isNotEmpty
        ? '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}@'
        : '';
    final name = p.name.isNotEmpty ? '#${Uri.encodeComponent(p.name)}' : '';
    return 'socks5://$userInfo${p.serverAddress}:${p.serverPort}$name';
  }
}
