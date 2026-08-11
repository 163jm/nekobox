import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/uri_util.dart';

/// TUIC 链接解析与生成。
/// tuic://uuid:password@host:port?sni=...#name
class TuicFmt {
  TuicFmt._();

  static const String type = ProfileType.tuic;

  static Profile parse(String raw) {
    final uri = Uri.parse(raw);
    final userInfo = uri.userInfo;
    final uiParts = UriUtil.parseUserInfo(userInfo);
    final uuid = uiParts.isNotEmpty ? uiParts[0] : '';
    final password = uiParts.length > 1 ? uiParts[1] : '';
    final host = uri.host;
    final port = uri.port != 0 ? uri.port : 443;
    if (uuid.isEmpty || host.isEmpty) {
      throw FormatException('无法解析 TUIC 链接: $raw');
    }
    return Profile(
      type: type,
      name: uri.fragment,
      serverAddress: host,
      serverPort: port,
      bean: {
        'uuid': uuid,
        'password': password,
        'congestionControl': UriUtil.strParam(
            uri, 'congestion_control', 'cubic'),
        'udpRelayMode': UriUtil.strParam(uri, 'udp_relay_mode', 'native'),
        'zeroRttHandshake': UriUtil.strParam(uri, 'zero_rtt_handshake', '') == '1',
        'heartbeatInterval': UriUtil.intParam(uri, 'heartbeat_interval', 10000),
        'sni': UriUtil.strParam(uri, 'sni', ''),
        'fp': UriUtil.strParam(uri, 'fp', ''),
        'allowInsecure': UriUtil.strParam(uri, 'allowInsecure', '') == '1',
      },
    );
  }
}

/// 导出
class TuicFmtExport {
  TuicFmtExport._();

  static String export(Profile p) {
    final uuid = p.bean['uuid'] ?? '';
    final password = p.bean['password'] ?? '';
    final userInfo = password.isNotEmpty ? '$uuid:$password' : uuid;
    final params = <String, String>{};
    final sni = p.bean['sni']?.toString() ?? '';
    if (sni.isNotEmpty) params['sni'] = sni;
    params['congestion_control'] =
        p.bean['congestionControl']?.toString() ?? 'cubic';
    params['udp_relay_mode'] = p.bean['udpRelayMode']?.toString() ?? 'native';

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final name = p.name.isNotEmpty ? '#${Uri.encodeComponent(p.name)}' : '';
    return 'tuic://${Uri.encodeComponent(userInfo)}@'
        '${p.serverAddress}:${p.serverPort}?$query$name';
  }
}
