import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/uri_util.dart';

/// SSH 链接解析与生成。
/// ssh://user@host:port?private_key=...#name
class SSHfmt {
  SSHfmt._();

  static const String type = ProfileType.ssh;

  static Profile parse(String raw) {
    final uri = Uri.parse(raw);
    final username = Uri.decodeComponent(uri.userInfo);
    final host = uri.host;
    final port = uri.port != 0 ? uri.port : 22;
    if (username.isEmpty || host.isEmpty) {
      throw FormatException('无法解析 SSH 链接: $raw');
    }
    return Profile(
      type: type,
      name: uri.fragment,
      serverAddress: host,
      serverPort: port,
      bean: {
        'username': username,
        'password': UriUtil.strParam(uri, 'password', ''),
        'privateKey': UriUtil.strParam(uri, 'private_key', ''),
        'hostKeyAlgorithms': UriUtil.strParam(
            uri, 'host_key_algorithms', ''),
        'clientVersion': UriUtil.strParam(uri, 'client_version', ''),
      },
    );
  }
}

/// 导出
class SSHfmtExport {
  SSHfmtExport._();

  static String export(Profile p) {
    final username = p.bean['username'] ?? '';
    final params = <String, String>{};
    final password = p.bean['password']?.toString() ?? '';
    if (password.isNotEmpty) params['password'] = password;
    final privateKey = p.bean['privateKey']?.toString() ?? '';
    if (privateKey.isNotEmpty) params['private_key'] = privateKey;
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final name = p.name.isNotEmpty ? '#${Uri.encodeComponent(p.name)}' : '';
    return 'ssh://${Uri.encodeComponent(username)}@'
        '${p.serverAddress}:${p.serverPort}?$query$name';
  }
}
