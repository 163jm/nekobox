import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/uri_util.dart';

/// ShadowTLS 链接解析与生成。
/// shadowtls://password@host:port?version=3&sni=...#name
class ShadowTLSFmt {
  ShadowTLSFmt._();

  static const String type = ProfileType.shadowtls;

  static Profile parse(String raw) {
    final uri = Uri.parse(raw);
    final password = Uri.decodeComponent(uri.userInfo);
    final host = uri.host;
    final port = uri.port != 0 ? uri.port : 443;
    if (host.isEmpty) {
      throw FormatException('无法解析 ShadowTLS 链接: $raw');
    }
    return Profile(
      type: type,
      name: uri.fragment,
      serverAddress: host,
      serverPort: port,
      bean: {
        'password': password,
        'version': UriUtil.intParam(uri, 'version', 3),
        'sni': UriUtil.strParam(uri, 'sni', ''),
        'allowInsecure': UriUtil.strParam(uri, 'allowInsecure', '') == '1',
      },
    );
  }
}
