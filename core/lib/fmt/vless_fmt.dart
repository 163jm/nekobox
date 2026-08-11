import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/uri_util.dart';

/// VLESS 链接解析与生成。
/// vless://uuid@host:port?encryption=none&security=tls&sni=...#name
class VLESSFmt {
  VLESSFmt._();

  static const String type = ProfileType.vless;

  static Profile parse(String raw) {
    final uri = Uri.parse(raw);
    final userInfo = uri.userInfo.isNotEmpty
        ? uri.userInfo
        : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
    final uuid = Uri.decodeComponent(userInfo);
    final host = uri.host.isNotEmpty ? uri.host : (uri.pathSegments.length > 1
        ? uri.pathSegments[1]
        : '');
    final port = uri.port != 0 ? uri.port : 443;
    final name = uri.fragment.isNotEmpty ? uri.fragment : '';
    if (uuid.isEmpty || host.isEmpty) {
      throw FormatException('无法解析 VLESS 链接: $raw');
    }
    final security = UriUtil.strParam(uri, 'security', '');
    final tls = security == 'tls' || security == 'reality';
    return Profile(
      type: type,
      name: name,
      serverAddress: host,
      serverPort: port,
      bean: {
        'uuid': uuid,
        'flow': UriUtil.strParam(uri, 'flow', ''),
        'tls': tls,
        'reality': security == 'reality',
        'sni': UriUtil.strParam(uri, 'sni', ''),
        'fp': UriUtil.strParam(uri, 'fp', ''),
        'publicKey': UriUtil.strParam(uri, 'pbk', ''),
        'shortId': UriUtil.strParam(uri, 'sid', ''),
        'spiderX': UriUtil.strParam(uri, 'spx', ''),
        'network': UriUtil.strParam(uri, 'type', 'tcp'),
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
}

/// 导出
class VLESSFmtExport {
  VLESSFmtExport._();

  static String export(Profile p) {
    final uuid = p.bean['uuid'] ?? '';
    final params = <String, String>{
      'encryption': 'none',
      'security': (p.bean['reality'] == true)
          ? 'reality'
          : ((p.bean['tls'] == true) ? 'tls' : ''),
    };
    final flow = p.bean['flow']?.toString() ?? '';
    if (flow.isNotEmpty) params['flow'] = flow;
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
    final sid = p.bean['shortId']?.toString() ?? '';
    if (sid.isNotEmpty) params['sid'] = sid;

    final query = params.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final name = p.name.isNotEmpty ? '#${Uri.encodeComponent(p.name)}' : '';
    return 'vless://$uuid@${p.serverAddress}:${p.serverPort}?$query$name';
  }
}
