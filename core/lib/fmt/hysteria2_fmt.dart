import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/uri_util.dart';

/// Hysteria 2 链接解析与生成。
/// hysteria2://password@host:port?sni=...&insecure=1#name
class Hysteria2Fmt {
  Hysteria2Fmt._();

  static const String type = ProfileType.hysteria2;

  static Profile parse(String raw) {
    final uri = Uri.parse(raw);
    final password = Uri.decodeComponent(uri.userInfo);
    final host = uri.host;
    final port = uri.port != 0 ? uri.port : 443;
    if (host.isEmpty) {
      throw FormatException('无法解析 Hysteria2 链接: $raw');
    }
    final mport = UriUtil.strParam(uri, 'mport', '');
    // 端口跳跃:host:1000-2000 或 mport 参数
    String? serverPorts;
    if (mport.isNotEmpty) {
      serverPorts = mport;
    } else if (port == 0) {
      final hostPort = raw.split('@').last;
      final seg = hostPort.split('?').first;
      if (seg.contains(':')) {
        final range = seg.split(':').last;
        if (range.contains('-') || range.contains(',')) {
          serverPorts = range;
        }
      }
    }
    final effectivePort =
        (serverPorts != null && !serverPorts.contains('-') && !serverPorts.contains(','))
            ? (int.tryParse(serverPorts) ?? port)
            : port;
    return Profile(
      type: type,
      name: uri.fragment,
      serverAddress: host,
      serverPort: effectivePort,
      bean: {
        'password': password,
        'sni': UriUtil.strParam(uri, 'sni', ''),
        'allowInsecure': UriUtil.strParam(uri, 'insecure', '') == '1' ||
            UriUtil.strParam(uri, 'allowInsecure', '') == '1',
        'upMbps': UriUtil.intParam(uri, 'upmbps', 0),
        'downMbps': UriUtil.intParam(uri, 'downmbps', 0),
        // 混淆(salamander)
        'obfs': UriUtil.strParam(uri, 'obfs-password', ''),
        // 证书指纹校验
        'pinSHA256': UriUtil.strParam(uri, 'pinSHA256', ''),
        if (serverPorts != null) 'serverPorts': serverPorts,
      },
    );
  }
}

/// 导出
class Hysteria2FmtExport {
  Hysteria2FmtExport._();

  static String export(Profile p) {
    final password = p.bean['password'] ?? '';
    final params = <String, String>{};
    final sni = p.bean['sni']?.toString() ?? '';
    if (sni.isNotEmpty) params['sni'] = sni;
    if (p.bean['allowInsecure'] == true) params['insecure'] = '1';
    final obfs = p.bean['obfs']?.toString() ?? '';
    if (obfs.isNotEmpty) params['obfs-password'] = obfs;
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final name = p.name.isNotEmpty ? '#${Uri.encodeComponent(p.name)}' : '';
    final userInfo = password.isNotEmpty
        ? '${Uri.encodeComponent(password)}@'
        : '';
    return 'hysteria2://$userInfo${p.serverAddress}:${p.serverPort}?$query$name';
  }
}
