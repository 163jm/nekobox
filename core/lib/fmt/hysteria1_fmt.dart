import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/uri_util.dart';

/// Hysteria v1 链接解析(对齐原版 HysteriaFmt)。
/// hysteria://host:port?auth=xxx&peer=sni&insecure=1|0&upmbps=100&downmbps=100&alpn=hysteria&obfsParam=xxx#name
class Hysteria1Fmt {
  Hysteria1Fmt._();

  static const String type = ProfileType.hysteria;

  static Profile parse(String raw) {
    // 复用 Uri 解析(hy:// 当作 https 处理 query 部分)
    final uri = Uri.parse(raw.replaceFirst('hysteria://', 'https://'));
    final host = uri.host;
    final port = uri.port != 0 ? uri.port : 443;
    if (host.isEmpty) {
      throw FormatException('无法解析 Hysteria 链接: $raw');
    }
    final auth = UriUtil.strParam(uri, 'auth', '');
    final insecure = UriUtil.strParam(uri, 'insecure', '');
    return Profile(
      type: type,
      name: uri.fragment,
      serverAddress: host,
      serverPort: port,
      bean: {
        'authPayload': auth,
        'sni': UriUtil.strParam(uri, 'peer', ''),
        'allowInsecure': insecure == '1' || insecure == 'true',
        'upMbps': int.tryParse(UriUtil.strParam(uri, 'upmbps', '')) ?? 0,
        'downMbps': int.tryParse(UriUtil.strParam(uri, 'downmbps', '')) ?? 0,
        'alpn': UriUtil.strParam(uri, 'alpn', ''),
        'obfuscation': UriUtil.strParam(uri, 'obfsParam', ''),
        'tls': true,
      },
    );
  }
}

/// 导出 hy:// 链接
class Hysteria1FmtExport {
  Hysteria1FmtExport._();

  static String export(Profile p) {
    final params = <String, String>{};
    final auth = p.bean['authPayload']?.toString() ?? '';
    if (auth.isNotEmpty) params['auth'] = auth;
    final sni = p.bean['sni']?.toString() ?? '';
    if (sni.isNotEmpty) params['peer'] = sni;
    if (p.bean['allowInsecure'] == true) params['insecure'] = '1';
    final up = (p.bean['upMbps'] as num?)?.toInt() ?? 0;
    final down = (p.bean['downMbps'] as num?)?.toInt() ?? 0;
    if (up > 0) params['upmbps'] = '$up';
    if (down > 0) params['downmbps'] = '$down';
    final alpn = p.bean['alpn']?.toString() ?? '';
    if (alpn.isNotEmpty) params['alpn'] = alpn;
    final obfs = p.bean['obfuscation']?.toString() ?? '';
    if (obfs.isNotEmpty) params['obfsParam'] = obfs;

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final name = p.name.isNotEmpty ? '#${Uri.encodeComponent(p.name)}' : '';
    return 'hysteria://${p.serverAddress}:${p.serverPort}?$query$name';
  }
}
