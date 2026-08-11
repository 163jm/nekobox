import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/uri_util.dart';

/// NaïveProxy 链接解析(对齐原版 NaiveBean)。
/// naive+https://user:pass@host:port?sni=xxx&fp=xxx#name
/// 生成 sing-box 'naive' outbound。
class NaiveFmt {
  NaiveFmt._();

  static const String type = ProfileType.naive;

  static Profile parse(String raw) {
    final uri = Uri.parse(raw.replaceFirst('naive+https://', 'https://'));
    final userInfo = uri.userInfo;
    final username = Uri.decodeComponent(
        userInfo.contains(':') ? userInfo.split(':').first : userInfo);
    final password = Uri.decodeComponent(
        userInfo.contains(':') ? userInfo.split(':').skip(1).join(':') : '');
    final host = uri.host;
    final port = uri.port != 0 ? uri.port : 443;
    if (host.isEmpty) {
      throw FormatException('无法解析 Naive 链接: $raw');
    }
    return Profile(
      type: type,
      name: uri.fragment,
      serverAddress: host,
      serverPort: port,
      bean: {
        'username': username,
        'password': password,
        'sni': UriUtil.strParam(uri, 'sni', ''),
        'fp': UriUtil.strParam(uri, 'fp', ''),
        'allowInsecure': UriUtil.strParam(uri, 'allowInsecure', '') == '1',
        'tls': true,
      },
    );
  }
}

/// 导出 naive+https:// 链接
class NaiveFmtExport {
  NaiveFmtExport._();

  static String export(Profile p) {
    final params = <String, String>{};
    final sni = p.bean['sni']?.toString() ?? '';
    if (sni.isNotEmpty) params['sni'] = sni;
    final fp = p.bean['fp']?.toString() ?? '';
    if (fp.isNotEmpty) params['fp'] = fp;
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final name = p.name.isNotEmpty ? '#${Uri.encodeComponent(p.name)}' : '';
    final user =
        '${Uri.encodeComponent(p.bean['username']?.toString() ?? '')}:'
        '${Uri.encodeComponent(p.bean['password']?.toString() ?? '')}';
    return 'naive+https://$user@${p.serverAddress}:${p.serverPort}'
        '${query.isEmpty ? '' : '?$query'}$name';
  }
}
